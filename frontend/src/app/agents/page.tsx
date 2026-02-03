'use client';

import { motion } from 'framer-motion';
import { Header } from '@/components/Header';
import { 
  Shield, TrendingUp, Activity, CheckCircle, 
  AlertTriangle, Clock, Star, Zap 
} from 'lucide-react';

const agents = [
  {
    name: 'Fee Optimizer Agent',
    address: '0x1234...5678',
    type: 'FeeOptimizer',
    status: 'active',
    reputation: 98,
    totalTasks: 1234,
    successRate: 99.2,
    lastActive: '2 min ago',
    description: 'Dynamically adjusts pool fees based on volatility and market conditions.',
    metrics: {
      feesSaved: '$12,450',
      optimizations: 892,
      avgImprovement: '15%',
    },
  },
  {
    name: 'MEV Hunter Agent',
    address: '0x2345...6789',
    type: 'MevHunter',
    status: 'active',
    reputation: 95,
    totalTasks: 987,
    successRate: 97.8,
    lastActive: '5 min ago',
    description: 'Detects and captures MEV opportunities, returning profits to LPs.',
    metrics: {
      mevCaptured: '$48,200',
      opportunities: 456,
      lpDonations: '$38,560',
    },
  },
  {
    name: 'Slippage Predictor',
    address: '0x3456...7890',
    type: 'SlippagePredictor',
    status: 'active',
    reputation: 92,
    totalTasks: 2345,
    successRate: 94.5,
    lastActive: '1 min ago',
    description: 'Uses ML to predict slippage and recommend optimal trade sizes.',
    metrics: {
      predictions: 2345,
      accuracy: '94.5%',
      avgImprovement: '0.3%',
    },
  },
  {
    name: 'Route Analyzer',
    address: '0x4567...8901',
    type: 'RouteAnalyzer',
    status: 'idle',
    reputation: 88,
    totalTasks: 567,
    successRate: 91.2,
    lastActive: '15 min ago',
    description: 'Finds optimal multi-hop routes across different liquidity sources.',
    metrics: {
      routesFound: 567,
      gasOptimized: '25%',
      avgSavings: '$8.50',
    },
  },
];

function AgentCard({ agent, index }: { agent: typeof agents[0]; index: number }) {
  const statusColor = agent.status === 'active' 
    ? 'bg-green-500' 
    : agent.status === 'idle' 
    ? 'bg-yellow-500' 
    : 'bg-red-500';
  
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: index * 0.1 }}
      className="glass-card rounded-xl p-6 hover:glow-blue transition-all duration-300"
    >
      <div className="flex items-start justify-between mb-4">
        <div className="flex items-center gap-3">
          <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-primary-500 to-accent-500 flex items-center justify-center">
            <Zap className="w-6 h-6 text-white" />
          </div>
          <div>
            <h3 className="text-lg font-semibold text-white">{agent.name}</h3>
            <div className="flex items-center gap-2 text-sm text-dark-400">
              <span>{agent.address}</span>
              <span className={`w-2 h-2 rounded-full ${statusColor}`} />
              <span className="capitalize">{agent.status}</span>
            </div>
          </div>
        </div>
        
        <div className="flex items-center gap-1">
          <Star className="w-4 h-4 text-yellow-400 fill-yellow-400" />
          <span className="font-semibold text-white">{agent.reputation}</span>
        </div>
      </div>
      
      <p className="text-dark-400 text-sm mb-4">{agent.description}</p>
      
      {/* Stats */}
      <div className="grid grid-cols-3 gap-4 mb-4">
        <div className="text-center p-3 bg-dark-800/50 rounded-lg">
          <div className="text-lg font-semibold text-white">{agent.totalTasks}</div>
          <div className="text-xs text-dark-400">Tasks</div>
        </div>
        <div className="text-center p-3 bg-dark-800/50 rounded-lg">
          <div className="text-lg font-semibold text-green-400">{agent.successRate}%</div>
          <div className="text-xs text-dark-400">Success</div>
        </div>
        <div className="text-center p-3 bg-dark-800/50 rounded-lg">
          <div className="text-lg font-semibold text-white flex items-center justify-center gap-1">
            <Clock className="w-3 h-3" />
            {agent.lastActive}
          </div>
          <div className="text-xs text-dark-400">Last Active</div>
        </div>
      </div>
      
      {/* Type-specific Metrics */}
      <div className="border-t border-dark-700 pt-4">
        <h4 className="text-sm font-medium text-dark-300 mb-2">Performance Metrics</h4>
        <div className="space-y-2">
          {Object.entries(agent.metrics).map(([key, value]) => (
            <div key={key} className="flex justify-between text-sm">
              <span className="text-dark-400 capitalize">{key.replace(/([A-Z])/g, ' $1').trim()}</span>
              <span className="text-white font-medium">{value}</span>
            </div>
          ))}
        </div>
      </div>
    </motion.div>
  );
}

