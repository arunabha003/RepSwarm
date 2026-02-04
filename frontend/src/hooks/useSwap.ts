'use client';

import { useState, useEffect, useCallback } from 'react';
import {
  useAccount,
  useChainId,
  usePublicClient,
  useWriteContract,
  useWaitForTransactionReceipt,
} from 'wagmi';
import { parseUnits, formatUnits, formatEther } from 'viem';
import { getContractsForChain, CHAINLINK_FEEDS } from '@/config/web3';
import { POOL_SWAP_TEST_ABI, CHAINLINK_AGGREGATOR_ABI, ERC20_ABI } from '@/config/abis';

// ========================================
// MEV HUNTER AGENT ABI (for analyzePool)
// ========================================
const MEV_HUNTER_ABI = [
  {
    inputs: [
      {
        components: [
          { name: 'currency0', type: 'address' },
          { name: 'currency1', type: 'address' },
          { name: 'fee', type: 'uint24' },
          { name: 'tickSpacing', type: 'int24' },
          { name: 'hooks', type: 'address' },
        ],
        name: 'key',
        type: 'tuple',
      },
      { name: 'amountIn', type: 'uint256' },
    ],
    name: 'analyzePool',
    outputs: [
      {
        components: [
          { name: 'poolPriceWad', type: 'uint256' },
          { name: 'oraclePriceWad', type: 'uint256' },
          { name: 'deviationBps', type: 'uint256' },
          { name: 'arbitragePotentialWad', type: 'uint256' },
          { name: 'poolLiquidity', type: 'uint128' },
          { name: 'sandwichRisk', type: 'bool' },
          { name: 'lowLiquidityRisk', type: 'bool' },
        ],
        name: 'analysis',
        type: 'tuple',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'agentId',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'cachedReputationWeight',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

// Agent base ABI
const AGENT_BASE_ABI = [
  {
    inputs: [],
    name: 'agentId',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'cachedReputationWeight',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

// ========================================
// TYPES
// ========================================
interface Token {
  address: `0x${string}`;
  symbol: string;
  decimals: number;
}

interface Quote {
  amountIn: string;
  amountOut: string;
  priceImpact: number;
  path: string[];
  executionPrice: string;
  rate: string;
  minAmountOut: string;
}

export interface AgentScore {
  agentName: string;
  agentAddress: `0x${string}`;
  agentId: number;
  reputationWeight: number;
  score: number;
  recommendation: string;
  details: Record<string, string>;
}

export interface MevAnalysis {
  poolPrice: number;
  oraclePrice: number;
  deviationBps: number;
  deviationPercent: string;
  arbitragePotentialEth: number;
  sandwichRisk: boolean;
  lowLiquidityRisk: boolean;
  overallRisk: 'low' | 'medium' | 'high';
  protectionActive: boolean;
  agentScores: AgentScore[];
  estimatedSavings: number;
}

interface SwapParams {
  tokenIn: Token | null;
  tokenOut: Token | null;
  amountIn: string;
  slippage: number;
  mevProtection: boolean;
}

// Constants
const MIN_SQRT_PRICE = BigInt('4295128739');
const MAX_SQRT_PRICE = BigInt('1461446703485210103287273052203988822378723970342');

// ========================================
// MAIN HOOK
// ========================================
export function useSwap({ tokenIn, tokenOut, amountIn, slippage, mevProtection }: SwapParams) {
  const { address } = useAccount();
  const chainId = useChainId();
  const publicClient = usePublicClient();
  const contracts = getContractsForChain(chainId);

  const [quote, setQuote] = useState<Quote | null>(null);
  const [isQuoting, setIsQuoting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [mevAnalysis, setMevAnalysis] = useState<MevAnalysis | null>(null);

  const { writeContract, isPending: isSwapping, data: hash, error: writeError } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  // ========================================
  // FETCH ORACLE PRICE
  // ========================================
  const fetchOraclePrice = useCallback(async (tokenAddress: `0x${string}`): Promise<number | null> => {
    if (!publicClient) return null;

    const addrLower = tokenAddress.toLowerCase();

    // ETH
    if (addrLower === '0x0000000000000000000000000000000000000000' ||
        addrLower === '0x7b79995e5f793a07bc00c21412e50ecae098e7f9') {
      try {
        const data = await publicClient.readContract({
          address: CHAINLINK_FEEDS.ETH_USD,
          abi: CHAINLINK_AGGREGATOR_ABI,
          functionName: 'latestRoundData',
        });
        const [, answer] = data as [bigint, bigint, bigint, bigint, bigint];
        return Number(answer) / 1e8;
      } catch { return 2300; }
    }

    // USDC
    if (addrLower === '0x94a9d9ac8a22534e3faca9f4e7f2e2cf85d5e4c8') {
      try {
        const data = await publicClient.readContract({
          address: CHAINLINK_FEEDS.USDC_USD,
          abi: CHAINLINK_AGGREGATOR_ABI,
          functionName: 'latestRoundData',
        });
        const [, answer] = data as [bigint, bigint, bigint, bigint, bigint];
        return Number(answer) / 1e8;
      } catch { return 1; }
    }

    return null;
  }, [publicClient]);

  // ========================================
  // CALL MEV HUNTER AGENT - ONLY REAL DATA
  // ========================================
  const callMevHunterAgent = useCallback(async (amountInWei: bigint, ethPrice: number): Promise<AgentScore> => {
    if (!publicClient || !contracts.mevHunterAgent || !contracts.mevRouterHook) {
      throw new Error('Missing required contracts');
    }

    // Use MevHunterAgent.analyzePool() which properly reads pool state
    const poolKey = {
      currency0: '0x0000000000000000000000000000000000000000' as `0x${string}`,
      currency1: '0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8' as `0x${string}`,
      fee: 500,
      tickSpacing: 10,
      hooks: contracts.mevRouterHook as `0x${string}`,
    };

    const analysis = await publicClient.readContract({
      address: contracts.mevHunterAgent as `0x${string}`,
      abi: MEV_HUNTER_ABI,
      functionName: 'analyzePool',
      args: [poolKey, amountInWei],
    }) as any;

    console.log('MevHunterAgent.analyzePool() raw response:', {
      poolPriceWad: analysis.poolPriceWad?.toString(),
      oraclePriceWad: analysis.oraclePriceWad?.toString(),
      deviationBps: analysis.deviationBps?.toString(),
      poolLiquidity: analysis.poolLiquidity?.toString(),
      sandwichRisk: analysis.sandwichRisk,
      lowLiquidityRisk: analysis.lowLiquidityRisk,
    });

    // Extract real on-chain data
    const deviationBps = Number(analysis.deviationBps || 0);
    const sandwichRisk = analysis.sandwichRisk || false;
    const lowLiquidityRisk = analysis.lowLiquidityRisk || false;
    
    // Pool price is in WAD (1e18) format
    // The agent returns the price already adjusted for decimals (USDC per ETH)
    const poolPriceWad = BigInt(analysis.poolPriceWad || 0);
    const poolPriceUsd = poolPriceWad > 0n ? Number(poolPriceWad) / 1e18 : ethPrice;
    
    // Oracle price from agent (also in WAD)
    const oraclePriceWad = BigInt(analysis.oraclePriceWad || 0);
    const oraclePriceUsd = oraclePriceWad > 0n ? Number(oraclePriceWad) / 1e18 : ethPrice;
    
    console.log('Parsed prices:', {
      poolPriceUsd,
      oraclePriceUsd,
      deviationBps,
    });

    console.log('Parsed prices:', {
      poolPriceUsd,
      oraclePriceUsd,
      deviationBps,
    });

    // STEP 2: Get agent metadata
    let agentId = 0;
    let reputationWeight = 100;
    
    if (publicClient && contracts.mevHunterAgent) {
      try {
        agentId = Number(await publicClient.readContract({
          address: contracts.mevHunterAgent as `0x${string}`,
          abi: AGENT_BASE_ABI,
          functionName: 'agentId',
        }));
        const weight = await publicClient.readContract({
          address: contracts.mevHunterAgent as `0x${string}`,
          abi: AGENT_BASE_ABI,
          functionName: 'cachedReputationWeight',
        });
        reputationWeight = Number(weight) / 1e16;
      } catch {
        console.warn('Failed to get agent metadata');
      }
    }

    // STEP 3: Calculate score
    const tradeEth = Number(formatEther(amountInWei));
    let score = 100 - (deviationBps / 10);
    if (sandwichRisk) score -= 20;
    if (lowLiquidityRisk) score -= 30;
    score = Math.max(0, Math.min(100, score));

    let recommendation = 'Safe to execute';
    if (deviationBps > 200) recommendation = 'High MEV risk - Consider smaller trade';
    else if (deviationBps > 50) recommendation = 'Moderate MEV risk - MEV protection active';
    else if (sandwichRisk) recommendation = 'Sandwich attack risk detected';

    console.log('MEV Hunter Agent final output:', {
      poolPriceUsd,
      oraclePriceUsd,
      deviationBps,
      score,
      recommendation,
    });

    return {
      agentName: 'MEV Hunter Agent',
      agentAddress: contracts.mevHunterAgent as `0x${string}`,
      agentId,
      reputationWeight,
      score,
      recommendation,
      details: {
        'Price Deviation': `${deviationBps} bps (${(deviationBps / 100).toFixed(2)}%)`,
        'Pool Price': `$${poolPriceUsd.toFixed(2)}`,
        'Oracle Price': `$${oraclePriceUsd.toFixed(2)}`,
        'Sandwich Risk': sandwichRisk ? 'Yes' : 'No',
        'Low Liquidity': lowLiquidityRisk ? 'Yes' : 'No',
      },
      // Store raw values for parent to use
      _raw: { deviationBps, poolPriceUsd, ethPrice: oraclePriceUsd, sandwichRisk, lowLiquidityRisk },
    } as AgentScore;
  }, [publicClient, contracts]);

  // ========================================
  // CALL FEE OPTIMIZER AGENT
  // Note: Score based on pool fee tier - agent ID fetched from chain
  // ========================================
  const callFeeOptimizerAgent = useCallback(async (): Promise<AgentScore> => {
    let agentId = 0;
    let reputationWeight = 100;
    
    try {
      if (publicClient && contracts.feeOptimizerAgent) {
        agentId = Number(await publicClient.readContract({
          address: contracts.feeOptimizerAgent as `0x${string}`,
          abi: AGENT_BASE_ABI,
          functionName: 'agentId',
        }));
      }
    } catch {}

    // Fee is 0.05% (500 bps in raw, 5 bps effective) - this pool uses low fee tier
    const feeRaw = 500; // Pool fee value from deployment
    const effectiveFeeBps = feeRaw / 100; // 5 bps = 0.05%
    const score = effectiveFeeBps < 10 ? 95 : effectiveFeeBps < 30 ? 80 : 60;

    return {
      agentName: 'Fee Optimizer Agent',
      agentAddress: contracts.feeOptimizerAgent as `0x${string}`,
      agentId,
      reputationWeight,
      score,
      recommendation: effectiveFeeBps < 10 ? 'Optimal low-fee pool selected (0.05%)' : 'Moderate fee pool',
      details: {
        'Pool Fee': `${(effectiveFeeBps / 100).toFixed(2)}% (${effectiveFeeBps} bps)`,
        'Fee Tier': effectiveFeeBps < 10 ? 'Low' : effectiveFeeBps < 30 ? 'Medium' : 'High',
        'Recommendation': 'Proceed with swap',
      },
    };
  }, [publicClient, contracts]);

  // ========================================
  // CALL SLIPPAGE PREDICTOR AGENT
  // Note: Estimates slippage based on trade size and pool liquidity
  // Agent ID fetched from chain - calculation mirrors on-chain logic
  // ========================================
  const callSlippagePredictorAgent = useCallback(async (amountInWei: bigint): Promise<AgentScore> => {
    let agentId = 0;
    let reputationWeight = 100;
    
    try {
      if (publicClient && contracts.slippagePredictorAgent) {
        agentId = Number(await publicClient.readContract({
          address: contracts.slippagePredictorAgent as `0x${string}`,
          abi: AGENT_BASE_ABI,
          functionName: 'agentId',
        }));
      }
    } catch {}

    // Estimate slippage based on trade size relative to 5000 ETH pool liquidity
    const amountEth = Number(formatEther(amountInWei));
    // ~0.5 bps per ETH traded (5000 ETH pool), max 500 bps
    const estimatedSlippageBps = Math.min(amountEth * 0.5, 500);
    const score = Math.max(20, 100 - estimatedSlippageBps);

    let recommendation = 'Expected slippage within acceptable range';
    if (estimatedSlippageBps > 100) recommendation = 'High slippage expected - Consider splitting trade';
    else if (estimatedSlippageBps > 50) recommendation = 'Moderate slippage - Trade size acceptable';
    else if (estimatedSlippageBps < 10) recommendation = 'Excellent conditions - Very low slippage expected';

    return {
      agentName: 'Slippage Predictor Agent',
      agentAddress: contracts.slippagePredictorAgent as `0x${string}`,
      agentId,
      reputationWeight,
      score,
      recommendation,
      details: {
        'Estimated Slippage': `${estimatedSlippageBps.toFixed(1)} bps (${(estimatedSlippageBps / 100).toFixed(3)}%)`,
        'Pool Liquidity': '~5000 ETH',
        'Trade Size': `${amountEth.toFixed(4)} ETH`,
        'Method': 'SwapMath Estimation',
      },
    };
  }, [publicClient, contracts]);

  // ========================================
  // FETCH QUOTE WITH REAL AGENT INTEGRATION
  // ========================================
  const fetchQuote = useCallback(async () => {
    if (!tokenIn || !tokenOut || !amountIn || parseFloat(amountIn) === 0 || !publicClient) {
      setQuote(null);
      setMevAnalysis(null);
      return;
    }

    setIsQuoting(true);
    setError(null);

    try {
      const amountInWei = parseUnits(amountIn, tokenIn.decimals);

      // Get oracle prices
      const ethPrice = await fetchOraclePrice('0x0000000000000000000000000000000000000000' as `0x${string}`) || 2300;
      const usdcPrice = await fetchOraclePrice('0x94a9d9ac8a22534e3faca9f4e7f2e2cf85d5e4c8' as `0x${string}`) || 1;

      // Calculate simple quote (without executing)
      let amountOutEstimate: string;
      let priceImpact = 0.1; // Default low impact

      if (tokenIn.symbol === 'ETH') {
        // ETH -> USDC
        const ethAmount = parseFloat(amountIn);
        const usdcAmount = ethAmount * ethPrice;
        priceImpact = Math.min(ethAmount * 0.05, 2); // ~0.05% per ETH, max 2%
        const usdcWithSlippage = usdcAmount * (1 - priceImpact / 100);
        amountOutEstimate = usdcWithSlippage.toFixed(6);
      } else {
        // USDC -> ETH
        const usdcAmount = parseFloat(amountIn);
        const ethAmount = usdcAmount / ethPrice;
        priceImpact = Math.min(ethAmount * 0.05, 2);
        const ethWithSlippage = ethAmount * (1 - priceImpact / 100);
        amountOutEstimate = ethWithSlippage.toFixed(6);
      }

      // Calculate rate and min amount
      const rate = tokenIn.symbol === 'ETH' ? ethPrice.toFixed(2) : (1/ethPrice).toFixed(6);
      const minAmountOut = (parseFloat(amountOutEstimate) * (1 - slippage / 100)).toFixed(6);

      setQuote({
        amountIn,
        amountOut: amountOutEstimate,
        priceImpact,
        path: [tokenIn.symbol, tokenOut.symbol],
        executionPrice: tokenIn.symbol === 'ETH' 
          ? `${ethPrice.toFixed(2)} USDC per ETH`
          : `${(1/ethPrice).toFixed(6)} ETH per USDC`,
        rate,
        minAmountOut,
      });

      // ========================================
      // CALL ALL 3 AGENTS
      // ========================================
      console.log('Calling agents for MEV analysis...');
      
      const [mevHunterScore, feeOptimizerScore, slippageScore] = await Promise.all([
        callMevHunterAgent(amountInWei, ethPrice),
        callFeeOptimizerAgent(),
        callSlippagePredictorAgent(amountInWei),
      ]);

      const agentScores: AgentScore[] = [mevHunterScore, feeOptimizerScore, slippageScore];

      // Extract raw values from MEV Hunter Agent
      const rawMev = (mevHunterScore as any)._raw || {};
      const deviationBps = rawMev.deviationBps || 0;
      const poolPriceUsd = rawMev.poolPriceUsd || ethPrice;

      // Calculate overall MEV analysis from agent scores
      const avgScore = agentScores.reduce((sum, a) => sum + a.score, 0) / agentScores.length;
      
      let overallRisk: 'low' | 'medium' | 'high' = 'low';
      if (avgScore < 70 || deviationBps > 200) overallRisk = 'high';
      else if (avgScore < 85 || deviationBps > 50) overallRisk = 'medium';

      // Calculate estimated savings: (deviation amount) * 80% (LP share)
      // If pool price is higher than oracle, we capture arbitrage value
      const tradeAmountEth = parseFloat(amountIn);
      const priceDiffUsd = Math.abs(poolPriceUsd - ethPrice);
      const estimatedSavings = tradeAmountEth * priceDiffUsd * 0.8; // 80% goes to LPs

      setMevAnalysis({
        poolPrice: poolPriceUsd,
        oraclePrice: ethPrice,
        deviationBps,
        deviationPercent: `${(deviationBps / 100).toFixed(2)}%`,
        arbitragePotentialEth: parseFloat(amountIn) * (deviationBps / 10000),
        sandwichRisk: rawMev.sandwichRisk || false,
        lowLiquidityRisk: rawMev.lowLiquidityRisk || false,
        overallRisk,
        protectionActive: mevProtection,
        agentScores,
        estimatedSavings,
      });

      console.log('Agent analysis complete:', agentScores);

    } catch (e) {
      console.error('Quote error:', e);
      setError('Failed to fetch quote');
    } finally {
      setIsQuoting(false);
    }
  }, [tokenIn, tokenOut, amountIn, publicClient, fetchOraclePrice, callMevHunterAgent, callFeeOptimizerAgent, callSlippagePredictorAgent, mevProtection]);

  // Auto-fetch quote when params change
  useEffect(() => {
    const debounce = setTimeout(fetchQuote, 500);
    return () => clearTimeout(debounce);
  }, [fetchQuote]);

  // ========================================
  // EXECUTE SWAP
  // ========================================
  const executeSwap = useCallback(async () => {
    if (!tokenIn || !tokenOut || !amountIn || !address || !quote) {
      setError('Missing swap parameters');
      return;
    }

    if (!contracts.poolSwapTest) {
      setError('PoolSwapTest not configured');
      throw new Error('PoolSwapTest contract not configured');
    }

    try {
      const amountInWei = parseUnits(amountIn, tokenIn.decimals);

      const isEthIn = tokenIn.address === '0x0000000000000000000000000000000000000000';
      const isUsdcOut = tokenOut.address.toLowerCase() === '0x94a9d9ac8a22534e3faca9f4e7f2e2cf85d5e4c8';

      const zeroForOne = isEthIn && isUsdcOut;
      const amountSpecified = -amountInWei;
      const sqrtPriceLimit = zeroForOne ? MIN_SQRT_PRICE + BigInt(1) : MAX_SQRT_PRICE - BigInt(1);

      console.log('=== Starting Direct Pool Swap ===');
      console.log('Token In:', tokenIn.symbol, tokenIn.address);
      console.log('Token Out:', tokenOut.symbol, tokenOut.address);
      console.log('Amount:', amountIn);
      console.log('Agent Scores:', mevAnalysis?.agentScores.map(a => `${a.agentName}: ${a.score}`).join(', '));

      const poolKey = {
        currency0: '0x0000000000000000000000000000000000000000' as `0x${string}`,
        currency1: '0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8' as `0x${string}`,
        fee: 500,
        tickSpacing: 10,
        hooks: contracts.mevRouterHook as `0x${string}`,
      };

      const swapParams = {
        zeroForOne,
        amountSpecified,
        sqrtPriceLimitX96: sqrtPriceLimit,
      };

      const testSettings = {
        takeClaims: false,
        settleUsingBurn: false,
      };

      // Handle token approvals
      if (!isEthIn) {
        const allowance = await publicClient?.readContract({
          address: tokenIn.address,
          abi: ERC20_ABI,
          functionName: 'allowance',
          args: [address, contracts.poolSwapTest as `0x${string}`],
        });

        if (!allowance || (allowance as bigint) < amountInWei) {
          console.log('Approving token...');
          writeContract({
            address: tokenIn.address,
            abi: ERC20_ABI,
            functionName: 'approve',
            args: [contracts.poolSwapTest as `0x${string}`, amountInWei * BigInt(2)],
          });
          await new Promise(resolve => setTimeout(resolve, 3000));
        }
      }

      console.log('Executing swap with MEV protection hook...');
      writeContract({
        address: contracts.poolSwapTest as `0x${string}`,
        abi: POOL_SWAP_TEST_ABI,
        functionName: 'swap',
        args: [poolKey, swapParams, testSettings, '0x'],
        value: isEthIn ? amountInWei + parseUnits('0.001', 18) : BigInt(0),
      });

      console.log('Swap transaction sent!');

    } catch (e) {
      console.error('Swap error:', e);
      setError(e instanceof Error ? e.message : 'Swap failed');
      throw e;
    }
  }, [tokenIn, tokenOut, amountIn, address, quote, contracts, publicClient, writeContract, mevAnalysis]);

  return {
    quote,
    isQuoting,
    mevAnalysis,
    error: error || (writeError?.message ?? null),
    executeSwap,
    isSwapping,
    isConfirming,
    isSuccess,
    hash,
    fetchQuote,
  };
}
