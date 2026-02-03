'use client';

import { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Header } from '@/components/Header';
import {
  Shield, TrendingUp, Activity, CheckCircle,
  AlertTriangle, Clock, Star, Zap, ExternalLink,
  Plus, Info, RefreshCw, ChevronDown, ChevronUp,
  Cpu, Database, Eye
} from 'lucide-react';
import { useAgentData, useProtocolStats } from '@/hooks/useContractData';
import { getContractsForChain } from '@/config/web3';
import { useChainId } from 'wagmi';

// Agent Type Icons
const agentIcons: Record<string, React.ElementType> = {
  FeeOptimizer: TrendingUp,
  MevHunter: Shield,
  SlippagePredictor: Eye,
};

// Agent Type Colors
const agentColors: Record<string, string> = {
  FeeOptimizer: 'from-blue-500 to-cyan-500',
  MevHunter: 'from-purple-500 to-pink-500',
  SlippagePredictor: 'from-green-500 to-emerald-500',
};

// How Agents Work Panel
function HowAgentsWork() {
  const [expanded, setExpanded] = useState(false);

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="glass-card rounded-xl p-6 mb-8"
    >
      <div
        className="flex items-center justify-between cursor-pointer"
        onClick={() => setExpanded(!expanded)}
      >
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-lg bg-gradient-to-br from-primary-500/20 to-accent-500/20 flex items-center justify-center">
            <Info className="w-5 h-5 text-primary-400" />
          </div>
          <div>
            <h3 className="text-lg font-semibold text-white">How Agents Work</h3>
            <p className="text-sm text-dark-400">Understanding the multi-agent swarm system</p>
          </div>
        </div>
        {expanded ? (
          <ChevronUp className="w-5 h-5 text-dark-400" />
        ) : (
          <ChevronDown className="w-5 h-5 text-dark-400" />
        )}
      </div>

      <AnimatePresence>
        {expanded && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            className="mt-6 space-y-6"
          >
            {/* Agent Flow Diagram */}
            <div className="grid md:grid-cols-4 gap-4">
              <div className="text-center p-4 bg-dark-800/50 rounded-xl">
                <div className="w-12 h-12 rounded-full bg-primary-500/20 flex items-center justify-center mx-auto mb-3">
                  <span className="text-primary-400 font-bold text-lg">1</span>
                </div>
                <h4 className="font-medium text-white mb-1">Intent Created</h4>
                <p className="text-xs text-dark-400">User submits swap intent with candidate paths</p>
              </div>

              <div className="text-center p-4 bg-dark-800/50 rounded-xl">
                <div className="w-12 h-12 rounded-full bg-accent-500/20 flex items-center justify-center mx-auto mb-3">
                  <span className="text-accent-400 font-bold text-lg">2</span>
                </div>
                <h4 className="font-medium text-white mb-1">Agents Propose</h4>
                <p className="text-xs text-dark-400">Each agent scores paths using their specialized algorithm</p>
              </div>

              <div className="text-center p-4 bg-dark-800/50 rounded-xl">
                <div className="w-12 h-12 rounded-full bg-green-500/20 flex items-center justify-center mx-auto mb-3">
                  <span className="text-green-400 font-bold text-lg">3</span>
                </div>
                <h4 className="font-medium text-white mb-1">Best Path Selected</h4>
                <p className="text-xs text-dark-400">Weighted consensus based on agent reputation</p>
              </div>

              <div className="text-center p-4 bg-dark-800/50 rounded-xl">
                <div className="w-12 h-12 rounded-full bg-yellow-500/20 flex items-center justify-center mx-auto mb-3">
                  <span className="text-yellow-400 font-bold text-lg">4</span>
                </div>
                <h4 className="font-medium text-white mb-1">Execute & Reward</h4>
                <p className="text-xs text-dark-400">Swap executes, feedback updates agent reputation</p>
              </div>
            </div>

            {/* Agent Type Explanations */}
            <div className="grid md:grid-cols-3 gap-4">
              <div className="p-4 border border-blue-500/30 rounded-xl bg-blue-500/5">
                <div className="flex items-center gap-2 mb-2">
                  <TrendingUp className="w-5 h-5 text-blue-400" />
                  <h4 className="font-medium text-white">Fee Optimizer</h4>
                </div>
                <p className="text-sm text-dark-400">
                  Analyzes LP fees across all pool hops in a path. Calculates total fee cost and scores routes
                  with lower fees higher (more negative score = better).
                </p>
                <div className="mt-3 p-2 bg-dark-800/50 rounded text-xs font-mono text-dark-300">
                  score = -Σ(path.lpFees)
                </div>
              </div>

              <div className="p-4 border border-purple-500/30 rounded-xl bg-purple-500/5">
                <div className="flex items-center gap-2 mb-2">
                  <Shield className="w-5 h-5 text-purple-400" />
                  <h4 className="font-medium text-white">MEV Hunter</h4>
                </div>
                <p className="text-sm text-dark-400">
                  Compares pool prices with Chainlink oracle prices. Detects MEV opportunities based on
                  price deviation and arbitrage potential.
                </p>
                <div className="mt-3 p-2 bg-dark-800/50 rounded text-xs font-mono text-dark-300">
                  risk = |poolPrice - oraclePrice| / oraclePrice
                </div>
              </div>

              <div className="p-4 border border-green-500/30 rounded-xl bg-green-500/5">
                <div className="flex items-center gap-2 mb-2">
                  <Eye className="w-5 h-5 text-green-400" />
                  <h4 className="font-medium text-white">Slippage Predictor</h4>
                </div>
                <p className="text-sm text-dark-400">
                  Uses Uniswap v4 SwapMath to simulate the actual swap. Predicts real output amount,
                  price impact, and slippage before execution.
                </p>
                <div className="mt-3 p-2 bg-dark-800/50 rounded text-xs font-mono text-dark-300">
                  slippage = (expected - simulated) / expected
                </div>
              </div>
            </div>

            {/* ERC-8004 Explanation */}
            <div className="p-4 bg-gradient-to-r from-primary-500/10 to-accent-500/10 rounded-xl border border-primary-500/20">
              <div className="flex items-center gap-2 mb-2">
                <Database className="w-5 h-5 text-primary-400" />
                <h4 className="font-medium text-white">ERC-8004 Identity & Reputation</h4>
              </div>
              <p className="text-sm text-dark-400 mb-3">
                Each agent is registered with the ERC-8004 standard on Sepolia. This provides:
              </p>
              <div className="grid md:grid-cols-2 gap-3">
                <div className="flex gap-2">
                  <CheckCircle className="w-4 h-4 text-green-400 flex-shrink-0 mt-0.5" />
                  <div>
                    <span className="text-sm text-white">On-chain Identity</span>
                    <p className="text-xs text-dark-400">Verifiable agent registration via NFT</p>
                  </div>
                </div>
                <div className="flex gap-2">
                  <CheckCircle className="w-4 h-4 text-green-400 flex-shrink-0 mt-0.5" />
                  <div>
                    <span className="text-sm text-white">Reputation Tracking</span>
                    <p className="text-xs text-dark-400">Feedback-based scoring after swaps</p>
                  </div>
                </div>
                <div className="flex gap-2">
                  <CheckCircle className="w-4 h-4 text-green-400 flex-shrink-0 mt-0.5" />
                  <div>
                    <span className="text-sm text-white">Weighted Voting</span>
                    <p className="text-xs text-dark-400">Higher reputation = more influence</p>
                  </div>
                </div>
                <div className="flex gap-2">
                  <CheckCircle className="w-4 h-4 text-green-400 flex-shrink-0 mt-0.5" />
                  <div>
                    <span className="text-sm text-white">Permissionless</span>
                    <p className="text-xs text-dark-400">Anyone can register an agent</p>
                  </div>
                </div>
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}

// Agent Card Component
function AgentCard({ agent, index }: { agent: any; index: number }) {
  const [expanded, setExpanded] = useState(false);
  const chainId = useChainId();
  const contracts = getContractsForChain(chainId);

  const Icon = agentIcons[agent.type] || Zap;
  const gradientColor = agentColors[agent.type] || 'from-primary-500 to-accent-500';

  const statusColor = agent.status === 'active'
    ? 'bg-green-500'
    : agent.status === 'idle'
      ? 'bg-yellow-500'
      : 'bg-red-500';

  const explorerUrl = `https://sepolia.etherscan.io/address/${agent.address}`;

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: index * 0.1 }}
      className="glass-card rounded-xl p-6 hover:glow-blue transition-all duration-300"
    >
      <div className="flex items-start justify-between mb-4">
        <div className="flex items-center gap-3">
          <div className={`w-12 h-12 rounded-xl bg-gradient-to-br ${gradientColor} flex items-center justify-center`}>
            <Icon className="w-6 h-6 text-white" />
          </div>
          <div>
            <h3 className="text-lg font-semibold text-white">{agent.name}</h3>
            <div className="flex items-center gap-2 text-sm text-dark-400">
              <a
                href={explorerUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="hover:text-primary-400 flex items-center gap-1"
              >
                {agent.address.slice(0, 6)}...{agent.address.slice(-4)}
                <ExternalLink className="w-3 h-3" />
              </a>
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
          <div className="text-lg font-semibold text-white">{agent.agentId || 'N/A'}</div>
          <div className="text-xs text-dark-400">ERC-8004 ID</div>
        </div>
        <div className="text-center p-3 bg-dark-800/50 rounded-lg">
          <div className="text-lg font-semibold text-green-400">{agent.successRate.toFixed(1)}%</div>
          <div className="text-xs text-dark-400">Success</div>
        </div>
        <div className="text-center p-3 bg-dark-800/50 rounded-lg">
          <div className="text-lg font-semibold text-white">{agent.reputationWeight.toFixed(0)}%</div>
          <div className="text-xs text-dark-400">Weight</div>
        </div>
      </div>

      {/* Expandable Details */}
      <button
        onClick={() => setExpanded(!expanded)}
        className="w-full flex items-center justify-center gap-1 py-2 text-sm text-dark-400 hover:text-white transition-colors"
      >
        {expanded ? 'Hide Details' : 'Show Details'}
        {expanded ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
      </button>

      <AnimatePresence>
        {expanded && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            className="border-t border-dark-700 pt-4 mt-2"
          >
            <h4 className="text-sm font-medium text-dark-300 mb-3">Technical Details</h4>
            <div className="space-y-2">
              {Object.entries(agent.metrics).map(([key, value]) => (
                <div key={key} className="flex justify-between text-sm">
                  <span className="text-dark-400">{key}</span>
                  <span className="text-white font-medium">{value as string}</span>
                </div>
              ))}
            </div>

            {/* Contract Link */}
            <div className="mt-4 p-3 bg-dark-800/50 rounded-lg">
              <div className="text-xs text-dark-400 mb-1">Contract Address</div>
              <a
                href={explorerUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="text-sm text-primary-400 hover:text-primary-300 font-mono flex items-center gap-1"
              >
                {agent.address}
                <ExternalLink className="w-3 h-3" />
              </a>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}

// Register Agent Section
function RegisterAgentSection() {
  const chainId = useChainId();
  const contracts = getContractsForChain(chainId);

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.5 }}
      className="mt-8"
    >
      <div className="glass-card rounded-xl p-8 max-w-3xl mx-auto">
        <div className="text-center mb-6">
          <h3 className="text-xl font-semibold text-white mb-2">
            Want to run an agent?
          </h3>
          <p className="text-dark-400">
            Deploy your own agent contract and register it with the ERC-8004 registry.
          </p>
        </div>

        <div className="grid md:grid-cols-3 gap-4 mb-6">
          <div className="p-4 bg-dark-800/50 rounded-xl text-center">
            <Cpu className="w-8 h-8 text-primary-400 mx-auto mb-2" />
            <h4 className="font-medium text-white mb-1">1. Deploy Contract</h4>
            <p className="text-xs text-dark-400">
              Implement ISwarmAgent interface
            </p>
          </div>
          <div className="p-4 bg-dark-800/50 rounded-xl text-center">
            <Database className="w-8 h-8 text-accent-400 mx-auto mb-2" />
            <h4 className="font-medium text-white mb-1">2. Register Identity</h4>
            <p className="text-xs text-dark-400">
              Get ERC-8004 agent ID on Sepolia
            </p>
          </div>
          <div className="p-4 bg-dark-800/50 rounded-xl text-center">
            <Zap className="w-8 h-8 text-green-400 mx-auto mb-2" />
            <h4 className="font-medium text-white mb-1">3. Start Earning</h4>
            <p className="text-xs text-dark-400">
              Propose on intents, build reputation
            </p>
          </div>
        </div>

        <div className="flex flex-col sm:flex-row gap-3 justify-center">
          <a
            href="https://github.com"
            target="_blank"
            rel="noopener noreferrer"
            className="px-6 py-3 rounded-xl bg-gradient-to-r from-primary-500 to-accent-500 text-white font-semibold hover:from-primary-400 hover:to-accent-400 transition-all text-center"
          >
            View Agent Template
          </a>
          <a
            href={`https://sepolia.etherscan.io/address/${contracts.agentRegistry}`}
            target="_blank"
            rel="noopener noreferrer"
            className="px-6 py-3 rounded-xl border border-dark-600 text-white font-semibold hover:bg-dark-700 transition-all flex items-center justify-center gap-2"
          >
            View Registry
            <ExternalLink className="w-4 h-4" />
          </a>
        </div>
      </div>
    </motion.div>
  );
}

