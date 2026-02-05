// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

import {SwarmAgentBase} from "./base/SwarmAgentBase.sol";
import {ISwarmAgent, IDynamicFeeAgent, AgentType, SwapContext, AgentResult} from "../interfaces/ISwarmAgent.sol";

/// @title DynamicFeeAgent
/// @notice Calculates optimal swap fees based on pool state and market conditions
/// @dev Implements IDynamicFeeAgent - contains ALL fee calculation logic
/// @dev ERC-8004 compatible - can be registered with identity registry
contract DynamicFeeAgent is SwarmAgentBase, IDynamicFeeAgent {
    // ============ Constants ============

    /// @notice Basis points scale
    uint256 public constant BASIS_POINTS = 10_000;

    /// @notice Minimum fee (0.01%)
    uint24 public constant MIN_FEE = 100;

    /// @notice Maximum fee (1%)
    uint24 public constant MAX_FEE = 10000;

    /// @notice Minimum liquidity threshold
    uint128 public constant MIN_SAFE_LIQUIDITY = 1e15;

    // ============ Configuration ============

    /// @notice Base fee when no special conditions (0.30%)
    uint24 public baseFee;

    /// @notice High volatility fee multiplier (basis points, e.g., 15000 = 1.5x)
    uint256 public volatilityMultiplier;

    /// @notice Low liquidity fee multiplier
    uint256 public lowLiquidityMultiplier;

    /// @notice MEV risk threshold (divergence bps above this triggers higher fee)
    uint256 public mevRiskThreshold;

    /// @notice MEV fee premium (additional fee when MEV risk detected)
    uint24 public mevFeePremium;

    // ============ State ============

    /// @notice Historical volatility per pool (updated by external calls)
    mapping(bytes32 => uint256) public poolVolatility;

    /// @notice Last update timestamp per pool
    mapping(bytes32 => uint256) public lastVolatilityUpdate;

    // ============ Events ============

    event ConfigUpdated(
        uint24 baseFee,
        uint256 volatilityMultiplier,
        uint256 lowLiquidityMultiplier
    );
    event VolatilityUpdated(bytes32 indexed poolId, uint256 volatility);

    // ============ Constructor ============

    constructor(
        IPoolManager _poolManager,
        address _owner
    ) SwarmAgentBase(_poolManager, _owner) {
        baseFee = 3000;              // 0.30%
        volatilityMultiplier = 15000; // 1.5x for high volatility
        lowLiquidityMultiplier = 20000; // 2x for low liquidity
        mevRiskThreshold = 50;       // 0.5% divergence
        mevFeePremium = 2000;        // 0.2% additional
    }

    // ============ ISwarmAgent Implementation ============

    /// @inheritdoc ISwarmAgent
    function agentType() external pure override returns (AgentType) {
        return AgentType.DYNAMIC_FEE;
    }

    /// @inheritdoc SwarmAgentBase
    function _execute(
        SwapContext calldata context
    ) internal override returns (AgentResult memory result) {
        FeeResult memory feeResult = _calculateFee(context);
        
        result.shouldAct = feeResult.useOverride;
        result.value = feeResult.recommendedFee;
        result.secondaryValue = feeResult.mevRisk;
        result.data = abi.encode(feeResult);
    }

    /// @inheritdoc SwarmAgentBase
    function _getRecommendation(
        SwapContext calldata context
    ) internal view override returns (AgentResult memory result) {
        FeeResult memory feeResult = _calculateFee(context);
        
        result.shouldAct = feeResult.useOverride;
        result.value = feeResult.recommendedFee;
        result.secondaryValue = feeResult.mevRisk;
        result.data = abi.encode(feeResult);
    }

    // ============ IDynamicFeeAgent Implementation ============

    /// @inheritdoc IDynamicFeeAgent
    function calculateFee(
        SwapContext calldata context
    ) external view override returns (FeeResult memory result) {
        return _calculateFee(context);
    }

    // ============ Core Logic ============

    /// @notice Calculate optimal fee - THE CORE LOGIC
    function _calculateFee(
        SwapContext calldata context
    ) internal view returns (FeeResult memory result) {
        result.recommendedFee = baseFee;
        result.useOverride = false;

        // 1. Check liquidity conditions
        if (context.liquidity < MIN_SAFE_LIQUIDITY) {
            // Very low liquidity - apply maximum fee
            result.recommendedFee = MAX_FEE;
            result.useOverride = true;
            return result;
        }

        // 2. Calculate MEV risk based on price divergence
        if (context.oraclePrice > 0 && context.poolPrice > 0) {
            uint256 divergenceBps = _calculateDivergenceBps(
                context.poolPrice,
                context.oraclePrice
            );
            
            result.mevRisk = divergenceBps;

            // If divergence exceeds threshold, add MEV premium
            if (divergenceBps > mevRiskThreshold) {
                result.recommendedFee += mevFeePremium;
                result.useOverride = true;
            }
        }

        // 3. Check volatility (if tracked)
        bytes32 poolIdBytes = bytes32(PoolId.unwrap(context.poolId));
        uint256 volatility = poolVolatility[poolIdBytes];
        
        if (volatility > 0) {
            result.volatility = volatility;
            
            // High volatility (>50) increases fee
            if (volatility > 50) {
                uint256 feeIncrease = FullMath.mulDiv(
                    result.recommendedFee,
                    volatilityMultiplier - BASIS_POINTS,
                    BASIS_POINTS
                );
                result.recommendedFee += uint24(feeIncrease);
                result.useOverride = true;
            }
        }

        // 4. Low liquidity multiplier (not as extreme as threshold)
        uint128 mediumLiquidity = MIN_SAFE_LIQUIDITY * 10;
        if (context.liquidity < mediumLiquidity && context.liquidity >= MIN_SAFE_LIQUIDITY) {
            uint256 liquidityRatio = FullMath.mulDiv(
                uint256(context.liquidity),
                BASIS_POINTS,
                uint256(mediumLiquidity)
            );
            
            // Scale fee inversely with liquidity
            uint256 feeMultiplier = lowLiquidityMultiplier - 
                FullMath.mulDiv(liquidityRatio, lowLiquidityMultiplier - BASIS_POINTS, BASIS_POINTS);
            
            result.recommendedFee = uint24(
                FullMath.mulDiv(result.recommendedFee, feeMultiplier, BASIS_POINTS)
            );
            result.useOverride = true;
        }

        // 5. Cap at maximum
        if (result.recommendedFee > MAX_FEE) {
            result.recommendedFee = MAX_FEE;
        }

        // 6. Ensure minimum fee
        if (result.recommendedFee < MIN_FEE) {
            result.recommendedFee = MIN_FEE;
        }
    }

    /// @notice Calculate price divergence in basis points
    function _calculateDivergenceBps(
        uint256 poolPrice,
        uint256 oraclePrice
    ) internal pure returns (uint256) {
        if (oraclePrice == 0) return 0;
        
        if (poolPrice > oraclePrice) {
            return FullMath.mulDiv(poolPrice - oraclePrice, BASIS_POINTS, oraclePrice);
        } else {
            return FullMath.mulDiv(oraclePrice - poolPrice, BASIS_POINTS, oraclePrice);
        }
    }

    // ============ External Data Updates ============

    /// @notice Update volatility for a pool (called by keeper/oracle)
    /// @param poolId The pool identifier
    /// @param volatility Volatility score (0-100)
    function updateVolatility(
        bytes32 poolId,
        uint256 volatility
    ) external onlyAuthorized {
        require(volatility <= 100, "Invalid volatility");
        poolVolatility[poolId] = volatility;
        lastVolatilityUpdate[poolId] = block.timestamp;
        emit VolatilityUpdated(poolId, volatility);
    }

    // ============ Admin Functions ============

    /// @notice Update fee configuration
    function setConfig(
        uint24 _baseFee,
        uint256 _volatilityMultiplier,
        uint256 _lowLiquidityMultiplier,
        uint256 _mevRiskThreshold,
        uint24 _mevFeePremium
    ) external onlyOwner {
        require(_baseFee <= MAX_FEE, "Invalid base fee");
        require(_mevFeePremium <= MAX_FEE, "Invalid premium");
        
        baseFee = _baseFee;
        volatilityMultiplier = _volatilityMultiplier;
        lowLiquidityMultiplier = _lowLiquidityMultiplier;
        mevRiskThreshold = _mevRiskThreshold;
        mevFeePremium = _mevFeePremium;
        
        emit ConfigUpdated(_baseFee, _volatilityMultiplier, _lowLiquidityMultiplier);
    }
}
