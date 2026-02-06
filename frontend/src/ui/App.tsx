import React, { useMemo, useState } from "react";
import { ethers } from "ethers";
import { cfg } from "../lib/config";
import { connectWallet, getReadProvider } from "../lib/wallet";
import {
  SwarmCoordinatorAbi,
  AgentExecutorAbi,
  LPFeeAccumulatorAbi,
  FlashLoanBackrunnerAbi,
  SwarmAgentRegistryAbi,
  SwarmAgentAbi,
  OracleRegistryAbi,
  PoolManagerAbi,
  ERC20Abi
} from "../lib/abis";
import { encodeCandidatePath, toBytes32PoolIdFromPoolKey, type PathKey } from "../lib/encode";

type Tab = "swap" | "intent" | "lp" | "backrun" | "admin";

type WalletState =
  | { status: "disconnected" }
  | { status: "connected"; signer: ethers.Signer; address: string; chainId: number };

function shortAddr(a: string) {
  if (!a || a.length < 10) return a;
  return `${a.slice(0, 6)}…${a.slice(-4)}`;
}

function isZeroAddr(a: string) {
  return a.toLowerCase() === "0x0000000000000000000000000000000000000000";
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
    // default: treat as ether unit for convenience
    return ethers.parseEther(t);
  }
  return BigInt(t);
}