export default function AgentsPage() {
  const activeAgents = agents.filter(a => a.status === 'active').length;
  const totalTasks = agents.reduce((sum, a) => sum + a.totalTasks, 0);
  const avgReputation = Math.round(agents.reduce((sum, a) => sum + a.reputation, 0) / agents.length);
  
  return (
    <main className="min-h-screen">
      <Header />
      
      <section className="pt-24 pb-12 px-4">
        <div className="max-w-7xl mx-auto">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
          >
            <h1 className="text-3xl font-bold text-white mb-2">Agent Network</h1>
            <p className="text-dark-400 mb-8">
              Our decentralized swarm of AI agents working to protect your trades
            </p>
          </motion.div>
          
          {/* Overview Stats */}
          <div className="grid md:grid-cols-4 gap-4 mb-8">
            <motion.div
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              className="glass-card rounded-xl p-4"
            >
              <div className="flex items-center gap-3 mb-2">
                <div className="w-10 h-10 rounded-lg bg-green-500/20 flex items-center justify-center">
                  <Activity className="w-5 h-5 text-green-400" />
                </div>
                <span className="text-sm text-dark-400">Active Agents</span>
              </div>
              <div className="text-2xl font-bold text-white">{activeAgents} / {agents.length}</div>
            </motion.div>
            
            <motion.div
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ delay: 0.1 }}
              className="glass-card rounded-xl p-4"
            >
              <div className="flex items-center gap-3 mb-2">
                <div className="w-10 h-10 rounded-lg bg-primary-500/20 flex items-center justify-center">
                  <CheckCircle className="w-5 h-5 text-primary-400" />
                </div>
                <span className="text-sm text-dark-400">Total Tasks</span>
              </div>
              <div className="text-2xl font-bold text-white">{totalTasks.toLocaleString()}</div>
            </motion.div>
            
            <motion.div
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ delay: 0.2 }}
              className="glass-card rounded-xl p-4"
            >
              <div className="flex items-center gap-3 mb-2">
                <div className="w-10 h-10 rounded-lg bg-yellow-500/20 flex items-center justify-center">
                  <Star className="w-5 h-5 text-yellow-400" />
                </div>
                <span className="text-sm text-dark-400">Avg Reputation</span>
              </div>
              <div className="text-2xl font-bold text-white">{avgReputation}</div>
            </motion.div>
            
            <motion.div
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ delay: 0.3 }}
              className="glass-card rounded-xl p-4"
            >
              <div className="flex items-center gap-3 mb-2">
                <div className="w-10 h-10 rounded-lg bg-accent-500/20 flex items-center justify-center">
                  <Shield className="w-5 h-5 text-accent-400" />
                </div>
                <span className="text-sm text-dark-400">MEV Protected</span>
              </div>
              <div className="text-2xl font-bold text-white">$48.2K</div>
            </motion.div>
          </div>
          
          {/* Agent Cards */}
          <div className="grid md:grid-cols-2 gap-6">
            {agents.map((agent, index) => (
              <AgentCard key={agent.address} agent={agent} index={index} />
            ))}
          </div>
          
          {/* Register New Agent CTA */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.5 }}
            className="mt-8 text-center"
          >
            <div className="glass-card rounded-xl p-8 max-w-2xl mx-auto">
              <h3 className="text-xl font-semibold text-white mb-2">
                Want to run an agent?
              </h3>
              <p className="text-dark-400 mb-4">
                Join our decentralized network and earn rewards for protecting swaps.
              </p>
              <button className="px-6 py-3 rounded-xl bg-gradient-to-r from-primary-500 to-accent-500 text-white font-semibold hover:from-primary-400 hover:to-accent-400 transition-all">
                Register Agent
              </button>
            </div>
          </motion.div>
        </div>
      </section>
    </main>
  );
}
