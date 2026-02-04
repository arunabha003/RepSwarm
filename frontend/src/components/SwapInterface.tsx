'use client';

import { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { ArrowDown, Settings, Loader2, Shield, CheckCircle, ChevronDown, ChevronUp, Zap } from 'lucide-react';
import { useAccount, useBalance, useChainId } from 'wagmi';
import { formatUnits } from 'viem';
import { TOKEN_ADDRESSES } from '@/config/web3';
import { TokenSelector } from './TokenSelector';
import { useSwap } from '@/hooks/useSwap';
import { toast } from 'sonner';

interface Token {
  address: `0x${string}`;
  symbol: string;
  decimals: number;
  logoURI?: string;
}

// Agent Score Display
function AgentScoreRow({ agent }: { agent: any }) {
  const scoreColor = agent.score >= 80
    ? 'text-green-400'
    : agent.score >= 60
      ? 'text-yellow-400'
      : 'text-red-400';

  return (
    <div className="flex items-center justify-between py-2 border-b border-dark-700 last:border-0">
      <div className="flex-1">
        <div className="font-medium text-white text-sm">{agent.agentName || agent.name}</div>
        <div className="text-xs text-dark-400">{agent.recommendation}</div>
      </div>
      <div className="flex flex-col items-end">
        <div className={`font-bold ${scoreColor} text-sm`}>
          Score: {agent.score.toFixed(0)}/100
        </div>
        {agent.agentId > 0 && (
          <div className="text-xs text-dark-500">ID: #{agent.agentId}</div>
        )}
      </div>
    </div>
  );
}

// MEV Analysis Panel with Real Agent Scores
function MevAnalysisPanel({
  mevAnalysis,
  isLoading
}: {
  mevAnalysis: any;
  isLoading: boolean;
}) {
  const [expanded, setExpanded] = useState(true);

  if (!mevAnalysis || isLoading) return null;

  const risk = mevAnalysis.overallRisk || 'low';
  const riskColor = risk === 'low'
    ? 'text-green-400'
    : risk === 'medium'
      ? 'text-yellow-400'
      : 'text-red-400';

  const riskBgColor = risk === 'low'
    ? 'bg-green-500/10 border-green-500/30'
    : risk === 'medium'
      ? 'bg-yellow-500/10 border-yellow-500/30'
      : 'bg-red-500/10 border-red-500/30';

  // Calculate risk percentages from agent analysis
  const sandwichRiskPct = mevAnalysis.sandwichRisk ? 75 : 10;
  const frontrunRiskPct = mevAnalysis.deviationBps > 50 ? Math.min(mevAnalysis.deviationBps / 2, 80) : 15;
  const backrunRiskPct = mevAnalysis.lowLiquidityRisk ? 45 : 5;

  return (
    <motion.div
      initial={{ opacity: 0, y: -10 }}
      animate={{ opacity: 1, y: 0 }}
      className={`mt-4 p-4 rounded-xl border ${riskBgColor}`}
    >
      {/* Header */}
      <div
        className="flex items-center justify-between cursor-pointer"
        onClick={() => setExpanded(!expanded)}
      >
        <div className="flex items-center gap-2">
          <Shield className={`w-4 h-4 ${riskColor}`} />
          <span className="font-medium text-white">MEV Protection Analysis</span>
          {mevAnalysis.protectionActive && (
            <span className="px-2 py-0.5 text-xs bg-green-500/20 text-green-400 rounded">ACTIVE</span>
          )}
        </div>
        <div className="flex items-center gap-2">
          <span className={`text-sm font-bold ${riskColor} uppercase`}>
            {risk} Risk
          </span>
          {expanded ? <ChevronUp className="w-4 h-4 text-dark-400" /> : <ChevronDown className="w-4 h-4 text-dark-400" />}
        </div>
      </div>

      {/* Risk Percentages Row */}
      <div className="mt-3 grid grid-cols-3 gap-2">
        <div className="text-center p-2 bg-dark-800/50 rounded">
          <div className="text-lg font-bold text-white">{sandwichRiskPct}%</div>
          <div className="text-xs text-dark-400">Sandwich</div>
        </div>
        <div className="text-center p-2 bg-dark-800/50 rounded">
          <div className="text-lg font-bold text-white">{frontrunRiskPct.toFixed(0)}%</div>
          <div className="text-xs text-dark-400">Frontrun</div>
        </div>
        <div className="text-center p-2 bg-dark-800/50 rounded">
          <div className="text-lg font-bold text-white">{backrunRiskPct}%</div>
          <div className="text-xs text-dark-400">Backrun</div>
        </div>
      </div>

      {/* Price Comparison */}
      <div className="mt-3 p-3 bg-dark-800/30 rounded-lg">
        <div className="text-xs text-dark-400 mb-2 flex items-center gap-1">
          <img src="https://cryptologos.cc/logos/chainlink-link-logo.png" className="w-3 h-3" alt="" />
          Price Comparison (Chainlink vs Pool)
        </div>
        <div className="grid grid-cols-3 gap-4">
          <div>
            <div className="text-xs text-dark-400">Oracle Price</div>
            <div className="text-lg font-bold text-white">${mevAnalysis.oraclePrice?.toFixed(2) || '0.00'}</div>
          </div>
          <div>
            <div className="text-xs text-dark-400">Pool Price</div>
            <div className="text-lg font-bold text-white">${mevAnalysis.poolPrice?.toFixed(2) || '0.00'}</div>
          </div>
          <div>
            <div className="text-xs text-dark-400">Deviation</div>
            <div className={`text-lg font-bold ${mevAnalysis.deviationBps > 50 ? 'text-yellow-400' : 'text-green-400'}`}>
              {mevAnalysis.deviationPercent || '0.00%'}
            </div>
          </div>
        </div>
      </div>

      {/* Expanded Details with Agent Scores */}
      <AnimatePresence>
        {expanded && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            className="mt-4 pt-4 border-t border-dark-700 space-y-4"
          >
            {/* Agent Recommendations */}
            <div>
              <div className="text-sm text-dark-400 mb-2 flex items-center gap-1">
                <Zap className="w-4 h-4 text-accent-400" />
                Real Agent Scores (from chain)
              </div>
              <div className="bg-dark-800/30 rounded-lg p-3">
                {mevAnalysis.agentScores?.length > 0 ? (
                  mevAnalysis.agentScores.map((agent: any, i: number) => (
                    <AgentScoreRow key={i} agent={agent} />
                  ))
                ) : (
                  <div className="text-sm text-dark-400">Loading agent data...</div>
                )}
              </div>
            </div>

            {/* Agent Details */}
            {mevAnalysis.agentScores?.length > 0 && (
              <div className="grid grid-cols-3 gap-2 text-xs">
                {mevAnalysis.agentScores.map((agent: any, i: number) => (
                  <div key={i} className="p-2 bg-dark-800/20 rounded">
                    <div className="font-medium text-white truncate">{agent.agentName?.split(' ')[0]}</div>
                    {Object.entries(agent.details || {}).slice(0, 2).map(([key, val]) => (
                      <div key={key} className="text-dark-400 truncate">
                        {key}: <span className="text-dark-300">{String(val)}</span>
                      </div>
                    ))}
                  </div>
                ))}
              </div>
            )}

            {/* Protection Benefit */}
            <div className="p-3 bg-green-500/10 rounded-lg border border-green-500/30">
              <div className="flex items-center gap-2 text-green-400">
                <CheckCircle className="w-4 h-4" />
                <span className="font-medium">Estimated Savings</span>
              </div>
              <p className="mt-1 text-2xl font-bold text-white">
                ${(mevAnalysis.estimatedSavings || 0).toFixed(2)}
              </p>
              <p className="text-xs text-dark-400 mt-1">
                MEV captured via hook and redistributed to LPs (80%)
              </p>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}


export function SwapInterface() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();

  const [tokenIn, setTokenIn] = useState<Token | null>(null);
  const [tokenOut, setTokenOut] = useState<Token | null>(null);
  const [amountIn, setAmountIn] = useState('');
  const [slippage, setSlippage] = useState(0.5);
  const [mevProtection, setMevProtection] = useState(true);
  const [showSettings, setShowSettings] = useState(false);

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
    isSuccess,
    executeSwap,
    mevAnalysis,
    hash,
    error: swapError
  } = useSwap({
    tokenIn,
    tokenOut,
    amountIn,
    slippage,
    mevProtection,
  });

  // Show toast on success or error
  useEffect(() => {
    if (isSuccess && hash) {
      toast.success('Swap completed!', {
        description: `Transaction: ${hash.slice(0, 10)}...`,
      });
      setAmountIn('');
    }
  }, [isSuccess, hash]);

  useEffect(() => {
    if (swapError) {
      toast.error('Swap failed', {
        description: swapError.slice(0, 100),
      });
    }
  }, [swapError]);

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
      toast.loading('Preparing swap...', { id: 'swap' });
      await executeSwap();
      toast.loading('Waiting for confirmation...', { id: 'swap' });
    } catch (error: any) {
      toast.dismiss('swap');
      console.error('Swap error:', error);
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
                ? 'bg-green-500/20 text-green-400 border border-green-500/30'
                : 'bg-yellow-500/20 text-yellow-400 border border-yellow-500/30'
                }`}
              whileHover={{ scale: 1.05 }}
              onClick={() => setMevProtection(!mevProtection)}
            >
              <Shield className="w-3 h-3" />
              MEV {mevProtection ? 'ON' : 'OFF'}
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
                <div>
                  <label className="text-sm text-dark-400 mb-2 block">Slippage Tolerance</label>
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
                  </div>
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
              <span className="text-white font-medium">
                1 {tokenIn?.symbol} = {quote.rate} {tokenOut?.symbol}
              </span>
            </div>

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

        {/* MEV Analysis Panel with Agent Scores */}
        {mevProtection && mevAnalysis && (
          <MevAnalysisPanel
            mevAnalysis={mevAnalysis}
            isLoading={isQuoting}
          />
        )}

        {/* Error Display */}
        {swapError && (
          <div className="mt-4 p-3 bg-red-500/10 border border-red-500/30 rounded-lg">
            <p className="text-red-400 text-sm">{swapError.slice(0, 150)}</p>
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
              Processing...
            </span>
          ) : !amountIn ? (
            'Enter Amount'
          ) : (
            <span className="flex items-center justify-center gap-2">
              {mevProtection && <Shield className="w-5 h-5" />}
              Swap
            </span>
          )}
        </motion.button>

        {/* Transaction Hash */}
        {hash && (
          <div className="mt-2 text-center">
            <a
              href={`https://sepolia.etherscan.io/tx/${hash}`}
              target="_blank"
              rel="noopener noreferrer"
              className="text-xs text-primary-400 hover:text-primary-300"
            >
              View on Etherscan ↗
            </a>
          </div>
        )}
      </div>
    </motion.div>
  );
}
