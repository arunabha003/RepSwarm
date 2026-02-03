'use client';

import { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { ArrowDown, Settings, Info, Loader2, Shield, CheckCircle, AlertTriangle } from 'lucide-react';
import { useAccount, useBalance, useChainId } from 'wagmi';
import { formatUnits, parseUnits } from 'viem';
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
              className={`flex items-center gap-1 px-2 py-1 rounded-lg text-xs font-medium ${
                mevProtection 
                  ? 'bg-green-500/20 text-green-400' 
                  : 'bg-yellow-500/20 text-yellow-400'
              }`}
              whileHover={{ scale: 1.05 }}
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
                        className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                          slippage === value
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
                    <Info className="w-3 h-3 text-dark-500" />
                  </div>
                  <button
                    onClick={() => setMevProtection(!mevProtection)}
                    className={`relative w-12 h-6 rounded-full transition-colors ${
                      mevProtection ? 'bg-primary-500' : 'bg-dark-600'
                    }`}
                  >
                    <motion.div
                      className="absolute top-1 w-4 h-4 rounded-full bg-white"
                      animate={{ left: mevProtection ? '1.5rem' : '0.25rem' }}
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
            {mevAnalysis && (
              <div className="flex items-center justify-between text-sm">
                <span className="text-dark-400 flex items-center gap-1">
                  <Shield className="w-3 h-3" />
                  MEV Risk
                </span>
                <span className={
                  mevAnalysis.risk === 'low' ? 'text-green-400' :
                  mevAnalysis.risk === 'medium' ? 'text-yellow-400' : 'text-red-400'
                }>
                  {mevAnalysis.risk.toUpperCase()}
                  {mevAnalysis.potentialSavings > 0 && (
                    <span className="text-green-400 ml-1">
                      (Saving ~${mevAnalysis.potentialSavings.toFixed(2)})
                    </span>
                  )}
                </span>
              </div>
            )}
          </motion.div>
        )}
        
        {/* Swap Button */}
        <motion.button
          onClick={handleSwap}
          disabled={!isConnected || !amountIn || isSwapping || isQuoting}
          className={`w-full mt-4 py-4 rounded-xl font-semibold text-lg transition-all ${
            !isConnected
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
            'Swap'
          )}
        </motion.button>
      </div>
    </motion.div>
  );
}
