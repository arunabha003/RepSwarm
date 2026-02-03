'use client';

import { motion } from 'framer-motion';
import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, AreaChart, Area } from 'recharts';
import { TrendingUp, Shield, Coins, Activity } from 'lucide-react';

// Sample data - in production, fetch from contracts
const mevProtectionData = [
  { time: '1h', protected: 12, captured: 1.2 },
  { time: '2h', protected: 15, captured: 1.8 },
  { time: '3h', protected: 23, captured: 2.4 },
  { time: '4h', protected: 28, captured: 3.1 },
  { time: '5h', protected: 35, captured: 3.8 },
  { time: '6h', protected: 42, captured: 4.2 },
];

const volumeData = [
  { time: '1h', volume: 45000 },
  { time: '2h', volume: 52000 },
  { time: '3h', volume: 48000 },
  { time: '4h', volume: 61000 },
  { time: '5h', volume: 58000 },
  { time: '6h', volume: 72000 },
];

interface StatCardProps {
  icon: React.ElementType;
  title: string;
  value: string;
  change?: string;
  positive?: boolean;
}

function StatCard({ icon: Icon, title, value, change, positive }: StatCardProps) {
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      className="glass-card rounded-xl p-4"
    >
      <div className="flex items-center gap-3 mb-2">
        <div className="w-10 h-10 rounded-lg bg-gradient-to-br from-primary-500/20 to-accent-500/20 flex items-center justify-center">
          <Icon className="w-5 h-5 text-primary-400" />
        </div>
        <span className="text-sm text-dark-400">{title}</span>
      </div>
      <div className="text-2xl font-bold text-white">{value}</div>
      {change && (
        <div className={`text-sm mt-1 ${positive ? 'text-green-400' : 'text-red-400'}`}>
          {positive ? '+' : ''}{change}
        </div>
      )}
    </motion.div>
  );
}

export function StatsPanel() {
  return (
    <div className="space-y-6">
      {/* Stats Grid */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <StatCard
          icon={Shield}
          title="Swaps Protected"
          value="2,847"
          change="12.5%"
          positive
        />
        <StatCard
          icon={Coins}
          title="MEV Captured"
          value="$12,450"
          change="8.2%"
          positive
        />
        <StatCard
          icon={TrendingUp}
          title="Volume (24h)"
          value="$1.2M"
          change="15.3%"
          positive
        />
        <StatCard
          icon={Activity}
          title="Active Agents"
          value="12"
        />
      </div>
      
      {/* Charts */}
      <div className="grid md:grid-cols-2 gap-6">
        {/* MEV Protection Chart */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2 }}
          className="glass-card rounded-xl p-4"
        >
          <h3 className="text-lg font-semibold text-white mb-4">MEV Protection Activity</h3>
          <ResponsiveContainer width="100%" height={200}>
            <AreaChart data={mevProtectionData}>
              <defs>
                <linearGradient id="colorProtected" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#0ea5e9" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="#0ea5e9" stopOpacity={0} />
                </linearGradient>
              </defs>
              <XAxis dataKey="time" stroke="#475569" fontSize={12} />
              <YAxis stroke="#475569" fontSize={12} />
              <Tooltip
                contentStyle={{
                  backgroundColor: 'rgba(30, 41, 59, 0.95)',
                  border: '1px solid rgba(100, 116, 139, 0.3)',
                  borderRadius: '8px',
                  color: '#fff',
                }}
              />
              <Area
                type="monotone"
                dataKey="protected"
                stroke="#0ea5e9"
                fill="url(#colorProtected)"
                strokeWidth={2}
              />
            </AreaChart>
          </ResponsiveContainer>
        </motion.div>
        
        {/* Volume Chart */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3 }}
          className="glass-card rounded-xl p-4"
        >
          <h3 className="text-lg font-semibold text-white mb-4">Trading Volume</h3>
          <ResponsiveContainer width="100%" height={200}>
            <AreaChart data={volumeData}>
              <defs>
                <linearGradient id="colorVolume" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#d946ef" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="#d946ef" stopOpacity={0} />
                </linearGradient>
              </defs>
              <XAxis dataKey="time" stroke="#475569" fontSize={12} />
              <YAxis stroke="#475569" fontSize={12} tickFormatter={(v) => `$${v/1000}k`} />
              <Tooltip
                contentStyle={{
                  backgroundColor: 'rgba(30, 41, 59, 0.95)',
                  border: '1px solid rgba(100, 116, 139, 0.3)',
                  borderRadius: '8px',
                  color: '#fff',
                }}
                formatter={(value: number) => [`$${value.toLocaleString()}`, 'Volume']}
              />
              <Area
                type="monotone"
                dataKey="volume"
                stroke="#d946ef"
                fill="url(#colorVolume)"
                strokeWidth={2}
              />
            </AreaChart>
          </ResponsiveContainer>
        </motion.div>
      </div>
    </div>
  );
}
