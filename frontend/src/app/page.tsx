'use client';

import { motion } from 'framer-motion';
import { Header } from '@/components/Header';
import { SwapInterface } from '@/components/SwapInterface';
import { FeaturesSection } from '@/components/FeaturesSection';
import { StatsPanel } from '@/components/StatsPanel';
import { useProtocolStats } from '@/hooks/useContractData';
import { Shield, TrendingUp, Activity } from 'lucide-react';

export default function Home() {
  const stats = useProtocolStats();

  return (
    <main className="min-h-screen">
      <Header />

      {/* Hero Section */}
      <section className="pt-24 pb-12 px-4">
        <div className="max-w-7xl mx-auto">
          <div className="grid lg:grid-cols-2 gap-12 items-center">
            {/* Left: Text */}
            <motion.div
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ duration: 0.6 }}
            >
              <h1 className="text-4xl md:text-5xl lg:text-6xl font-bold text-white leading-tight mb-6">
                <span className="bg-gradient-to-r from-primary-400 via-accent-400 to-primary-400 bg-clip-text text-transparent">
                  Multi-Agent
                </span>
                <br />
                Trade Router
              </h1>
              <p className="text-lg text-dark-300 mb-8 max-w-lg">
                Swap with confidence using our AI-powered agent swarm.
                MEV protection, optimal routing, and LP rewards — all built on Uniswap v4.
              </p>

              {/* Live Stats from Contracts */}
              <div className="flex gap-8 text-center">
                <div>
                  <div className="flex items-center justify-center gap-2">
                    {stats.isLoading ? (
                      <div className="h-8 w-16 bg-dark-700 rounded animate-pulse" />
                    ) : (
                      <span className="text-2xl font-bold text-white">
                        ${stats.volume24hUsd.toLocaleString(undefined, { maximumFractionDigits: 0 })}
                      </span>
                    )}
                  </div>
                  <div className="text-sm text-dark-400 flex items-center gap-1 justify-center">
                    <TrendingUp className="w-3 h-3" />
                    Volume Protected
                  </div>
                </div>
                <div>
                  <div className="flex items-center justify-center gap-2">
                    {stats.isLoading ? (
                      <div className="h-8 w-16 bg-dark-700 rounded animate-pulse" />
                    ) : (
                      <span className="text-2xl font-bold text-white">
                        ${stats.lpFeesDistributedUsd.toLocaleString(undefined, { maximumFractionDigits: 0 })}
                      </span>
                    )}
                  </div>
                  <div className="text-sm text-dark-400 flex items-center gap-1 justify-center">
                    <Shield className="w-3 h-3" />
                    MEV Returned to LPs
                  </div>
                </div>
                <div>
                  <div className="flex items-center justify-center gap-2">
                    {stats.isLoading ? (
                      <div className="h-8 w-16 bg-dark-700 rounded animate-pulse" />
                    ) : (
                      <span className="text-2xl font-bold text-white">
                        {stats.swapsProtected.toLocaleString()}
                      </span>
                    )}
                  </div>
                  <div className="text-sm text-dark-400 flex items-center gap-1 justify-center">
                    <Activity className="w-3 h-3" />
                    Swaps Secured
                  </div>
                </div>
              </div>

              {/* Live indicator */}
              {stats.lastUpdated && (
                <div className="mt-4 flex items-center gap-2 text-xs text-dark-500">
                  <span className="w-2 h-2 bg-green-400 rounded-full animate-pulse" />
                  Live data from contracts
                </div>
              )}
            </motion.div>

            {/* Right: Swap Interface */}
            <motion.div
              initial={{ opacity: 0, x: 20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ duration: 0.6, delay: 0.2 }}
            >
              <SwapInterface />
            </motion.div>
          </div>
        </div>
      </section>

      {/* Stats Section */}
      <section className="py-12 px-4">
        <div className="max-w-7xl mx-auto">
          <StatsPanel />
        </div>
      </section>

      {/* Features Section */}
      <FeaturesSection />

      {/* How It Works */}
      <section className="py-16 px-4">
        <div className="max-w-4xl mx-auto text-center">
          <motion.h2
            initial={{ opacity: 0, y: 20 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            className="text-3xl font-bold text-white mb-12"
          >
            How It Works
          </motion.h2>

          <div className="grid md:grid-cols-3 gap-8">
            {[
              {
                step: '01',
                title: 'Submit Intent',
                description: 'Define your swap parameters with optional MEV protection enabled. Our agents analyze multiple routing options.',
              },
              {
                step: '02',
                title: 'Agent Analysis',
                description: 'Three specialized agents score routes: Fee Optimizer, MEV Hunter (using Chainlink oracles), and Slippage Predictor (using SwapMath).',
              },
              {
                step: '03',
                title: 'Protected Execution',
                description: 'Swap executes through MEV-protected hook. Captured MEV is redistributed: 80% to LPs, 10% treasury, 10% keepers.',
              },
            ].map((item, index) => (
              <motion.div
                key={item.step}
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ delay: index * 0.1 }}
                className="relative"
              >
                <div className="text-6xl font-bold text-dark-800 mb-4">{item.step}</div>
                <h3 className="text-xl font-semibold text-white mb-2">{item.title}</h3>
                <p className="text-dark-400">{item.description}</p>
              </motion.div>
            ))}
          </div>
        </div>
      </section>

      {/* Technical Details Section */}
      <section className="py-16 px-4 bg-dark-900/50">
        <div className="max-w-6xl mx-auto">
          <motion.h2
            initial={{ opacity: 0, y: 20 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            className="text-3xl font-bold text-white mb-8 text-center"
          >
            Built on Real Infrastructure
          </motion.h2>

          <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-6">
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              className="glass-card rounded-xl p-6 text-center"
            >
              <img
                src="https://cryptologos.cc/logos/uniswap-uni-logo.png"
                alt="Uniswap"
                className="w-12 h-12 mx-auto mb-3"
              />
              <h3 className="font-semibold text-white mb-1">Uniswap v4</h3>
              <p className="text-sm text-dark-400">
                Hook-based MEV protection using beforeSwap/afterSwap
              </p>
            </motion.div>

            <motion.div
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ delay: 0.1 }}
              className="glass-card rounded-xl p-6 text-center"
            >
              <img
                src="https://cryptologos.cc/logos/chainlink-link-logo.png"
                alt="Chainlink"
                className="w-12 h-12 mx-auto mb-3"
              />
              <h3 className="font-semibold text-white mb-1">Chainlink Oracles</h3>
              <p className="text-sm text-dark-400">
                Real price feeds for MEV opportunity detection
              </p>
            </motion.div>

            <motion.div
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ delay: 0.2 }}
              className="glass-card rounded-xl p-6 text-center"
            >
              <img
                src="https://cryptologos.cc/logos/aave-aave-logo.png"
                alt="Aave"
                className="w-12 h-12 mx-auto mb-3"
              />
              <h3 className="font-semibold text-white mb-1">Aave v3</h3>
              <p className="text-sm text-dark-400">
                Flash loans for capital-efficient backrunning
              </p>
            </motion.div>

            <motion.div
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ delay: 0.3 }}
              className="glass-card rounded-xl p-6 text-center"
            >
              <div className="w-12 h-12 mx-auto mb-3 rounded-full bg-gradient-to-br from-primary-500 to-accent-500 flex items-center justify-center text-white font-bold">
                8004
              </div>
              <h3 className="font-semibold text-white mb-1">ERC-8004</h3>
              <p className="text-sm text-dark-400">
                On-chain agent identity & reputation
              </p>
            </motion.div>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="py-8 px-4 border-t border-dark-800">
        <div className="max-w-7xl mx-auto flex flex-col md:flex-row justify-between items-center gap-4">
          <div className="text-dark-400 text-sm">
            Built for ETH Global HackMoney 2024 · Powered by Uniswap v4
          </div>
          <div className="flex gap-6">
            <a href="#" className="text-dark-400 hover:text-white transition-colors">
              Docs
            </a>
            <a href="#" className="text-dark-400 hover:text-white transition-colors">
              GitHub
            </a>
            <a href="#" className="text-dark-400 hover:text-white transition-colors">
              Twitter
            </a>
          </div>
        </div>
      </footer>
    </main>
  );
}
