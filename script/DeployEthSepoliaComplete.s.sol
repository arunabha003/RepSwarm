// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SwarmCoordinator} from "../src/SwarmCoordinator.sol";
import {MevRouterHookV2} from "../src/hooks/MevRouterHookV2.sol";
import {LPFeeAccumulator} from "../src/LPFeeAccumulator.sol";
import {FlashLoanBackrunner} from "../src/backrun/FlashLoanBackrunner.sol";
import {OracleRegistry} from "../src/oracles/OracleRegistry.sol";
import {SwarmAgentRegistry} from "../src/erc8004/SwarmAgentRegistry.sol";
import {IOracleRegistry} from "../src/interfaces/IChainlinkOracle.sol";
import {MevHunterAgent} from "../src/agents/MevHunterAgent.sol";
import {SlippagePredictorAgent} from "../src/agents/SlippagePredictorAgent.sol";
import {FeeOptimizerAgent} from "../src/agents/FeeOptimizerAgent.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {ISwarmCoordinator} from "../src/interfaces/ISwarmCoordinator.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

/// @title DeployEthSepoliaComplete
/// @notice Complete deployment to Ethereum Sepolia with pool creation and liquidity
/// @dev Follows detox-hook approach with minimal liquidity
contract DeployEthSepoliaComplete is Script {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    // ============ Ethereum Sepolia Addresses ============
    
    // Uniswap V4 on Eth Sepolia (from official docs)
    address constant POOL_MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    address constant POSITION_MANAGER = 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4;
    address constant POOL_SWAP_TEST = 0x9B6b46e2c869aa39918Db7f52f5557FE577B6eEe;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    
    // ERC-8004 registries on Sepolia
    address constant ERC8004_IDENTITY = 0x8004A818BFB912233c491871b3d84c89A494BD9e;
    address constant ERC8004_REPUTATION = 0x8004B663056A597Dffe9eCcC1965A193B7388713;
    
    // Aave V3 Pool on Sepolia
    address constant AAVE_POOL = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    
    // Chainlink Sepolia Feeds
    address constant ETH_USD = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address constant USDC_USD = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
    address constant LINK_USD = 0xc59E3633BAAC79493d908e63626716e204A45EdF;
    
    // Sepolia Tokens
    address constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address constant USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8; // Aave USDC
    address constant LINK = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
    
    // CREATE2 deployer
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // ============ Pool Configuration - MINIMAL like DetoxHook ============
    
    // DetoxHook uses only 1 USDC worth of liquidity!
    uint256 constant LIQUIDITY_USDC_AMOUNT = 1e6;  // 1 USDC (6 decimals) - Note: Aave USDC might use 18 decimals
    uint24 constant POOL_FEE = 500;  // 0.05% fee like DetoxHook
    int24 constant TICK_SPACING_POOL_1 = 10;  // Fine-grained
    int24 constant TICK_SPACING_POOL_2 = 60;  // Standard
    
    // sqrtPriceX96 for ETH/USDC 
    // Price = 2200 USDC/ETH (~3% above oracle at $2140 to test MEV capture)
    // For currency0=ETH, currency1=USDC: sqrt(price * 1e12) * 2^96 (accounting for 18 vs 6 decimal difference)
    // Pool at $2200 while oracle at $2140 = ~2.8% discrepancy for MEV testing
    uint160 constant SQRT_PRICE_2200 = 3715891345215073490873980141568;  // Pool price for testing
    uint160 constant SQRT_PRICE_2250 = 3757984620312892268098150793216;  // Pool2 slightly higher
    
    // State variables
    MevRouterHookV2 public hook;
    PoolModifyLiquidityTest public modifyLiquidityRouter;
    PoolKey public poolKey1;
    PoolKey public poolKey2;
    
    function run() external {
        // Anvil default account
        uint256 pk = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(pk);
        
        console.log("===========================================");
        console.log("  DEPLOYING TO ETH SEPOLIA (FORK)");
        console.log("===========================================");
        console.log("Deployer:", deployer);
        console.log("Deployer ETH Balance:", deployer.balance / 1e18, "ETH");
        console.log("PoolManager:", POOL_MANAGER);
        console.log("PositionManager:", POSITION_MANAGER);
        
        // Check if PoolManager exists
        require(POOL_MANAGER.code.length > 0, "PoolManager not found - wrong network?");
        console.log("[OK] PoolManager exists");
        
        vm.startBroadcast(pk);
        
        // Step 1: Wrap ETH to WETH
        console.log("");
        console.log("=== Step 1: Prepare WETH ===");
        uint256 wethAmount = 0.1 ether;
        IWETH(WETH).deposit{value: wethAmount}();
        console.log("Wrapped", wethAmount / 1e18, "ETH to WETH");
        
        // Step 2: Deploy Oracle Registry
        console.log("");
        console.log("=== Step 2: Deploy Oracle Registry ===");
        OracleRegistry oracle = new OracleRegistry();
        oracle.setPriceFeed(WETH, address(0), ETH_USD);
        oracle.setPriceFeed(address(0), address(0), ETH_USD); // Native ETH
        oracle.setPriceFeed(USDC, address(0), USDC_USD);
        oracle.setPriceFeed(LINK, address(0), LINK_USD);
        console.log("OracleRegistry:", address(oracle));
        
        // Step 3: Deploy LP Fee Accumulator
        console.log("");
        console.log("=== Step 3: Deploy LP Fee Accumulator ===");
        LPFeeAccumulator lpAcc = new LPFeeAccumulator(
            IPoolManager(POOL_MANAGER),
            0.0001 ether,
            5 minutes
        );
        console.log("LPFeeAccumulator:", address(lpAcc));
        
        // Step 4: Deploy Hook using HookMiner
        console.log("");
        console.log("=== Step 4: Deploy MevRouterHookV2 ===");
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | 
            Hooks.AFTER_SWAP_FLAG | 
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
            Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        
        bytes memory constructorArgs = abi.encode(
            IPoolManager(POOL_MANAGER),
            IOracleRegistry(address(oracle)),
            deployer
        );
        
        (address hookAddr, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(MevRouterHookV2).creationCode,
            constructorArgs
        );
        console.log("Hook target address:", hookAddr);
        
        hook = new MevRouterHookV2{salt: salt}(
            IPoolManager(POOL_MANAGER),
            IOracleRegistry(address(oracle)),
            deployer
        );
        require(address(hook) == hookAddr, "Hook address mismatch");
        console.log("MevRouterHookV2:", address(hook));
        
        // Link hook and LP accumulator
        hook.setLPFeeAccumulator(address(lpAcc));
        lpAcc.setHookAuthorization(address(hook), true);
        
        // Step 5: Deploy SwarmCoordinator
        console.log("");
        console.log("=== Step 5: Deploy SwarmCoordinator ===");
        SwarmCoordinator coord = new SwarmCoordinator(
            IPoolManager(POOL_MANAGER),
            deployer,
            ERC8004_IDENTITY,
            ERC8004_REPUTATION
        );
        console.log("SwarmCoordinator:", address(coord));
        
        // Step 6: Deploy FlashLoanBackrunner
        console.log("");
        console.log("=== Step 6: Deploy FlashLoanBackrunner ===");
        FlashLoanBackrunner backrun = new FlashLoanBackrunner(
            IPoolManager(POOL_MANAGER),
            AAVE_POOL
        );
        backrun.setLPFeeAccumulator(address(lpAcc));
        console.log("FlashLoanBackrunner:", address(backrun));
        
        // Step 7: Deploy Agent Registry
        console.log("");
        console.log("=== Step 7: Deploy Agent Registry ===");
        SwarmAgentRegistry registry = new SwarmAgentRegistry(ERC8004_IDENTITY, ERC8004_REPUTATION);
        registry.setFeedbackClientAuthorization(address(coord), true);
        console.log("AgentRegistry:", address(registry));
        
        // Step 8: Deploy Agents
        console.log("");
        console.log("=== Step 8: Deploy Agents ===");
        FeeOptimizerAgent feeAgent = new FeeOptimizerAgent(
            ISwarmCoordinator(address(coord)),
            IPoolManager(POOL_MANAGER)
        );
        console.log("FeeOptimizerAgent:", address(feeAgent));
        
        SlippagePredictorAgent slipAgent = new SlippagePredictorAgent(
            ISwarmCoordinator(address(coord)),
            IPoolManager(POOL_MANAGER)
        );
        console.log("SlippagePredictorAgent:", address(slipAgent));
        
        MevHunterAgent mevAgent = new MevHunterAgent(
            ISwarmCoordinator(address(coord)),
            IPoolManager(POOL_MANAGER),
            IOracleRegistry(address(oracle))
        );
        console.log("MevHunterAgent:", address(mevAgent));
        
        // Register agents
        coord.registerAgent(address(feeAgent), 1, true);
        coord.registerAgent(address(slipAgent), 2, true);
        coord.registerAgent(address(mevAgent), 3, true);
        console.log("Agents registered");
        
        // Step 9: Deploy PoolModifyLiquidityTest
        console.log("");
        console.log("=== Step 9: Deploy Liquidity Router ===");
        modifyLiquidityRouter = new PoolModifyLiquidityTest(IPoolManager(POOL_MANAGER));
        console.log("PoolModifyLiquidityTest:", address(modifyLiquidityRouter));
        
        // Step 10: Initialize Pool 1 (ETH/USDC @ 2500)
        console.log("");
        console.log("=== Step 10: Initialize Pool 1 ===");
        _initializePool1();
        
        // Step 11: Initialize Pool 2 (ETH/USDC @ 2600)
        console.log("");
        console.log("=== Step 11: Initialize Pool 2 ===");
        _initializePool2();
        
        // Step 12: Add minimal liquidity (like DetoxHook)
        console.log("");
        console.log("=== Step 12: Add Liquidity ===");
        _addLiquidity();
        
        vm.stopBroadcast();
        
        // Final Summary
        console.log("");
        console.log("===========================================");
        console.log("  DEPLOYMENT COMPLETE!");
        console.log("===========================================");
        console.log("");
        console.log("Addresses:");
        console.log("  Hook:", address(hook));
        console.log("  Coordinator:", address(coord));
        console.log("  OracleRegistry:", address(oracle));
        console.log("  LPFeeAccumulator:", address(lpAcc));
        console.log("");
        console.log("Pool 1 ID:", vm.toString(PoolId.unwrap(poolKey1.toId())));
        console.log("Pool 2 ID:", vm.toString(PoolId.unwrap(poolKey2.toId())));
        console.log("");
        console.log("Test Swap Command:");
        console.log("  cast send", POOL_SWAP_TEST);
    }
    
    function _initializePool1() internal {
        // ETH (address(0)) < any ERC20, so ETH is always currency0
        poolKey1 = PoolKey({
            currency0: Currency.wrap(address(0)),  // ETH
            currency1: Currency.wrap(USDC),
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING_POOL_1,
            hooks: IHooks(address(hook))
        });
        
        console.log("Pool 1 Config:");
        console.log("  Currency0 (ETH):", Currency.unwrap(poolKey1.currency0));
        console.log("  Currency1 (USDC):", Currency.unwrap(poolKey1.currency1));
        console.log("  Fee:", POOL_FEE);
        console.log("  TickSpacing:", TICK_SPACING_POOL_1);
        console.log("  Hook:", address(hook));
        
        // Initialize at $2200 (3% above oracle $2140) to create MEV opportunity for testing
        try IPoolManager(POOL_MANAGER).initialize(poolKey1, SQRT_PRICE_2200) returns (int24 tick) {
            console.log("  -> Initialized at tick:", tick);
            console.log("  -> Pool price: $2200 (oracle: ~$2140, 3% discrepancy for MEV testing)");
        } catch Error(string memory reason) {
            console.log("  -> Init failed (may exist):", reason);
        } catch {
            console.log("  -> Init failed with unknown error");
        }
    }
    
    function _initializePool2() internal {
        poolKey2 = PoolKey({
            currency0: Currency.wrap(address(0)),  // ETH
            currency1: Currency.wrap(USDC),
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING_POOL_2,
            hooks: IHooks(address(hook))
        });
        
        console.log("Pool 2 Config:");
        console.log("  Currency0 (ETH):", Currency.unwrap(poolKey2.currency0));
        console.log("  Currency1 (USDC):", Currency.unwrap(poolKey2.currency1));
        console.log("  Fee:", POOL_FEE);
        console.log("  TickSpacing:", TICK_SPACING_POOL_2);
        console.log("  Hook:", address(hook));
        
        // Initialize at $2250 (slightly higher than pool1) 
        try IPoolManager(POOL_MANAGER).initialize(poolKey2, SQRT_PRICE_2250) returns (int24 tick) {
            console.log("  -> Initialized at tick:", tick);
            console.log("  -> Pool2 price: $2250");
        } catch Error(string memory reason) {
            console.log("  -> Init failed (may exist):", reason);
        } catch {
            console.log("  -> Init failed with unknown error");
        }
    }
    
    function _addLiquidity() internal {
        // Check USDC balance
        uint256 usdcBalance = IERC20(USDC).balanceOf(msg.sender);
        console.log("USDC Balance:", usdcBalance);
        
        if (usdcBalance == 0) {
            console.log("WARNING: No USDC balance. Need to get USDC from faucet.");
            console.log("For Aave testnet USDC, use: https://staging.aave.com/faucet/");
            console.log("");
            console.log("Pool initialized but NO LIQUIDITY added.");
            console.log("After getting USDC, run AddLiquiditySepoliaFork.s.sol");
            return;
        }
        
        // Approve tokens
        IERC20(USDC).approve(address(modifyLiquidityRouter), type(uint256).max);
        IERC20(WETH).approve(address(modifyLiquidityRouter), type(uint256).max);
        
        // Calculate ETH amount based on price
        // At 2500 USDC/ETH, 1 USDC = 0.0004 ETH
        uint256 ethAmount = 0.001 ether;  // Small amount for testing
        
        console.log("Adding liquidity:");
        console.log("  ETH:", ethAmount);
        console.log("  USDC:", LIQUIDITY_USDC_AMOUNT);
        
        // Get current tick
        (uint160 sqrtPrice, int24 tick,,) = IPoolManager(POOL_MANAGER).getSlot0(poolKey1.toId());
        console.log("  Current tick:", tick);
        
        // Calculate tick range around current tick
        int24 tickLower = ((tick - 6000) / TICK_SPACING_POOL_1) * TICK_SPACING_POOL_1;
        int24 tickUpper = ((tick + 6000) / TICK_SPACING_POOL_1) * TICK_SPACING_POOL_1;
        
        try modifyLiquidityRouter.modifyLiquidity{value: ethAmount}(
            poolKey1,
            ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int256(LIQUIDITY_USDC_AMOUNT),
                salt: bytes32(0)
            }),
            ""
        ) {
            console.log("  -> Pool 1 liquidity added!");
        } catch Error(string memory reason) {
            console.log("  -> Pool 1 liquidity failed:", reason);
        } catch {
            console.log("  -> Pool 1 liquidity failed (unknown)");
        }
    }
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function balanceOf(address) external view returns (uint256);
}
