'use client';

import { motion } from 'framer-motion';
import { AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer, PieChart, Pie, Cell } from 'recharts';
import { TrendingUp, Shield, Coins, Activity, RefreshCw, Info, DollarSign, Users } from 'lucide-react';
import { useProtocolStats, useRewardDistribution } from '@/hooks/useContractData';
import { useState } from 'react';

interface StatCardProps {
  icon: React.ElementType;
  title: string;
  value: string;
  subValue?: string;
  change?: string;
  positive?: boolean;
  tooltip?: string;
  isLoading?: boolean;
}

function StatCard({ icon: Icon, title, value, subValue, change, positive, tooltip, isLoading }: StatCardProps) {
  const [showTooltip, setShowTooltip] = useState(false);

  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      className="glass-card rounded-xl p-4 relative"
    >
      <div className="flex items-center justify-between mb-2">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-lg bg-gradient-to-br from-primary-500/20 to-accent-500/20 flex items-center justify-center">
            <Icon className="w-5 h-5 text-primary-400" />
          </div>
          <span className="text-sm text-dark-400">{title}</span>
        </div>
        {tooltip && (
          <button
            onMouseEnter={() => setShowTooltip(true)}
            onMouseLeave={() => setShowTooltip(false)}
            className="text-dark-500 hover:text-dark-300"
          >
            <Info className="w-4 h-4" />
          </button>
        )}
      </div>

      {showTooltip && tooltip && (
        <div className="absolute right-4 top-12 z-10 bg-dark-800 border border-dark-600 rounded-lg p-2 text-xs text-dark-300 max-w-[200px]">
          {tooltip}
        </div>
      )}

      {isLoading ? (
        <div className="h-8 bg-dark-700 rounded animate-pulse" />
      ) : (
        <>
          <div className="text-2xl font-bold text-white">{value}</div>
          {subValue && <div className="text-sm text-dark-400">{subValue}</div>}
        </>
      )}
      {change && !isLoading && (
        <div className={`text-sm mt-1 ${positive ? 'text-green-400' : 'text-red-400'}`}>
          {positive ? '+' : ''}{change}
        </div>
      )}
    </motion.div>
  );
}

// Reward Distribution Component
function RewardDistributionCard() {
  const { distribution, isLoading } = useRewardDistribution();

  const pieData = [
    { name: 'LP Rewards', value: distribution.lpSharePercent, color: '#0ea5e9' },
    { name: 'Treasury', value: distribution.treasurySharePercent, color: '#d946ef' },
    { name: 'Keepers', value: distribution.keeperSharePercent, color: '#22c55e' },
  ];

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.3 }}
      className="glass-card rounded-xl p-4"
    >
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold text-white">MEV Reward Distribution</h3>
        <div className="flex items-center gap-1 text-xs text-dark-400">
          <DollarSign className="w-3 h-3" />
          <span>Real-time from contracts</span>
        </div>
      </div>

      <div className="grid md:grid-cols-2 gap-4">
        {/* Pie Chart */}
        <div className="h-[160px]">
          <ResponsiveContainer width="100%" height="100%">
            <PieChart>
              <Pie
                data={pieData}
                cx="50%"
                cy="50%"
                innerRadius={40}
                outerRadius={70}
                paddingAngle={2}
                dataKey="value"
              >
                {pieData.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={entry.color} />
                ))}
              </Pie>
              <Tooltip
                contentStyle={{
                  backgroundColor: 'rgba(30, 41, 59, 0.95)',
                  border: '1px solid rgba(100, 116, 139, 0.3)',
                  borderRadius: '8px',
                  color: '#fff',
                }}
                formatter={(value: number) => [`${value}%`, 'Share']}
              />
            </PieChart>
          </ResponsiveContainer>
        </div>

        {/* Distribution Details */}
        <div className="space-y-3">
          <div className="text-center mb-2">
            <div className="text-2xl font-bold text-white">
              {distribution.totalCaptured.toFixed(4)} ETH
            </div>
            <div className="text-sm text-dark-400">Total MEV Captured</div>
          </div>

          {pieData.map((item) => (
            <div key={item.name} className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <div
                  className="w-3 h-3 rounded-full"
                  style={{ backgroundColor: item.color }}
                />
                <span className="text-sm text-dark-300">{item.name}</span>
              </div>
              <span className="text-sm font-medium text-white">{item.value}%</span>
            </div>
          ))}

          <div className="pt-2 border-t border-dark-700">
            <div className="text-xs text-dark-400 text-center">
              80% to LPs via donate() • 10% Treasury • 10% Keepers
            </div>
          </div>
        </div>
      </div>
    </motion.div>
  );
}

