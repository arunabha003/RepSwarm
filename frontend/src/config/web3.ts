'use client';

import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { sepolia, mainnet, arbitrum, optimism, base } from 'wagmi/chains';

export const config = getDefaultConfig({
  appName: 'Swarm Router',
  projectId: process.env.NEXT_PUBLIC_WC_PROJECT_ID || 'YOUR_PROJECT_ID',
  chains: [sepolia, mainnet, arbitrum, optimism, base],
  ssr: true,
});

// Contract addresses per network
export const CONTRACT_ADDRESSES: Record<number, {
  poolManager: `0x${string}`;
  mevRouterHook: `0x${string}`;
  lpFeeAccumulator: `0x${string}`;
  backrunExecutor: `0x${string}`;
  swarmCoordinator: `0x${string}`;
}> = {
  // Sepolia testnet
  11155111: {
    poolManager: '0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A',
    mevRouterHook: '0x0000000000000000000000000000000000000000', // Deploy and update
    lpFeeAccumulator: '0x0000000000000000000000000000000000000000',
    backrunExecutor: '0x0000000000000000000000000000000000000000',
    swarmCoordinator: '0x0000000000000000000000000000000000000000',
  },
};

// Token addresses per network
export const TOKEN_ADDRESSES: Record<number, Record<string, {
  address: `0x${string}`;
  symbol: string;
  decimals: number;
  logoURI?: string;
}>> = {
  11155111: {
    ETH: {
      address: '0x0000000000000000000000000000000000000000',
      symbol: 'ETH',
      decimals: 18,
      logoURI: 'https://assets.coingecko.com/coins/images/279/small/ethereum.png',
    },
    WETH: {
      address: '0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9',
      symbol: 'WETH',
      decimals: 18,
      logoURI: 'https://assets.coingecko.com/coins/images/2518/small/weth.png',
    },
    USDC: {
      address: '0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8',
      symbol: 'USDC',
      decimals: 6,
      logoURI: 'https://assets.coingecko.com/coins/images/6319/small/usdc.png',
    },
    DAI: {
      address: '0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357',
      symbol: 'DAI',
      decimals: 18,
      logoURI: 'https://assets.coingecko.com/coins/images/9956/small/dai-multi-collateral-mcd.png',
    },
  },
};
