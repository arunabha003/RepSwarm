'use client';

import { motion } from 'framer-motion';
import { Header } from '@/components/Header';
import { StatsPanel } from '@/components/StatsPanel';
import { 
  LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, 
  AreaChart, Area, BarChart, Bar, PieChart, Pie, Cell 
} from 'recharts';
import { Shield, TrendingUp, Users, Zap, DollarSign, Activity } from 'lucide-react';

// Extended mock data for analytics
const dailyMevData = [
  { day: 'Mon', captured: 1200, protected: 45 },
  { day: 'Tue', captured: 1800, protected: 62 },
  { day: 'Wed', captured: 2400, protected: 78 },
  { day: 'Thu', captured: 1600, protected: 54 },
  { day: 'Fri', captured: 3200, protected: 95 },
  { day: 'Sat', captured: 2800, protected: 88 },
  { day: 'Sun', captured: 2100, protected: 71 },
];

const agentPerformance = [
  { name: 'FeeOptimizer', success: 98, tasks: 342 },
  { name: 'MevHunter', success: 95, tasks: 287 },
  { name: 'SlippagePredictor', success: 92, tasks: 456 },
  { name: 'RouteAnalyzer', success: 97, tasks: 389 },
];

const lpDonations = [
  { pool: 'ETH/USDC', amount: 4500 },
  { pool: 'ETH/DAI', amount: 3200 },
  { pool: 'WBTC/ETH', amount: 2800 },
  { pool: 'USDC/USDT', amount: 1800 },
];

const COLORS = ['#0ea5e9', '#d946ef', '#22c55e', '#f59e0b'];

