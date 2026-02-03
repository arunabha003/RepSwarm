'use client';

import { motion } from 'framer-motion';
import { Header } from '@/components/Header';
import { StatsPanel } from '@/components/StatsPanel';
import {
  LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer,
  AreaChart, Area, BarChart, Bar, PieChart, Pie, Cell
} from 'recharts';
import { Shield, TrendingUp, Users, Zap, DollarSign, Activity, Info, ExternalLink, Database } from 'lucide-react';
import { useProtocolStats, useAgentData, useRewardDistribution } from '@/hooks/useContractData';
import { getContractsForChain, CHAINLINK_FEEDS } from '@/config/web3';
import { useChainId } from 'wagmi';

const COLORS = ['#0ea5e9', '#d946ef', '#22c55e', '#f59e0b'];

// Contract Explorer Component
function ContractExplorer() {
  const chainId = useChainId();
  const contracts = getContractsForChain(chainId);

  const contractList = [
    { name: 'PoolManager', address: contracts.poolManager, description: 'Uniswap v4 Core' },
    { name: 'MevRouterHookV2', address: contracts.mevRouterHook, description: 'MEV Detection & Capture' },
    { name: 'LPFeeAccumulator', address: contracts.lpFeeAccumulator, description: 'LP Fee Distribution' },
    { name: 'SwarmCoordinator', address: contracts.swarmCoordinator, description: 'Intent Orchestration' },
    { name: 'FlashLoanBackrunner', address: contracts.flashLoanBackrunner, description: 'Aave Flash Loans' },
    { name: 'OracleRegistry', address: contracts.oracleRegistry, description: 'Chainlink Integration' },
    { name: 'AgentRegistry', address: contracts.agentRegistry, description: 'ERC-8004 Agents' },
  ];

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.6 }}
      className="glass-card rounded-xl p-6"
    >
      <h3 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
        <Database className="w-5 h-5 text-primary-400" />
        Deployed Contracts
      </h3>
      <p className="text-sm text-dark-400 mb-4">
        All data is fetched directly from these contracts on the Sepolia fork
      </p>

      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-dark-400 border-b border-dark-700">
              <th className="pb-3 font-medium">Contract</th>
              <th className="pb-3 font-medium">Description</th>
              <th className="pb-3 font-medium">Address</th>
            </tr>
          </thead>
          <tbody>
            {contractList.map((contract, i) => (
              <tr key={i} className="border-b border-dark-800 hover:bg-dark-800/30">
                <td className="py-3 text-white font-medium">{contract.name}</td>
                <td className="py-3 text-dark-400">{contract.description}</td>
                <td className="py-3">
                  <a
                    href={`https://sepolia.etherscan.io/address/${contract.address}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-primary-400 hover:text-primary-300 font-mono text-xs flex items-center gap-1"
                  >
                    {contract.address.slice(0, 10)}...{contract.address.slice(-8)}
                    <ExternalLink className="w-3 h-3" />
                  </a>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </motion.div>
  );
}

// MEV Distribution Flow Component
function MevDistributionFlow() {
  const { distribution } = useRewardDistribution();

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.3 }}
      className="glass-card rounded-xl p-6"
    >
      <h3 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
        <DollarSign className="w-5 h-5 text-green-400" />
        MEV Value Flow
      </h3>

      <div className="relative">
        {/* Flow Diagram */}
        <div className="flex flex-col md:flex-row items-center justify-between gap-4 mb-6">
          {/* Source */}
          <div className="text-center p-4 bg-red-500/10 border border-red-500/30 rounded-xl w-full md:w-auto">
            <div className="text-2xl font-bold text-red-400">${(distribution.totalCaptured * 2000).toFixed(0)}</div>
            <div className="text-sm text-dark-400">MEV Detected</div>
            <div className="text-xs text-dark-500 mt-1">Oracle Price Deviation</div>
          </div>

          {/* Arrow */}
          <div className="hidden md:block text-dark-500">→</div>

          {/* Capture */}
          <div className="text-center p-4 bg-purple-500/10 border border-purple-500/30 rounded-xl w-full md:w-auto">
            <div className="text-2xl font-bold text-purple-400">${(distribution.totalCaptured * 2000).toFixed(0)}</div>
            <div className="text-sm text-dark-400">MEV Captured</div>
            <div className="text-xs text-dark-500 mt-1">Hook beforeSwap/afterSwap</div>
          </div>

          {/* Arrow */}
          <div className="hidden md:block text-dark-500">→</div>

          {/* Distribution */}
          <div className="grid grid-cols-3 gap-2 w-full md:w-auto">
            <div className="text-center p-3 bg-blue-500/10 border border-blue-500/30 rounded-lg">
              <div className="text-lg font-bold text-blue-400">{distribution.lpSharePercent}%</div>
              <div className="text-xs text-dark-400">LPs</div>
            </div>
            <div className="text-center p-3 bg-pink-500/10 border border-pink-500/30 rounded-lg">
              <div className="text-lg font-bold text-pink-400">{distribution.treasurySharePercent}%</div>
              <div className="text-xs text-dark-400">Treasury</div>
            </div>
            <div className="text-center p-3 bg-green-500/10 border border-green-500/30 rounded-lg">
              <div className="text-lg font-bold text-green-400">{distribution.keeperSharePercent}%</div>
              <div className="text-xs text-dark-400">Keepers</div>
            </div>
          </div>
        </div>

        {/* Breakdown */}
        <div className="grid grid-cols-3 gap-4 pt-4 border-t border-dark-700">
          <div>
            <div className="text-sm text-dark-400 mb-1">LP Rewards (via donate())</div>
            <div className="text-xl font-bold text-blue-400">
              {distribution.lpShare.toFixed(4)} ETH
            </div>
            <div className="text-xs text-dark-500">
              ≈ ${(distribution.lpShare * 2000).toLocaleString()}
            </div>
          </div>
          <div>
            <div className="text-sm text-dark-400 mb-1">Protocol Treasury</div>
            <div className="text-xl font-bold text-pink-400">
              {distribution.treasuryShare.toFixed(4)} ETH
            </div>
            <div className="text-xs text-dark-500">
              ≈ ${(distribution.treasuryShare * 2000).toLocaleString()}
            </div>
          </div>
          <div>
            <div className="text-sm text-dark-400 mb-1">Keeper Incentives</div>
            <div className="text-xl font-bold text-green-400">
              {distribution.keeperShare.toFixed(4)} ETH
            </div>
            <div className="text-xs text-dark-500">
              ≈ ${(distribution.keeperShare * 2000).toLocaleString()}
            </div>
          </div>
        </div>
      </div>
    </motion.div>
  );
}

// Agent Comparison Component
function AgentComparison() {
  const { agents, isLoading } = useAgentData();

  if (isLoading) {
    return (
      <div className="glass-card rounded-xl p-6 animate-pulse">
        <div className="h-8 bg-dark-700 rounded w-1/3 mb-4" />
        <div className="h-64 bg-dark-700 rounded" />
      </div>
    );
  }

  const chartData = agents.map(agent => ({
    name: agent.type,
    reputation: agent.reputation,
    weight: agent.reputationWeight,
    successRate: agent.successRate,
  }));

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.4 }}
      className="glass-card rounded-xl p-6"
    >
      <h3 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
        <Users className="w-5 h-5 text-accent-400" />
        Agent Performance Comparison
      </h3>
      <ResponsiveContainer width="100%" height={280}>
        <BarChart data={chartData} layout="vertical">
          <XAxis type="number" domain={[0, 100]} stroke="#475569" />
          <YAxis dataKey="name" type="category" stroke="#475569" width={120} />
          <Tooltip
            contentStyle={{
              backgroundColor: 'rgba(30, 41, 59, 0.95)',
              border: '1px solid rgba(100, 116, 139, 0.3)',
              borderRadius: '8px',
              color: '#fff',
            }}
          />
          <Bar dataKey="successRate" name="Success Rate %" fill="#22c55e" radius={[0, 4, 4, 0]} />
          <Bar dataKey="reputation" name="Reputation" fill="#d946ef" radius={[0, 4, 4, 0]} />
        </BarChart>
      </ResponsiveContainer>

      {/* Agent Details Table */}
      <div className="mt-4 pt-4 border-t border-dark-700 overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-dark-400">
              <th className="pb-2 font-medium">Agent</th>
              <th className="pb-2 font-medium">Data Source</th>
              <th className="pb-2 font-medium">Scoring Method</th>
              <th className="pb-2 font-medium">Weight</th>
            </tr>
          </thead>
          <tbody>
            {agents.map((agent, i) => (
              <tr key={i} className="border-t border-dark-800">
                <td className="py-2 text-white font-medium">{agent.name}</td>
                <td className="py-2 text-dark-300">{agent.metrics['Data Source']}</td>
                <td className="py-2 text-dark-300">{agent.metrics['Score Method']}</td>
                <td className="py-2 text-primary-400">{agent.metrics['Weight']}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </motion.div>
  );
}

// Oracle Integration Component  
function OracleIntegration() {
  const oracleFeeds = [
    { pair: 'ETH/USD', address: CHAINLINK_FEEDS.ETH_USD, decimals: 8 },
    { pair: 'USDC/USD', address: CHAINLINK_FEEDS.USDC_USD, decimals: 8 },
    { pair: 'LINK/USD', address: CHAINLINK_FEEDS.LINK_USD, decimals: 8 },
  ];

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.5 }}
      className="glass-card rounded-xl p-6"
    >
      <h3 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
        <img src="https://cryptologos.cc/logos/chainlink-link-logo.png" className="w-5 h-5" alt="" />
        Chainlink Oracle Feeds
      </h3>
      <p className="text-sm text-dark-400 mb-4">
        MEV detection compares pool prices with these oracle feeds to identify arbitrage opportunities
      </p>

      <div className="space-y-3">
        {oracleFeeds.map((feed, i) => (
          <div key={i} className="flex items-center justify-between p-3 bg-dark-800/50 rounded-lg">
            <div className="flex items-center gap-3">
              <div className="w-8 h-8 rounded-full bg-primary-500/20 flex items-center justify-center">
                <span className="text-xs font-bold text-primary-400">{feed.pair.split('/')[0]}</span>
              </div>
              <div>
                <div className="font-medium text-white">{feed.pair}</div>
                <div className="text-xs text-dark-400">Decimals: {feed.decimals}</div>
              </div>
            </div>
            <a
              href={`https://sepolia.etherscan.io/address/${feed.address}`}
              target="_blank"
              rel="noopener noreferrer"
              className="text-primary-400 hover:text-primary-300 text-xs font-mono flex items-center gap-1"
            >
              {feed.address.slice(0, 10)}...
              <ExternalLink className="w-3 h-3" />
            </a>
          </div>
        ))}
      </div>
    </motion.div>
  );
}

