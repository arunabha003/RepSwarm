import React, { useEffect, useMemo, useState } from "react";
import { ethers } from "ethers";
import { cfg } from "../lib/config";
import { connectWallet, getReadProvider } from "../lib/wallet";
import {
  SwarmCoordinatorAbi,
  AgentExecutorAbi,
  LPFeeAccumulatorAbi,
  FlashLoanBackrunnerAbi,
  FlashBackrunExecutorAgentAbi,
  SimpleRouteAgentAbi,
  SwarmAgentRegistryAbi,
  SwarmAgentAbi,
  OracleRegistryAbi,
  PoolManagerAbi,
  ERC20Abi
} from "../lib/abis";
import { encodeCandidatePath, toBytes32PoolIdFromPoolKey, type PathKey } from "../lib/encode";

type Tab = "dashboard" | "swap" | "intent" | "lp" | "backrun" | "admin";

type WalletState =
  | { status: "disconnected" }
  | { status: "connected"; signer: ethers.Signer; address: string; chainId: number };

// ==================== Helper Functions ====================

function shortAddr(a: string) {
  if (!a || a.length < 10) return a;
  return `${a.slice(0, 6)}…${a.slice(-4)}`;
}

function isZeroAddr(a: string) {
  return a.toLowerCase() === "0x0000000000000000000000000000000000000000";
}

function extractRevertData(e: any): string | null {
  const cands = [e?.data, e?.error?.data, e?.info?.error?.data, e?.cause?.data];
  for (const c of cands) {
    if (typeof c === "string" && c.startsWith("0x")) return c;
  }
  return null;
}

function fmtContractError(e: any, contract: ethers.Contract | null): string {
  const data = extractRevertData(e);
  if (data && contract?.interface?.parseError) {
    try {
      const parsed: any = contract.interface.parseError(data);
      if (parsed && parsed.name) {
        const args = parsed?.args ? Array.from(parsed.args).map((x: any) => String(x)).join(", ") : "";
        return args ? `${parsed.name}(${args})` : String(parsed.name);
      }
    } catch {
      // ignore; fall back below
    }
  }
  return e?.shortMessage ?? e?.reason ?? e?.message ?? String(e);
}

function sortCurrencies(a: string, b: string): { currency0: string; currency1: string } {
  const aa = BigInt(a.toLowerCase());
  const bb = BigInt(b.toLowerCase());
  return aa < bb ? { currency0: a, currency1: b } : { currency0: b, currency1: a };
}

function parseBn(s: string): bigint {
  const t = s.trim();
  if (t === "") return 0n;
  if (t.startsWith("0x")) return BigInt(t);
  if (t.includes(".")) {
    return ethers.parseEther(t);
  }
  return BigInt(t);
}

function parseUnitsSafe(s: string, decimals: number): bigint {
  const t = s.trim();
  if (t === "") return 0n;
  if (t.startsWith("0x")) return BigInt(t);
  // Treat user-entered decimals as human units (e.g. "11000" DAI => 11000e18).
  return ethers.parseUnits(t, decimals);
}

function fmt18(x: bigint, decimals = 18, fracDigits = 6): string {
  // Avoid Number(...) here: balances on forks can be huge and exceed JS float precision.
  const s = ethers.formatUnits(x, decimals);
  if (fracDigits <= 0) return s.split(".")[0] ?? s;
  const dot = s.indexOf(".");
  if (dot === -1) return s;
  const i = s.slice(0, dot);
  const f = s.slice(dot + 1, dot + 1 + fracDigits);
  return `${i}.${f}`;
}

function fmtSignedUnits(x: bigint, decimals = 18, fracDigits = 3): string {
  const neg = x < 0n;
  const abs = neg ? -x : x;
  const out = fmt18(abs, decimals, fracDigits);
  return neg ? `-${out}` : out;
}

async function readTokenMeta(token: string, runner: any): Promise<{ symbol: string; decimals: number }> {
  if (isZeroAddr(token)) return { symbol: "ETH", decimals: 18 };
  const erc20 = new ethers.Contract(token, ERC20Abi, runner);
  const [decimals, symbol] = await Promise.all([
    erc20.decimals().catch(() => 18),
    erc20.symbol().catch(() => "TOKEN")
  ]);
  return { symbol: String(symbol), decimals: Number(decimals) };
}

function sqrtPriceX96ToPrice18(sqrtPriceX96: bigint): bigint {
  const Q192 = 2n ** 192n;
  const num = sqrtPriceX96 * sqrtPriceX96 * 10n ** 18n;
  return num / Q192;
}

function bpsDiff(a: bigint, b: bigint): bigint {
  if (b === 0n) return 0n;
  return ((a - b) * 10000n) / b;
}

// ==================== Uniswap v4 Pool State Helpers ====================

// v4-core StateLibrary constants (lib/v4-core/src/libraries/StateLibrary.sol)
const V4_POOLS_SLOT = ethers.toBeHex(6, 32);
const V4_LIQUIDITY_OFFSET = 3n;

function v4PoolStateSlot(poolId: string): string {
  // slot key of Pool.State value: `pools[poolId]`
  // keccak256(abi.encodePacked(poolId, POOLS_SLOT))
  return ethers.solidityPackedKeccak256(["bytes32", "bytes32"], [poolId, V4_POOLS_SLOT]);
}

function addBytes32Slot(slot: string, offset: bigint): string {
  return ethers.toBeHex(BigInt(slot) + offset, 32);
}

function int24From(u: bigint): number {
  // Interpret low 24 bits as signed int24.
  const x = u & 0xffffffn;
  const signed = (x & 0x800000n) !== 0n ? x - 0x1000000n : x;
  return Number(signed);
}

function decodeV4Slot0Word(word: string): { sqrtPriceX96: bigint; tick: number; protocolFee: number; lpFee: number } {
  const data = BigInt(word);
  const sqrtPriceX96 = data & ((1n << 160n) - 1n);
  const tick = int24From(data >> 160n);
  const protocolFee = Number((data >> 184n) & 0xffffffn);
  const lpFee = Number((data >> 208n) & 0xffffffn);
  return { sqrtPriceX96, tick, protocolFee, lpFee };
}

async function readV4Slot0(poolManager: ethers.Contract, poolId: string) {
  const stateSlot = v4PoolStateSlot(poolId);
  const word = (await poolManager.extsload(stateSlot)) as string;
  return decodeV4Slot0Word(word);
}

async function readV4Liquidity(poolManager: ethers.Contract, poolId: string): Promise<bigint> {
  const stateSlot = v4PoolStateSlot(poolId);
  const liqSlot = addBytes32Slot(stateSlot, V4_LIQUIDITY_OFFSET);
  const word = (await poolManager.extsload(liqSlot)) as string;
  return BigInt(word);
}

// ==================== Info Tooltip Component ====================

interface InfoTooltipProps {
  title: string;
  children: React.ReactNode;
}

function InfoTooltip({ title, children }: InfoTooltipProps) {
  const [visible, setVisible] = useState(false);

  return (
    <div className="tooltipWrap">
      <button
        className="infoBtn"
        onClick={() => setVisible(!visible)}
        onMouseEnter={() => setVisible(true)}
        onMouseLeave={() => setVisible(false)}
        aria-label="More information"
      >
        i
      </button>
      <div className={`tooltip ${visible ? "visible" : ""}`}>
        <div className="tooltipTitle">{title}</div>
        <div className="tooltipText">{children}</div>
      </div>
    </div>
  );
}

// ==================== Main App ====================