export function App() {
  const [tab, setTab] = useState<Tab>("swap");
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
      <div className="topbar">
        <div className="brand">
          <h1>Swarm Protocol</h1>
          <p>MEV protection + redistribution. Intent routing. Backrun automation-ready.</p>
        </div>
        <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
          {wallet.status === "connected" ? (
            <span className="pill ok">
              {shortAddr(wallet.address)} · chain {wallet.chainId}
            </span>
          ) : (
            <span className="pill bad">wallet disconnected</span>
          )}
          <button className="btn btnPrimary" onClick={onConnect}>
            {wallet.status === "connected" ? "Reconnect" : "Connect Wallet"}
          </button>
        </div>
      </div>

      <div className="tabs" role="tablist" aria-label="Swarm tabs">
        <button className="tab" aria-selected={tab === "swap"} onClick={() => setTab("swap")}>
          Quick Intent
        </button>
        <button className="tab" aria-selected={tab === "intent"} onClick={() => setTab("intent")}>
          Intent Desk
        </button>
        <button className="tab" aria-selected={tab === "lp"} onClick={() => setTab("lp")}>
          LP Donations
        </button>
        <button className="tab" aria-selected={tab === "backrun"} onClick={() => setTab("backrun")}>
          Backrun
        </button>
        <button className="tab" aria-selected={tab === "admin"} onClick={() => setTab("admin")}>
          Admin
        </button>
      </div>

      {toast ? <div className={`toast ${toast.kind}`}>{toast.msg}</div> : null}

      <ProtocolDashboard
        wallet={wallet}
        coordinator={coordinator}
        agentExecutor={agentExecutor}
        swarmAgentRegistry={swarmAgentRegistry}
        oracleRegistry={oracleRegistry}
        poolManager={poolManager}
        onToast={setToast}
      />

      {tab === "swap" ? (
        <QuickIntentPanel coordinator={coordinator} poolManager={poolManager} onToast={setToast} />
      ) : tab === "intent" ? (
        <IntentDeskPanel coordinator={coordinator} onToast={setToast} />
      ) : tab === "lp" ? (
        <LpPanel lpAccumulator={lpAccumulator} onToast={setToast} />
      ) : tab === "backrun" ? (
        <BackrunPanel flashBackrunner={flashBackrunner} onToast={setToast} />
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

function fmt18(x: bigint, decimals = 18, sig = 6): string {
  if (decimals === 18) {
    return Number(ethers.formatUnits(x, 18)).toPrecision(sig);
  }
  return Number(ethers.formatUnits(x, decimals)).toPrecision(sig);
}

function sqrtPriceX96ToPrice18(sqrtPriceX96: bigint): bigint {
  // price = (sqrtPriceX96^2 / 2^192) in Q0.0; scale to 1e18
  const Q192 = 2n ** 192n;
  const num = sqrtPriceX96 * sqrtPriceX96 * 10n ** 18n;
  return num / Q192;
}

function bpsDiff(a: bigint, b: bigint): bigint {
  // (a-b)/b * 10000
  if (b === 0n) return 0n;
  return ((a - b) * 10000n) / b;
}

function ProtocolDashboard({
  wallet,
  coordinator,
  agentExecutor,
  swarmAgentRegistry,
  oracleRegistry,
  poolManager,
  onToast
}: {
  wallet: WalletState;
  coordinator: ethers.Contract | null;
  agentExecutor: ethers.Contract | null;
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

      // Market data
      if (oracleRegistry && poolManager && poolId !== "0x") {
        const [o, s0, liq] = await Promise.all([
          oracleRegistry.getLatestPrice(cfg.defaultPool.currencyOut, cfg.defaultPool.currencyIn),
          poolManager.getSlot0(poolId),
          poolManager.getLiquidity(poolId)
        ]);
        const oraclePrice18 = BigInt(o[0]);
        const oracleUpdatedAt = BigInt(o[1]);
        const sqrt = BigInt(s0[0]);
        const tick = Number(s0[1]);
        const lpFee = Number(s0[3]);
        const poolPrice18 = sqrtPriceX96ToPrice18(sqrt);
        const diffBps = bpsDiff(poolPrice18, oraclePrice18);
        setMarket({
          oraclePrice18,
          oracleUpdatedAt,
          poolPrice18,
          tick,
          lpFee,
          liquidity: BigInt(liq),
          diffBps,
          poolId
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
        const [arbAddr, feeAddr, backAddr] = await Promise.all([agentExecutor.agents(0), agentExecutor.agents(1), agentExecutor.agents(2)]);

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
    } catch (e: any) {
      onToast({ kind: "bad", msg: e?.shortMessage ?? e?.message ?? String(e) });
    } finally {
      setBusy(false);
    }
  }

  const spotOut = useMemo(() => {
    if (!market) return null;
    // default UI intent is currencyIn (DAI) -> currencyOut (WETH). oracle/pool prices are DAI per WETH.
    // So: outWETH ~= inDAI / price(DAI per WETH).
    if (!balances) return null;
    return {
      // just a helper, not a real quote
      per1: (10n ** 18n * 10n ** 18n) / market.poolPrice18 // WETH per 1 DAI (1e18 scaled)
    };
  }, [market, balances]);

  return (
    <div className="dash">
      <div className="dashHeader">
        <div>
          <div className="dashTitle">Dashboard</div>
          <div className="dashSub mono">
            poolId {market?.poolId ? shortAddr(market.poolId) : "—"} · oracle {shortAddr(cfg.oracleRegistry)} · poolManager{" "}
            {shortAddr(cfg.poolManager)}
          </div>
        </div>
        <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
          <button className="btn btnPrimary" disabled={busy} onClick={loadAll}>
            {busy ? "Loading…" : "Refresh Dashboard"}
          </button>
        </div>
      </div>

      <div className="dashGrid">
        <div className="dashCard">
          <div className="dashCardTitle mono">Market</div>
          {!market ? (
            <div className="muted">Set `VITE_ORACLE_REGISTRY` + `VITE_POOL_MANAGER` and refresh.</div>
          ) : (
            <div className="kvs" style={{ marginTop: 0 }}>
              <div className="kv">
                <b>Oracle Price</b>
                <span className="mono">{fmt18(market.oraclePrice18)} DAI/WETH</span>
              </div>
              <div className="kv">
                <b>Pool Spot Price</b>
                <span className="mono">{fmt18(market.poolPrice18)} DAI/WETH</span>
              </div>
              <div className="kv">
                <b>Diff</b>
                <span className="mono">{String(market.diffBps)} bps</span>
              </div>
              <div className="kv">
                <b>Tick</b>
                <span className="mono">{String(market.tick)}</span>
              </div>
              <div className="kv">
                <b>LP Fee (slot0)</b>
                <span className="mono">{String(market.lpFee)}</span>
              </div>
              <div className="kv">
                <b>Liquidity</b>
                <span className="mono">{String(market.liquidity)}</span>
              </div>
              {spotOut ? (
                <div className="kv">
                  <b>Spot (WETH / 1 DAI)</b>
                  <span className="mono">{fmt18(spotOut.per1)} WETH</span>
                </div>
              ) : null}
              <div className="muted" style={{ marginTop: 8 }}>
                Spot numbers are informational only (no fees, no slippage, no hook effects).
              </div>
            </div>
          )}
        </div>

        <div className="dashCard">
          <div className="dashCardTitle mono">Wallet</div>
          {wallet.status !== "connected" ? (
            <div className="muted">Connect wallet to see balances.</div>
          ) : !balances ? (
            <div className="muted">Refresh dashboard to load balances.</div>
          ) : (
            <div className="kvs" style={{ marginTop: 0 }}>
              <div className="kv">
                <b>ETH</b>
                <span className="mono">{fmt18(balances.eth)} ETH</span>
              </div>
              <div className="kv">
                <b>{balances.inSym}</b>
                <span className="mono">{fmt18(balances.inBal, balances.inDec)} {balances.inSym}</span>
              </div>
              <div className="kv">
                <b>{balances.outSym}</b>
                <span className="mono">{fmt18(balances.outBal, balances.outDec)} {balances.outSym}</span>
              </div>
            </div>
          )}
        </div>

        <div className="dashCard">
          <div className="dashCardTitle mono">Hook Agents</div>
          {!hookAgents ? (
            <div className="muted">Refresh dashboard to load hook agent status.</div>
          ) : (
            <div className="kvs" style={{ marginTop: 0 }}>
              {[hookAgents.arb, hookAgents.fee, hookAgents.backrun].map((a: any) => (
                <div className="kv" key={a.type}>
                  <b>{a.type}</b>
                  <span className="mono">
                    {shortAddr(a.addr)} · id {a.agentId ?? "—"} · conf {a.confidence ?? "—"} · ok/exec {a.ok ?? "—"}/{a.exec ?? "—"} · repTier{" "}
                    {a.repTier ?? "—"} · repCount {a.repCount ?? "—"}
                  </span>
                </div>
              ))}
              <div className="muted" style={{ marginTop: 8 }}>
                `id` is the agent's ERC-8004 identity ID stored in the agent contract (0 means "not linked").
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

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
  const [deadlineSec, setDeadlineSec] = useState("0");
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
  const [allow, setAllow] = useState<bigint | null>(null);
  const [preview, setPreview] = useState<null | { poolId: string; price18: bigint; estOut: bigint; note: string }>(
    null
  );

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
      const signerAddr = await runner.getAddress?.();
      if (!signerAddr) return;
      const token = new ethers.Contract(currencyIn, ERC20Abi, runner);
      const tokenOut = new ethers.Contract(currencyOut, ERC20Abi, runner);
      const [decimals, symbol, balance, allowance] = await Promise.all([
        token.decimals().catch(() => 18),
        token.symbol().catch(() => "TOKEN"),
        token.balanceOf(signerAddr),
        token.allowance(signerAddr, await coordinator.getAddress())
      ]);
      setTokenMeta({ symbol: String(symbol), decimals: Number(decimals) });
      setBal(BigInt(balance));
      setAllow(BigInt(allowance));

      const [outDecimals, outSymbol] = await Promise.all([
        tokenOut.decimals().catch(() => 18),
        tokenOut.symbol().catch(() => "TOKEN_OUT")
      ]);
      setTokenOutMeta({ symbol: String(outSymbol), decimals: Number(outDecimals) });
    } catch {
      // Ignore; token might be native or non-standard.
    }
  }

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
      onToast({ kind: "bad", msg: e?.shortMessage ?? e?.message ?? String(e) });
    } finally {
      setBusy(false);
    }
  }

  async function previewSpot() {
    if (!poolManager) return onToast({ kind: "bad", msg: "PoolManager not configured (set VITE_POOL_MANAGER)." });
    onToast(null);
    setBusy(true);
    try {
      const { currency0, currency1 } = sortCurrencies(currencyIn, currencyOut);
      const pid = toBytes32PoolIdFromPoolKey({
        currency0,
        currency1,
        fee: Number(fee),
        tickSpacing: Number(tickSpacing),
        hooks
      });
      const s0 = await poolManager.getSlot0(pid);
      const sqrt = BigInt(s0[0]);
      const price18 = sqrtPriceX96ToPrice18(sqrt); // currency1 per currency0

      const amtIn = parseBn(amountIn);
      let estOut = 0n;
      let note = "spot estimate (no slippage/fees)";
      if (currencyIn.toLowerCase() === currency0.toLowerCase() && currencyOut.toLowerCase() === currency1.toLowerCase()) {
        // in = currency0, out = currency1: out ~= in * price
        estOut = (amtIn * price18) / 10n ** 18n;
      } else if (currencyIn.toLowerCase() === currency1.toLowerCase() && currencyOut.toLowerCase() === currency0.toLowerCase()) {
        // in = currency1, out = currency0: out ~= in / price
        if (price18 > 0n) estOut = (amtIn * 10n ** 18n) / price18;
      } else {
        note = "poolKey mismatch (check tokens)";
      }

      setPreview({ poolId: pid, price18, estOut, note });
    } catch (e: any) {
      onToast({ kind: "bad", msg: e?.shortMessage ?? e?.message ?? String(e) });
    } finally {
      setBusy(false);
    }
  }

  async function create() {
    if (!coordinator) return onToast({ kind: "bad", msg: "Coordinator not configured (set VITE_COORDINATOR)." });
    setBusy(true);
    onToast(null);
    try {
      const params = {
        currencyIn,
        currencyOut,
        amountIn: parseBn(amountIn),
        amountOutMin: parseBn(amountOutMin),
        deadline: BigInt(deadlineSec || "0"),
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
      onToast({ kind: "ok", msg: `Intent created. intentId=${intentId} tx=${receipt.hash}` });
      await refreshAllowanceAndBalance();
    } catch (e: any) {
      onToast({ kind: "bad", msg: e?.shortMessage ?? e?.message ?? String(e) });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="row">
      <div className="card">
        <div className="cardHeader">
          <h2>Create MEV-Protected Intent (1-hop)</h2>
          <span className="pill">coordinator {shortAddr(cfg.coordinator)}</span>
        </div>
        <div style={{ display: "flex", gap: 10, flexWrap: "wrap", marginBottom: 10 }}>
          <button className="btn" disabled={busy} onClick={refreshAllowanceAndBalance}>
            Refresh Balance/Allowance
          </button>
          <button className="btn" disabled={busy} onClick={previewSpot}>
            Spot Preview
          </button>
          <button className="btn btnPrimary" disabled={busy} onClick={approveMax}>
            Approve In Token
          </button>
          {tokenMeta ? <span className="pill ok">{tokenMeta.symbol}</span> : <span className="pill">token?</span>}
        </div>
        <div className="kvs" style={{ marginTop: 0 }}>
          <div className="kv">
            <b>Balance</b>
            <span className="mono">{bal === null ? "—" : String(bal)}</span>
          </div>
          <div className="kv">
            <b>Allowance → Coordinator</b>
            <span className="mono">{allow === null ? "—" : String(allow)}</span>
          </div>
        </div>
        <div className="grid2">
          <div className="field">
            <label>Currency In (token address)</label>
            <input value={currencyIn} onChange={(e) => setCurrencyIn(e.target.value)} />
          </div>
          <div className="field">
            <label>Currency Out (token address)</label>
            <input value={currencyOut} onChange={(e) => setCurrencyOut(e.target.value)} />
          </div>

          <div className="field">
            <label>Amount In (ether units if decimal)</label>
            <input value={amountIn} onChange={(e) => setAmountIn(e.target.value)} />
          </div>
          <div className="field">
            <label>Min Out (raw or ether units)</label>
            <input value={amountOutMin} onChange={(e) => setAmountOutMin(e.target.value)} />
          </div>

          <div className="field">
            <label>MEV Fee (bps)</label>
            <input value={mevFeeBps} onChange={(e) => setMevFeeBps(e.target.value)} />
          </div>
          <div className="field">
            <label>Treasury Share (bps of MEV fee)</label>
            <input value={treasuryBps} onChange={(e) => setTreasuryBps(e.target.value)} />
          </div>

          <div className="field">
            <label>LP Share (bps of MEV fee)</label>
            <input value={lpShareBps} onChange={(e) => setLpShareBps(e.target.value)} />
          </div>
          <div className="field">
            <label>Deadline (unix seconds, 0 = none)</label>
            <input value={deadlineSec} onChange={(e) => setDeadlineSec(e.target.value)} />
          </div>

          <div className="field">
            <label>Pool Fee (uint24)</label>
            <input value={fee} onChange={(e) => setFee(e.target.value)} />
          </div>
          <div className="field">
            <label>Tick Spacing (int24)</label>
            <input value={tickSpacing} onChange={(e) => setTickSpacing(e.target.value)} />
          </div>

          <div className="field" style={{ gridColumn: "1 / -1" }}>
            <label>Hooks (SwarmHook address)</label>
            <input value={hooks} onChange={(e) => setHooks(e.target.value)} />
          </div>
        </div>

        <div style={{ display: "flex", gap: 10, marginTop: 12 }}>
          <button className="btn btnPrimary" disabled={busy} onClick={create}>
            {busy ? "Creating…" : "Create Intent"}
          </button>
          {lastIntentId ? <span className="pill ok">last intentId {lastIntentId}</span> : null}
        </div>

        {preview ? (
          <div className="toast" style={{ marginTop: 12 }}>
            <div style={{ color: "rgba(255,255,255,0.78)", marginBottom: 6 }}>Spot Preview</div>
            <div className="kvs" style={{ marginTop: 0 }}>
              <div className="kv">
                <b>poolId</b>
                <span className="mono">{preview.poolId}</span>
              </div>
              <div className="kv">
                <b>spot price (currency1/currency0)</b>
                <span className="mono">{fmt18(preview.price18)}</span>
              </div>
              <div className="kv">
                <b>estimated out</b>
                <span className="mono">
                  {tokenOutMeta ? `${fmt18(preview.estOut, tokenOutMeta.decimals)} ${tokenOutMeta.symbol}` : String(preview.estOut)}
                </span>
              </div>
            </div>
            <div className="muted" style={{ marginTop: 8 }}>
              {preview.note}
            </div>
          </div>
        ) : null}

        <div className="toast" style={{ marginTop: 12 }}>
          <div style={{ color: "rgba(255,255,255,0.78)", marginBottom: 6 }}>Candidate path bytes (auto-built):</div>
          <div className="mono" style={{ wordBreak: "break-all", color: "rgba(255,255,255,0.9)" }}>
            {candidateBytes}
          </div>
        </div>
      </div>

      <div className="card">
        <div className="cardHeader">
          <h2>How It Completes</h2>
          <span className="pill">agent-driven</span>
        </div>
        <p className="muted">
          An intent is a MEV-protected swap request. Route agents submit proposals. When proposals exist, the requester
          executes the intent and receives the swap output. SwarmHook applies MEV fee accounting on-chain.
        </p>
        <div className="kvs">
          <div className="kv">
            <b>Step 1</b>
            <span>Create intent</span>
          </div>
          <div className="kv">
            <b>Step 2</b>
            <span>Agents propose best candidate</span>
          </div>
          <div className="kv">
            <b>Step 3</b>
            <span>You execute the intent (you receive output)</span>
          </div>
        </div>
        <p className="muted" style={{ marginTop: 12 }}>
          If your team runs the route agent, proposals can be submitted automatically (server-side agent bot).
        </p>
      </div>
    </div>
  );
}

function IntentDeskPanel({
  coordinator,
  onToast
}: {
  coordinator: ethers.Contract | null;
  onToast: (t: { kind: "ok" | "bad"; msg: string } | null) => void;
}) {
  const [intentId, setIntentId] = useState("");
  const [candidateId, setCandidateId] = useState("0");
  const [score, setScore] = useState("0");
  const [data, setData] = useState("0x");
  const [info, setInfo] = useState<any | null>(null);
  const [busy, setBusy] = useState(false);

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
    } catch (e: any) {
      onToast({ kind: "bad", msg: e?.shortMessage ?? e?.message ?? String(e) });
    } finally {
      setBusy(false);
    }
  }

  async function propose() {
    if (!coordinator) return onToast({ kind: "bad", msg: "Coordinator not configured." });
    onToast(null);
    setBusy(true);
    try {
      const tx = await coordinator.submitProposal(BigInt(intentId), BigInt(candidateId), BigInt(score), data);
      const receipt = await tx.wait(1);
      onToast({ kind: "ok", msg: `Proposal submitted. tx=${receipt.hash}` });
      await load();
    } catch (e: any) {
      onToast({ kind: "bad", msg: e?.shortMessage ?? e?.message ?? String(e) });
    } finally {
      setBusy(false);
    }
  }

  async function execute() {
    if (!coordinator) return onToast({ kind: "bad", msg: "Coordinator not configured." });
    onToast(null);
    setBusy(true);
    try {
      const tx = await coordinator.executeIntent(BigInt(intentId));
      const receipt = await tx.wait(1);
      onToast({ kind: "ok", msg: `Intent executed. tx=${receipt.hash}` });
      await load();
    } catch (e: any) {
      onToast({ kind: "bad", msg: e?.shortMessage ?? e?.message ?? String(e) });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="row">
      <div className="card">
        <div className="cardHeader">
          <h2>Intent Desk</h2>
          <span className="pill">load · propose · execute</span>
        </div>
        <div className="grid2">
          <div className="field">
            <label>Intent ID</label>
            <input value={intentId} onChange={(e) => setIntentId(e.target.value)} placeholder="0" />
          </div>
          <div style={{ display: "flex", gap: 10, alignItems: "end" }}>
            <button className="btn btnPrimary" disabled={busy || intentId.trim() === ""} onClick={load}>
              {busy ? "Loading…" : "Load"}
            </button>
            <button className="btn" disabled={busy || intentId.trim() === ""} onClick={execute}>
              Execute (Requester)
            </button>
          </div>
        </div>

        <div style={{ height: 12 }} />

        <div className="cardHeader">
          <h2>Submit Proposal (Route Agent)</h2>
          <span className="pill">requires agent registration</span>
        </div>
        <div className="grid2">
          <div className="field">
            <label>Candidate ID</label>
            <input value={candidateId} onChange={(e) => setCandidateId(e.target.value)} />
          </div>
          <div className="field">
            <label>Score (int256; lower is better)</label>
            <input value={score} onChange={(e) => setScore(e.target.value)} />
          </div>
          <div className="field" style={{ gridColumn: "1 / -1" }}>
            <label>Data (bytes, optional)</label>
            <input value={data} onChange={(e) => setData(e.target.value)} />
          </div>
        </div>
        <div style={{ display: "flex", gap: 10, marginTop: 12 }}>
          <button className="btn btnPrimary" disabled={busy || intentId.trim() === ""} onClick={propose}>
            Submit Proposal
          </button>
        </div>
      </div>

      <div className="card">
        <div className="cardHeader">
          <h2>State</h2>
          <span className="pill">read-only</span>
        </div>
        {!info ? (
          <p className="muted">Load an intent to see details.</p>
        ) : (
          <>
            <div className="kvs">
              <div className="kv">
                <b>Requester</b>
                <span className="mono">{shortAddr(info.intent.requester)}</span>
              </div>
              <div className="kv">
                <b>Executed</b>
                <span className="mono">{String(info.intent.executed)}</span>
              </div>
              <div className="kv">
                <b>Candidate Count</b>
                <span className="mono">{String(info.count)}</span>
              </div>
              <div className="kv">
                <b>Amount In</b>
                <span className="mono">{String(info.intent.amountIn)}</span>
              </div>
              <div className="kv">
                <b>Min Out</b>
                <span className="mono">{String(info.intent.amountOutMin)}</span>
              </div>
            </div>
            <div style={{ height: 12 }} />
            <div className="cardHeader">
              <h2>Proposals</h2>
              <span className="pill">{info.proposals.length}</span>
            </div>
            {info.proposals.length === 0 ? (
              <p className="muted">No proposals yet.</p>
            ) : (
              <div className="kvs">
                {info.proposals.map((p: any) => (
                  <div className="kv" key={p.agent}>
                    <b className="mono">{shortAddr(p.agent)}</b>
                    <span className="mono">
                      candidate={String(p.candidateId)} score={String(p.score)}
                    </span>
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

function LpPanel({
  lpAccumulator,
  onToast
}: {
  lpAccumulator: ethers.Contract | null;
  onToast: (t: { kind: "ok" | "bad"; msg: string } | null) => void;
}) {
  const [poolId, setPoolId] = useState("0x");
  const [busy, setBusy] = useState(false);
  const [info, setInfo] = useState<any | null>(null);

  async function load() {
    if (!lpAccumulator) return onToast({ kind: "bad", msg: "LPFeeAccumulator not configured." });
    onToast(null);
    setBusy(true);
    try {
      const r = await lpAccumulator.canDonate(poolId);
      setInfo({ canDonate: r[0], amount0: r[1], amount1: r[2] });
    } catch (e: any) {
      onToast({ kind: "bad", msg: e?.shortMessage ?? e?.message ?? String(e) });
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
      onToast({ kind: "ok", msg: `Donated to LPs. tx=${receipt.hash}` });
      await load();
    } catch (e: any) {
      onToast({ kind: "bad", msg: e?.shortMessage ?? e?.message ?? String(e) });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="row">
      <div className="card">
        <div className="cardHeader">
          <h2>LP Donation</h2>
          <span className="pill">anyone can call donate</span>
        </div>
        <div className="field">
          <label>Pool ID (bytes32)</label>
          <input value={poolId} onChange={(e) => setPoolId(e.target.value)} placeholder="0x…" />
        </div>
        <div style={{ display: "flex", gap: 10, marginTop: 12 }}>
          <button className="btn btnPrimary" disabled={busy || poolId === "0x"} onClick={load}>
            Load
          </button>
          <button className="btn" disabled={busy || poolId === "0x"} onClick={donate}>
            Donate To LPs
          </button>
        </div>
        {info ? (
          <div className="kvs">
            <div className="kv">
              <b>Can Donate</b>
              <span className="mono">{String(info.canDonate)}</span>
            </div>
            <div className="kv">
              <b>Amount0</b>
              <span className="mono">{String(info.amount0)}</span>
            </div>
            <div className="kv">
              <b>Amount1</b>
              <span className="mono">{String(info.amount1)}</span>
            </div>
          </div>
        ) : null}
      </div>

      <div className="card">
        <div className="cardHeader">
          <h2>PoolId Helper</h2>
          <span className="pill">compute off-chain</span>
        </div>
        <PoolIdHelper onToast={onToast} />
      </div>
    </div>
  );
}

function PoolIdHelper({ onToast }: { onToast: (t: { kind: "ok" | "bad"; msg: string } | null) => void }) {
  const [currency0, setCurrency0] = useState(cfg.defaultPool.currencyIn);
  const [currency1, setCurrency1] = useState(cfg.defaultPool.currencyOut);
  const [fee, setFee] = useState(String(cfg.defaultPool.fee || 8388608));
  const [tickSpacing, setTickSpacing] = useState(String(cfg.defaultPool.tickSpacing || 60));
  const [hooks, setHooks] = useState(cfg.defaultPool.hooks);
  const [out, setOut] = useState("");

  function compute() {
    try {
      const id = toBytes32PoolIdFromPoolKey({
        currency0,
        currency1,
        fee: Number(fee),
        tickSpacing: Number(tickSpacing),
        hooks
      });
      setOut(id);
      onToast({ kind: "ok", msg: `Computed poolId=${id}` });
    } catch (e: any) {
      onToast({ kind: "bad", msg: e?.message ?? String(e) });
    }
  }

  return (
    <>
      <div className="grid2">
        <div className="field">
          <label>currency0</label>
          <input value={currency0} onChange={(e) => setCurrency0(e.target.value)} />
        </div>
        <div className="field">
          <label>currency1</label>
          <input value={currency1} onChange={(e) => setCurrency1(e.target.value)} />
        </div>
        <div className="field">
          <label>fee</label>
          <input value={fee} onChange={(e) => setFee(e.target.value)} />
        </div>
        <div className="field">
          <label>tickSpacing</label>
          <input value={tickSpacing} onChange={(e) => setTickSpacing(e.target.value)} />
        </div>
        <div className="field" style={{ gridColumn: "1 / -1" }}>
          <label>hooks</label>
          <input value={hooks} onChange={(e) => setHooks(e.target.value)} />
        </div>
      </div>
      <div style={{ display: "flex", gap: 10, marginTop: 12 }}>
        <button className="btn btnPrimary" onClick={compute}>
          Compute PoolId
        </button>
      </div>
      {out ? (
        <div className="toast" style={{ marginTop: 12 }}>
          <div className="mono" style={{ wordBreak: "break-all" }}>
            {out}
          </div>
        </div>
      ) : null}
    </>
  );
}

function BackrunPanel({
  flashBackrunner,
  onToast
}: {
  flashBackrunner: ethers.Contract | null;
  onToast: (t: { kind: "ok" | "bad"; msg: string } | null) => void;
}) {
  const [poolId, setPoolId] = useState("0x");
  const [amount, setAmount] = useState("0.01");
  const [minProfit, setMinProfit] = useState("0");
  const [busy, setBusy] = useState(false);
  const [info, setInfo] = useState<any | null>(null);

  async function load() {
    if (!flashBackrunner) return onToast({ kind: "bad", msg: "FlashLoanBackrunner not configured." });
    onToast(null);
    setBusy(true);
    try {
      const r = await flashBackrunner.getPendingBackrun(poolId);
      setInfo({
        targetPrice: r[0],
        currentPrice: r[1],
        backrunAmount: r[2],
        zeroForOne: r[3],
        timestamp: r[4],
        blockNumber: r[5],
        executed: r[6]
      });
    } catch (e: any) {
      onToast({ kind: "bad", msg: e?.shortMessage ?? e?.message ?? String(e) });
    } finally {
      setBusy(false);
    }
  }

  async function execFlash() {
    if (!flashBackrunner) return onToast({ kind: "bad", msg: "FlashLoanBackrunner not configured." });
    onToast(null);
    setBusy(true);
    try {
      const tx = await flashBackrunner.executeBackrunPartial(poolId, parseBn(amount), parseBn(minProfit));
      const receipt = await tx.wait(1);
      onToast({ kind: "ok", msg: `Backrun executed (flashloan). tx=${receipt.hash}` });
      await load();
    } catch (e: any) {
      onToast({ kind: "bad", msg: e?.shortMessage ?? e?.message ?? String(e) });
    } finally {
      setBusy(false);
    }
  }

  async function execCapital() {
    if (!flashBackrunner) return onToast({ kind: "bad", msg: "FlashLoanBackrunner not configured." });
    onToast(null);
    setBusy(true);
    try {
      const tx = await flashBackrunner.executeBackrunWithCapital(poolId, parseBn(amount), parseBn(minProfit));
      const receipt = await tx.wait(1);
      onToast({ kind: "ok", msg: `Backrun executed (capital). tx=${receipt.hash}` });
      await load();
    } catch (e: any) {
      onToast({ kind: "bad", msg: e?.shortMessage ?? e?.message ?? String(e) });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="row">
      <div className="card">
        <div className="cardHeader">
          <h2>Backrun Console</h2>
          <span className="pill">keeper tooling</span>
        </div>
        <p className="muted">
          In production you run an event-driven keeper. This console is a manual fallback to inspect pending
          opportunities and execute them.
        </p>
        <div className="field">
          <label>Pool ID (bytes32)</label>
          <input value={poolId} onChange={(e) => setPoolId(e.target.value)} placeholder="0x…" />
        </div>
        <div className="grid2" style={{ marginTop: 10 }}>
          <div className="field">
            <label>Amount (ether units if decimal)</label>
            <input value={amount} onChange={(e) => setAmount(e.target.value)} />
          </div>
          <div className="field">
            <label>Min Profit (wei, optional)</label>
            <input value={minProfit} onChange={(e) => setMinProfit(e.target.value)} />
          </div>
        </div>
        <div style={{ display: "flex", gap: 10, marginTop: 12 }}>
          <button className="btn btnPrimary" disabled={busy || poolId === "0x"} onClick={load}>
            Load
          </button>
          <button className="btn" disabled={busy || poolId === "0x"} onClick={execFlash}>
            Execute (Flashloan)
          </button>
          <button className="btn" disabled={busy || poolId === "0x"} onClick={execCapital}>
            Execute (Capital)
          </button>
        </div>
      </div>

      <div className="card">
        <div className="cardHeader">
          <h2>Pending Opportunity</h2>
          <span className="pill">read-only</span>
        </div>
        {!info ? (
          <p className="muted">Load a poolId to see details.</p>
        ) : (
          <div className="kvs">
            <div className="kv">
              <b>Executed</b>
              <span className="mono">{String(info.executed)}</span>
            </div>
            <div className="kv">
              <b>Backrun Amount</b>
              <span className="mono">{String(info.backrunAmount)}</span>
            </div>
            <div className="kv">
              <b>Direction</b>
              <span className="mono">{info.zeroForOne ? "zeroForOne" : "oneForZero"}</span>
            </div>
            <div className="kv">
              <b>Detected Block</b>
              <span className="mono">{String(info.blockNumber)}</span>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

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

  const [loadedHookAgents, setLoadedHookAgents] = useState<{ arb: string; fee: string; backrun: string } | null>(
    null
  );
  const [arbId, setArbId] = useState<string>("—");
  const [feeId, setFeeId] = useState<string>("—");
  const [backrunId, setBackrunId] = useState<string>("—");

  const [newAgentAddr, setNewAgentAddr] = useState("0x");
  const [newAgentName, setNewAgentName] = useState("Swarm Hook Agent");
  const [newAgentDesc, setNewAgentDesc] = useState("Hook agent");
  const [newAgentTypeStr, setNewAgentTypeStr] = useState("generic");
  const [newAgentVersion, setNewAgentVersion] = useState("1.0.0");

  const [treasury, setTreasury] = useState("0x");
  const [enfId, setEnfId] = useState(false);
  const [enfRep, setEnfRep] = useState(false);

  const [routeAgent, setRouteAgent] = useState("0x");
  const [routeAgentId, setRouteAgentId] = useState("0");
  const [routeActive, setRouteActive] = useState(true);

  const [repReg, setRepReg] = useState("0x");
  const [tag1, setTag1] = useState("swarm-routing");
  const [tag2, setTag2] = useState("mev-protection");
  const [minRep, setMinRep] = useState("0");
  const [clientsCsv, setClientsCsv] = useState("");
  const [busy, setBusy] = useState(false);

  const [switchRepRegistry, setSwitchRepRegistry] = useState("0x");
  const [switchTag1, setSwitchTag1] = useState("swarm-hook");
  const [switchTag2, setSwitchTag2] = useState("hook-agents");
  const [switchMinRepWad, setSwitchMinRepWad] = useState("0");
  const [switchClientsCsv, setSwitchClientsCsv] = useState("");
  const [switchEnabled, setSwitchEnabled] = useState(false);

  async function ex(fn: () => Promise<any>) {
    onToast(null);
    setBusy(true);
    try {
      const tx = await fn();
      const receipt = await tx.wait(1);
      onToast({ kind: "ok", msg: `tx=${receipt.hash}` });
    } catch (e: any) {
      onToast({ kind: "bad", msg: e?.shortMessage ?? e?.message ?? String(e) });
    } finally {
      setBusy(false);
    }
  }

  async function loadCurrentHookAgents() {
    if (!agentExecutor) return onToast({ kind: "bad", msg: "AgentExecutor not configured." });
    onToast(null);
    setBusy(true);
    try {
      const [arb, fee, backrun] = await Promise.all([agentExecutor.agents(0), agentExecutor.agents(1), agentExecutor.agents(2)]);
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
      onToast({ kind: "ok", msg: "Loaded hook agents from AgentExecutor." });
    } catch (e: any) {
      onToast({ kind: "bad", msg: e?.shortMessage ?? e?.message ?? String(e) });
    } finally {
      setBusy(false);
    }
  }

  async function registerHookAgentOnERC8004(agentAddress: string, name: string, description: string) {
    if (!swarmAgentRegistry) return onToast({ kind: "bad", msg: "Set VITE_SWARM_AGENT_REGISTRY to use ERC-8004 registration." });
    if (isZeroAddr(agentAddress)) return onToast({ kind: "bad", msg: "Agent address is 0x0." });
    onToast(null);
    setBusy(true);
    try {
      const runner = swarmAgentRegistry.runner as any;
      const idReg = await swarmAgentRegistry.identityRegistry();

      // 1) Register identity in the official ERC-8004 identity registry (via SwarmAgentRegistry helper).
      try {
        const tx = await swarmAgentRegistry.registerAgent(agentAddress, name, description, newAgentTypeStr, newAgentVersion);
        await tx.wait(1);
      } catch {
        // If already registered, this reverts; we'll just read the existing ID below.
      }

      const agentId = await swarmAgentRegistry.agentIdentities(agentAddress);
      if (BigInt(agentId) === 0n) throw new Error("ERC-8004 register failed (agentId=0)");

      // 2) Bind that agentId into the hook-agent contract so it can be reputation-scored later.
      const agent = new ethers.Contract(agentAddress, SwarmAgentAbi, runner);
      const tx2 = await agent.configureIdentity(agentId, idReg);
      const r2 = await tx2.wait(1);
      onToast({ kind: "ok", msg: `ERC-8004 linked. agentId=${String(agentId)} tx=${r2.hash}` });
      await loadCurrentHookAgents();
    } catch (e: any) {
      onToast({ kind: "bad", msg: e?.shortMessage ?? e?.message ?? String(e) });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="row">
      <div className="card">
        <div className="cardHeader">
          <h2>AgentExecutor (Hook Agents)</h2>
          <span className="pill">owner-only</span>
        </div>
        {!agentExecutor ? (
          <p className="muted">Set `VITE_AGENT_EXECUTOR` to use this panel.</p>
        ) : (
          <>
            <div style={{ display: "flex", gap: 10, marginBottom: 10, flexWrap: "wrap" }}>
              <button className="btn btnPrimary" disabled={busy} onClick={loadCurrentHookAgents}>
                Load Hook Agents
              </button>
              <span className="pill">registry {shortAddr(cfg.swarmAgentRegistry)}</span>
            </div>

            {loadedHookAgents ? (
              <div className="toast" style={{ marginBottom: 12 }}>
                <div style={{ color: "rgba(255,255,255,0.78)", marginBottom: 8 }}>Current Hook Agents (from AgentExecutor)</div>
                <div className="kvs" style={{ marginTop: 0 }}>
                  <div className="kv">
                    <b>ARBITRAGE</b>
                    <span className="mono">{shortAddr(loadedHookAgents.arb)} · agentId {arbId}</span>
                  </div>
                  <div className="kv">
                    <b>DYNAMIC_FEE</b>
                    <span className="mono">{shortAddr(loadedHookAgents.fee)} · agentId {feeId}</span>
                  </div>
                  <div className="kv">
                    <b>BACKRUN</b>
                    <span className="mono">{shortAddr(loadedHookAgents.backrun)} · agentId {backrunId}</span>
                  </div>
                </div>
                <div className="muted" style={{ marginTop: 10 }}>
                  These IDs should be set by the deploy script. If they are `0`, redeploy with `REGISTER_ERC8004_HOOK_AGENTS=true`.
                </div>
              </div>
            ) : null}

            <div className="grid2">
              <div className="field">
                <label>Agent Type (0=ARB,1=FEE,2=BACKRUN)</label>
                <input value={agentType} onChange={(e) => setAgentType(e.target.value)} />
              </div>
              <div className="field">
                <label>Agent Address</label>
                <input value={agentAddr} onChange={(e) => setAgentAddr(e.target.value)} />
              </div>
              <div className="field">
                <label>Backup Agent Address</label>
                <input value={backupAddr} onChange={(e) => setBackupAddr(e.target.value)} />
              </div>
              <div className="field">
                <label>Enabled</label>
                <select value={String(enabled)} onChange={(e) => setEnabled(e.target.value === "true")}>
                  <option value="true">true</option>
                  <option value="false">false</option>
                </select>
              </div>
            </div>
            <div style={{ display: "flex", gap: 10, marginTop: 12, flexWrap: "wrap" }}>
              <button className="btn btnPrimary" disabled={busy} onClick={() => ex(() => agentExecutor.registerAgent(Number(agentType), agentAddr))}>
                Register/Switch Agent
              </button>
              <button className="btn" disabled={busy} onClick={() => ex(() => agentExecutor.setBackupAgent(Number(agentType), backupAddr))}>
                Set Backup
              </button>
              <button
                className="btn"
                disabled={busy}
                onClick={async () => {
                  if (!agentExecutor) return;
                  try {
                    const b = await agentExecutor.backupAgents(Number(agentType));
                    if (isZeroAddr(String(b))) return onToast({ kind: "bad", msg: "No backup agent set for this type." });
                    await ex(() => agentExecutor.registerAgent(Number(agentType), String(b)));
                  } catch (e: any) {
                    onToast({ kind: "bad", msg: e?.shortMessage ?? e?.message ?? String(e) });
                  }
                }}
              >
                Switch To Backup Now
              </button>
              <button className="btn" disabled={busy} onClick={() => ex(() => agentExecutor.setAgentEnabled(Number(agentType), enabled))}>
                Set Enabled
              </button>
              <button className="btn" disabled={busy} onClick={() => ex(() => agentExecutor.checkAndSwitchAgentIfBelowThreshold(Number(agentType)))}>
                Check & Switch (Reputation)
              </button>
            </div>

            <div style={{ height: 12 }} />
            <div className="cardHeader">
              <h2>Reputation Threshold Switch (Hook Agents)</h2>
              <span className="pill">owner-only · off-path</span>
            </div>
            <div className="grid2">
              <div className="field">
                <label>Agent Type</label>
                <input value={agentType} onChange={(e) => setAgentType(e.target.value)} />
              </div>
              <div className="field">
                <label>Reputation Registry</label>
                <input value={switchRepRegistry} onChange={(e) => setSwitchRepRegistry(e.target.value)} placeholder="0x…" />
              </div>
              <div className="field">
                <label>tag1</label>
                <input value={switchTag1} onChange={(e) => setSwitchTag1(e.target.value)} />
              </div>
              <div className="field">
                <label>tag2</label>
                <input value={switchTag2} onChange={(e) => setSwitchTag2(e.target.value)} />
              </div>
              <div className="field">
                <label>minReputationWad (int256)</label>
                <input value={switchMinRepWad} onChange={(e) => setSwitchMinRepWad(e.target.value)} />
              </div>
              <div className="field">
                <label>Enabled</label>
                <select value={String(switchEnabled)} onChange={(e) => setSwitchEnabled(e.target.value === "true")}>
                  <option value="true">true</option>
                  <option value="false">false</option>
                </select>
              </div>
              <div className="field" style={{ gridColumn: "1 / -1" }}>
                <label>clients (comma-separated)</label>
                <input value={switchClientsCsv} onChange={(e) => setSwitchClientsCsv(e.target.value)} placeholder="0xabc...,0xdef..." />
              </div>
            </div>
            <div style={{ display: "flex", gap: 10, marginTop: 12, flexWrap: "wrap" }}>
              <button
                className="btn"
                disabled={busy}
                onClick={() =>
                  ex(() =>
                    agentExecutor.setReputationSwitchConfig(
                      Number(agentType),
                      switchRepRegistry,
                      switchTag1,
                      switchTag2,
                      BigInt(switchMinRepWad),
                      switchEnabled
                    )
                  )
                }
              >
                Set Switch Config
              </button>
              <button
                className="btn btnPrimary"
                disabled={busy}
                onClick={() =>
                  ex(() =>
                    agentExecutor.setReputationSwitchClients(
                      Number(agentType),
                      switchClientsCsv.split(",").map((x) => x.trim()).filter(Boolean)
                    )
                  )
                }
              >
                Set Switch Clients
              </button>
            </div>

            <div style={{ height: 12 }} />
            <div className="cardHeader">
              <h2>Onboard New Hook Agent (ERC-8004)</h2>
              <span className="pill">advanced</span>
            </div>
            {!swarmAgentRegistry ? (
              <p className="muted">Set `VITE_SWARM_AGENT_REGISTRY` to use this section.</p>
            ) : (
              <>
                <div className="grid2">
                  <div className="field">
                    <label>New Agent Address</label>
                    <input value={newAgentAddr} onChange={(e) => setNewAgentAddr(e.target.value)} />
                  </div>
                  <div className="field">
                    <label>Name</label>
                    <input value={newAgentName} onChange={(e) => setNewAgentName(e.target.value)} />
                  </div>
                  <div className="field" style={{ gridColumn: "1 / -1" }}>
                    <label>Description</label>
                    <input value={newAgentDesc} onChange={(e) => setNewAgentDesc(e.target.value)} />
                  </div>
                  <div className="field">
                    <label>agentType (ERC-8004 metadata)</label>
                    <input value={newAgentTypeStr} onChange={(e) => setNewAgentTypeStr(e.target.value)} />
                  </div>
                  <div className="field">
                    <label>version</label>
                    <input value={newAgentVersion} onChange={(e) => setNewAgentVersion(e.target.value)} />
                  </div>
                </div>
                <div style={{ display: "flex", gap: 10, marginTop: 12, flexWrap: "wrap" }}>
                  <button
                    className="btn btnPrimary"
                    disabled={busy}
                    onClick={() => registerHookAgentOnERC8004(newAgentAddr, newAgentName, newAgentDesc)}
                  >
                    Register + Link ERC-8004
                  </button>
                  <span className="muted">
                    After linking, use “Register/Switch Agent” above to swap it into AgentExecutor.
                  </span>
                </div>
              </>
            )}
          </>
        )}
      </div>

      <div className="card">
        <div className="cardHeader">
          <h2>Coordinator (Routing + ERC-8004)</h2>
          <span className="pill">owner-only</span>
        </div>
        {!coordinator ? (
          <p className="muted">Set `VITE_COORDINATOR` to use this panel.</p>
        ) : (
          <>
            <div className="grid2">
              <div className="field">
                <label>Treasury</label>
                <input value={treasury} onChange={(e) => setTreasury(e.target.value)} />
              </div>
              <div className="field">
                <label>Enforce Identity</label>
                <select value={String(enfId)} onChange={(e) => setEnfId(e.target.value === "true")}>
                  <option value="true">true</option>
                  <option value="false">false</option>
                </select>
              </div>
              <div className="field">
                <label>Enforce Reputation</label>
                <select value={String(enfRep)} onChange={(e) => setEnfRep(e.target.value === "true")}>
                  <option value="true">true</option>
                  <option value="false">false</option>
                </select>
              </div>
              <div style={{ display: "flex", gap: 10, alignItems: "end" }}>
                <button className="btn" disabled={busy} onClick={() => ex(() => coordinator.setTreasury(treasury))}>
                  Set Treasury
                </button>
                <button className="btn btnPrimary" disabled={busy} onClick={() => ex(() => coordinator.setEnforcement(enfId, enfRep))}>
                  Set Enforcement
                </button>
              </div>
            </div>

            <div style={{ height: 12 }} />

            <div className="cardHeader">
              <h2>Register Route Agent</h2>
              <span className="pill">proposal eligibility</span>
            </div>
            <div className="grid2">
              <div className="field">
                <label>Agent Address</label>
                <input value={routeAgent} onChange={(e) => setRouteAgent(e.target.value)} />
              </div>
              <div className="field">
                <label>ERC-8004 Agent ID</label>
                <input value={routeAgentId} onChange={(e) => setRouteAgentId(e.target.value)} />
              </div>
              <div className="field">
                <label>Active</label>
                <select value={String(routeActive)} onChange={(e) => setRouteActive(e.target.value === "true")}>
                  <option value="true">true</option>
                  <option value="false">false</option>
                </select>
              </div>
              <div style={{ display: "flex", gap: 10, alignItems: "end" }}>
                <button
                  className="btn btnPrimary"
                  disabled={busy}
                  onClick={() => ex(() => coordinator.registerAgent(routeAgent, BigInt(routeAgentId), routeActive))}
                >
                  Register Agent
                </button>
              </div>
            </div>

            <div style={{ height: 12 }} />

            <div className="cardHeader">
              <h2>Reputation Rules</h2>
              <span className="pill">ERC-8004</span>
            </div>
            <div className="grid2">
              <div className="field">
                <label>Reputation Registry</label>
                <input value={repReg} onChange={(e) => setRepReg(e.target.value)} />
              </div>
              <div className="field">
                <label>minReputationWad (int256)</label>
                <input value={minRep} onChange={(e) => setMinRep(e.target.value)} />
              </div>
              <div className="field">
                <label>tag1</label>
                <input value={tag1} onChange={(e) => setTag1(e.target.value)} />
              </div>
              <div className="field">
                <label>tag2</label>
                <input value={tag2} onChange={(e) => setTag2(e.target.value)} />
              </div>
              <div className="field" style={{ gridColumn: "1 / -1" }}>
                <label>clients (comma-separated addresses)</label>
                <input value={clientsCsv} onChange={(e) => setClientsCsv(e.target.value)} />
              </div>
            </div>
            <div style={{ display: "flex", gap: 10, marginTop: 12, flexWrap: "wrap" }}>
              <button
                className="btn"
                disabled={busy}
                onClick={() => ex(() => coordinator.setReputationConfig(repReg, tag1, tag2, BigInt(minRep)))}
              >
                Set Reputation Config
              </button>
              <button
                className="btn btnPrimary"
                disabled={busy}
                onClick={() =>
                  ex(() => coordinator.setReputationClients(clientsCsv.split(",").map((x) => x.trim()).filter(Boolean)))
                }
              >
                Set Clients
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