export default function AnalyticsPage() {
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
            <p className="text-dark-400 mb-8">Real-time metrics and performance data</p>
          </motion.div>
          
          {/* Overview Stats */}
          <StatsPanel />
          
          {/* Charts Grid */}
          <div className="grid lg:grid-cols-2 gap-6 mt-8">
            {/* Weekly MEV Activity */}
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.2 }}
              className="glass-card rounded-xl p-6"
            >
              <h3 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
                <Shield className="w-5 h-5 text-primary-400" />
                Weekly MEV Activity
              </h3>
              <ResponsiveContainer width="100%" height={300}>
                <AreaChart data={dailyMevData}>
                  <defs>
                    <linearGradient id="colorCaptured" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#0ea5e9" stopOpacity={0.3} />
                      <stop offset="95%" stopColor="#0ea5e9" stopOpacity={0} />
                    </linearGradient>
                  </defs>
                  <XAxis dataKey="day" stroke="#475569" />
                  <YAxis stroke="#475569" />
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
                    dataKey="captured"
                    stroke="#0ea5e9"
                    fill="url(#colorCaptured)"
                    strokeWidth={2}
                    name="MEV Captured ($)"
                  />
                </AreaChart>
              </ResponsiveContainer>
            </motion.div>
            
            {/* Agent Performance */}
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.3 }}
              className="glass-card rounded-xl p-6"
            >
              <h3 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
                <Users className="w-5 h-5 text-accent-400" />
                Agent Performance
              </h3>
              <ResponsiveContainer width="100%" height={300}>
                <BarChart data={agentPerformance} layout="vertical">
                  <XAxis type="number" domain={[0, 100]} stroke="#475569" />
                  <YAxis dataKey="name" type="category" stroke="#475569" width={120} />
                  <Tooltip
                    contentStyle={{
                      backgroundColor: 'rgba(30, 41, 59, 0.95)',
                      border: '1px solid rgba(100, 116, 139, 0.3)',
                      borderRadius: '8px',
                      color: '#fff',
                    }}
                    formatter={(value: number) => [`${value}%`, 'Success Rate']}
                  />
                  <Bar dataKey="success" fill="#d946ef" radius={[0, 4, 4, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </motion.div>
            
            {/* LP Donations Distribution */}
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.4 }}
              className="glass-card rounded-xl p-6"
            >
              <h3 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
                <DollarSign className="w-5 h-5 text-green-400" />
                LP Donations by Pool
              </h3>
              <div className="flex items-center justify-center">
                <ResponsiveContainer width="100%" height={300}>
                  <PieChart>
                    <Pie
                      data={lpDonations}
                      cx="50%"
                      cy="50%"
                      innerRadius={60}
                      outerRadius={100}
                      paddingAngle={5}
                      dataKey="amount"
                      label={({ pool, percent }) => `${pool} ${(percent * 100).toFixed(0)}%`}
                    >
                      {lpDonations.map((entry, index) => (
                        <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                      ))}
                    </Pie>
                    <Tooltip
                      contentStyle={{
                        backgroundColor: 'rgba(30, 41, 59, 0.95)',
                        border: '1px solid rgba(100, 116, 139, 0.3)',
                        borderRadius: '8px',
                        color: '#fff',
                      }}
                      formatter={(value: number) => [`$${value.toLocaleString()}`, 'Donated']}
                    />
                  </PieChart>
                </ResponsiveContainer>
              </div>
            </motion.div>
            
            {/* Swaps Protected */}
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.5 }}
              className="glass-card rounded-xl p-6"
            >
              <h3 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
                <Activity className="w-5 h-5 text-orange-400" />
                Swaps Protected
              </h3>
              <ResponsiveContainer width="100%" height={300}>
                <LineChart data={dailyMevData}>
                  <XAxis dataKey="day" stroke="#475569" />
                  <YAxis stroke="#475569" />
                  <Tooltip
                    contentStyle={{
                      backgroundColor: 'rgba(30, 41, 59, 0.95)',
                      border: '1px solid rgba(100, 116, 139, 0.3)',
                      borderRadius: '8px',
                      color: '#fff',
                    }}
                  />
                  <Line
                    type="monotone"
                    dataKey="protected"
                    stroke="#22c55e"
                    strokeWidth={3}
                    dot={{ fill: '#22c55e', strokeWidth: 2 }}
                    name="Swaps Protected"
                  />
                </LineChart>
              </ResponsiveContainer>
            </motion.div>
          </div>
          
          {/* Recent Activity Table */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.6 }}
            className="glass-card rounded-xl p-6 mt-8"
          >
            <h3 className="text-lg font-semibold text-white mb-4">Recent Protected Swaps</h3>
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead>
                  <tr className="text-left text-dark-400 text-sm border-b border-dark-700">
                    <th className="pb-3 font-medium">Time</th>
                    <th className="pb-3 font-medium">Pair</th>
                    <th className="pb-3 font-medium">Amount</th>
                    <th className="pb-3 font-medium">MEV Saved</th>
                    <th className="pb-3 font-medium">Status</th>
                  </tr>
                </thead>
                <tbody className="text-sm">
                  {[
                    { time: '2 min ago', pair: 'ETH → USDC', amount: '$5,240', saved: '$26.20', status: 'Protected' },
                    { time: '5 min ago', pair: 'USDC → DAI', amount: '$12,000', saved: '$48.00', status: 'Protected' },
                    { time: '8 min ago', pair: 'WBTC → ETH', amount: '$8,500', saved: '$34.00', status: 'Protected' },
                    { time: '12 min ago', pair: 'ETH → USDC', amount: '$3,200', saved: '$12.80', status: 'Protected' },
                    { time: '15 min ago', pair: 'DAI → USDC', amount: '$25,000', saved: '$75.00', status: 'Protected' },
                  ].map((tx, i) => (
                    <tr key={i} className="border-b border-dark-800 hover:bg-dark-800/30 transition-colors">
                      <td className="py-3 text-dark-300">{tx.time}</td>
                      <td className="py-3 text-white font-medium">{tx.pair}</td>
                      <td className="py-3 text-white">{tx.amount}</td>
                      <td className="py-3 text-green-400">+{tx.saved}</td>
                      <td className="py-3">
                        <span className="px-2 py-1 rounded-full bg-green-500/20 text-green-400 text-xs">
                          {tx.status}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </motion.div>
        </div>
      </section>
    </main>
  );
}
