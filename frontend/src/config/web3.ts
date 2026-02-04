'use client';

import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { sepolia, mainnet } from 'wagmi/chains';
import type { Chain } from 'wagmi/chains';

// Custom Anvil chain (Sepolia fork)
export const anvilFork: Chain = {
  id: 31337,
  name: 'Anvil (ETH Sepolia Fork)',
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
// CONTRACT ADDRESSES - ETH SEPOLIA FORK
// ========================================
// Deployed via script/DeployEthSepoliaComplete.s.sol

export interface ContractAddresses {
  // Uniswap V4 Core (Official Sepolia)
  poolManager: `0x${string}`;
  positionManager: `0x${string}`;
  poolSwapTest: `0x${string}`;
  permit2: `0x${string}`;
  // Core Protocol (Our Deployed)
  mevRouterHook: `0x${string}`;
  lpFeeAccumulator: `0x${string}`;
  swarmCoordinator: `0x${string}`;
  flashLoanBackrunner: `0x${string}`;
  oracleRegistry: `0x${string}`;
  poolModifyLiquidityTest: `0x${string}`;
  // Agent Registry & Agents
  agentRegistry: `0x${string}`;
  feeOptimizerAgent: `0x${string}`;
  slippagePredictorAgent: `0x${string}`;
  mevHunterAgent: `0x${string}`;
  // ERC-8004 (Live Sepolia)
  erc8004IdentityRegistry: `0x${string}`;
  erc8004ReputationRegistry: `0x${string}`;
}

// ETH SEPOLIA FORK ADDRESSES - From DeployEthSepoliaComplete.s.sol
export const ANVIL_CONTRACTS: ContractAddresses = {
  // Uniswap V4 Core (Official Sepolia)
  poolManager: '0xE03A1074c86CFeDd5C142C4F04F1a1536e203543',
  positionManager: '0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4',
  poolSwapTest: '0x9B6b46e2c869aa39918Db7f52f5557FE577B6eEe',
  permit2: '0x000000000022D473030F116dDEE9F6B43aC78BA3',
  // Our Deployed Contracts
  mevRouterHook: '0xB33ac5E0ebA7d47f3D9cFB78C29519801a7380Cc',
  lpFeeAccumulator: '0xc1ec8B65bb137602963f88eb063fa7236f4744f2',
  swarmCoordinator: '0x79cA020FeE712048cAA49De800B4606cC516A331',
  flashLoanBackrunner: '0xd91d0433c10291448a8DC00C3ba14Af8b94c7656',
  oracleRegistry: '0x7A1efaf375798B6B0df2BE94CF8A13F68c9E74eE',
  poolModifyLiquidityTest: '0xFe2a7099f7810C486505016482beE86665244A2C',
  // Agents
  agentRegistry: '0x26c13B3900bf570d9830678D2e22C439778627EA',
  feeOptimizerAgent: '0xae6D0f561c4907D211Ed69cBCc2fd0A0e03A2AaE',
  slippagePredictorAgent: '0x3440e175a85aa6CD595e9E8b05c515ac546FB91c',
  mevHunterAgent: '0x95Ce3FE31BB597AD6aAc2639a03ca8f24741b508',
  // ERC-8004 (Live Sepolia contracts - work on fork!)
  erc8004IdentityRegistry: '0x8004A818BFB912233c491871b3d84c89A494BD9e',
  erc8004ReputationRegistry: '0x8004B663056A597Dffe9eCcC1965A193B7388713',
};

export const CONTRACT_ADDRESSES: Record<number, ContractAddresses> = {
  // Anvil Fork (localhost:8545 - ETH Sepolia Fork)
  31337: ANVIL_CONTRACTS,
  // Sepolia testnet (same addresses when deployed to real Sepolia)
  11155111: ANVIL_CONTRACTS,
};

// Helper to get contracts for current chain
export function getContractsForChain(chainId: number): ContractAddresses {
  return CONTRACT_ADDRESSES[chainId] || ANVIL_CONTRACTS;
}

// Pool IDs (from deployment)
export const POOL_IDS = {
  // ETH/USDC Pool 1 (fee=500, tickSpacing=10) - with new hook
  ETH_USDC_POOL1: '0x56dd7cd7a7e4d96b64e561f9f1074e5cd8351e2926795765f49ea9aff7a50814' as `0x${string}`,
  // ETH/USDC Pool 2 (fee=500, tickSpacing=60) - with new hook
  ETH_USDC_POOL2: '0x22c0f245cdb5800fb8b9b51ecf92ab275ef0b2bff513a3689e4b7f5f8e78f6b1' as `0x${string}`,
};

// Token addresses per network
export const TOKEN_ADDRESSES: Record<number, Record<string, {
  address: `0x${string}`;
  symbol: string;
  decimals: number;
  logoURI?: string;
  chainlinkFeed?: `0x${string}`;
}>> = {
  // Anvil Fork uses ETH Sepolia tokens
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
      // Aave testnet USDC - 18 decimals!
      address: '0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8',
      symbol: 'USDC',
      decimals: 18, // Aave test USDC uses 18 decimals
      logoURI: 'https://assets.coingecko.com/coins/images/6319/small/usdc.png',
      chainlinkFeed: '0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E',
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
      // Aave testnet USDC - 18 decimals!
      address: '0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8',
      symbol: 'USDC',
      decimals: 18,
      logoURI: 'https://assets.coingecko.com/coins/images/6319/small/usdc.png',
      chainlinkFeed: '0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E',
    },
    LINK: {
      address: '0x779877A7B0D9E8603169DdbD7836e478b4624789',
      symbol: 'LINK',
      decimals: 18,
      logoURI: 'https://assets.coingecko.com/coins/images/877/small/chainlink-new-logo.png',
      chainlinkFeed: '0xc59E3633BAAC79493d908e63626716e204A45EdF',
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