export function App() {
  const [tab, setTab] = useState<Tab>("dashboard");
  const [wallet, setWallet] = useState<WalletState>({ status: "disconnected" });
  const [toast, setToast] = useState<{ kind: "ok" | "bad"; msg: string } | null>(null);

  const readProvider = useMemo(() => getReadProvider(), []);

  const coordinator = useMemo(() => {
    const p = wallet.status === "connected" ? wallet.signer : readProvider;
    if (!p || isZeroAddr(cfg.coordinator)) return null;
    return new ethers.Contract(cfg.coordinator, SwarmCoordinatorAbi, p);
  }, [wallet, readProvider]);

  const agentExecutor = useMemo(() => {
    const p = wallet.status === "connected" ? wallet.signer : readProvider;
    if (!p || isZeroAddr(cfg.agentExecutor)) return null;
    return new ethers.Contract(cfg.agentExecutor, AgentExecutorAbi, p);
  }, [wallet, readProvider]);

  const lpAccumulator = useMemo(() => {
    const p = wallet.status === "connected" ? wallet.signer : readProvider;
    if (!p || isZeroAddr(cfg.lpAccumulator)) return null;
    return new ethers.Contract(cfg.lpAccumulator, LPFeeAccumulatorAbi, p);
  }, [wallet, readProvider]);

  const flashBackrunner = useMemo(() => {
    const p = wallet.status === "connected" ? wallet.signer : readProvider;
    if (!p || isZeroAddr(cfg.flashBackrunner)) return null;
    return new ethers.Contract(cfg.flashBackrunner, FlashLoanBackrunnerAbi, p);
  }, [wallet, readProvider]);

  const flashBackrunExecutorAgent = useMemo(() => {
    const p = wallet.status === "connected" ? wallet.signer : readProvider;
    if (!p || isZeroAddr(cfg.flashBackrunExecutorAgent)) return null;
    return new ethers.Contract(cfg.flashBackrunExecutorAgent, FlashBackrunExecutorAgentAbi, p);
  }, [wallet, readProvider]);

  const simpleRouteAgent = useMemo(() => {
    const p = wallet.status === "connected" ? wallet.signer : readProvider;
    if (!p || isZeroAddr(cfg.simpleRouteAgent)) return null;
    return new ethers.Contract(cfg.simpleRouteAgent, SimpleRouteAgentAbi, p);
  }, [wallet, readProvider]);

  const swarmAgentRegistry = useMemo(() => {
    const p = wallet.status === "connected" ? wallet.signer : readProvider;
    if (!p || isZeroAddr(cfg.swarmAgentRegistry)) return null;
    return new ethers.Contract(cfg.swarmAgentRegistry, SwarmAgentRegistryAbi, p);
  }, [wallet, readProvider]);

  const oracleRegistry = useMemo(() => {
    const p = wallet.status === "connected" ? wallet.signer : readProvider;
    if (!p || isZeroAddr(cfg.oracleRegistry)) return null;
    return new ethers.Contract(cfg.oracleRegistry, OracleRegistryAbi, p);
  }, [wallet, readProvider]);

  const poolManager = useMemo(() => {
    const p = wallet.status === "connected" ? wallet.signer : readProvider;
    if (!p || isZeroAddr(cfg.poolManager)) return null;
    return new ethers.Contract(cfg.poolManager, PoolManagerAbi, p);
  }, [wallet, readProvider]);

  async function onConnect() {
    try {
      const w = await connectWallet();
      setWallet({ status: "connected", signer: w.signer, address: w.address, chainId: w.chainId });
      setToast({ kind: "ok", msg: `Connected: ${shortAddr(w.address)} (chainId=${w.chainId})` });
    } catch (e: any) {
      setToast({ kind: "bad", msg: e?.message ?? String(e) });
    }
  }

  return (
    <div className="wrap">
      {/* Top Bar */}
      <div className="topbar">
        <div className="brand">
          <h1>Swarm Protocol</h1>
          <p>MEV protection · Value redistribution · Intent routing</p>
        </div>
        <div className="topbarActions">
          {wallet.status === "connected" ? (
            <span className="pill ok">
              <span className="statusDot active" />
              {shortAddr(wallet.address)} · Chain {wallet.chainId}
            </span>
          ) : (
            <span className="pill bad">
              <span className="statusDot inactive" />
              Disconnected
            </span>
          )}
          <button className="btn btnPrimary" onClick={onConnect}>
            {wallet.status === "connected" ? "Reconnect" : "Connect Wallet"}
          </button>
        </div>
      </div>

      {/* Tab Navigation */}
      <div className="tabs" role="tablist" aria-label="Swarm tabs">
        <button className="tab" aria-selected={tab === "dashboard"} onClick={() => setTab("dashboard")}>
          📊 Dashboard
        </button>
        <button className="tab" aria-selected={tab === "swap"} onClick={() => setTab("swap")}>
          🔄 Quick Intent
        </button>
        <button className="tab" aria-selected={tab === "intent"} onClick={() => setTab("intent")}>
          📋 Intent Desk
        </button>
        <button className="tab" aria-selected={tab === "lp"} onClick={() => setTab("lp")}>
          💰 LP Donations
        </button>
        <button className="tab" aria-selected={tab === "backrun"} onClick={() => setTab("backrun")}>
          ⚡ Backrun
        </button>
        <button className="tab" aria-selected={tab === "admin"} onClick={() => setTab("admin")}>
          ⚙️ Admin
        </button>
      </div>

      {/* Toast Notification */}
      {toast && (
        <div className={`toast ${toast.kind}`}>
          {toast.kind === "ok" ? "✓ " : "✗ "}
          {toast.msg}
        </div>
      )}

      {/* Tab Content */}
      {tab === "dashboard" ? (
        <ProtocolDashboard
          wallet={wallet}
          coordinator={coordinator}
          agentExecutor={agentExecutor}
          simpleRouteAgent={simpleRouteAgent}
          swarmAgentRegistry={swarmAgentRegistry}
          oracleRegistry={oracleRegistry}
          poolManager={poolManager}
          onToast={setToast}
        />
      ) : tab === "swap" ? (
        <QuickIntentPanel coordinator={coordinator} poolManager={poolManager} onToast={setToast} />
      ) : tab === "intent" ? (
        <IntentDeskPanel coordinator={coordinator} simpleRouteAgent={simpleRouteAgent} onToast={setToast} />
      ) : tab === "lp" ? (
        <LpPanel lpAccumulator={lpAccumulator} onToast={setToast} />
      ) : tab === "backrun" ? (
        <BackrunPanel
          flashBackrunner={flashBackrunner}
          flashBackrunExecutorAgent={flashBackrunExecutorAgent}
          onToast={setToast}
        />
      ) : (
        <AdminPanel
          coordinator={coordinator}
          agentExecutor={agentExecutor}
          swarmAgentRegistry={swarmAgentRegistry}
          onToast={setToast}
        />
      )}
    </div>
  );
}

// ==================== Protocol Dashboard ====================

