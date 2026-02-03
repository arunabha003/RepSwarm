// MevRouterHookV2 ABI (minimal for frontend)
export const MEV_ROUTER_HOOK_ABI = [
  {
    inputs: [
      { name: 'poolId', type: 'bytes32' },
    ],
    name: 'getPoolStats',
    outputs: [
      { name: 'totalSwaps', type: 'uint256' },
      { name: 'totalVolume', type: 'uint256' },
      { name: 'totalMevCaptured', type: 'uint256' },
      { name: 'avgSlippage', type: 'uint256' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { name: 'poolId', type: 'bytes32' },
    ],
    name: 'dynamicFees',
    outputs: [{ name: '', type: 'uint24' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

// LPFeeAccumulator ABI
export const LP_FEE_ACCUMULATOR_ABI = [
  {
    inputs: [
      { name: 'poolId', type: 'bytes32' },
    ],
    name: 'getPoolFeeInfo',
    outputs: [
      { name: 'accumulatedFees', type: 'uint256' },
      { name: 'lastDonationTime', type: 'uint256' },
      { name: 'totalDonated', type: 'uint256' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { name: 'poolId', type: 'bytes32' },
    ],
    name: 'donateToLPs',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
] as const;

// SwarmCoordinator ABI
export const SWARM_COORDINATOR_ABI = [
  {
    inputs: [
      {
        components: [
          { name: 'user', type: 'address' },
          { name: 'tokenIn', type: 'address' },
          { name: 'tokenOut', type: 'address' },
          { name: 'amountIn', type: 'uint256' },
          { name: 'minAmountOut', type: 'uint256' },
          { name: 'maxSlippage', type: 'uint256' },
          { name: 'deadline', type: 'uint256' },
          { name: 'mevProtection', type: 'bool' },
        ],
        name: 'intent',
        type: 'tuple',
      },
    ],
    name: 'submitIntent',
    outputs: [{ name: 'intentId', type: 'bytes32' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [{ name: 'intentId', type: 'bytes32' }],
    name: 'getIntentStatus',
    outputs: [
      { name: 'status', type: 'uint8' },
      { name: 'actualAmountOut', type: 'uint256' },
      { name: 'mevCaptured', type: 'uint256' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'getActiveAgents',
    outputs: [
      {
        components: [
          { name: 'agentAddress', type: 'address' },
          { name: 'agentType', type: 'uint8' },
          { name: 'reputation', type: 'uint256' },
          { name: 'totalTasks', type: 'uint256' },
          { name: 'successRate', type: 'uint256' },
        ],
        name: '',
        type: 'tuple[]',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

// SimpleBackrunExecutor ABI
export const BACKRUN_EXECUTOR_ABI = [
  {
    inputs: [{ name: 'poolId', type: 'bytes32' }],
    name: 'poolProfits',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'token', type: 'address' }],
    name: 'getAvailableCapital',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

// ERC20 ABI (minimal)
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
] as const;
