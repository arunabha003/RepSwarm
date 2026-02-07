export const SwarmCoordinatorAbi = [
  // Errors (to decode reverts in the UI)
  "error IntentExpired()",
  "error IntentAlreadyExecuted(uint256 intentId)",
  "error NoCandidates()",
  "error NoProposals(uint256 intentId)",
  "error AgentNotApproved()",
  "error AlreadyProposed()",
  "error DeadlinePassed(uint256 deadline)",
  "error InvalidCandidate(uint256 candidateId)",
  "error InvalidBps(uint256 value)",
  "error UnauthorizedAgent(address agent)",
  "error ReputationTooLow(int128 value,uint8 decimals)",
  "error InvalidPath()",
  "error FeedbackFailed()",

  "event IntentCreated(uint256 indexed intentId,address indexed requester,uint256 candidateCount)",
  "event ProposalSubmitted(uint256 indexed intentId,address indexed agent,uint256 indexed agentId,uint256 candidateId,int256 score)",
  "event IntentExecuted(uint256 indexed intentId,address indexed executor,uint256 candidateId,uint256 agentId)",
  "function nextIntentId() view returns (uint256)",
  "function getIntent(uint256 intentId) view returns (tuple(address requester,address currencyIn,address currencyOut,uint128 amountIn,uint128 amountOutMin,uint64 deadline,uint16 mevFeeBps,uint16 treasuryBps,uint16 lpShareBps,bool executed))",
  "function getCandidateCount(uint256 intentId) view returns (uint256)",
  "function getCandidatePath(uint256 intentId,uint256 candidateId) view returns (bytes)",
  "function getProposalAgents(uint256 intentId) view returns (address[])",
  "function getProposal(uint256 intentId,address agent) view returns (tuple(uint256 agentId,uint256 candidateId,int256 score,bytes data,uint64 timestamp))",
  "function agents(address agent) view returns (tuple(uint256 agentId,bool active))",
  "function treasury() view returns (address)",
  "function enforceIdentity() view returns (bool)",
  "function enforceReputation() view returns (bool)",
  "function registerAgent(address agent,uint256 agentId,bool active)",
  "function setTreasury(address treasury)",
  "function setEnforcement(bool enforceIdentity,bool enforceReputation)",
  "function setReputationConfig(address registry,string tag1,string tag2,int256 minReputationWad)",
  "function setReputationClients(address[] clients)",
  "function createIntent((address currencyIn,address currencyOut,uint128 amountIn,uint128 amountOutMin,uint64 deadline,uint16 mevFeeBps,uint16 treasuryBps,uint16 lpShareBps) params, bytes[] candidatePaths) returns (uint256)",
  "function submitProposal(uint256 intentId,uint256 candidateId,int256 score,bytes data)",
  "function executeIntent(uint256 intentId) payable"
];

export const AgentExecutorAbi = [
  "event AgentRegistered(uint8 indexed agentType,address indexed agent,uint256 agentId)",
  "event AgentSwitched(uint8 indexed agentType,address indexed oldAgent,address indexed newAgent)",
  "event AgentEnabled(uint8 indexed agentType,bool enabled)",
  "event AgentSwitchedDueToReputation(uint8 indexed agentType,address indexed oldAgent,address indexed newAgent,int256 reputationWad)",
  "event OnchainScoringConfigUpdated(address indexed registry,string tag1,string tag2,int128 successWad,int128 failureWad,bool enabled)",
  "function owner() view returns (address)",
  "function agents(uint8 agentType) view returns (address)",
  "function backupAgents(uint8 agentType) view returns (address)",
  "function agentEnabled(uint8 agentType) view returns (bool)",
  "function agentStats(address agent) view returns (uint256 executionCount,uint256 successCount,uint256 totalValueProcessed,uint64 lastExecution)",
  "function scoringEnabled() view returns (bool)",
  "function scoringReputationRegistry() view returns (address)",
  "function scoringTag1() view returns (string)",
  "function scoringTag2() view returns (string)",
  "function scoringSuccessWad() view returns (int128)",
  "function scoringFailureWad() view returns (int128)",
  "function registerAgent(uint8 agentType,address agent)",
  "function setBackupAgent(uint8 agentType,address agent)",
  "function setAgentEnabled(uint8 agentType,bool enabled)",
  "function setOnchainScoringConfig(address reputationRegistry,string tag1,string tag2,int128 successWad,int128 failureWad,bool enabled)",
  "function setReputationSwitchConfig(uint8 agentType,address registry,string tag1,string tag2,int256 minReputationWad,bool enabled)",
  "function setReputationSwitchClients(uint8 agentType,address[] clients)",
  "function checkAndSwitchAgentIfBelowThreshold(uint8 agentType) returns (bool)",
  "function getReputationSwitchConfig(uint8 agentType) view returns (address registry,int256 minReputationWad,bool enabled,uint256 clientCount,string tag1,string tag2)"
];

