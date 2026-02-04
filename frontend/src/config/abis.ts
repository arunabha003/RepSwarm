// ========================================
// SWARM COORDINATOR ABI (Full)
// ========================================
export const SWARM_COORDINATOR_ABI = [
  // Intent Creation
  {
    inputs: [
      {
        components: [
          { name: 'currencyIn', type: 'address' },
          { name: 'currencyOut', type: 'address' },
          { name: 'amountIn', type: 'uint128' },
          { name: 'amountOutMin', type: 'uint128' },
          { name: 'deadline', type: 'uint64' },
          { name: 'mevFeeBps', type: 'uint16' },
          { name: 'treasuryBps', type: 'uint16' },
          { name: 'lpShareBps', type: 'uint16' },
        ],
        name: 'params',
        type: 'tuple',
      },
      { name: 'candidatePaths', type: 'bytes[]' },
    ],
    name: 'createIntent',
    outputs: [{ name: 'intentId', type: 'uint256' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  // Execute Intent
  {
    inputs: [{ name: 'intentId', type: 'uint256' }],
    name: 'executeIntent',
    outputs: [],
    stateMutability: 'payable',
    type: 'function',
  },
  // Submit Proposal (for agents)
  {
    inputs: [
      { name: 'intentId', type: 'uint256' },
      { name: 'candidateId', type: 'uint256' },
      { name: 'score', type: 'int256' },
      { name: 'data', type: 'bytes' },
    ],
    name: 'submitProposal',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  // Get Intent
  {
    inputs: [{ name: 'intentId', type: 'uint256' }],
    name: 'getIntent',
    outputs: [
      {
        components: [
          { name: 'requester', type: 'address' },
          { name: 'currencyIn', type: 'address' },
          { name: 'currencyOut', type: 'address' },
          { name: 'amountIn', type: 'uint256' },
          { name: 'amountOutMin', type: 'uint256' },
          { name: 'deadline', type: 'uint256' },
          { name: 'mevFeeBps', type: 'uint16' },
          { name: 'treasuryBps', type: 'uint16' },
          { name: 'lpShareBps', type: 'uint16' },
          { name: 'executed', type: 'bool' },
        ],
        name: '',
        type: 'tuple',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  // Get Candidate Count
  {
    inputs: [{ name: 'intentId', type: 'uint256' }],
    name: 'getCandidateCount',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  // Get Proposal
  {
    inputs: [
      { name: 'intentId', type: 'uint256' },
      { name: 'agent', type: 'address' },
    ],
    name: 'getProposal',
    outputs: [
      {
        components: [
          { name: 'agentId', type: 'uint256' },
          { name: 'candidateId', type: 'uint256' },
          { name: 'score', type: 'int256' },
          { name: 'data', type: 'bytes' },
          { name: 'timestamp', type: 'uint64' },
        ],
        name: '',
        type: 'tuple',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  // Get Proposal Agents
  {
    inputs: [{ name: 'intentId', type: 'uint256' }],
    name: 'getProposalAgents',
    outputs: [{ name: '', type: 'address[]' }],
    stateMutability: 'view',
    type: 'function',
  },
  // Get Agent Info
  {
    inputs: [{ name: 'agent', type: 'address' }],
    name: 'getAgentInfo',
    outputs: [
      {
        components: [
          { name: 'approved', type: 'bool' },
          { name: 'identityId', type: 'uint256' },
        ],
        name: '',
        type: 'tuple',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  // Get Agent Reputation
  {
    inputs: [{ name: 'agentId', type: 'uint256' }],
    name: 'getAgentReputation',
    outputs: [
      { name: 'count', type: 'uint64' },
      { name: 'reputationWad', type: 'int256' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  // State variables
  {
    inputs: [],
    name: 'nextIntentId',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'treasury',
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'enforceIdentity',
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'enforceReputation',
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'view',
    type: 'function',
  },
  // Events
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: 'intentId', type: 'uint256' },
      { indexed: true, name: 'requester', type: 'address' },
      { indexed: false, name: 'candidateCount', type: 'uint256' },
    ],
    name: 'IntentCreated',
    type: 'event',
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: 'intentId', type: 'uint256' },
      { indexed: true, name: 'executor', type: 'address' },
      { indexed: false, name: 'candidateId', type: 'uint256' },
      { indexed: false, name: 'agentId', type: 'uint256' },
    ],
    name: 'IntentExecuted',
    type: 'event',
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: 'intentId', type: 'uint256' },
      { indexed: true, name: 'agent', type: 'address' },
      { indexed: true, name: 'agentId', type: 'uint256' },
      { indexed: false, name: 'candidateId', type: 'uint256' },
      { indexed: false, name: 'score', type: 'int256' },
    ],
    name: 'ProposalSubmitted',
    type: 'event',
  },
] as const;

// ========================================
// MEV ROUTER HOOK V2 ABI
// ========================================
export const MEV_ROUTER_HOOK_ABI = [
  {
    inputs: [{ name: 'poolId', type: 'bytes32' }],
    name: 'accumulatedTokens',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'poolId', type: 'bytes32' }],
    name: 'lastSwapPoolPrice',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'poolId', type: 'bytes32' }],
    name: 'lastSwapOraclePrice',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'hookShareBps',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'backrunEnabled',
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'view',
    type: 'function',
  },
  // Events
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: 'poolId', type: 'bytes32' },
      { indexed: true, name: 'currency', type: 'address' },
      { indexed: false, name: 'hookShare', type: 'uint256' },
      { indexed: false, name: 'arbitrageOpportunity', type: 'uint256' },
      { indexed: false, name: 'zeroForOne', type: 'bool' },
    ],
    name: 'ArbitrageCaptured',
    type: 'event',
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: 'poolId', type: 'bytes32' },
      { indexed: false, name: 'backrunAmount', type: 'uint256' },
      { indexed: false, name: 'profit', type: 'uint256' },
      { indexed: false, name: 'lpShare', type: 'uint256' },
    ],
    name: 'BackrunExecuted',
    type: 'event',
  },
] as const;

// ========================================
// LP FEE ACCUMULATOR ABI
// ========================================
export const LP_FEE_ACCUMULATOR_ABI = [
  {
    inputs: [
      { name: 'poolId', type: 'bytes32' },
      { name: 'currency', type: 'address' },
    ],
    name: 'accumulatedFees',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'poolId', type: 'bytes32' }],
    name: 'lastDonationTime',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { name: 'poolId', type: 'bytes32' },
      { name: 'currency', type: 'address' },
    ],
    name: 'totalDonated',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'minDonationThreshold',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'minDonationInterval',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  // Events
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: 'poolId', type: 'bytes32' },
      { indexed: true, name: 'currency', type: 'address' },
      { indexed: false, name: 'amount', type: 'uint256' },
    ],
    name: 'FeesAccumulated',
    type: 'event',
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: 'poolId', type: 'bytes32' },
      { indexed: true, name: 'currency0', type: 'address' },
      { indexed: true, name: 'currency1', type: 'address' },
      { indexed: false, name: 'amount0', type: 'uint256' },
      { indexed: false, name: 'amount1', type: 'uint256' },
    ],
    name: 'FeesDonatedToLPs',
    type: 'event',
  },
] as const;

