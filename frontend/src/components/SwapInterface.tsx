'use client';

import { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { ArrowDown, Settings, Info, Loader2, Shield, CheckCircle, AlertTriangle, ChevronDown, ChevronUp, Zap, TrendingDown, Eye } from 'lucide-react';
import { useAccount, useBalance, useChainId } from 'wagmi';
import { formatUnits, parseUnits } from 'viem';
import { TOKEN_ADDRESSES } from '@/config/web3';
import { TokenSelector } from './TokenSelector';
import { useSwap } from '@/hooks/useSwap';
import { useMevAnalysis, useSlippageData } from '@/hooks/useContractData';
import { toast } from 'sonner';

interface Token {
  address: `0x${string}`;
  symbol: string;
  decimals: number;
  logoURI?: string;
}

// MEV Protection Details Panel
function MevProtectionPanel({
  analysis,
  isLoading
}: {
  analysis: any;
  isLoading: boolean;
}) {
  const [expanded, setExpanded] = useState(false);

  if (isLoading) {
    return (
      <div className="p-3 bg-dark-800/50 rounded-lg animate-pulse">
        <div className="h-4 bg-dark-700 rounded w-3/4" />
      </div>
    );
  }

  if (!analysis) return null;

  const riskColor = analysis.overallRisk === 'low'
    ? 'text-green-400'
    : analysis.overallRisk === 'medium'
      ? 'text-yellow-400'
      : 'text-red-400';

  const riskBgColor = analysis.overallRisk === 'low'
    ? 'bg-green-500/10'
    : analysis.overallRisk === 'medium'
      ? 'bg-yellow-500/10'
      : 'bg-red-500/10';

  return (
    <motion.div
      initial={{ opacity: 0, height: 0 }}
      animate={{ opacity: 1, height: 'auto' }}
      className={`p-4 rounded-xl ${riskBgColor}`}
    >
      {/* Header */}
      <div
        className="flex items-center justify-between cursor-pointer"
        onClick={() => setExpanded(!expanded)}
      >
        <div className="flex items-center gap-2">
          <Shield className={`w-4 h-4 ${riskColor}`} />
          <span className="font-medium text-white">MEV Protection Analysis</span>
        </div>
        <div className="flex items-center gap-2">
          <span className={`text-sm font-medium ${riskColor}`}>
            {analysis.overallRisk.toUpperCase()} RISK
          </span>
          {expanded ? (
            <ChevronUp className="w-4 h-4 text-dark-400" />
          ) : (
            <ChevronDown className="w-4 h-4 text-dark-400" />
          )}
        </div>
      </div>

      {/* Expanded Details */}
      <AnimatePresence>
        {expanded && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            className="mt-4 space-y-4"
          >
            {/* Risk Breakdown */}
            <div className="grid grid-cols-3 gap-3">
              <div className="text-center p-2 bg-dark-800/50 rounded-lg">
                <div className="text-lg font-bold text-white">{analysis.sandwichRisk}%</div>
                <div className="text-xs text-dark-400">Sandwich Risk</div>
              </div>
              <div className="text-center p-2 bg-dark-800/50 rounded-lg">
                <div className="text-lg font-bold text-white">{analysis.frontrunRisk}%</div>
                <div className="text-xs text-dark-400">Frontrun Risk</div>
              </div>
              <div className="text-center p-2 bg-dark-800/50 rounded-lg">
                <div className="text-lg font-bold text-white">{analysis.backrunRisk}%</div>
                <div className="text-xs text-dark-400">Backrun Risk</div>
              </div>
            </div>

            {/* Oracle vs Pool Price */}
            <div className="p-3 bg-dark-800/50 rounded-lg">
              <div className="flex items-center gap-2 mb-2">
                <Eye className="w-4 h-4 text-primary-400" />
                <span className="text-sm font-medium text-white">Price Comparison</span>
              </div>
              <div className="grid grid-cols-2 gap-2 text-sm">
                <div>
                  <span className="text-dark-400">Oracle Price: </span>
                  <span className="text-white">${analysis.oraclePrice.toFixed(2)}</span>
                </div>
                <div>
                  <span className="text-dark-400">Pool Price: </span>
                  <span className="text-white">${analysis.poolPrice.toFixed(2)}</span>
                </div>
              </div>
              <div className="mt-2 text-sm">
                <span className="text-dark-400">Deviation: </span>
                <span className={analysis.deviationBps > 50 ? 'text-yellow-400' : 'text-green-400'}>
                  {analysis.deviationPercent}% ({analysis.deviationBps} bps)
                </span>
              </div>
            </div>

            {/* Agent Scores */}
            <div>
              <div className="flex items-center gap-2 mb-2">
                <Zap className="w-4 h-4 text-accent-400" />
                <span className="text-sm font-medium text-white">Agent Recommendations</span>
              </div>
              <div className="space-y-2">
                {analysis.agentScores.map((agent: any) => (
                  <div key={agent.agent} className="flex items-center justify-between p-2 bg-dark-800/50 rounded-lg">
                    <div>
                      <span className="text-sm text-white">{agent.agent}</span>
                      <p className="text-xs text-dark-400">{agent.recommendation}</p>
                    </div>
                    <div className={`text-sm font-medium ${agent.score < 0 ? 'text-green-400' : 'text-yellow-400'}`}>
                      Score: {agent.score}
                    </div>
                  </div>
                ))}
              </div>
            </div>

            {/* Protection Method */}
            <div className="p-3 bg-green-500/10 rounded-lg">
              <div className="flex items-center gap-2">
                <CheckCircle className="w-4 h-4 text-green-400" />
                <span className="text-sm text-green-400">
                  Estimated savings: ${analysis.estimatedSavings.toFixed(2)}
                </span>
              </div>
              <p className="text-xs text-dark-400 mt-1">{analysis.protectionMethod}</p>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}

// Slippage Details Panel
function SlippagePanel({
  slippage,
  isLoading,
  tokenOut
}: {
  slippage: any;
  isLoading: boolean;
  tokenOut: Token | null;
}) {
  if (isLoading) {
    return (
      <div className="p-3 bg-dark-800/50 rounded-lg animate-pulse">
        <div className="h-4 bg-dark-700 rounded w-3/4" />
      </div>
    );
  }

  if (!slippage) return null;

  const slippageColor = slippage.slippageBps < 50
    ? 'text-green-400'
    : slippage.slippageBps < 100
      ? 'text-yellow-400'
      : 'text-red-400';

  return (
    <div className="p-3 bg-dark-800/30 rounded-lg space-y-2">
      <div className="flex items-center gap-2">
        <TrendingDown className="w-4 h-4 text-primary-400" />
        <span className="text-sm font-medium text-white">Slippage Analysis</span>
        <span className="text-xs text-dark-400">(SwapMath Simulation)</span>
      </div>

      <div className="grid grid-cols-2 gap-2 text-sm">
        <div className="flex justify-between">
          <span className="text-dark-400">Expected Output:</span>
          <span className="text-white">{slippage.expectedOutput.toFixed(2)} {tokenOut?.symbol}</span>
        </div>
        <div className="flex justify-between">
          <span className="text-dark-400">Simulated Output:</span>
          <span className="text-white">{slippage.simulatedOutput.toFixed(2)} {tokenOut?.symbol}</span>
        </div>
      </div>

      <div className="grid grid-cols-3 gap-2">
        <div className="text-center p-2 bg-dark-800/50 rounded">
          <div className={`text-sm font-medium ${slippageColor}`}>{slippage.slippagePercent}%</div>
          <div className="text-xs text-dark-400">Slippage</div>
        </div>
        <div className="text-center p-2 bg-dark-800/50 rounded">
          <div className="text-sm font-medium text-white">{slippage.priceImpactPercent}%</div>
          <div className="text-xs text-dark-400">Price Impact</div>
        </div>
        <div className="text-center p-2 bg-dark-800/50 rounded">
          <div className="text-sm font-medium text-white">{slippage.liquidityDepth}</div>
          <div className="text-xs text-dark-400">Liquidity</div>
        </div>
      </div>

      <div className="text-xs text-dark-400 italic">
        💡 {slippage.recommendation}
      </div>
    </div>
  );
}

export function SwapInterface() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();

  // Token state
  const [tokenIn, setTokenIn] = useState<Token | null>(null);
  const [tokenOut, setTokenOut] = useState<Token | null>(null);
  const [amountIn, setAmountIn] = useState('');
  const [slippage, setSlippage] = useState(0.5);
  const [mevProtection, setMevProtection] = useState(true);
  const [showSettings, setShowSettings] = useState(false);
  const [showDetails, setShowDetails] = useState(true);

  // Load default tokens
  useEffect(() => {
    if (chainId && TOKEN_ADDRESSES[chainId]) {
      const tokens = TOKEN_ADDRESSES[chainId];
      setTokenIn(tokens.ETH);
      setTokenOut(tokens.USDC);
    }
  }, [chainId]);

  // Get balances
  const { data: balanceIn } = useBalance({
    address,
    token: tokenIn?.address === '0x0000000000000000000000000000000000000000'
      ? undefined
      : tokenIn?.address,
  });

  // Use swap hook
  const {
    quote,
    isQuoting,
    isSwapping,
    executeSwap,
    mevAnalysis
  } = useSwap({
    tokenIn,
    tokenOut,
    amountIn,
    slippage,
    mevProtection,
  });

  // Use real MEV analysis
  const { analysis: mevDetails, isLoading: mevLoading } = useMevAnalysis(tokenIn, tokenOut, amountIn);

  // Use real slippage data
  const { slippage: slippageData, isLoading: slippageLoading } = useSlippageData(tokenIn, tokenOut, amountIn);

  const handleSwap = async () => {
    if (!isConnected) {
      toast.error('Please connect your wallet');
      return;
    }

    if (!tokenIn || !tokenOut || !amountIn) {
      toast.error('Please fill in all fields');
      return;
    }

    try {
      await executeSwap();
      toast.success('Swap executed successfully!');
      setAmountIn('');
    } catch (error: any) {
      toast.error(error.message || 'Swap failed');
    }
  };

  const handleFlipTokens = () => {
    const temp = tokenIn;
    setTokenIn(tokenOut);
    setTokenOut(temp);
    setAmountIn('');
  };

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="w-full max-w-md mx-auto"
    >
      <div className="glass-card rounded-2xl p-4 shadow-xl">
        {/* Header */}
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-white">Swap</h2>
          <div className="flex items-center gap-2">
            {/* MEV Protection Badge */}
            <motion.div
              className={`flex items-center gap-1 px-2 py-1 rounded-lg text-xs font-medium cursor-pointer ${mevProtection
                  ? 'bg-green-500/20 text-green-400'
                  : 'bg-yellow-500/20 text-yellow-400'
                }`}
              whileHover={{ scale: 1.05 }}
              onClick={() => setMevProtection(!mevProtection)}
            >
              <Shield className="w-3 h-3" />
              MEV {mevProtection ? 'Protected' : 'Off'}
            </motion.div>

            <motion.button
              onClick={() => setShowSettings(!showSettings)}
              className="p-2 rounded-lg hover:bg-dark-700/50 transition-colors"
              whileHover={{ rotate: 90 }}
              whileTap={{ scale: 0.9 }}
            >
              <Settings className="w-5 h-5 text-dark-400" />
            </motion.button>
          </div>
        </div>

        {/* Settings Panel */}
        <AnimatePresence>
          {showSettings && (
            <motion.div
              initial={{ height: 0, opacity: 0 }}
              animate={{ height: 'auto', opacity: 1 }}
              exit={{ height: 0, opacity: 0 }}
              className="mb-4 overflow-hidden"
            >
              <div className="p-4 bg-dark-800/50 rounded-xl space-y-4">
                {/* Slippage */}
                <div>
                  <label className="text-sm text-dark-400 mb-2 block">
                    Slippage Tolerance
                  </label>
                  <div className="flex gap-2">
                    {[0.1, 0.5, 1.0].map((value) => (
                      <button
                        key={value}
                        onClick={() => setSlippage(value)}
                        className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${slippage === value
                            ? 'bg-primary-500 text-white'
                            : 'bg-dark-700 text-dark-300 hover:bg-dark-600'
                          }`}
                      >
                        {value}%
                      </button>
                    ))}
                    <input
                      type="number"
                      value={slippage}
                      onChange={(e) => setSlippage(parseFloat(e.target.value) || 0)}
                      className="w-20 px-3 py-1.5 rounded-lg bg-dark-700 text-white text-sm focus:outline-none focus:ring-2 focus:ring-primary-500"
                      placeholder="Custom"
                    />
                  </div>
                </div>

                {/* MEV Protection Toggle */}
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <Shield className="w-4 h-4 text-primary-400" />
                    <span className="text-sm text-dark-300">MEV Protection</span>
                    <div className="group relative">
                      <Info className="w-3 h-3 text-dark-500 cursor-help" />
                      <div className="absolute bottom-full left-0 mb-2 w-48 p-2 bg-dark-800 border border-dark-600 rounded-lg text-xs text-dark-300 opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all z-10">
                        Uses Chainlink oracles to detect MEV opportunities and captures value for LPs
                      </div>
                    </div>
                  </div>
                  <button
                    onClick={() => setMevProtection(!mevProtection)}
                    className={`relative w-12 h-6 rounded-full transition-colors ${mevProtection ? 'bg-primary-500' : 'bg-dark-600'
                      }`}
                  >
                    <motion.div
                      className="absolute top-1 w-4 h-4 rounded-full bg-white"
                      animate={{ left: mevProtection ? '1.5rem' : '0.25rem' }}
                    />
                  </button>
                </div>

                {/* Show Details Toggle */}
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <Eye className="w-4 h-4 text-accent-400" />
                    <span className="text-sm text-dark-300">Show Analysis Details</span>
                  </div>
                  <button
                    onClick={() => setShowDetails(!showDetails)}
                    className={`relative w-12 h-6 rounded-full transition-colors ${showDetails ? 'bg-accent-500' : 'bg-dark-600'
                      }`}
                  >
                    <motion.div
                      className="absolute top-1 w-4 h-4 rounded-full bg-white"
                      animate={{ left: showDetails ? '1.5rem' : '0.25rem' }}
                    />
                  </button>
                </div>
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        {/* Input Token */}
        <div className="space-y-2">
          <div className="p-4 bg-dark-800/50 rounded-xl">
            <div className="flex items-center justify-between mb-2">
              <span className="text-sm text-dark-400">You pay</span>
              {balanceIn && (
                <button
                  onClick={() => setAmountIn(formatUnits(balanceIn.value, balanceIn.decimals))}
                  className="text-sm text-primary-400 hover:text-primary-300"
                >
                  Balance: {parseFloat(formatUnits(balanceIn.value, balanceIn.decimals)).toFixed(4)}
                </button>
              )}
            </div>
            <div className="flex items-center gap-3">
              <input
                type="number"
                value={amountIn}
                onChange={(e) => setAmountIn(e.target.value)}
                placeholder="0.0"
                className="flex-1 bg-transparent text-2xl font-semibold text-white focus:outline-none"
              />
              <TokenSelector
                selectedToken={tokenIn}
                onSelect={setTokenIn}
                chainId={chainId}
              />
            </div>
          </div>

          {/* Swap Button */}
          <div className="flex justify-center -my-2 relative z-10">
            <motion.button
              onClick={handleFlipTokens}
              className="p-2 rounded-xl bg-dark-800 border border-dark-700 hover:bg-dark-700 transition-colors"
              whileHover={{ scale: 1.1, rotate: 180 }}
              whileTap={{ scale: 0.9 }}
            >
              <ArrowDown className="w-5 h-5 text-dark-400" />
            </motion.button>
          </div>

          {/* Output Token */}
          <div className="p-4 bg-dark-800/50 rounded-xl">
            <div className="flex items-center justify-between mb-2">
              <span className="text-sm text-dark-400">You receive</span>
            </div>
            <div className="flex items-center gap-3">
              <div className="flex-1 text-2xl font-semibold">
                {isQuoting ? (
                  <Loader2 className="w-6 h-6 animate-spin text-dark-400" />
                ) : quote ? (
                  <span className="text-white">{quote.amountOut}</span>
                ) : (
                  <span className="text-dark-500">0.0</span>
                )}
              </div>
              <TokenSelector
                selectedToken={tokenOut}
                onSelect={setTokenOut}
                chainId={chainId}
              />
            </div>
          </div>
        </div>

        {/* Quote Details */}
        {quote && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            className="mt-4 p-4 bg-dark-800/30 rounded-xl space-y-2"
          >
            <div className="flex items-center justify-between text-sm">
              <span className="text-dark-400">Rate</span>
              <span className="text-white">
                1 {tokenIn?.symbol} = {quote.rate} {tokenOut?.symbol}
              </span>
            </div>
            {quote.oraclePrice && (
              <div className="flex items-center justify-between text-sm">
                <span className="text-dark-400 flex items-center gap-1">
                  <img src="https://cryptologos.cc/logos/chainlink-link-logo.png" className="w-3 h-3" alt="" />
                  Oracle Price
                </span>
                <span className="text-white">{quote.oraclePrice}</span>
              </div>
            )}
            <div className="flex items-center justify-between text-sm">
              <span className="text-dark-400">Price Impact</span>
              <span className={quote.priceImpact > 1 ? 'text-yellow-400' : 'text-green-400'}>
                {quote.priceImpact.toFixed(2)}%
              </span>
            </div>
            <div className="flex items-center justify-between text-sm">
              <span className="text-dark-400">Min. Received</span>
              <span className="text-white">
                {quote.minAmountOut} {tokenOut?.symbol}
              </span>
            </div>
          </motion.div>
        )}

        {/* MEV Protection Details */}
        {mevProtection && showDetails && amountIn && parseFloat(amountIn) > 0 && (
          <div className="mt-4">
            <MevProtectionPanel
              analysis={mevDetails}
              isLoading={mevLoading}
            />
          </div>
        )}

        {/* Slippage Details */}
        {showDetails && amountIn && parseFloat(amountIn) > 0 && (
          <div className="mt-4">
            <SlippagePanel
              slippage={slippageData}
              isLoading={slippageLoading}
              tokenOut={tokenOut}
            />
          </div>
        )}

        {/* Swap Button */}
        <motion.button
          onClick={handleSwap}
          disabled={!isConnected || !amountIn || isSwapping || isQuoting}
          className={`w-full mt-4 py-4 rounded-xl font-semibold text-lg transition-all ${!isConnected
              ? 'bg-dark-700 text-dark-400 cursor-not-allowed'
              : isSwapping || isQuoting
                ? 'bg-primary-600 text-white cursor-wait'
                : 'bg-gradient-to-r from-primary-500 to-accent-500 text-white hover:from-primary-400 hover:to-accent-400 glow-blue'
            }`}
          whileHover={isConnected && !isSwapping ? { scale: 1.02 } : {}}
          whileTap={isConnected && !isSwapping ? { scale: 0.98 } : {}}
        >
          {!isConnected ? (
            'Connect Wallet'
          ) : isSwapping ? (
            <span className="flex items-center justify-center gap-2">
              <Loader2 className="w-5 h-5 animate-spin" />
              Swapping...
            </span>
          ) : !amountIn ? (
            'Enter Amount'
          ) : (
            <span className="flex items-center justify-center gap-2">
              {mevProtection && <Shield className="w-5 h-5" />}
              Swap {mevProtection ? 'with MEV Protection' : ''}
            </span>
          )}
        </motion.button>
      </div>
    </motion.div>
  );
}