// MEV Protection Explanation Card
function MevProtectionExplainer() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.4 }}
      className="glass-card rounded-xl p-4"
    >
      <h3 className="text-lg font-semibold text-white mb-4">How MEV Protection Works</h3>

      <div className="space-y-4">
        <div className="flex gap-3">
          <div className="w-8 h-8 rounded-lg bg-primary-500/20 flex items-center justify-center flex-shrink-0">
            <span className="text-primary-400 font-bold">1</span>
          </div>
          <div>
            <h4 className="text-sm font-medium text-white">Oracle Price Comparison</h4>
            <p className="text-xs text-dark-400">
              Chainlink oracles provide reference prices. Pool prices are compared to detect MEV opportunities.
            </p>
          </div>
        </div>

        <div className="flex gap-3">
          <div className="w-8 h-8 rounded-lg bg-primary-500/20 flex items-center justify-center flex-shrink-0">
            <span className="text-primary-400 font-bold">2</span>
          </div>
          <div>
            <h4 className="text-sm font-medium text-white">Hook Captures Value</h4>
            <p className="text-xs text-dark-400">
              MevRouterHookV2 detects price deviations in beforeSwap/afterSwap and captures arbitrage value.
            </p>
          </div>
        </div>

        <div className="flex gap-3">
          <div className="w-8 h-8 rounded-lg bg-primary-500/20 flex items-center justify-center flex-shrink-0">
            <span className="text-primary-400 font-bold">3</span>
          </div>
          <div>
            <h4 className="text-sm font-medium text-white">Flash Loan Backrunning</h4>
            <p className="text-xs text-dark-400">
              Aave V3 flash loans execute atomic backruns to restore prices, capturing profit without capital.
            </p>
          </div>
        </div>

        <div className="flex gap-3">
          <div className="w-8 h-8 rounded-lg bg-green-500/20 flex items-center justify-center flex-shrink-0">
            <span className="text-green-400 font-bold">4</span>
          </div>
          <div>
            <h4 className="text-sm font-medium text-white">LP Redistribution</h4>
            <p className="text-xs text-dark-400">
              80% of captured MEV is donated back to LPs via Uniswap V4's donate() function.
            </p>
          </div>
        </div>
      </div>
    </motion.div>
  );
}

export function StatsPanel() {
  const stats = useProtocolStats();
  const [isRefreshing, setIsRefreshing] = useState(false);

  const handleRefresh = async () => {
    setIsRefreshing(true);
    // Stats auto-refresh, this is just visual feedback
    await new Promise(r => setTimeout(r, 1000));
    setIsRefreshing(false);
  };

  return (
    <div className="space-y-6">
      {/* Header with refresh */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-xl font-bold text-white">Live Protocol Stats</h2>
          <p className="text-sm text-dark-400">
            {stats.lastUpdated
              ? `Last updated: ${stats.lastUpdated.toLocaleTimeString()}`
              : 'Fetching data from contracts...'}
          </p>
        </div>
        <motion.button
          onClick={handleRefresh}
          className="p-2 rounded-lg hover:bg-dark-700/50 transition-colors"
          whileHover={{ scale: 1.1 }}
          whileTap={{ scale: 0.9 }}
          animate={isRefreshing ? { rotate: 360 } : {}}
          transition={{ duration: 1, repeat: isRefreshing ? Infinity : 0 }}
        >
          <RefreshCw className={`w-5 h-5 text-dark-400 ${isRefreshing ? 'text-primary-400' : ''}`} />
        </motion.button>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <StatCard
          icon={Shield}
          title="Swaps Protected"
          value={stats.swapsProtected.toLocaleString()}
          tooltip="Total number of swap intents created through the protocol"
          isLoading={stats.isLoading}
        />
        <StatCard
          icon={Coins}
          title="MEV Captured"
          value={stats.totalMevCaptured}
          subValue={`≈ $${stats.totalMevCapturedUsd.toLocaleString(undefined, { maximumFractionDigits: 0 })}`}
          tooltip="Total MEV value detected and captured by the hook"
          isLoading={stats.isLoading}
        />
        <StatCard
          icon={TrendingUp}
          title="LP Fees Distributed"
          value={stats.lpFeesDistributed}
          subValue={`≈ $${stats.lpFeesDistributedUsd.toLocaleString(undefined, { maximumFractionDigits: 0 })}`}
          tooltip="80% of captured MEV redistributed to LPs via donate()"
          isLoading={stats.isLoading}
        />
        <StatCard
          icon={Activity}
          title="Active Agents"
          value={String(stats.activeAgents)}
          subValue="ERC-8004 Registered"
          tooltip="AI agents registered with ERC-8004 identity"
          isLoading={stats.isLoading}
        />
      </div>

      {/* Charts Row */}
      <div className="grid md:grid-cols-2 gap-6">
        <RewardDistributionCard />
        <MevProtectionExplainer />
      </div>
    </div>
  );
}
