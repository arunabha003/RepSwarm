# Swarm Keeper (Event-Driven Backrun Executor)

This is an off-chain keeper service that listens for `BackrunOpportunityDetected` events and executes the recorded backrun using the `FlashLoanBackrunner`.

The user never does this manually. This is the “automation” piece that makes backruns happen immediately after swaps.

## Setup

1. Install deps:

```bash
cd keeper
npm install
```

2. Create env:

```bash
cp .env.example .env
```

3. Fill in:

- `KEEPER_PRIVATE_KEY`
- `FLASH_BACKRUNNER_ADDRESS`
- `SEPOLIA_RPC_URL` (and optionally `SEPOLIA_WS_URL`)

Important: the backrunner owner must authorize your keeper:

- `FlashLoanBackrunner.setKeeperAuthorization(keeper,true)`

## Run

```bash
cd keeper
npm run start
```

## Hook-Agent Scoring (ERC-8004)

If you want hook agents to accumulate **official ERC-8004 reputation** (so the admin can switch them when they fall below a threshold), run the scoring keeper too:

1. In `keeper/.env`, set:

- `AGENT_EXECUTOR_ADDRESS`
- `ERC8004_REPUTATION_REGISTRY` (Sepolia default is in `.env.example`)
- `SCORE_TAG1` / `SCORE_TAG2`

2. Configure AgentExecutor switching to use the keeper EOA as a client address (in the frontend Admin tab):

- `Set Switch Config`
- `Set Switch Clients` = `<KEEPER_EOA_ADDRESS>`

3. Run:

```bash
cd keeper
npm run score
```

## Options

- `DRY_RUN=true` to simulate only (no txs).
- `MAX_FLASHLOAN_AMOUNT_WEI` to cap execution size (recommended for testnets).
- `MIN_PROFIT_WEI` to require extra profit on top of repaying the flashloan (defaults to 0).