export const SwarmAgentRegistryAbi = [
  "event AgentRegistered(address indexed agentContract,uint256 indexed agentId,string name,string agentType)",
  "function owner() view returns (address)",
  "function identityRegistry() view returns (address)",
  "function reputationRegistry() view returns (address)",
  "function agentIdentities(address agentContract) view returns (uint256)",
  "function registerAgent(address agentContract,string name,string description,string agentType,string version) returns (uint256)",
  "function getAgentReputation(address agentContract) view returns (uint64 count,int256 reputationWad,uint8 tier)",
  "function getReputationWeight(address agentContract) view returns (uint256 weight)"
];

export const SwarmAgentAbi = [
  "function agentType() view returns (uint8)",
  "function getAgentId() view returns (uint256)",
  "function identityRegistry() view returns (address)",
  "function getConfidence() view returns (uint8)",
  "function configureIdentity(uint256 agentId,address identityRegistry)"
];

export const OracleRegistryAbi = [
  "error StalePrice(uint256 updatedAt,uint256 maxAge)",
  "error InvalidPrice(int256 price)",
  "error FeedNotFound(address base,address quote)",
  "error ZeroAddress()",
  "function getLatestPrice(address base,address quote) view returns (uint256 price,uint256 updatedAt)",
  "function getPriceFeed(address base,address quote) view returns (address)"
];

export const PoolManagerAbi = [
  // Uniswap v4 PoolManager does NOT expose getSlot0/getLiquidity as external methods.
  // Read pool state via IExtsload + the slot math used by v4-core's StateLibrary.
  "function extsload(bytes32 slot) view returns (bytes32 value)"
];

export const LPFeeAccumulatorAbi = [
  "event FeesAccumulated(bytes32 indexed poolId,address indexed currency,uint256 amount)",
  "event FeesDonatedToLPs(bytes32 indexed poolId,address indexed currency0,address indexed currency1,uint256 amount0,uint256 amount1)",
  "function accumulatedFees(bytes32 poolId,address currency) view returns (uint256)",
  "function canDonate(bytes32 poolId) view returns (bool canDonate,uint256 amount0,uint256 amount1)",
  "function getTotalDonated(bytes32 poolId,address currency) view returns (uint256)",
  "function donateToLPs(bytes32 poolId)"
];

export const FlashLoanBackrunnerAbi = [
  "event BackrunOpportunityDetected(bytes32 indexed poolId,uint256 targetPrice,uint256 currentPrice,uint256 backrunAmount,bool zeroForOne)",
  "event BackrunExecuted(bytes32 indexed poolId,uint256 flashLoanAmount,uint256 profit,uint256 lpShare,address keeper)",
  "function authorizedKeepers(address) view returns (bool)",
  "function getPendingBackrun(bytes32 poolId) view returns (uint256 targetPrice,uint256 currentPrice,uint256 backrunAmount,bool zeroForOne,uint64 timestamp,uint64 blockNumber,bool executed)",
  "function checkProfitability(bytes32 poolId) view returns (bool profitable,uint256 estimatedProfit)",
  "function executeBackrunPartial(bytes32 poolId,uint256 flashLoanAmount,uint256 minProfit)",
  "function executeBackrunWithCapital(bytes32 poolId,uint256 amountIn,uint256 minProfit)"
];

export const FlashBackrunExecutorAgentAbi = [
  "event BackrunExecuted(bytes32 indexed poolId,address indexed caller,address token,uint256 amountIn,uint256 bounty)",
  "function maxFlashloanAmount() view returns (uint256)",
  "function minProfit() view returns (uint256)",
  "function execute(bytes32 poolId) returns (address token,uint256 bounty)"
];

export const SimpleRouteAgentAbi = [
  "event ProposalSent(uint256 indexed intentId,uint256 indexed candidateId,int256 score,bytes data)",
  "function defaultCandidateId() view returns (uint256)",
  "function defaultScore() view returns (int256)",
  "function propose(uint256 intentId) returns (uint256 candidateId,int256 score)"
];

export const ERC20Abi = [
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address owner,address spender) view returns (uint256)",
  "function approve(address spender,uint256 amount) returns (bool)"
];