// ========================================
// FLASHLOAN BACKRUNNER ABI
// ========================================
export const FLASHLOAN_BACKRUNNER_ABI = [
  {
    inputs: [{ name: 'poolId', type: 'bytes32' }],
    name: 'totalProfits',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'poolId', type: 'bytes32' }],
    name: 'checkProfitability',
    outputs: [
      { name: 'profitable', type: 'bool' },
      { name: 'estimatedProfit', type: 'uint256' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'poolId', type: 'bytes32' }],
    name: 'getPendingBackrun',
    outputs: [
      { name: 'targetPrice', type: 'uint256' },
      { name: 'currentPrice', type: 'uint256' },
      { name: 'backrunAmount', type: 'uint256' },
      { name: 'zeroForOne', type: 'bool' },
      { name: 'timestamp', type: 'uint64' },
      { name: 'executed', type: 'bool' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  // Events
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: 'poolId', type: 'bytes32' },
      { indexed: false, name: 'targetPrice', type: 'uint256' },
      { indexed: false, name: 'currentPrice', type: 'uint256' },
      { indexed: false, name: 'backrunAmount', type: 'uint256' },
      { indexed: false, name: 'zeroForOne', type: 'bool' },
    ],
    name: 'BackrunOpportunityDetected',
    type: 'event',
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: 'poolId', type: 'bytes32' },
      { indexed: false, name: 'flashLoanAmount', type: 'uint256' },
      { indexed: false, name: 'profit', type: 'uint256' },
      { indexed: false, name: 'lpShare', type: 'uint256' },
      { indexed: false, name: 'keeper', type: 'address' },
    ],
    name: 'BackrunExecuted',
    type: 'event',
  },
] as const;