export default function AnalyticsPage() {
  const stats = useProtocolStats();

  return (
    <main className="min-h-screen">
      <Header />

      <section className="pt-24 pb-12 px-4">
        <div className="max-w-7xl mx-auto">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
          >
            <h1 className="text-3xl font-bold text-white mb-2">Protocol Analytics</h1>
            <p className="text-dark-400 mb-2">Real-time data from contracts on Sepolia fork</p>
            {stats.lastUpdated && (
              <div className="flex items-center gap-2 text-xs text-dark-500 mb-8">
                <span className="w-2 h-2 bg-green-400 rounded-full animate-pulse" />
                Last updated: {stats.lastUpdated.toLocaleTimeString()}
              </div>
            )}
          </motion.div>

          {/* Overview Stats */}
          <StatsPanel />

          {/* MEV Distribution Flow */}
          <div className="mt-8">
            <MevDistributionFlow />
          </div>

          {/* Charts Grid */}
          <div className="grid lg:grid-cols-2 gap-6 mt-8">
            <AgentComparison />
            <OracleIntegration />
          </div>

          {/* Contract Explorer */}
          <div className="mt-8">
            <ContractExplorer />
          </div>

          {/* Technical Info */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.7 }}
            className="glass-card rounded-xl p-6 mt-8"
          >
            <h3 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
              <Info className="w-5 h-5 text-yellow-400" />
              How Data is Calculated
            </h3>

            <div className="grid md:grid-cols-2 gap-6">
              <div>
                <h4 className="font-medium text-white mb-2">MEV Detection</h4>
                <ul className="text-sm text-dark-400 space-y-1">
                  <li>• Pool price calculated from sqrtPriceX96</li>
                  <li>• Oracle price from Chainlink latestRoundData()</li>
                  <li>• Deviation = |pool - oracle| / oracle × 10000 bps</li>
                  <li>• MEV threshold: 50 bps (0.5%) deviation</li>
                </ul>
              </div>
              <div>
                <h4 className="font-medium text-white mb-2">Reward Distribution</h4>
                <ul className="text-sm text-dark-400 space-y-1">
                  <li>• LP Share: 80% via PoolManager.donate()</li>
                  <li>• Treasury: 10% for protocol development</li>
                  <li>• Keepers: 10% for backrun execution</li>
                  <li>• Distribution happens per pool, per token</li>
                </ul>
              </div>
              <div>
                <h4 className="font-medium text-white mb-2">Agent Scoring</h4>
                <ul className="text-sm text-dark-400 space-y-1">
                  <li>• Each agent calculates route scores</li>
                  <li>• Scores weighted by ERC-8004 reputation</li>
                  <li>• Weighted average determines best path</li>
                  <li>• Feedback updates reputation post-swap</li>
                </ul>
              </div>
              <div>
                <h4 className="font-medium text-white mb-2">Flash Loan Backruns</h4>
                <ul className="text-sm text-dark-400 space-y-1">
                  <li>• Aave V3 flashLoanSimple() for capital</li>
                  <li>• Atomic swap to restore pool price</li>
                  <li>• Profit after loan repayment distributed</li>
                  <li>• No capital at risk for keeper</li>
                </ul>
              </div>
            </div>
          </motion.div>
        </div>
      </section>
    </main>
  );
}
