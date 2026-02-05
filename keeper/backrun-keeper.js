import "dotenv/config";
import { ethers } from "ethers";

const FLASH_BACKRUNNER_ABI = [
  // view
  "function authorizedKeepers(address) view returns (bool)",
  "function pendingBackruns(bytes32) view returns (tuple((address,address,uint24,int24,address) poolKey,uint256 targetPrice,uint256 currentPrice,uint256 backrunAmount,bool zeroForOne,uint64 timestamp,uint64 blockNumber,bool executed))",
  // execution
  "function executeBackrunPartial(bytes32 poolId,uint256 flashLoanAmount,uint256 minProfit)",
  // events
  "event BackrunOpportunityDetected(bytes32 indexed poolId,uint256 targetPrice,uint256 currentPrice,uint256 backrunAmount,bool zeroForOne)"
];

function env(name, fallback = undefined) {
  const v = process.env[name];
  return v === undefined || v === "" ? fallback : v;
}

function requiredEnv(name) {
  const v = env(name);
  if (!v) throw new Error(`Missing required env var: ${name}`);
  return v;
}

function parseBool(v, fallback = false) {
  if (v === undefined || v === null) return fallback;
  const s = String(v).toLowerCase();
  if (s === "true" || s === "1" || s === "yes") return true;
  if (s === "false" || s === "0" || s === "no") return false;
  return fallback;
}

function parseBigInt(v, fallback) {
  if (v === undefined || v === null || v === "") return fallback;
  return BigInt(v);
}

function chainUrls(chain) {
  if (chain === "sepolia") {
    return {
      rpcUrl: env("SEPOLIA_RPC_URL"),
      wsUrl: env("SEPOLIA_WS_URL")
    };
  }
  if (chain === "mainnet") {
    return {
      rpcUrl: env("MAINNET_RPC_URL"),
      wsUrl: env("MAINNET_WS_URL")
    };
  }
  return {
    rpcUrl: env("RPC_URL"),
    wsUrl: env("WS_URL")
  };
}

async function main() {
  const chain = env("CHAIN", "sepolia");
  const { rpcUrl, wsUrl } = chainUrls(chain);
  const backrunnerAddress = requiredEnv("FLASH_BACKRUNNER_ADDRESS");
  const keeperPk = requiredEnv("KEEPER_PRIVATE_KEY");

  const pollIntervalMs = Number(env("POLL_INTERVAL_MS", "2500"));
  const maxAmount = parseBigInt(env("MAX_FLASHLOAN_AMOUNT_WEI"), 50_000_000_000_000_000n); // 0.05 ETH
  const minProfit = parseBigInt(env("MIN_PROFIT_WEI"), 0n);
  const dryRun = parseBool(env("DRY_RUN", "false"), false);

  let provider;
  if (wsUrl) {
    provider = new ethers.WebSocketProvider(wsUrl);
    console.log(`[keeper] using websocket provider (${chain})`);
  } else if (rpcUrl) {
    provider = new ethers.JsonRpcProvider(rpcUrl);
    console.log(`[keeper] using http provider + polling (${chain})`);
  } else {
    throw new Error(`Missing RPC URL for chain=${chain}. Set ${chain.toUpperCase()}_RPC_URL or RPC_URL.`);
  }

  const wallet = new ethers.Wallet(keeperPk, provider);
  const backrunner = new ethers.Contract(backrunnerAddress, FLASH_BACKRUNNER_ABI, wallet);

  const isAuth = await backrunner.authorizedKeepers(wallet.address);
  if (!isAuth) {
    throw new Error(
      `[keeper] keeper ${wallet.address} is not authorized on backrunner ${backrunnerAddress}. ` +
        `Owner must call setKeeperAuthorization(keeper,true).`
    );
  }

  const filter = backrunner.filters.BackrunOpportunityDetected();
  console.log(`[keeper] listening for BackrunOpportunityDetected on ${backrunnerAddress}`);
  console.log(`[keeper] dryRun=${dryRun} maxAmount=${maxAmount} minProfit=${minProfit} pollIntervalMs=${pollIntervalMs}`);

  const handle = async (log) => {
    const { poolId, backrunAmount } = log.args;
    try {
      const opp = await backrunner.pendingBackruns(poolId);
      if (opp.executed) return;
      if (opp.backrunAmount === 0n) return;

      const amountIn = opp.backrunAmount < maxAmount ? opp.backrunAmount : maxAmount;
      if (amountIn === 0n) return;

      // Simulate first; if it reverts, skip.
      await backrunner.executeBackrunPartial.staticCall(poolId, amountIn, minProfit);

      if (dryRun) {
        console.log(`[keeper] DRY_RUN would execute poolId=${poolId} amountIn=${amountIn} recorded=${backrunAmount}`);
        return;
      }

      const tx = await backrunner.executeBackrunPartial(poolId, amountIn, minProfit);
      console.log(`[keeper] tx sent poolId=${poolId} amountIn=${amountIn} tx=${tx.hash}`);
      await tx.wait(1);
      console.log(`[keeper] tx confirmed ${tx.hash}`);
    } catch (e) {
      const msg = e?.shortMessage || e?.reason || e?.message || String(e);
      console.log(`[keeper] skip poolId=${poolId} (reason: ${msg})`);
    }
  };

  // Websocket: subscribe directly.
  if (provider instanceof ethers.WebSocketProvider) {
    backrunner.on(filter, (...args) => {
      const event = args[args.length - 1];
      handle(event).catch(() => {});
    });
    return;
  }

  // HTTP: polling queryFilter.
  let last = await provider.getBlockNumber();
  console.log(`[keeper] polling from block ${last}`);
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const latest = await provider.getBlockNumber();
    if (latest > last) {
      const logs = await backrunner.queryFilter(filter, last + 1, latest);
      for (const log of logs) {
        await handle(log);
      }
      last = latest;
    }
    await new Promise((r) => setTimeout(r, pollIntervalMs));
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