// ========================================
// ORACLE REGISTRY ABI
// ========================================
export const ORACLE_REGISTRY_ABI = [
  {
    inputs: [
      { name: 'base', type: 'address' },
      { name: 'quote', type: 'address' },
    ],
    name: 'getLatestPrice',
    outputs: [
      { name: 'price', type: 'uint256' },
      { name: 'updatedAt', type: 'uint256' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { name: 'base', type: 'address' },
      { name: 'quote', type: 'address' },
    ],
    name: 'hasPriceFeed',
    outputs: [{ name: 'exists', type: 'bool' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'maxStaleness',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

// ========================================
// AGENT BASE ABI (for all agents)
// ========================================
export const AGENT_ABI = [
  {
    inputs: [{ name: 'intentId', type: 'uint256' }],
    name: 'propose',
    outputs: [
      { name: 'candidateId', type: 'uint256' },
      { name: 'score', type: 'int256' },
    ],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [],
    name: 'agentId',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'cachedReputationWeight',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'useReputationWeighting',
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

// ========================================
// ERC-8004 IDENTITY REGISTRY ABI
// ========================================
export const ERC8004_IDENTITY_ABI = [
  // ERC-721 methods
  {
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    name: 'ownerOf',
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'owner', type: 'address' }],
    name: 'balanceOf',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  // Agent-specific
  {
    inputs: [],
    name: 'register',
    outputs: [{ name: 'agentId', type: 'uint256' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [{ name: 'agentId', type: 'uint256' }],
    name: 'getAgentWallet',
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'agentId', type: 'uint256' },
    ],
    name: 'isAuthorizedOrOwner',
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

// ========================================
// ERC-8004 REPUTATION REGISTRY ABI
// ========================================
export const ERC8004_REPUTATION_ABI = [
  {
    inputs: [
      { name: 'agentId', type: 'uint256' },
      { name: 'clientAddresses', type: 'address[]' },
      { name: 'tag1', type: 'string' },
      { name: 'tag2', type: 'string' },
    ],
    name: 'getSummary',
    outputs: [
      { name: 'count', type: 'uint64' },
      { name: 'summaryValue', type: 'int128' },
      { name: 'summaryValueDecimals', type: 'uint8' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'agentId', type: 'uint256' }],
    name: 'getClients',
    outputs: [{ name: '', type: 'address[]' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { name: 'agentId', type: 'uint256' },
      { name: 'clientAddress', type: 'address' },
    ],
    name: 'getLastIndex',
    outputs: [{ name: '', type: 'uint64' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

// ========================================
// SWARM AGENT REGISTRY ABI
// ========================================
export const SWARM_AGENT_REGISTRY_ABI = [
  {
    inputs: [
      { name: 'agentContract', type: 'address' },
      { name: 'name', type: 'string' },
      { name: 'description', type: 'string' },
      { name: 'agentType', type: 'string' },
    ],
    name: 'registerAgent',
    outputs: [{ name: 'agentId', type: 'uint256' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [{ name: 'agentContract', type: 'address' }],
    name: 'getAgentByContract',
    outputs: [
      {
        components: [
          { name: 'agentId', type: 'uint256' },
          { name: 'agentContract', type: 'address' },
          { name: 'owner', type: 'address' },
          { name: 'name', type: 'string' },
          { name: 'description', type: 'string' },
          { name: 'agentType', type: 'string' },
          { name: 'version', type: 'string' },
          { name: 'isActive', type: 'bool' },
          { name: 'totalProposals', type: 'uint256' },
          { name: 'successfulProposals', type: 'uint256' },
          { name: 'cachedReputation', type: 'int256' },
          { name: 'lastUpdateTime', type: 'uint256' },
        ],
        name: '',
        type: 'tuple',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'getActiveAgentCount',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'agentId', type: 'uint256' }],
    name: 'getAgentById',
    outputs: [
      {
        components: [
          { name: 'agentId', type: 'uint256' },
          { name: 'agentContract', type: 'address' },
          { name: 'owner', type: 'address' },
          { name: 'name', type: 'string' },
          { name: 'description', type: 'string' },
          { name: 'agentType', type: 'string' },
          { name: 'version', type: 'string' },
          { name: 'isActive', type: 'bool' },
          { name: 'totalProposals', type: 'uint256' },
          { name: 'successfulProposals', type: 'uint256' },
          { name: 'cachedReputation', type: 'int256' },
          { name: 'lastUpdateTime', type: 'uint256' },
        ],
        name: '',
        type: 'tuple',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  // Events
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: 'agentId', type: 'uint256' },
      { indexed: true, name: 'agentContract', type: 'address' },
      { indexed: true, name: 'owner', type: 'address' },
      { indexed: false, name: 'name', type: 'string' },
    ],
    name: 'AgentRegistered',
    type: 'event',
  },
] as const;

// ========================================
// ERC20 ABI (minimal)
// ========================================
export const ERC20_ABI = [
  {
    inputs: [{ name: 'account', type: 'address' }],
    name: 'balanceOf',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'decimals',
    outputs: [{ name: '', type: 'uint8' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'symbol',
    outputs: [{ name: '', type: 'string' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'approve',
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    name: 'allowance',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { name: 'to', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'transfer',
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
] as const;

// ========================================
// CHAINLINK AGGREGATOR ABI
// ========================================
export const CHAINLINK_AGGREGATOR_ABI = [
  {
    inputs: [],
    name: 'latestRoundData',
    outputs: [
      { name: 'roundId', type: 'uint80' },
      { name: 'answer', type: 'int256' },
      { name: 'startedAt', type: 'uint256' },
      { name: 'updatedAt', type: 'uint256' },
      { name: 'answeredInRound', type: 'uint80' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'decimals',
    outputs: [{ name: '', type: 'uint8' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'description',
    outputs: [{ name: '', type: 'string' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

// ========================================
// POOL SWAP TEST ABI (Uniswap V4)
// ========================================
export const POOL_SWAP_TEST_ABI = [
  {
    inputs: [
      {
        components: [
          { name: 'currency0', type: 'address' },
          { name: 'currency1', type: 'address' },
          { name: 'fee', type: 'uint24' },
          { name: 'tickSpacing', type: 'int24' },
          { name: 'hooks', type: 'address' },
        ],
        name: 'key',
        type: 'tuple',
      },
      {
        components: [
          { name: 'zeroForOne', type: 'bool' },
          { name: 'amountSpecified', type: 'int256' },
          { name: 'sqrtPriceLimitX96', type: 'uint160' },
        ],
        name: 'params',
        type: 'tuple',
      },
      {
        components: [
          { name: 'takeClaims', type: 'bool' },
          { name: 'settleUsingBurn', type: 'bool' },
        ],
        name: 'testSettings',
        type: 'tuple',
      },
      { name: 'hookData', type: 'bytes' },
    ],
    name: 'swap',
    outputs: [
      {
        components: [
          { name: 'amount0', type: 'int128' },
          { name: 'amount1', type: 'int128' },
        ],
        name: 'delta',
        type: 'tuple',
      },
    ],
    stateMutability: 'payable',
    type: 'function',
  },
] as const;
// ========================================
// POOL MANAGER ABI (for reading pool state)
// ========================================
export const POOL_MANAGER_ABI = [
  {
    inputs: [{ name: 'id', type: 'bytes32' }],
    name: 'getSlot0',
    outputs: [
      { name: 'sqrtPriceX96', type: 'uint160' },
      { name: 'tick', type: 'int24' },
      { name: 'protocolFee', type: 'uint24' },
      { name: 'lpFee', type: 'uint24' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'id', type: 'bytes32' }],
    name: 'getLiquidity',
    outputs: [{ name: 'liquidity', type: 'uint128' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const;
