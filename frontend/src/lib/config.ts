export function env(name: string, fallback = ""): string {
  const v = (import.meta as any).env?.[name];
  if (v === undefined || v === null || String(v).trim() === "") return fallback;
  return String(v);
}

export function addr(name: string): string {
  const v = env(name, "0x0000000000000000000000000000000000000000");
  return v;
}

export const cfg = {
  readRpcUrl: env("VITE_READ_RPC_URL", ""),
  coordinator: addr("VITE_COORDINATOR"),
  agentExecutor: addr("VITE_AGENT_EXECUTOR"),
  lpAccumulator: addr("VITE_LP_ACCUMULATOR"),
  flashBackrunner: addr("VITE_FLASH_BACKRUNNER"),
  swarmAgentRegistry: addr("VITE_SWARM_AGENT_REGISTRY"),
  oracleRegistry: addr("VITE_ORACLE_REGISTRY"),
  poolManager: addr("VITE_POOL_MANAGER"),
  defaultPool: {
    currencyIn: addr("VITE_POOL_CURRENCY_IN"),
    currencyOut: addr("VITE_POOL_CURRENCY_OUT"),
    fee: Number(env("VITE_POOL_FEE", "0")),
    tickSpacing: Number(env("VITE_POOL_TICK_SPACING", "60")),
    hooks: addr("VITE_POOL_HOOKS")
  }
};