function ProtocolDashboard({
  wallet,
  coordinator,
  agentExecutor,
  simpleRouteAgent,
  swarmAgentRegistry,
  oracleRegistry,
  poolManager,
  onToast
}: {
  wallet: WalletState;
  coordinator: ethers.Contract | null;
  agentExecutor: ethers.Contract | null;
  simpleRouteAgent: ethers.Contract | null;
  swarmAgentRegistry: ethers.Contract | null;
  oracleRegistry: ethers.Contract | null;
  poolManager: ethers.Contract | null;
  onToast: (t: { kind: "ok" | "bad"; msg: string } | null) => void;
}) {
  const [busy, setBusy] = useState(false);
  const [market, setMarket] = useState<null | {
    oraclePrice18: bigint;
    oracleUpdatedAt: bigint;
    poolPrice18: bigint;
    tick: number;
    lpFee: number;
    liquidity: bigint;
    diffBps: bigint;
    poolId: string;
    oracleErr?: string;
  }>(null);

  const [balances, setBalances] = useState<null | {
    eth: bigint;
    inBal: bigint;
    outBal: bigint;
    inSym: string;
    outSym: string;
    inDec: number;
    outDec: number;
  }>(null);

  const [hookAgents, setHookAgents] = useState<null | {
    arb: any;
    fee: any;
    backrun: any;
  }>(null);
  const [routeAgentInfo, setRouteAgentInfo] = useState<any | null>(null);

  const poolId = useMemo(() => {
    try {
      const { currency0, currency1 } = sortCurrencies(cfg.defaultPool.currencyIn, cfg.defaultPool.currencyOut);
      return toBytes32PoolIdFromPoolKey({
        currency0,
        currency1,
        fee: Number(cfg.defaultPool.fee),
        tickSpacing: Number(cfg.defaultPool.tickSpacing),
        hooks: cfg.defaultPool.hooks
      });
    } catch {
      return "0x";
    }
  }, []);

  async function loadAll() {
    onToast(null);
    setBusy(true);
    try {
      const addr = wallet.status === "connected" ? wallet.address : null;
      const rp = (coordinator?.runner ?? agentExecutor?.runner ?? oracleRegistry?.runner ?? poolManager?.runner) as any;
      const provider = rp?.provider ?? (rp instanceof ethers.JsonRpcProvider ? rp : null);

      // Market data (never hard-fail the whole dashboard if the oracle call reverts)
      if (poolManager && poolId !== "0x") {
        const [s0, liq] = await Promise.all([readV4Slot0(poolManager, poolId), readV4Liquidity(poolManager, poolId)]);
        const sqrt = BigInt(s0.sqrtPriceX96);
        const tick = Number(s0.tick);
        const lpFee = Number(s0.lpFee);
        const poolPrice18 = sqrtPriceX96ToPrice18(sqrt);

        let oraclePrice18 = 0n;
        let oracleUpdatedAt = 0n;
        let oracleErr: string | undefined;

        if (oracleRegistry) {
          try {
            const o = await oracleRegistry.getLatestPrice(cfg.defaultPool.currencyOut, cfg.defaultPool.currencyIn);
            oraclePrice18 = BigInt(o[0]);
            oracleUpdatedAt = BigInt(o[1]);
          } catch (e: any) {
            oracleErr = fmtContractError(e, oracleRegistry);
          }
        } else {
          oracleErr = "oracle registry not configured";
        }

        const diffBps = oraclePrice18 > 0n ? bpsDiff(poolPrice18, oraclePrice18) : 0n;

        setMarket({
          oraclePrice18,
          oracleUpdatedAt,
          poolPrice18,
          tick,
          lpFee,
          liquidity: BigInt(liq),
          diffBps,
          poolId,
          oracleErr
        });
      }

      // Balances
      if (addr && provider) {
        const inTok = new ethers.Contract(cfg.defaultPool.currencyIn, ERC20Abi, provider);
        const outTok = new ethers.Contract(cfg.defaultPool.currencyOut, ERC20Abi, provider);
        const [eth, inDec, inSym, inBal, outDec, outSym, outBal] = await Promise.all([
          provider.getBalance(addr),
          inTok.decimals().catch(() => 18),
          inTok.symbol().catch(() => "IN"),
          inTok.balanceOf(addr),
          outTok.decimals().catch(() => 18),
          outTok.symbol().catch(() => "OUT"),
          outTok.balanceOf(addr)
        ]);
        setBalances({
          eth: BigInt(eth),
          inBal: BigInt(inBal),
          outBal: BigInt(outBal),
          inSym: String(inSym),
          outSym: String(outSym),
          inDec: Number(inDec),
          outDec: Number(outDec)
        });
      }

      // Hook agent status
      if (agentExecutor) {
        const runner = agentExecutor.runner as any;
        const [arbAddr, feeAddr, backAddr] = await Promise.all([
          agentExecutor.agents(0),
          agentExecutor.agents(1),
          agentExecutor.agents(2)
        ]);

        const loadOne = async (t: "ARB" | "FEE" | "BACKRUN", a: string) => {
          const base: any = { type: t, addr: String(a) };
          if (isZeroAddr(String(a))) return base;
          try {
            const agent = new ethers.Contract(String(a), SwarmAgentAbi, runner);
            const [agentId, conf, stats] = await Promise.all([
              agent.getAgentId().catch(() => 0n),
              agent.getConfidence().catch(() => 0),
              agentExecutor.agentStats(String(a)).catch(() => null)
            ]);
            base.agentId = String(agentId);
            base.confidence = Number(conf);
            if (stats) {
              base.exec = String(stats[0]);
              base.ok = String(stats[1]);
              base.last = String(stats[3]);
            }
            if (swarmAgentRegistry) {
              try {
                const rep = await swarmAgentRegistry.getAgentReputation(String(a));
                base.repCount = String(rep[0]);
                base.repWad = String(rep[1]);
                base.repTier = String(rep[2]);
              } catch {
                // ignore
              }
            }
          } catch {
            // ignore
          }
          return base;
        };

        const [arb, fee, backrun] = await Promise.all([
          loadOne("ARB", String(arbAddr)),
          loadOne("FEE", String(feeAddr)),
          loadOne("BACKRUN", String(backAddr))
        ]);
        setHookAgents({ arb, fee, backrun });
      }

      // Route agent (ERC-8004) status
      const routeAddr = String(cfg.simpleRouteAgent);
      const routeBase: any = { addr: routeAddr, configured: !isZeroAddr(routeAddr) };
      if (!isZeroAddr(routeAddr)) {
        const routeRunner = (simpleRouteAgent?.runner ??
          coordinator?.runner ??
          swarmAgentRegistry?.runner ??
          agentExecutor?.runner) as any;
        const route =
          simpleRouteAgent ??
          (routeRunner ? new ethers.Contract(routeAddr, SimpleRouteAgentAbi, routeRunner) : null);

        if (route) {
          try {
            const [defaultCandidateId, defaultScore, erc8004Id, rep, coordMeta] = await Promise.all([
              route.defaultCandidateId().catch(() => 0n),
              route.defaultScore().catch(() => 0n),
              swarmAgentRegistry?.agentIdentities(routeAddr).catch(() => 0n) ?? Promise.resolve(0n),
              swarmAgentRegistry?.getAgentReputation(routeAddr).catch(() => null) ?? Promise.resolve(null),
              coordinator?.agents(routeAddr).catch(() => null) ?? Promise.resolve(null)
            ]);

            routeBase.defaultCandidateId = String(defaultCandidateId);
            routeBase.defaultScore = String(defaultScore);
            routeBase.erc8004Id = String(erc8004Id);
            if (rep) {
              routeBase.repCount = String(rep[0]);
              routeBase.repWad = String(rep[1]);
              routeBase.repTier = String(rep[2]);
            }
            if (coordMeta) {
              routeBase.coordinatorAgentId = String(coordMeta[0]);
              routeBase.coordinatorActive = Boolean(coordMeta[1]);
            }
          } catch {
            // ignore route metadata failures
          }
        }
      }
      setRouteAgentInfo(routeBase);
    } catch (e: any) {
      onToast({
        kind: "bad",
        msg: fmtContractError(e, coordinator ?? agentExecutor ?? oracleRegistry ?? poolManager ?? swarmAgentRegistry)
      });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="dash">
      <div className="dashHeader">
        <div>
          <div className="dashTitleWrap">
            <div className="dashTitle">📊 Protocol Dashboard</div>
            <InfoTooltip title="Protocol Dashboard">
              Real-time overview of the Swarm protocol status including market prices, your wallet balances, and the
              current state of on-chain hook agents that process every swap.
            </InfoTooltip>
          </div>
          <div className="dashSub mono">
            Pool {market?.poolId ? shortAddr(market.poolId) : "—"} · Oracle {shortAddr(cfg.oracleRegistry)} ·
            PoolManager {shortAddr(cfg.poolManager)}
          </div>
        </div>
        <button className="btn btnPrimary" disabled={busy} onClick={loadAll}>
          {busy ? "Loading…" : "Refresh Dashboard"}
        </button>
      </div>

      <div className="dashGrid">
        {/* Market Card */}
        <div className="dashCard">
          <div className="dashCardHeader">
            <div className="dashCardTitle">
              📈 Market
              <InfoTooltip title="Market Data">
                Shows the current oracle price (from Chainlink) vs the pool's spot price. The difference in bps
                indicates potential arbitrage opportunity. Hook agents use this data to protect your swaps.
              </InfoTooltip>
            </div>
          </div>
          {!market ? (
            <p className="muted">Click Refresh to load market data</p>
          ) : (
            <div className="kvs">
              <div className="kv">
                <b>Oracle Price</b>
                <span>{market.oraclePrice18 > 0n ? `${fmt18(market.oraclePrice18)} DAI/WETH` : "—"}</span>
              </div>
              <div className="kv">
                <b>Pool Spot Price</b>
                <span>{fmt18(market.poolPrice18)} DAI/WETH</span>
              </div>
              <div className="kv">
                <b>Price Diff</b>
                <span>{market.oraclePrice18 > 0n ? `${String(market.diffBps)} bps` : "—"}</span>
              </div>
              <div className="kv">
                <b>Liquidity</b>
                <span>{String(market.liquidity)}</span>
              </div>
              {market.oracleErr ? (
                <div className="kv">
                  <b>Oracle Status</b>
                  <span className="mono">{market.oracleErr}</span>
                </div>
              ) : null}
            </div>
          )}
        </div>

        {/* Wallet Card */}
        <div className="dashCard">
          <div className="dashCardHeader">
            <div className="dashCardTitle">
              👛 Wallet
              <InfoTooltip title="Your Wallet">
                Your current token balances. You'll need tokens to create intents and execute swaps. Make sure you have
                enough of the input token and ETH for gas.
              </InfoTooltip>
            </div>
          </div>
          {wallet.status !== "connected" ? (
            <p className="muted">Connect wallet to see balances</p>
          ) : !balances ? (
            <p className="muted">Click Refresh to load balances</p>
          ) : (
            <div className="kvs">
              <div className="kv">
                <b>ETH</b>
                <span>{fmt18(balances.eth)} ETH</span>
              </div>
              <div className="kv">
                <b>{balances.inSym}</b>
                <span>
                  {fmt18(balances.inBal, balances.inDec)} {balances.inSym}
                </span>
              </div>
              <div className="kv">
                <b>{balances.outSym}</b>
                <span>
                  {fmt18(balances.outBal, balances.outDec)} {balances.outSym}
                </span>
              </div>
            </div>
          )}
        </div>

        {/* Individual Hook Agent Cards */}
        {hookAgents ? (
          <>
            {/* Arbitrage Agent Card */}
            <div className="dashCard agent-arb">
              <div className="agentCardRow">
                <div className="agentCardIcon arb">🎯</div>
                <div>
                  <div className="agentCardName">Arbitrage Agent</div>
                  <span className="agentCardType arb">ARB · Slot 0</span>
                </div>
              </div>
              <div className="kvs">
                <div className="kv">
                  <b>Address</b>
                  <span>{shortAddr(hookAgents.arb.addr)}</span>
                </div>
                <div className="kv">
                  <b>Agent ID</b>
                  <span>{hookAgents.arb.agentId ?? "—"}</span>
                </div>
                <div className="kv">
                  <b>Confidence</b>
                  <span>{hookAgents.arb.confidence !== undefined ? hookAgents.arb.confidence : "—"}</span>
                </div>
                <div className="kv">
                  <b>Executions</b>
                  <span>{hookAgents.arb.exec ?? "—"} total · {hookAgents.arb.ok ?? "—"} ok</span>
                </div>
                <div className="kv">
                  <b>Reputation</b>
                  <span>
                    {hookAgents.arb.repWad !== undefined
                      ? `${fmtSignedUnits(BigInt(hookAgents.arb.repWad), 18, 3)} (${hookAgents.arb.repCount ?? "0"} fb)`
                      : "—"}
                  </span>
                </div>
              </div>
            </div>

            {/* Dynamic Fee Agent Card */}
            <div className="dashCard agent-fee">
              <div className="agentCardRow">
                <div className="agentCardIcon fee">⚡</div>
                <div>
                  <div className="agentCardName">Dynamic Fee Agent</div>
                  <span className="agentCardType fee">FEE · Slot 1</span>
                </div>
              </div>
              <div className="kvs">
                <div className="kv">
                  <b>Address</b>
                  <span>{shortAddr(hookAgents.fee.addr)}</span>
                </div>
                <div className="kv">
                  <b>Agent ID</b>
                  <span>{hookAgents.fee.agentId ?? "—"}</span>
                </div>
                <div className="kv">
                  <b>Confidence</b>
                  <span>{hookAgents.fee.confidence !== undefined ? hookAgents.fee.confidence : "—"}</span>
                </div>
                <div className="kv">
                  <b>Executions</b>
                  <span>{hookAgents.fee.exec ?? "—"} total · {hookAgents.fee.ok ?? "—"} ok</span>
                </div>
                <div className="kv">
                  <b>Reputation</b>
                  <span>
                    {hookAgents.fee.repWad !== undefined
                      ? `${fmtSignedUnits(BigInt(hookAgents.fee.repWad), 18, 3)} (${hookAgents.fee.repCount ?? "0"} fb)`
                      : "—"}
                  </span>
                </div>
              </div>
            </div>

            {/* Backrun Agent Card */}
            <div className="dashCard agent-backrun">
              <div className="agentCardRow">
                <div className="agentCardIcon backrun">🔁</div>
                <div>
                  <div className="agentCardName">Backrun Agent</div>
                  <span className="agentCardType backrun">BACKRUN · Slot 2</span>
                </div>
              </div>
              <div className="kvs">
                <div className="kv">
                  <b>Address</b>
                  <span>{shortAddr(hookAgents.backrun.addr)}</span>
                </div>
                <div className="kv">
                  <b>Agent ID</b>
                  <span>{hookAgents.backrun.agentId ?? "—"}</span>
                </div>
                <div className="kv">
                  <b>Confidence</b>
                  <span>{hookAgents.backrun.confidence !== undefined ? hookAgents.backrun.confidence : "—"}</span>
                </div>
                <div className="kv">
                  <b>Executions</b>
                  <span>{hookAgents.backrun.exec ?? "—"} total · {hookAgents.backrun.ok ?? "—"} ok</span>
                </div>
                <div className="kv">
                  <b>Reputation</b>
                  <span>
                    {hookAgents.backrun.repWad !== undefined
                      ? `${fmtSignedUnits(BigInt(hookAgents.backrun.repWad), 18, 3)} (${hookAgents.backrun.repCount ?? "0"} fb)`
                      : "—"}
                  </span>
                </div>
              </div>
            </div>
          </>
        ) : (
          <div className="dashCard">
            <div className="dashCardHeader">
              <div className="dashCardTitle">🤖 Hook Agents</div>
            </div>
            <p className="muted">Click Refresh to load agent status</p>
          </div>
        )}

        {/* Route Agent Card */}
        <div className="dashCard agent-route">
          <div className="agentCardRow">
            <div className="agentCardIcon route">🧭</div>
            <div>
              <div className="agentCardName">Route Agent</div>
              <span className="agentCardType route">ERC-8004 · Router</span>
            </div>
          </div>
          {!routeAgentInfo ? (
            <p className="muted">Click Refresh to load route agent status</p>
          ) : !routeAgentInfo.configured ? (
            <p className="muted">Not configured (set VITE_SIMPLE_ROUTE_AGENT)</p>
          ) : (
            <div className="kvs">
              <div className="kv">
                <b>Address</b>
                <span>{shortAddr(routeAgentInfo.addr)}</span>
              </div>
              <div className="kv">
                <b>Coordinator</b>
                <span>
                  {routeAgentInfo.coordinatorAgentId ?? "—"} ·{" "}
                  {routeAgentInfo.coordinatorActive === undefined
                    ? "—"
                    : routeAgentInfo.coordinatorActive
                      ? "active"
                      : "inactive"}
                </span>
              </div>
              <div className="kv">
                <b>ERC-8004 ID</b>
                <span>{routeAgentInfo.erc8004Id ?? "—"}</span>
              </div>
              <div className="kv">
                <b>Reputation</b>
                <span>
                  {routeAgentInfo.repWad !== undefined
                    ? `${fmtSignedUnits(BigInt(routeAgentInfo.repWad), 18, 3)} (${routeAgentInfo.repCount ?? "0"} fb)`
                    : "—"}
                </span>
              </div>
              <div className="kv">
                <b>Defaults</b>
                <span>
                  candidate={routeAgentInfo.defaultCandidateId ?? "—"} · score={routeAgentInfo.defaultScore ?? "—"}
                </span>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

// ==================== Quick Intent Panel ====================

function QuickIntentPanel({
  coordinator,
  poolManager,
  onToast
}: {
  coordinator: ethers.Contract | null;
  poolManager: ethers.Contract | null;
  onToast: (t: { kind: "ok" | "bad"; msg: string } | null) => void;
}) {
  const [currencyIn, setCurrencyIn] = useState(cfg.defaultPool.currencyIn);
  const [currencyOut, setCurrencyOut] = useState(cfg.defaultPool.currencyOut);
  const [amountIn, setAmountIn] = useState("0.01");
  const [amountOutMin, setAmountOutMin] = useState("0");
  const [deadlineMinutes, setDeadlineMinutes] = useState("60");
  const [mevFeeBps, setMevFeeBps] = useState("30");
  const [treasuryBps, setTreasuryBps] = useState("200");
  const [lpShareBps, setLpShareBps] = useState("8000");
  const [fee, setFee] = useState(String(cfg.defaultPool.fee || 8388608));
  const [tickSpacing, setTickSpacing] = useState(String(cfg.defaultPool.tickSpacing || 60));
  const [hooks, setHooks] = useState(cfg.defaultPool.hooks);
  const [lastIntentId, setLastIntentId] = useState<string>("");
  const [busy, setBusy] = useState(false);
  const [tokenMeta, setTokenMeta] = useState<{ symbol: string; decimals: number } | null>(null);
  const [tokenOutMeta, setTokenOutMeta] = useState<{ symbol: string; decimals: number } | null>(null);
  const [bal, setBal] = useState<bigint | null>(null);
  const [outBal, setOutBal] = useState<bigint | null>(null);
  const [allow, setAllow] = useState<bigint | null>(null);
  const [preview, setPreview] = useState<null | { poolId: string; price18: bigint; estOut: bigint; note: string }>(null);

  const candidateBytes = useMemo(() => {
    const path: PathKey[] = [
      {
        intermediateCurrency: currencyOut,
        fee: Number(fee),
        tickSpacing: Number(tickSpacing),
        hooks,
        hookData: "0x"
      }
    ];
    try {
      return encodeCandidatePath(path);
    } catch {
      return "0x";
    }
  }, [currencyOut, fee, tickSpacing, hooks]);

  async function refreshAllowanceAndBalance() {
    try {
      if (!coordinator) return;
      const runner = coordinator.runner as any;
      if (!runner) return;
      if (!ethers.isAddress(currencyIn) || !ethers.isAddress(currencyOut)) return;
      const signerAddr = await runner.getAddress?.();
      if (!signerAddr) return;
      const token = new ethers.Contract(currencyIn, ERC20Abi, runner);
      const tokenOut = new ethers.Contract(currencyOut, ERC20Abi, runner);
      const [inMeta, outMeta, balance, outBalance, allowance] = await Promise.all([
        readTokenMeta(currencyIn, runner),
        readTokenMeta(currencyOut, runner),
        token.balanceOf(signerAddr),
        tokenOut.balanceOf(signerAddr),
        token.allowance(signerAddr, await coordinator.getAddress())
      ]);
      setTokenMeta(inMeta);
      setTokenOutMeta(outMeta);
      setBal(BigInt(balance));
      setOutBal(BigInt(outBalance));
      setAllow(BigInt(allowance));
    } catch {
      // Ignore
    }
  }

  useEffect(() => {
    setPreview(null);
    setTokenMeta(null);
    setTokenOutMeta(null);
    setBal(null);
    setOutBal(null);
    setAllow(null);
    if (!coordinator) return;
    if (!ethers.isAddress(currencyIn) || !ethers.isAddress(currencyOut)) return;
    void refreshAllowanceAndBalance();
  }, [coordinator, currencyIn, currencyOut]);

  async function approveMax() {
    if (!coordinator) return onToast({ kind: "bad", msg: "Coordinator not configured." });
    onToast(null);
    setBusy(true);
    try {
      const runner = coordinator.runner as any;
      const token = new ethers.Contract(currencyIn, ERC20Abi, runner);
      const tx = await token.approve(await coordinator.getAddress(), ethers.MaxUint256);
      const receipt = await tx.wait(1);
      onToast({ kind: "ok", msg: `Approved. tx=${receipt.hash}` });
      await refreshAllowanceAndBalance();
    } catch (e: any) {
      onToast({ kind: "bad", msg: fmtContractError(e, coordinator) });
    } finally {
      setBusy(false);
    }
  }

  async function previewSpot() {
    if (!poolManager) return onToast({ kind: "bad", msg: "PoolManager not configured." });
    onToast(null);
    setBusy(true);
    try {
      if (!ethers.isAddress(currencyIn) || !ethers.isAddress(currencyOut)) {
        throw new Error("Invalid token address.");
      }
      const runner = (coordinator?.runner ?? poolManager.runner) as any;
      const [inMeta, outMeta] = await Promise.all([readTokenMeta(currencyIn, runner), readTokenMeta(currencyOut, runner)]);
      setTokenMeta(inMeta);
      setTokenOutMeta(outMeta);

      const { currency0, currency1 } = sortCurrencies(currencyIn, currencyOut);
      const pid = toBytes32PoolIdFromPoolKey({
        currency0,
        currency1,
        fee: Number(fee),
        tickSpacing: Number(tickSpacing),
        hooks
      });
      const s0 = await readV4Slot0(poolManager, pid);
      const sqrt = BigInt(s0.sqrtPriceX96);
      const price18 = sqrtPriceX96ToPrice18(sqrt);

      const amtIn = parseUnitsSafe(amountIn, inMeta.decimals);
      let estOut = 0n;
      let note = "Spot-only estimate (ignores price impact/slippage/fees). Large trades can execute far below this.";
      if (currencyIn.toLowerCase() === currency0.toLowerCase() && currencyOut.toLowerCase() === currency1.toLowerCase()) {
        estOut = (amtIn * price18) / 10n ** 18n;
      } else if (currencyIn.toLowerCase() === currency1.toLowerCase() && currencyOut.toLowerCase() === currency0.toLowerCase()) {
        if (price18 > 0n) estOut = (amtIn * 10n ** 18n) / price18;
      } else {
        note = "Pool key mismatch (check tokens)";
      }

      setPreview({ poolId: pid, price18, estOut, note });
    } catch (e: any) {
      onToast({ kind: "bad", msg: fmtContractError(e, poolManager) });
    } finally {
      setBusy(false);
    }
  }

  async function create() {
    if (!coordinator) return onToast({ kind: "bad", msg: "Coordinator not configured." });
    setBusy(true);
    onToast(null);
    try {
      if (!ethers.isAddress(currencyIn) || !ethers.isAddress(currencyOut)) {
        throw new Error("Invalid token address.");
      }
      const runner = coordinator.runner as any;
      const [inMeta, outMeta] = await Promise.all([readTokenMeta(currencyIn, runner), readTokenMeta(currencyOut, runner)]);
      setTokenMeta(inMeta);
      setTokenOutMeta(outMeta);
      const params = {
        currencyIn,
        currencyOut,
        amountIn: parseUnitsSafe(amountIn, inMeta.decimals),
        amountOutMin: parseUnitsSafe(amountOutMin, outMeta.decimals),
        deadline: BigInt(Math.floor(Date.now() / 1000) + Number(deadlineMinutes || "60") * 60),
        mevFeeBps: Number(mevFeeBps),
        treasuryBps: Number(treasuryBps),
        lpShareBps: Number(lpShareBps)
      };

      const tx = await coordinator.createIntent(params, [candidateBytes]);
      const receipt = await tx.wait(1);

      const ev = receipt.logs
        .map((l: any) => {
          try {
            return coordinator.interface.parseLog(l);
          } catch {
            return null;
          }
        })
        .find((x: any) => x && x.name === "IntentCreated");

      const intentId = ev ? String(ev.args.intentId) : "(unknown)";
      setLastIntentId(intentId);
      onToast({ kind: "ok", msg: `Intent created! ID: ${intentId}` });
      await refreshAllowanceAndBalance();
    } catch (e: any) {
      onToast({ kind: "bad", msg: fmtContractError(e, coordinator) });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="row">
      {/* Create Intent Card */}
      <div className="card">
        <div className="cardHeader">
          <div className="cardTitleWrap">
            <h2>Create MEV-Protected Intent</h2>
            <InfoTooltip title="What is an Intent?">
              An intent is an MEV-protected swap request. Instead of swapping directly, you declare your intention to swap.
              Route agents then compete to find the best execution path, and the swap is executed with MEV protection
              from the Swarm hook. This protects you from sandwich attacks and front-running.
            </InfoTooltip>
          </div>
          <span className="pill info">{shortAddr(cfg.coordinator)}</span>
        </div>

        {/* Quick Actions */}
        <div className="flexRow mb-4">
          <button className="btn" disabled={busy} onClick={refreshAllowanceAndBalance}>
            Refresh Balance
          </button>
          <button className="btn" disabled={busy} onClick={previewSpot}>
            Preview Spot
          </button>
          <button className="btn btnPrimary" disabled={busy} onClick={approveMax}>
            Approve Token
          </button>
          {tokenMeta && <span className="pill ok">{tokenMeta.symbol}</span>}
        </div>

        {/* Balance/Allowance Display */}
        <div className="kvs mb-4">
          <div className="kv">
            <b>Input Balance</b>
            <span>{bal === null ? "—" : fmt18(bal, tokenMeta?.decimals ?? 18)} {tokenMeta?.symbol ?? ""}</span>
          </div>
          <div className="kv">
            <b>Output Balance</b>
            <span>{outBal === null ? "—" : fmt18(outBal, tokenOutMeta?.decimals ?? 18)} {tokenOutMeta?.symbol ?? ""}</span>
          </div>
          <div className="kv">
            <b>Allowance</b>
            <span>{allow === null ? "—" : fmt18(allow, tokenMeta?.decimals ?? 18)}</span>
          </div>
        </div>

        {/* Form Fields */}
        <div className="grid2">
          <div className="field">
            <label>Token In (address)</label>
            <input value={currencyIn} onChange={(e) => setCurrencyIn(e.target.value)} />
          </div>
          <div className="field">
            <label>Token Out (address)</label>
            <input value={currencyOut} onChange={(e) => setCurrencyOut(e.target.value)} />
          </div>
          <div className="field">
            <label>Amount In</label>
            <input value={amountIn} onChange={(e) => setAmountIn(e.target.value)} placeholder="0.01" />
          </div>
          <div className="field">
            <label>Min Amount Out</label>
            <input value={amountOutMin} onChange={(e) => setAmountOutMin(e.target.value)} placeholder="0" />
          </div>
          <div className="field">
            <label>MEV Fee (bps)</label>
            <input value={mevFeeBps} onChange={(e) => setMevFeeBps(e.target.value)} />
          </div>
          <div className="field">
            <label>LP Share (bps)</label>
            <input value={lpShareBps} onChange={(e) => setLpShareBps(e.target.value)} />
          </div>
          <div className="field">
            <label>Deadline (minutes from now)</label>
            <input value={deadlineMinutes} onChange={(e) => setDeadlineMinutes(e.target.value)} placeholder="60" />
          </div>
        </div>

        <div className="mt-4">
          <button className="btn btnPrimary" disabled={busy} onClick={create}>
            {busy ? "Creating…" : "Create Intent"}
          </button>
          {lastIntentId && <span className="pill ok mt-3" style={{ marginLeft: 12 }}>Intent #{lastIntentId}</span>}
        </div>

        {/* Preview Box */}
        {preview && (
          <div className="previewBox">
            <div className="previewTitle">Spot Preview</div>
            <div className="kvs">
              <div className="kv">
                <b>Pool ID</b>
                <span>{shortAddr(preview.poolId)}</span>
              </div>
              <div className="kv">
                <b>Spot Estimate (not guaranteed)</b>
                <span>
                  {tokenOutMeta ? `${fmt18(preview.estOut, tokenOutMeta.decimals)} ${tokenOutMeta.symbol}` : String(preview.estOut)}
                </span>
              </div>
            </div>
            <p className="muted mt-3">{preview.note}</p>
          </div>
        )}
      </div>

      {/* How It Works Card */}
      <div className="card">
        <div className="cardHeader">
          <div className="cardTitleWrap">
            <h2>How It Works</h2>
            <InfoTooltip title="Intent Flow">
              The intent system separates order submission from execution, allowing for MEV protection and optimal
              routing through the Swarm hook.
            </InfoTooltip>
          </div>
          <span className="pill">Agent-Driven</span>
        </div>

        <div className="stepsList">
          <div className="step">
            <div className="stepNum">1</div>
            <div className="stepContent">
              <div className="stepTitle">Create Intent</div>
              <div className="stepDesc">Submit your swap intent with desired parameters. No tokens are swapped yet.</div>
            </div>
          </div>
          <div className="step">
            <div className="stepNum">2</div>
            <div className="stepContent">
              <div className="stepTitle">Agents Propose Routes</div>
              <div className="stepDesc">Route agents analyze your intent and propose the best execution paths.</div>
            </div>
          </div>
          <div className="step">
            <div className="stepNum">3</div>
            <div className="stepContent">
              <div className="stepTitle">Execute Intent</div>
              <div className="stepDesc">You execute the winning proposal. The swap goes through the MEV-protected hook.</div>
            </div>
          </div>
        </div>

        <p className="muted mt-4">
          Route proposals can be triggered from the frontend through `SimpleRouteAgent`, so no `cast` command is needed
          for the demo flow.
        </p>
      </div>
    </div>
  );
}

// ==================== Intent Desk Panel ====================

function IntentDeskPanel({
  coordinator,
  simpleRouteAgent,
  onToast
}: {
  coordinator: ethers.Contract | null;
  simpleRouteAgent: ethers.Contract | null;
  onToast: (t: { kind: "ok" | "bad"; msg: string } | null) => void;
}) {
  const [intentId, setIntentId] = useState("");
  const [info, setInfo] = useState<any | null>(null);
  const [payer, setPayer] = useState<string>("");
  const [inMeta, setInMeta] = useState<{ symbol: string; decimals: number } | null>(null);
  const [inBal, setInBal] = useState<bigint | null>(null);
  const [inAllow, setInAllow] = useState<bigint | null>(null);
  const [busy, setBusy] = useState(false);

  async function refreshPayerAndAllowance(intent: any) {
    try {
      if (!coordinator) return;
      const runner: any = coordinator.runner;
      const addr = await runner?.getAddress?.();
      if (!addr) return;
      setPayer(String(addr));

      const tokenIn = String(intent.currencyIn);
      if (isZeroAddr(tokenIn)) return;

      const erc20 = new ethers.Contract(tokenIn, ERC20Abi, runner);
      const [decimals, symbol, bal, allow] = await Promise.all([
        erc20.decimals().catch(() => 18),
        erc20.symbol().catch(() => "TOKEN_IN"),
        erc20.balanceOf(addr),
        erc20.allowance(addr, await coordinator.getAddress())
      ]);

      setInMeta({ symbol: String(symbol), decimals: Number(decimals) });
      setInBal(BigInt(bal));
      setInAllow(BigInt(allow));
    } catch {
      // ignore (read-only wallets, weird tokens, etc.)
    }
  }

  async function load() {
    if (!coordinator) return onToast({ kind: "bad", msg: "Coordinator not configured." });
    onToast(null);
    setBusy(true);
    try {
      const id = BigInt(intentId);
      const intent = await coordinator.getIntent(id);
      const count = await coordinator.getCandidateCount(id);
      const agents = await coordinator.getProposalAgents(id);
      const props: any[] = [];
      for (const a of agents) {
        const p = await coordinator.getProposal(id, a);
        props.push({ agent: a, ...p });
      }
      setInfo({ intent, count: Number(count), proposalAgents: agents, proposals: props });
      await refreshPayerAndAllowance(intent);
    } catch (e: any) {
      onToast({ kind: "bad", msg: fmtContractError(e, coordinator) });
    } finally {
      setBusy(false);
    }
  }

  async function ensureAllowanceForIntent(intent: any) {
    if (!coordinator) return;
    const tokenIn = String(intent.currencyIn);
    const amountIn = BigInt(intent.amountIn);
    if (isZeroAddr(tokenIn)) return;

    const runner: any = coordinator.runner;
    const addr = await runner?.getAddress?.();
    if (!addr) return;

    const erc20 = new ethers.Contract(tokenIn, ERC20Abi, runner);
    const allow: bigint = BigInt(await erc20.allowance(addr, await coordinator.getAddress()));
    if (allow >= amountIn) return;

    const txa = await erc20.approve(await coordinator.getAddress(), ethers.MaxUint256);
    await txa.wait(1);
  }

  async function autoProposeAndExecute() {
    if (!coordinator) return onToast({ kind: "bad", msg: "Coordinator not configured." });
    if (!simpleRouteAgent) return onToast({ kind: "bad", msg: "SimpleRouteAgent not configured." });
    onToast(null);
    setBusy(true);
    try {
      const intent = info?.intent ?? (await coordinator.getIntent(BigInt(intentId)));
      let proposeHash = "skipped";
      try {
        const tx1 = await simpleRouteAgent.propose(BigInt(intentId));
        const r1 = await tx1.wait(1);
        proposeHash = shortAddr(r1.hash);
      } catch {
        // If already proposed, continue to execute.
      }

      await ensureAllowanceForIntent(intent);
      const tx2 = await coordinator.executeIntent(BigInt(intentId));
      const r2 = await tx2.wait(1);
      onToast({
        kind: "ok",
        msg: `Auto flow complete. propose=${proposeHash} execute=${shortAddr(r2.hash)}`
      });
      await load();
    } catch (e: any) {
      onToast({ kind: "bad", msg: fmtContractError(e, simpleRouteAgent ?? coordinator) });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="row">
      {/* Intent Management Card */}
      <div className="card">
        <div className="cardHeader">
          <div className="cardTitleWrap">
            <h2>Intent Manager</h2>
            <InfoTooltip title="Intent Management">
              Load an existing intent and execute one-click router flow using the configured `SimpleRouteAgent`.
            </InfoTooltip>
          </div>
          <span className="pill">Load · Auto Route+Execute</span>
        </div>

        <div className="grid2 mb-4">
          <div className="field">
            <label>Intent ID</label>
            <input value={intentId} onChange={(e) => setIntentId(e.target.value)} placeholder="Enter intent ID" />
          </div>
          <div className="flexRow" style={{ alignItems: "flex-end" }}>
            <button className="btn btnPrimary" disabled={busy || !intentId.trim()} onClick={load}>
              {busy ? "Loading…" : "Load Intent"}
            </button>
            <button className="btn" disabled={busy || !intentId.trim() || !simpleRouteAgent} onClick={autoProposeAndExecute}>
              Auto Propose + Execute via Router
            </button>
          </div>
        </div>

        <div className="kvs mb-4">
          <div className="kv">
            <b>Router Agent</b>
            <span>{simpleRouteAgent ? shortAddr(cfg.simpleRouteAgent) : "Not configured (set VITE_SIMPLE_ROUTE_AGENT)"}</span>
          </div>
        </div>

        {info?.intent ? (
          <div className="kvs mb-4">
            <div className="kv">
              <b>Payer</b>
              <span className="mono">{payer ? shortAddr(payer) : "—"}</span>
            </div>
            <div className="kv">
              <b>Input Token</b>
              <span className="mono">{shortAddr(String(info.intent.currencyIn))}</span>
            </div>
            <div className="kv">
              <b>Amount In</b>
              <span>{inMeta ? `${fmt18(BigInt(info.intent.amountIn), inMeta.decimals)} ${inMeta.symbol}` : String(info.intent.amountIn)}</span>
            </div>
            <div className="kv">
              <b>Balance</b>
              <span>{inBal === null ? "—" : `${fmt18(inBal, inMeta?.decimals ?? 18)} ${inMeta?.symbol ?? ""}`}</span>
            </div>
            <div className="kv">
              <b>Allowance</b>
              <span>{inAllow === null ? "—" : `${fmt18(inAllow, inMeta?.decimals ?? 18)} ${inMeta?.symbol ?? ""}`}</span>
            </div>
          </div>
        ) : null}

        <p className="muted mt-3">
          This view now uses a single route action button: `Auto Propose + Execute via Router`.
        </p>
      </div>

      {/* Intent State Card */}
      <div className="card">
        <div className="cardHeader">
          <div className="cardTitleWrap">
            <h2>Intent State</h2>
            <InfoTooltip title="Current Intent State">
              View the current state of the loaded intent including the requester address, execution status, and all
              submitted proposals from route agents.
            </InfoTooltip>
          </div>
          <span className="pill">Read-Only</span>
        </div>

        {!info ? (
          <div className="emptyState">
            <p>Load an intent to see its details</p>
          </div>
        ) : (
          <>
            <div className="kvs mb-4">
              <div className="kv">
                <b>Requester</b>
                <span>{shortAddr(info.intent.requester)}</span>
              </div>
              <div className="kv">
                <b>Status</b>
                <span>
                  <span className={`statusDot ${info.intent.executed ? "active" : "pending"}`} />
                  {info.intent.executed ? "Executed" : "Pending"}
                </span>
              </div>
              <div className="kv">
                <b>Candidates</b>
                <span>{info.count}</span>
              </div>
              <div className="kv">
                <b>Amount In</b>
                <span>
                  {inMeta ? `${fmt18(BigInt(info.intent.amountIn), inMeta.decimals)} ${inMeta.symbol}` : String(info.intent.amountIn)}
                </span>
              </div>
            </div>

            <div className="sectionHeader">
              <h3>Proposals ({info.proposals.length})</h3>
            </div>

            {info.proposals.length === 0 ? (
              <p className="muted">No proposals submitted yet</p>
            ) : (
              <div className="kvs">
                {info.proposals.map((p: any) => (
                  <div className="kv" key={p.agent}>
                    <b>{shortAddr(p.agent)}</b>
                    <span>Candidate: {String(p.candidateId)} · Score: {String(p.score)}</span>
                  </div>
                ))}
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}

// ==================== LP Panel ====================

function LpPanel({
  lpAccumulator,
  onToast
}: {
  lpAccumulator: ethers.Contract | null;
  onToast: (t: { kind: "ok" | "bad"; msg: string } | null) => void;
}) {
  const [poolId, setPoolId] = useState(() => {
    try {
      const { currency0, currency1 } = sortCurrencies(cfg.defaultPool.currencyIn, cfg.defaultPool.currencyOut);
      return toBytes32PoolIdFromPoolKey({
        currency0,
        currency1,
        fee: Number(cfg.defaultPool.fee),
        tickSpacing: Number(cfg.defaultPool.tickSpacing),
        hooks: cfg.defaultPool.hooks
      });
    } catch {
      return "0x";
    }
  });
  const [busy, setBusy] = useState(false);
  const [info, setInfo] = useState<any | null>(null);
  const [token0Meta, setToken0Meta] = useState<{ symbol: string; decimals: number } | null>(null);
  const [token1Meta, setToken1Meta] = useState<{ symbol: string; decimals: number } | null>(null);

  async function load() {
    if (!lpAccumulator) return onToast({ kind: "bad", msg: "LPFeeAccumulator not configured." });
    onToast(null);
    setBusy(true);
    try {
      const { currency0, currency1 } = sortCurrencies(cfg.defaultPool.currencyIn, cfg.defaultPool.currencyOut);
      const [r, m0, m1, totalDonated0, totalDonated1] = await Promise.all([
        lpAccumulator.canDonate(poolId),
        readTokenMeta(currency0, lpAccumulator.runner as any),
        readTokenMeta(currency1, lpAccumulator.runner as any),
        lpAccumulator.getTotalDonated(poolId, currency0).catch(() => 0n),
        lpAccumulator.getTotalDonated(poolId, currency1).catch(() => 0n)
      ]);
      setInfo({ canDonate: r[0], amount0: r[1], amount1: r[2], totalDonated0: BigInt(totalDonated0), totalDonated1: BigInt(totalDonated1) });
      setToken0Meta(m0);
      setToken1Meta(m1);
    } catch (e: any) {
      onToast({ kind: "bad", msg: fmtContractError(e, lpAccumulator) });
    } finally {
      setBusy(false);
    }
  }

  async function donate() {
    if (!lpAccumulator) return onToast({ kind: "bad", msg: "LPFeeAccumulator not configured." });
    onToast(null);
    setBusy(true);
    try {
      const tx = await lpAccumulator.donateToLPs(poolId);
      const receipt = await tx.wait(1);
      onToast({ kind: "ok", msg: `Donated to LPs! tx=${shortAddr(receipt.hash)}` });
      await load();
    } catch (e: any) {
      onToast({ kind: "bad", msg: fmtContractError(e, lpAccumulator) });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="row">
      {/* LP Donation Card */}
      <div className="card">
        <div className="cardHeader">
          <div className="cardTitleWrap">
            <h2>LP Fee Donation</h2>
            <InfoTooltip title="LP Fee Accumulator">
              The LPFeeAccumulator collects MEV profits captured by the Swarm hook. When thresholds are met, anyone can
              call donate to redistribute these profits to liquidity providers. This ensures LPs benefit from MEV
              protection.
            </InfoTooltip>
          </div>
          <span className="pill ok">Public Function</span>
        </div>

        <div className="field mb-4">
          <label>Pool ID (bytes32)</label>
          <input value={poolId} onChange={(e) => setPoolId(e.target.value)} placeholder="0x..." />
        </div>

        <div className="flexRow mb-4">
          <button className="btn btnPrimary" disabled={busy || poolId === "0x"} onClick={load}>
            Check Donation Status
          </button>
          <button className="btn" disabled={busy || poolId === "0x"} onClick={donate}>
            Donate to LPs
          </button>
        </div>

        {info && (
          <div className="kvs">
            <div className="kv">
              <b>Pool Key Order</b>
              <span className="mono">
                c0={shortAddr(sortCurrencies(cfg.defaultPool.currencyIn, cfg.defaultPool.currencyOut).currency0)} ·
                c1={shortAddr(sortCurrencies(cfg.defaultPool.currencyIn, cfg.defaultPool.currencyOut).currency1)}
              </span>
            </div>
            <div className="kv">
              <b>Can Donate</b>
              <span>
                <span className={`statusDot ${info.canDonate ? "active" : "inactive"}`} />
                {info.canDonate ? "Yes" : "No"}
              </span>
            </div>
            <div className="kv">
              <b>Amount 0 (accumulated)</b>
              <span>
                {fmt18(BigInt(info.amount0), token0Meta?.decimals ?? 18)} {token0Meta?.symbol ?? ""}
                {" · raw "}
                {String(info.amount0)}
              </span>
            </div>
            <div className="kv">
              <b>Amount 1 (accumulated)</b>
              <span>
                {fmt18(BigInt(info.amount1), token1Meta?.decimals ?? 18)} {token1Meta?.symbol ?? ""}
                {" · raw "}
                {String(info.amount1)}
              </span>
            </div>
            <div className="kv">
              <b>Total Donated ({token0Meta?.symbol ?? "Token0"})</b>
              <span>
                {fmt18(info.totalDonated0, token0Meta?.decimals ?? 18)} {token0Meta?.symbol ?? ""}
              </span>
            </div>
            <div className="kv">
              <b>Total Donated ({token1Meta?.symbol ?? "Token1"})</b>
              <span>
                {fmt18(info.totalDonated1, token1Meta?.decimals ?? 18)} {token1Meta?.symbol ?? ""}
              </span>
            </div>
          </div>
        )}
      </div>

      {/* Pool ID Helper Card */}
      <div className="card">
        <div className="cardHeader">
          <div className="cardTitleWrap">
            <h2>Pool ID Calculator</h2>
            <InfoTooltip title="Compute Pool ID">
              Uniswap v4 pool IDs are computed from the pool key parameters. Use this helper to generate the correct
              pool ID for any pool configuration.
            </InfoTooltip>
          </div>
          <span className="pill">Utility</span>
        </div>
        <PoolIdHelper onToast={onToast} />
      </div>
    </div>
  );
}

function PoolIdHelper({ onToast }: { onToast: (t: { kind: "ok" | "bad"; msg: string } | null) => void }) {
  const sortedDefaults = sortCurrencies(cfg.defaultPool.currencyIn, cfg.defaultPool.currencyOut);
  const [currency0, setCurrency0] = useState(sortedDefaults.currency0);
  const [currency1, setCurrency1] = useState(sortedDefaults.currency1);
  const [fee, setFee] = useState(String(cfg.defaultPool.fee || 8388608));
  const [tickSpacing, setTickSpacing] = useState(String(cfg.defaultPool.tickSpacing || 60));
  const [hooks, setHooks] = useState(cfg.defaultPool.hooks);
  const [out, setOut] = useState("");

  function compute() {
    try {
      // PoolKey requires currency0 < currency1 (Uniswap v4 convention).
      const sorted = sortCurrencies(currency0, currency1);
      if (sorted.currency0 !== currency0 || sorted.currency1 !== currency1) {
        setCurrency0(sorted.currency0);
        setCurrency1(sorted.currency1);
      }
      const id = toBytes32PoolIdFromPoolKey({
        currency0: sorted.currency0,
        currency1: sorted.currency1,
        fee: Number(fee),
        tickSpacing: Number(tickSpacing),
        hooks
      });
      setOut(id);
      onToast({ kind: "ok", msg: "Pool ID computed successfully" });
    } catch (e: any) {
      onToast({ kind: "bad", msg: e?.message ?? String(e) });
    }
  }

  return (
    <>
      <div className="grid2">
        <div className="field">
          <label>Currency 0</label>
          <input value={currency0} onChange={(e) => setCurrency0(e.target.value)} />
        </div>
        <div className="field">
          <label>Currency 1</label>
          <input value={currency1} onChange={(e) => setCurrency1(e.target.value)} />
        </div>
        <div className="field">
          <label>Fee</label>
          <input value={fee} onChange={(e) => setFee(e.target.value)} />
        </div>
        <div className="field">
          <label>Tick Spacing</label>
          <input value={tickSpacing} onChange={(e) => setTickSpacing(e.target.value)} />
        </div>
        <div className="field" style={{ gridColumn: "1 / -1" }}>
          <label>Hooks Address</label>
          <input value={hooks} onChange={(e) => setHooks(e.target.value)} />
        </div>
      </div>

      <div className="mt-4">
        <button className="btn btnPrimary" onClick={compute}>
          Compute Pool ID
        </button>
      </div>

      {out && (
        <div className="codeBlock mt-4">{out}</div>
      )}
    </>
  );
}

// ==================== Backrun Panel ====================

function BackrunPanel({
  flashBackrunner,
  flashBackrunExecutorAgent,
  onToast
}: {
  flashBackrunner: ethers.Contract | null;
  flashBackrunExecutorAgent: ethers.Contract | null;
  onToast: (t: { kind: "ok" | "bad"; msg: string } | null) => void;
}) {
  type BackrunnerEventInfo = {
    txHash: string;
    blockNumber: number;
    flashLoanAmount: bigint;
    profit: bigint;
    lpShare: bigint;
    keeper: string;
  };

  type ExecutorEventInfo = {
    txHash: string;
    blockNumber: number;
    caller: string;
    token: string;
    amountIn: bigint;
    bounty: bigint;
  };

  const [poolId, setPoolId] = useState(() => {
    try {
      const { currency0, currency1 } = sortCurrencies(cfg.defaultPool.currencyIn, cfg.defaultPool.currencyOut);
      return toBytes32PoolIdFromPoolKey({
        currency0,
        currency1,
        fee: Number(cfg.defaultPool.fee),
        tickSpacing: Number(cfg.defaultPool.tickSpacing),
        hooks: cfg.defaultPool.hooks
      });
    } catch {
      return "0x";
    }
  });
  const [busy, setBusy] = useState(false);
  const [info, setInfo] = useState<any | null>(null);
  const [profitability, setProfitability] = useState<{ profitable: boolean; estimatedProfit: bigint } | null>(null);
  const [executorConfig, setExecutorConfig] = useState<{ maxFlashloanAmount: bigint; minProfit: bigint } | null>(null);
  const [lastBackrunnerExec, setLastBackrunnerExec] = useState<BackrunnerEventInfo | null>(null);
  const [lastExecutorExec, setLastExecutorExec] = useState<ExecutorEventInfo | null>(null);

  const normalizedPoolId = poolId.trim();
  const validPoolId = normalizedPoolId.startsWith("0x") && normalizedPoolId.length === 66;

  function getProvider(contract: ethers.Contract | null): ethers.Provider | null {
    if (!contract) return null;
    const runner = contract.runner as any;
    const provider = runner?.provider ?? runner;
    return provider && typeof provider.getBlockNumber === "function" ? (provider as ethers.Provider) : null;
  }

  function parseBackrunnerEventFromReceipt(receipt: ethers.TransactionReceipt): BackrunnerEventInfo | null {
    if (!flashBackrunner) return null;
    for (const log of receipt.logs) {
      try {
        const parsed = flashBackrunner.interface.parseLog(log as any) as any;
        if (parsed?.name !== "BackrunExecuted") continue;
        return {
          txHash: receipt.hash,
          blockNumber: receipt.blockNumber,
          flashLoanAmount: BigInt(parsed.args[1]),
          profit: BigInt(parsed.args[2]),
          lpShare: BigInt(parsed.args[3]),
          keeper: String(parsed.args[4])
        };
      } catch {
        // ignore unrelated logs
      }
    }
    return null;
  }

  function parseExecutorEventFromReceipt(receipt: ethers.TransactionReceipt): ExecutorEventInfo | null {
    if (!flashBackrunExecutorAgent) return null;
    for (const log of receipt.logs) {
      try {
        const parsed = flashBackrunExecutorAgent.interface.parseLog(log as any) as any;
        if (parsed?.name !== "BackrunExecuted") continue;
        return {
          txHash: receipt.hash,
          blockNumber: receipt.blockNumber,
          caller: String(parsed.args[1]),
          token: String(parsed.args[2]),
          amountIn: BigInt(parsed.args[3]),
          bounty: BigInt(parsed.args[4])
        };
      } catch {
        // ignore unrelated logs
      }
    }
    return null;
  }

  async function loadRecentExecutionEvents(poolIdValue: string) {
    const provider = getProvider(flashBackrunner) ?? getProvider(flashBackrunExecutorAgent);
    if (!provider) return;

    const latestBlock = await provider.getBlockNumber();
    const fromBlock = Math.max(0, latestBlock - 5000);

    let recentBackrunner: BackrunnerEventInfo | null = null;
    if (flashBackrunner) {
      try {
        const events = await flashBackrunner.queryFilter(
          flashBackrunner.filters.BackrunExecuted(poolIdValue),
          fromBlock,
          latestBlock
        );
        const evt = events.length > 0 ? (events[events.length - 1] as any) : null;
        if (evt?.args) {
          recentBackrunner = {
            txHash: String(evt.transactionHash),
            blockNumber: Number(evt.blockNumber),
            flashLoanAmount: BigInt(evt.args[1]),
            profit: BigInt(evt.args[2]),
            lpShare: BigInt(evt.args[3]),
            keeper: String(evt.args[4])
          };
        }
      } catch {
        // keep null
      }
    }
    setLastBackrunnerExec(recentBackrunner);

    let recentExecutor: ExecutorEventInfo | null = null;
    if (flashBackrunExecutorAgent) {
      try {
        const events = await flashBackrunExecutorAgent.queryFilter(
          flashBackrunExecutorAgent.filters.BackrunExecuted(poolIdValue, null),
          fromBlock,
          latestBlock
        );
        const evt = events.length > 0 ? (events[events.length - 1] as any) : null;
        if (evt?.args) {
          recentExecutor = {
            txHash: String(evt.transactionHash),
            blockNumber: Number(evt.blockNumber),
            caller: String(evt.args[1]),
            token: String(evt.args[2]),
            amountIn: BigInt(evt.args[3]),
            bounty: BigInt(evt.args[4])
          };
        }
      } catch {
        // keep null
      }
    }
    setLastExecutorExec(recentExecutor);
  }

  async function load() {
    if (!flashBackrunner) return onToast({ kind: "bad", msg: "FlashLoanBackrunner not configured." });
    if (!validPoolId) return onToast({ kind: "bad", msg: "Enter a valid bytes32 pool ID." });
    onToast(null);
    setBusy(true);
    try {
      const r = await flashBackrunner.getPendingBackrun(normalizedPoolId);
      setInfo({
        targetPrice: r[0],
        currentPrice: r[1],
        backrunAmount: r[2],
        zeroForOne: r[3],
        timestamp: r[4],
        blockNumber: r[5],
        executed: r[6]
      });
      // Check profitability
      try {
        const prof = await flashBackrunner.checkProfitability(normalizedPoolId);
        setProfitability({ profitable: Boolean(prof[0]), estimatedProfit: BigInt(prof[1]) });
      } catch {
        setProfitability(null);
      }
      if (flashBackrunExecutorAgent) {
        try {
          const [maxFlashloanAmount, cfgMinProfit] = await Promise.all([
            flashBackrunExecutorAgent.maxFlashloanAmount(),
            flashBackrunExecutorAgent.minProfit()
          ]);
          setExecutorConfig({
            maxFlashloanAmount: BigInt(maxFlashloanAmount),
            minProfit: BigInt(cfgMinProfit)
          });
        } catch {
          setExecutorConfig(null);
        }
      } else {
        setExecutorConfig(null);
      }
      await loadRecentExecutionEvents(normalizedPoolId);
    } catch (e: any) {
      onToast({ kind: "bad", msg: fmtContractError(e, flashBackrunner) });
    } finally {
      setBusy(false);
    }
  }

  async function execViaExecutorAgent() {
    if (!flashBackrunExecutorAgent) return onToast({ kind: "bad", msg: "Executor agent not configured." });
    if (!validPoolId) return onToast({ kind: "bad", msg: "Enter a valid bytes32 pool ID." });
    onToast(null);
    setBusy(true);
    try {
      const tx = await flashBackrunExecutorAgent.execute(normalizedPoolId);
      const receipt = await tx.wait(1);
      if (!receipt) throw new Error("No transaction receipt returned.");
      const execEvent = parseExecutorEventFromReceipt(receipt);
      const backrunEvent = parseBackrunnerEventFromReceipt(receipt);
      if (execEvent) setLastExecutorExec(execEvent);
      if (backrunEvent) setLastBackrunnerExec(backrunEvent);
      onToast({
        kind: "ok",
        msg: execEvent
          ? `Executor backrun tx=${shortAddr(receipt.hash)} bounty=${fmt18(execEvent.bounty)}`
          : `Executor backrun tx=${shortAddr(receipt.hash)}`
      });
      await load();
    } catch (e: any) {
      onToast({ kind: "bad", msg: fmtContractError(e, flashBackrunExecutorAgent) });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="row">
      {/* Backrun Console Card */}
      <div className="card">
        <div className="cardHeader">
          <div className="cardTitleWrap">
            <h2>Backrun Console</h2>
            <InfoTooltip title="Backrun Execution">
              Hook logic can detect and record backrun opportunities during swaps. Execution is transaction-driven: a
              manual caller, bot, or the permissionless executor-agent must submit the execution transaction.
              <br /><br />
              Profits are split: 80% to LP accumulator, 20% to keeper/executor.
            </InfoTooltip>
          </div>
          <span className="pill warn">Execution Tool</span>
        </div>

        <p className="muted mb-4">
          Opportunity detection is automatic; execution is not autonomous unless an external caller or bot triggers it.
          Use this panel to execute and inspect on-chain telemetry.
        </p>

        <div className="field mb-4">
          <label>Hook Pool ID (bytes32)</label>
          <input value={poolId} onChange={(e) => setPoolId(e.target.value)} placeholder="0x... (from deploy output Hook Pool poolId)" />
        </div>

        <div className="flexRow">
          <button className="btn btnPrimary" disabled={busy || !validPoolId} onClick={load}>
            Load Opportunity
          </button>
          <button className="btn" disabled={busy || !validPoolId || !flashBackrunExecutorAgent} onClick={execViaExecutorAgent}>
            Execute (Executor Agent)
          </button>
        </div>

        <div className="kvs mt-4">
          <div className="kv">
            <b>Executor Agent</b>
            <span>
              {flashBackrunExecutorAgent
                ? shortAddr(cfg.flashBackrunExecutorAgent)
                : "Not configured (set VITE_FLASH_BACKRUN_EXECUTOR_AGENT)"}
            </span>
          </div>
          {flashBackrunExecutorAgent ? (
            <>
              <div className="kv">
                <b>Executor Max Flashloan</b>
                <span>
                  {executorConfig
                    ? `${fmt18(executorConfig.maxFlashloanAmount)} (${String(executorConfig.maxFlashloanAmount)} raw)`
                    : "Load to fetch"}
                </span>
              </div>
              <div className="kv">
                <b>Executor Min Profit</b>
                <span>{executorConfig ? String(executorConfig.minProfit) : "Load to fetch"}</span>
              </div>
            </>
          ) : null}
        </div>
      </div>

      {/* Pending Opportunity Card */}
      <div className="card">
        <div className="cardHeader">
          <div className="cardTitleWrap">
            <h2>Pending Opportunity</h2>
            <InfoTooltip title="Backrun Opportunity Details">
              Shows the current pending backrun opportunity for the selected pool. If executed is true, the opportunity
              has already been captured.
            </InfoTooltip>
          </div>
          <span className="pill">Read-Only</span>
        </div>

        {!info ? (
          <div className="emptyState">
            <p>Load a pool ID to see pending opportunities</p>
          </div>
        ) : (
          <div className="kvs">
            <div className="kv">
              <b>Status</b>
              <span>
                <span className={`statusDot ${info.executed ? "inactive" : "active"}`} />
                {info.executed ? "Already Executed" : "Available"}
              </span>
            </div>
            <div className="kv">
              <b>Target Price</b>
              <span>{fmt18(BigInt(info.targetPrice))} DAI/WETH</span>
            </div>
            <div className="kv">
              <b>Current Price</b>
              <span>{fmt18(BigInt(info.currentPrice))} DAI/WETH</span>
            </div>
            <div className="kv">
              <b>Backrun Amount</b>
              <span>{fmt18(BigInt(info.backrunAmount))} WETH</span>
            </div>
            <div className="kv">
              <b>Direction</b>
              <span>{info.zeroForOne ? "Zero → One (sell WETH)" : "One → Zero (buy WETH)"}</span>
            </div>
            <div className="kv">
              <b>Detected Block</b>
              <span>{String(info.blockNumber)}</span>
            </div>
            <div className="kv">
              <b>Detected Time</b>
              <span>{BigInt(info.timestamp) > 0n ? new Date(Number(BigInt(info.timestamp)) * 1000).toLocaleString() : "—"}</span>
            </div>
            {profitability && (
              <>
                <div className="kv">
                  <b>Profitable</b>
                  <span>
                    <span className={`statusDot ${profitability.profitable ? "active" : "inactive"}`} />
                    {profitability.profitable ? "Yes — Ready to execute" : "No"}
                  </span>
                </div>
                <div className="kv">
                  <b>Estimated Profit</b>
                  <span>{fmt18(profitability.estimatedProfit)} WETH</span>
                </div>
              </>
            )}
          </div>
        )}

        <div className="kvs mt-4">
          <div className="kv">
            <b>Last Backrunner Event</b>
            <span>{lastBackrunnerExec ? shortAddr(lastBackrunnerExec.txHash) : "—"}</span>
          </div>
          <div className="kv">
            <b>Flash Loan Amount</b>
            <span>
              {lastBackrunnerExec ? `${fmt18(lastBackrunnerExec.flashLoanAmount)} WETH` : "—"}
            </span>
          </div>
          <div className="kv">
            <b>Backrunner Profit</b>
            <span>
              {lastBackrunnerExec ? `${fmt18(lastBackrunnerExec.profit)} WETH` : "—"}
            </span>
          </div>
          <div className="kv">
            <b>LP Share (80%)</b>
            <span>
              {lastBackrunnerExec ? `${fmt18(lastBackrunnerExec.lpShare)} WETH` : "—"}
            </span>
          </div>
          <div className="kv">
            <b>Keeper Bounty (20%)</b>
            <span>
              {lastBackrunnerExec
                ? `${fmt18(lastBackrunnerExec.profit - lastBackrunnerExec.lpShare)} WETH`
                : "—"}
            </span>
          </div>
          <div className="kv">
            <b>Backrunner Keeper</b>
            <span>{lastBackrunnerExec ? shortAddr(lastBackrunnerExec.keeper) : "—"}</span>
          </div>
          <div className="kv">
            <b>Last Executor Event</b>
            <span>{lastExecutorExec ? shortAddr(lastExecutorExec.txHash) : "—"}</span>
          </div>
          <div className="kv">
            <b>Executor Bounty</b>
            <span>{lastExecutorExec ? `${fmt18(lastExecutorExec.bounty)} WETH` : "—"}</span>
          </div>
          <div className="kv">
            <b>Executor Caller</b>
            <span>{lastExecutorExec ? shortAddr(lastExecutorExec.caller) : "—"}</span>
          </div>
        </div>
      </div>
    </div>
  );
}

// ==================== Admin Panel ====================

function AdminPanel({
  coordinator,
  agentExecutor,
  swarmAgentRegistry,
  onToast
}: {
  coordinator: ethers.Contract | null;
  agentExecutor: ethers.Contract | null;
  swarmAgentRegistry: ethers.Contract | null;
  onToast: (t: { kind: "ok" | "bad"; msg: string } | null) => void;
}) {
  const [agentType, setAgentType] = useState("0");
  const [agentAddr, setAgentAddr] = useState("0x");
  const [backupAddr, setBackupAddr] = useState("0x");
  const [enabled, setEnabled] = useState(true);
  const [loadedHookAgents, setLoadedHookAgents] = useState<{ arb: string; fee: string; backrun: string } | null>(null);
  const [arbId, setArbId] = useState<string>("—");
  const [feeId, setFeeId] = useState<string>("—");
  const [backrunId, setBackrunId] = useState<string>("—");

  const [routeAgent, setRouteAgent] = useState("0x");
  const [routeAgentId, setRouteAgentId] = useState("0");
  const [routeActive, setRouteActive] = useState(true);
  const [busy, setBusy] = useState(false);

  async function ex(fn: () => Promise<any>) {
    onToast(null);
    setBusy(true);
    try {
      const tx = await fn();
      const receipt = await tx.wait(1);
      onToast({ kind: "ok", msg: `Transaction confirmed: ${shortAddr(receipt.hash)}` });
    } catch (e: any) {
      onToast({ kind: "bad", msg: fmtContractError(e, coordinator ?? agentExecutor ?? swarmAgentRegistry) });
    } finally {
      setBusy(false);
    }
  }

  async function loadCurrentHookAgents() {
    if (!agentExecutor) return onToast({ kind: "bad", msg: "AgentExecutor not configured." });
    onToast(null);
    setBusy(true);
    try {
      const [arb, fee, backrun] = await Promise.all([
        agentExecutor.agents(0),
        agentExecutor.agents(1),
        agentExecutor.agents(2)
      ]);
      const next = { arb: String(arb), fee: String(fee), backrun: String(backrun) };
      setLoadedHookAgents(next);

      const runner = agentExecutor.runner as any;
      const tryGetId = async (addr: string) => {
        try {
          if (isZeroAddr(addr)) return "0";
          const a = new ethers.Contract(addr, SwarmAgentAbi, runner);
          const id = await a.getAgentId();
          return String(id);
        } catch {
          return "?";
        }
      };
      const [a0, a1, a2] = await Promise.all([tryGetId(next.arb), tryGetId(next.fee), tryGetId(next.backrun)]);
      setArbId(a0);
      setFeeId(a1);
      setBackrunId(a2);
      onToast({ kind: "ok", msg: "Hook agents loaded successfully" });
    } catch (e: any) {
      onToast({ kind: "bad", msg: fmtContractError(e, agentExecutor) });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="row">
      {/* Agent Executor Card */}
      <div className="card">
        <div className="cardHeader">
          <div className="cardTitleWrap">
            <h2>Hook Agent Management</h2>
            <InfoTooltip title="AgentExecutor Admin">
              The AgentExecutor manages on-chain hook agents. As admin, you can:
              <br />• Register/switch active agents
              <br />• Set backup agents for failover
              <br />• Enable/disable agent types
              <br />• Configure reputation-based switching
            </InfoTooltip>
          </div>
          <span className="pill warn">Owner Only</span>
        </div>

        {!agentExecutor ? (
          <p className="muted">Set VITE_AGENT_EXECUTOR to use this panel.</p>
        ) : (
          <>
            <div className="flexRow mb-4">
              <button className="btn btnPrimary" disabled={busy} onClick={loadCurrentHookAgents}>
                Load Current Agents
              </button>
            </div>

            {loadedHookAgents && (
              <div className="previewBox mb-4">
                <div className="previewTitle">Current Hook Agents</div>
                <div className="kvs">
                  <div className="kv">
                    <b>ARBITRAGE (0)</b>
                    <span>{shortAddr(loadedHookAgents.arb)} · ID: {arbId}</span>
                  </div>
                  <div className="kv">
                    <b>DYNAMIC_FEE (1)</b>
                    <span>{shortAddr(loadedHookAgents.fee)} · ID: {feeId}</span>
                  </div>
                  <div className="kv">
                    <b>BACKRUN (2)</b>
                    <span>{shortAddr(loadedHookAgents.backrun)} · ID: {backrunId}</span>
                  </div>
                </div>
              </div>
            )}

            <div className="divider" />

            <div className="sectionHeader">
              <h3>Register/Switch Agent</h3>
            </div>

            <div className="grid2">
              <div className="field">
                <label>Agent Type (0=ARB, 1=FEE, 2=BACKRUN)</label>
                <input value={agentType} onChange={(e) => setAgentType(e.target.value)} />
              </div>
              <div className="field">
                <label>New Agent Address</label>
                <input value={agentAddr} onChange={(e) => setAgentAddr(e.target.value)} />
              </div>
              <div className="field">
                <label>Backup Address</label>
                <input value={backupAddr} onChange={(e) => setBackupAddr(e.target.value)} />
              </div>
              <div className="field">
                <label>Enabled</label>
                <select value={String(enabled)} onChange={(e) => setEnabled(e.target.value === "true")}>
                  <option value="true">Enabled</option>
                  <option value="false">Disabled</option>
                </select>
              </div>
            </div>

            <div className="flexRow mt-4">
              <button className="btn btnPrimary" disabled={busy} onClick={() => ex(() => agentExecutor.registerAgent(Number(agentType), agentAddr))}>
                Register Agent
              </button>
              <button className="btn" disabled={busy} onClick={() => ex(() => agentExecutor.setBackupAgent(Number(agentType), backupAddr))}>
                Set Backup
              </button>
              <button className="btn" disabled={busy} onClick={() => ex(() => agentExecutor.setAgentEnabled(Number(agentType), enabled))}>
                Set Enabled
              </button>
            </div>
          </>
        )}
      </div>

      {/* Coordinator Admin Card */}
      <div className="card">
        <div className="cardHeader">
          <div className="cardTitleWrap">
            <h2>Coordinator Settings</h2>
            <InfoTooltip title="Coordinator Admin">
              The Coordinator handles intent routing. As admin, you can:
              <br />• Register route agents (who can submit proposals)
              <br />• Configure ERC-8004 enforcement (identity/reputation gating)
              <br />• Set treasury address for fee collection
            </InfoTooltip>
          </div>
          <span className="pill warn">Owner Only</span>
        </div>

        {!coordinator ? (
          <p className="muted">Set VITE_COORDINATOR to use this panel.</p>
        ) : (
          <>
            <div className="sectionHeader">
              <h3>Register Route Agent</h3>
              <InfoTooltip title="Route Agent Registration">
                Route agents can submit proposals for intents. In the demo, you can register your own wallet as a route
                agent to test the proposal flow manually.
              </InfoTooltip>
            </div>

            <div className="grid2">
              <div className="field">
                <label>Agent Address</label>
                <input value={routeAgent} onChange={(e) => setRouteAgent(e.target.value)} placeholder="0x..." />
              </div>
              <div className="field">
                <label>ERC-8004 Agent ID</label>
                <input value={routeAgentId} onChange={(e) => setRouteAgentId(e.target.value)} placeholder="0" />
              </div>
              <div className="field">
                <label>Active</label>
                <select value={String(routeActive)} onChange={(e) => setRouteActive(e.target.value === "true")}>
                  <option value="true">Active</option>
                  <option value="false">Inactive</option>
                </select>
              </div>
              <div className="flexRow" style={{ alignItems: "flex-end" }}>
                <button
                  className="btn btnPrimary"
                  disabled={busy}
                  onClick={() => ex(() => coordinator.registerAgent(routeAgent, BigInt(routeAgentId), routeActive))}
                >
                  Register Agent
                </button>
              </div>
            </div>

            <p className="muted mt-4">
              💡 <b>Tip:</b> To test the full flow, register your connected wallet address as a route agent. Then you
              can create intents and submit proposals yourself.
            </p>
          </>
        )}
      </div>
    </div>
  );
}
