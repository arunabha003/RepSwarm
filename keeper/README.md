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

## Options

- `DRY_RUN=true` to simulate only (no txs).
- `MAX_FLASHLOAN_AMOUNT_WEI` to cap execution size (recommended for testnets).
- `MIN_PROFIT_WEI` to require extra profit on top of repaying the flashloan (defaults to 0).

