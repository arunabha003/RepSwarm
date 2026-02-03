'use client';

import { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { ChevronDown, Search } from 'lucide-react';
import { TOKEN_ADDRESSES } from '@/config/web3';

interface Token {
  address: `0x${string}`;
  symbol: string;
  decimals: number;
  logoURI?: string;
}

interface TokenSelectorProps {
  selectedToken: Token | null;
  onSelect: (token: Token) => void;
  chainId: number;
}

export function TokenSelector({ selectedToken, onSelect, chainId }: TokenSelectorProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [search, setSearch] = useState('');
  
  const tokens = chainId && TOKEN_ADDRESSES[chainId] 
    ? Object.values(TOKEN_ADDRESSES[chainId])
    : [];
  
  const filteredTokens = tokens.filter(token =>
    token.symbol.toLowerCase().includes(search.toLowerCase())
  );
  
  return (
    <div className="relative">
      <motion.button
        onClick={() => setIsOpen(!isOpen)}
        className="flex items-center gap-2 px-3 py-2 rounded-xl bg-dark-700 hover:bg-dark-600 transition-colors"
        whileHover={{ scale: 1.02 }}
        whileTap={{ scale: 0.98 }}
      >
        {selectedToken ? (
          <>
            {selectedToken.logoURI && (
              <img
                src={selectedToken.logoURI}
                alt={selectedToken.symbol}
                className="w-6 h-6 rounded-full"
                onError={(e) => {
                  (e.target as HTMLImageElement).style.display = 'none';
                }}
              />
            )}
            <span className="font-semibold text-white">{selectedToken.symbol}</span>
          </>
        ) : (
          <span className="text-dark-400">Select</span>
        )}
        <ChevronDown className={`w-4 h-4 text-dark-400 transition-transform ${isOpen ? 'rotate-180' : ''}`} />
      </motion.button>
      
      <AnimatePresence>
        {isOpen && (
          <>
            {/* Backdrop */}
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              className="fixed inset-0 z-40"
              onClick={() => setIsOpen(false)}
            />
            
            {/* Dropdown */}
            <motion.div
              initial={{ opacity: 0, y: -10, scale: 0.95 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: -10, scale: 0.95 }}
              className="absolute right-0 top-full mt-2 w-64 glass-card rounded-xl p-2 z-50 shadow-2xl"
            >
              {/* Search */}
              <div className="relative mb-2">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-dark-400" />
                <input
                  type="text"
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  placeholder="Search token..."
                  className="w-full pl-9 pr-4 py-2 bg-dark-800/50 rounded-lg text-sm text-white placeholder:text-dark-500 focus:outline-none focus:ring-2 focus:ring-primary-500"
                />
              </div>
              
              {/* Token List */}
              <div className="max-h-64 overflow-y-auto space-y-1">
                {filteredTokens.map((token) => (
                  <motion.button
                    key={token.address}
                    onClick={() => {
                      onSelect(token);
                      setIsOpen(false);
                      setSearch('');
                    }}
                    className={`w-full flex items-center gap-3 px-3 py-2 rounded-lg transition-colors ${
                      selectedToken?.address === token.address
                        ? 'bg-primary-500/20 text-primary-400'
                        : 'hover:bg-dark-700/50 text-white'
                    }`}
                    whileHover={{ x: 4 }}
                  >
                    {token.logoURI ? (
                      <img
                        src={token.logoURI}
                        alt={token.symbol}
                        className="w-8 h-8 rounded-full"
                        onError={(e) => {
                          (e.target as HTMLImageElement).style.display = 'none';
                        }}
                      />
                    ) : (
                      <div className="w-8 h-8 rounded-full bg-gradient-to-br from-primary-500 to-accent-500 flex items-center justify-center text-sm font-bold">
                        {token.symbol[0]}
                      </div>
                    )}
                    <div className="text-left">
                      <div className="font-semibold">{token.symbol}</div>
                      <div className="text-xs text-dark-400">
                        {token.address.slice(0, 6)}...{token.address.slice(-4)}
                      </div>
                    </div>
                  </motion.button>
                ))}
                
                {filteredTokens.length === 0 && (
                  <div className="py-4 text-center text-dark-400 text-sm">
                    No tokens found
                  </div>
                )}
              </div>
            </motion.div>
          </>
        )}
      </AnimatePresence>
    </div>
  );
}
