'use client';

import { motion } from 'framer-motion';
import { Shield, Zap, TrendingUp, Users, ArrowRight } from 'lucide-react';

const features = [
  {
    icon: Shield,
    title: 'MEV Protection',
    description: 'Advanced arbitrage detection protects your swaps from sandwich attacks and front-running.',
    color: 'from-green-500 to-emerald-500',
  },
  {
    icon: Zap,
    title: 'Multi-Agent Routing',
    description: 'AI agents analyze optimal routes, predict slippage, and find the best execution path.',
    color: 'from-primary-500 to-cyan-500',
  },
  {
    icon: TrendingUp,
    title: 'LP Fee Optimization',
    description: 'Captured MEV profits are returned to liquidity providers through automated donations.',
    color: 'from-accent-500 to-pink-500',
  },
  {
    icon: Users,
    title: 'Swarm Intelligence',
    description: 'Decentralized agent network with reputation scoring ensures reliable execution.',
    color: 'from-orange-500 to-amber-500',
  },
];

export function FeaturesSection() {
  return (
    <section className="py-16">
      <div className="text-center mb-12">
        <motion.h2
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          className="text-3xl font-bold text-white mb-4"
        >
          Why Use Swarm Router?
        </motion.h2>
        <motion.p
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ delay: 0.1 }}
          className="text-dark-400 max-w-2xl mx-auto"
        >
          Built on Uniswap v4 hooks, our multi-agent system provides intelligent trade routing
          with real MEV protection.
        </motion.p>
      </div>
      
      <div className="grid md:grid-cols-2 gap-6 max-w-4xl mx-auto px-4">
        {features.map((feature, index) => (
          <motion.div
            key={feature.title}
            initial={{ opacity: 0, y: 20 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ delay: index * 0.1 }}
            className="group glass-card rounded-2xl p-6 hover:glow-blue transition-all duration-300"
          >
            <div className={`w-12 h-12 rounded-xl bg-gradient-to-br ${feature.color} flex items-center justify-center mb-4`}>
              <feature.icon className="w-6 h-6 text-white" />
            </div>
            <h3 className="text-xl font-semibold text-white mb-2">{feature.title}</h3>
            <p className="text-dark-400">{feature.description}</p>
            
            <motion.div
              className="mt-4 flex items-center gap-2 text-primary-400 opacity-0 group-hover:opacity-100 transition-opacity"
              initial={{ x: -10 }}
              whileHover={{ x: 0 }}
            >
              <span className="text-sm font-medium">Learn more</span>
              <ArrowRight className="w-4 h-4" />
            </motion.div>
          </motion.div>
        ))}
      </div>
    </section>
  );
}
