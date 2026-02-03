'use client';

import { ConnectButton } from '@rainbow-me/rainbowkit';
import Link from 'next/link';
import { motion } from 'framer-motion';
import { Zap, Shield, BarChart3 } from 'lucide-react';

export function Header() {
  return (
    <header className="fixed top-0 left-0 right-0 z-50 glass">
      <nav className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16">
          {/* Logo */}
          <Link href="/" className="flex items-center gap-2">
            <motion.div
              className="w-10 h-10 rounded-xl bg-gradient-to-br from-primary-500 to-accent-500 flex items-center justify-center"
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
            >
              <Zap className="w-6 h-6 text-white" />
            </motion.div>
            <span className="text-xl font-bold bg-gradient-to-r from-primary-400 to-accent-400 bg-clip-text text-transparent">
              Swarm Router
            </span>
          </Link>

          {/* Navigation Links */}
          <div className="hidden md:flex items-center gap-6">
            <NavLink href="/" icon={<Zap className="w-4 h-4" />}>
              Swap
            </NavLink>
            <NavLink href="/analytics" icon={<BarChart3 className="w-4 h-4" />}>
              Analytics
            </NavLink>
            <NavLink href="/agents" icon={<Shield className="w-4 h-4" />}>
              Agents
            </NavLink>
          </div>

          {/* Connect Button */}
          <ConnectButton
            chainStatus="icon"
            showBalance={{ smallScreen: false, largeScreen: true }}
          />
        </div>
      </nav>
    </header>
  );
}

function NavLink({
  href,
  icon,
  children,
}: {
  href: string;
  icon: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <Link
      href={href}
      className="flex items-center gap-2 px-4 py-2 rounded-lg text-dark-300 hover:text-white hover:bg-dark-800/50 transition-all duration-200"
    >
      {icon}
      <span className="font-medium">{children}</span>
    </Link>
  );
}
