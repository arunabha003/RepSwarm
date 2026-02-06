import "dotenv/config";
import { ethers } from "ethers";

// Minimal ABIs
const AgentExecutorAbi = [
  "event AgentExecuted(uint8 indexed agentType,address indexed agent,bool success,uint256 value)"
];

const SwarmAgentAbi = ["function getAgentId() view returns (uint256)"];

const ReputationRegistryAbi = [
  "function giveFeedback(uint256 agentId,int128 value,uint8 valueDecimals,string tag1,string tag2,string endpoint,string feedbackURI,bytes32 feedbackHash)"
];

function req(name) {
  const v = process.env[name];
  if (!v || String(v).trim() === "") throw new Error(`Missing env var: ${name}`);
  return String(v);
}

function env(name, fallback) {
  const v = process.env[name];
  if (!v || String(v).trim() === "") return fallback;
  return String(v);
}

function parseAddr(s) {
  return ethers.getAddress(s);
}

async function main() {
  const rpcUrl = env("SEPOLIA_RPC_URL", env("RPC_URL", ""));
  if (!rpcUrl) throw new Error("Set SEPOLIA_RPC_URL (or RPC_URL)");

  const pk = req("KEEPER_PRIVATE_KEY");
  const agentExecutorAddr = parseAddr(req("AGENT_EXECUTOR_ADDRESS"));
  const repRegistryAddr = parseAddr(req("ERC8004_REPUTATION_REGISTRY"));

  const tag1 = env("SCORE_TAG1", "swarm-hook");
  const tag2 = env("SCORE_TAG2", "hook-agents");
  const scoreUp = BigInt(env("SCORE_UP_WAD", String(1n * 10n ** 18n))); // +1 WAD
  const scoreDown = BigInt(env("SCORE_DOWN_WAD", String(1n * 10n ** 18n))); // -1 WAD
  const minIntervalMs = Number(env("MIN_FEEDBACK_INTERVAL_MS", "5000"));

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(pk, provider);

  const executor = new ethers.Contract(agentExecutorAddr, AgentExecutorAbi, provider);
  const rep = new ethers.Contract(repRegistryAddr, ReputationRegistryAbi, wallet);

  console.log("=== Swarm Hook-Agent Score Keeper ===");
  console.log("rpcUrl:", rpcUrl);
  console.log("keeper:", await wallet.getAddress());
  console.log("agentExecutor:", agentExecutorAddr);
  console.log("reputationRegistry:", repRegistryAddr);
  console.log("tags:", `${tag1} / ${tag2}`);
  console.log("minIntervalMs:", minIntervalMs);

  const lastFeedbackAt = new Map(); // key: `${agentType}:${agentAddr}` -> ms

  executor.on("AgentExecuted", async (agentType, agent, success, value, ev) => {
    try {
      const key = `${agentType}:${agent.toLowerCase()}`;
      const now = Date.now();
      const last = lastFeedbackAt.get(key) ?? 0;
      if (now - last < minIntervalMs) return;
      lastFeedbackAt.set(key, now);

      const agentContract = new ethers.Contract(agent, SwarmAgentAbi, provider);
      const agentId = await agentContract.getAgentId();
      if (BigInt(agentId) === 0n) {
        console.log(`[skip] agent=${agent} has agentId=0 (not ERC-8004 linked)`);
        return;
      }

      const delta = success ? scoreUp : -scoreDown;
      const tx = await rep.giveFeedback(
        agentId,
        delta,
        18,
        tag1,
        tag2,
        "",
        "",
        ethers.ZeroHash
      );
      const receipt = await tx.wait(1);

      console.log(
        `[feedback] block=${ev.blockNumber} type=${agentType} agentId=${agentId} success=${success} value=${value} tx=${receipt.hash}`
      );
    } catch (e) {
      console.log("[error] scoring failed:", e?.shortMessage ?? e?.message ?? String(e));
    }
  });
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

