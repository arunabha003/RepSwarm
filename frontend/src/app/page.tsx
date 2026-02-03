'use client';

import { motion } from 'framer-motion';
import { Header } from '@/components/Header';
import { SwapInterface } from '@/components/SwapInterface';
import { FeaturesSection } from '@/components/FeaturesSection';
import { StatsPanel } from '@/components/StatsPanel';

export default function Home() {
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
              
              {/* Quick stats */}
              <div className="flex gap-8 text-center">
                <div>
                  <div className="text-2xl font-bold text-white">$12M+</div>
                  <div className="text-sm text-dark-400">Volume Protected</div>
                </div>
                <div>
                  <div className="text-2xl font-bold text-white">$48K</div>
                  <div className="text-sm text-dark-400">MEV Returned to LPs</div>
                </div>
                <div>
                  <div className="text-2xl font-bold text-white">2,847</div>
                  <div className="text-sm text-dark-400">Swaps Secured</div>
                </div>
              </div>
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
                description: 'Define your swap parameters with optional MEV protection enabled.',
              },
              {
                step: '02',
                title: 'Agent Analysis',
                description: 'Our AI agents analyze routes, predict slippage, and detect MEV opportunities.',
              },
              {
                step: '03',
                title: 'Protected Execution',
                description: 'Swap executes through MEV-protected hook, profits returned to LPs.',
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
