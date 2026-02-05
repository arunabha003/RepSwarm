import { ethers } from "ethers";
import { cfg } from "./config";

type Eip1193Provider = {
  request: (args: { method: string; params?: any[] }) => Promise<any>;
  on?: (event: string, cb: (...args: any[]) => void) => void;
  removeListener?: (event: string, cb: (...args: any[]) => void) => void;
};

export function getInjected(): Eip1193Provider | null {
  const anyWin = window as any;
  const eth = anyWin?.ethereum as Eip1193Provider | undefined;
  return eth ?? null;
}

export async function connectWallet(): Promise<{
  provider: ethers.BrowserProvider;
  signer: ethers.Signer;
  address: string;
  chainId: number;
}> {
  const injected = getInjected();
  if (!injected) throw new Error("No injected wallet found (install MetaMask).");
  await injected.request({ method: "eth_requestAccounts" });
  const provider = new ethers.BrowserProvider(injected as any);
  const signer = await provider.getSigner();
  const address = await signer.getAddress();
  const network = await provider.getNetwork();
  return { provider, signer, address, chainId: Number(network.chainId) };
}

export function getReadProvider(): ethers.Provider | null {
  if (!cfg.readRpcUrl) return null;
  return new ethers.JsonRpcProvider(cfg.readRpcUrl);
}

