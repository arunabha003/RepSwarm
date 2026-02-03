'use client';

import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { sepolia, mainnet } from 'wagmi/chains';
import type { Chain } from 'wagmi/chains';

// Custom Anvil chain (Sepolia fork)
export const anvilFork: Chain = {
  id: 31337,
  name: 'Anvil (Sepolia Fork)',
  nativeCurrency: {
    decimals: 18,
    name: 'Ether',
    symbol: 'ETH',
  },
  rpcUrls: {
    default: { http: ['http://127.0.0.1:8545'] },
  },
  testnet: true,
};

export const config = getDefaultConfig({
  appName: 'Swarm Router',
  projectId: process.env.NEXT_PUBLIC_WC_PROJECT_ID || 'demo-project-id',
  chains: [anvilFork, sepolia, mainnet],
  ssr: true,
});

// ========================================
// CONTRACT ADDRESSES
// ========================================
// These get updated after running DeployAnvilFork.s.sol
// The deployment script outputs the exact addresses to paste here

export interface ContractAddresses {
  // Core Protocol
  poolManager: `0x${string}`;
  mevRouterHook: `0x${string}`;
  lpFeeAccumulator: `0x${string}`;
  swarmCoordinator: `0x${string}`;
  flashLoanBackrunner: `0x${string}`;
  oracleRegistry: `0x${string}`;
  // Agent Registry
  agentRegistry: `0x${string}`;
  // Agents
  feeOptimizerAgent: `0x${string}`;
  slippagePredictorAgent: `0x${string}`;
  mevHunterAgent: `0x${string}`;
  // ERC-8004 (Live Sepolia)
  erc8004IdentityRegistry: `0x${string}`;
  erc8004ReputationRegistry: `0x${string}`;
}

// ANVIL FORK ADDRESSES - Updated from DeployAnvilFork.s.sol deployment
export const ANVIL_CONTRACTS: ContractAddresses = {
  // Core Protocol
  poolManager: '0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A', // Sepolia PoolManager (forked)
  mevRouterHook: '0xa8bC1A201651AD743B994789aB71ebB13Edd00cc',
  lpFeeAccumulator: '0x0613E647b87fa28301FA87228dA114f24642214e',
  swarmCoordinator: '0x04D0FD893917F86Ff93Bf3966BeB65AE907C5184',
  flashLoanBackrunner: '0x8CDBA30696859364c24Be3b942FE83c953c9Cd9f',
  oracleRegistry: '0x11DAa049d4C16824487B0ED8021c6De88284F4bB',
  agentRegistry: '0x1Ca42F54a82abf19242c94fE42c96Ef40d4EFE27',
  feeOptimizerAgent: '0xe3f89724666d4220e816c80bafcC993337a5e1BF',
  slippagePredictorAgent: '0x9Bf916a9ca3120768b8F8BeCE4B50829854103D0',
  mevHunterAgent: '0x16A69B4a700D09234E79D6F87B4E9af4AFDfAE8a',
  // ERC-8004 (Live Sepolia contracts - work on fork!)
  erc8004IdentityRegistry: '0x8004A818BFB912233c491871b3d84c89A494BD9e',
  erc8004ReputationRegistry: '0x8004B663056A597Dffe9eCcC1965A193B7388713',
};

export const CONTRACT_ADDRESSES: Record<number, ContractAddresses> = {
  // Anvil Fork (localhost:8545)
  31337: ANVIL_CONTRACTS,
  // Sepolia testnet
  11155111: {
    ...ANVIL_CONTRACTS, // Same structure, update when deployed to real Sepolia
  },
};

// Helper to get contracts for current chain
export function getContractsForChain(chainId: number): ContractAddresses {
  return CONTRACT_ADDRESSES[chainId] || ANVIL_CONTRACTS;
}

// Token addresses per network
export const TOKEN_ADDRESSES: Record<number, Record<string, {
  address: `0x${string}`;
  symbol: string;
  decimals: number;
  logoURI?: string;
  chainlinkFeed?: `0x${string}`;
}>> = {
  // Anvil Fork uses same Sepolia tokens
  31337: {
    ETH: {
      address: '0x0000000000000000000000000000000000000000',
      symbol: 'ETH',
      decimals: 18,
      logoURI: 'https://assets.coingecko.com/coins/images/279/small/ethereum.png',
      chainlinkFeed: '0x694AA1769357215DE4FAC081bf1f309aDC325306',
    },
    WETH: {
      address: '0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9',
      symbol: 'WETH',
      decimals: 18,
      logoURI: 'https://assets.coingecko.com/coins/images/2518/small/weth.png',
      chainlinkFeed: '0x694AA1769357215DE4FAC081bf1f309aDC325306',
    },
    USDC: {
      address: '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238',
      symbol: 'USDC',
      decimals: 6,
      logoURI: 'https://assets.coingecko.com/coins/images/6319/small/usdc.png',
      chainlinkFeed: '0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E',
    },
    DAI: {
      address: '0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357',
      symbol: 'DAI',
      decimals: 18,
      logoURI: 'https://assets.coingecko.com/coins/images/9956/small/dai-multi-collateral-mcd.png',
    },
    LINK: {
      address: '0x779877A7B0D9E8603169DdbD7836e478b4624789',
      symbol: 'LINK',
      decimals: 18,
      logoURI: 'https://assets.coingecko.com/coins/images/877/small/chainlink-new-logo.png',
      chainlinkFeed: '0xc59E3633BAAC79493d908e63626716e204A45EdF',
    },
  },
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
      address: '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238',
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

// Chainlink Price Feed addresses (Sepolia - works on fork)
export const CHAINLINK_FEEDS = {
  ETH_USD: '0x694AA1769357215DE4FAC081bf1f309aDC325306' as `0x${string}`,
  USDC_USD: '0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E' as `0x${string}`,
  LINK_USD: '0xc59E3633BAAC79493d908e63626716e204A45EdF' as `0x${string}`,
  BTC_USD: '0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43' as `0x${string}`,
};

// Aave V3 addresses (Sepolia - works on fork)
export const AAVE_V3 = {
  pool: '0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951' as `0x${string}`,
  poolDataProvider: '0x3e9708d80f7B3e43118013075F7e95CE3AB31F31' as `0x${string}`,
};