export default function AgentsPage() {
  const { agents, isLoading, refetch } = useAgentData();
  const stats = useProtocolStats();
  const chainId = useChainId();
  const contracts = getContractsForChain(chainId);
  const [isRefreshing, setIsRefreshing] = useState(false);

  const handleRefresh = async () => {
    setIsRefreshing(true);
    await refetch();
    await new Promise(r => setTimeout(r, 500));
    setIsRefreshing(false);
  };

  const activeAgents = agents.filter(a => a.status === 'active').length;
  const avgReputation = agents.length > 0
    ? Math.round(agents.reduce((sum, a) => sum + a.reputation, 0) / agents.length)
    : 0;

  return (
    <main className="min-h-screen">
      <Header />

      <section className="pt-24 pb-12 px-4">
        <div className="max-w-7xl mx-auto">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            className="flex items-center justify-between mb-8"
          >
            <div>
              <h1 className="text-3xl font-bold text-white mb-2">Agent Network</h1>
              <p className="text-dark-400">
                Real-time data from deployed contracts on Sepolia fork
              </p>
            </div>
            <motion.button
              onClick={handleRefresh}
              className="p-2 rounded-lg hover:bg-dark-700/50 transition-colors"
              whileHover={{ scale: 1.1 }}
              animate={isRefreshing ? { rotate: 360 } : {}}
              transition={{ duration: 1, repeat: isRefreshing ? Infinity : 0 }}
            >
              <RefreshCw className={`w-5 h-5 ${isRefreshing ? 'text-primary-400' : 'text-dark-400'}`} />
            </motion.button>
          </motion.div>

          {/* How Agents Work - Collapsible */}
          <HowAgentsWork />

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
              <div className="text-2xl font-bold text-white">
                {isLoading ? '...' : `${activeAgents} / ${agents.length}`}
              </div>
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
                <span className="text-sm text-dark-400">Total Proposals</span>
              </div>
              <div className="text-2xl font-bold text-white">
                {stats.isLoading ? '...' : stats.totalProposals.toLocaleString()}
              </div>
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
              <div className="text-2xl font-bold text-white">
                {isLoading ? '...' : avgReputation}
              </div>
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
              <div className="text-2xl font-bold text-white">
                ${stats.totalMevCapturedUsd.toLocaleString(undefined, { maximumFractionDigits: 0 })}
              </div>
            </motion.div>
          </div>

          {/* Agent Cards */}
          {isLoading ? (
            <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
              {[1, 2, 3].map((i) => (
                <div key={i} className="glass-card rounded-xl p-6 animate-pulse">
                  <div className="h-12 bg-dark-700 rounded-xl mb-4" />
                  <div className="h-4 bg-dark-700 rounded w-3/4 mb-2" />
                  <div className="h-4 bg-dark-700 rounded w-1/2" />
                </div>
              ))}
            </div>
          ) : (
            <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
              {agents.map((agent, index) => (
                <AgentCard key={agent.address} agent={agent} index={index} />
              ))}
            </div>
          )}

          {/* Register New Agent CTA */}
          <RegisterAgentSection />
        </div>
      </section>
    </main>
  );
}
