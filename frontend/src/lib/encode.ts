import { ethers } from "ethers";

export type PathKey = {
  intermediateCurrency: string;
  fee: number;
  tickSpacing: number;
  hooks: string;
  hookData: string; // 0x...
};

export function encodeCandidatePath(path: PathKey[]): string {
  const coder = ethers.AbiCoder.defaultAbiCoder();
  const tupleType =
    "tuple(address intermediateCurrency,uint24 fee,int24 tickSpacing,address hooks,bytes hookData)[]";
  const value = path.map((p) => ({
    intermediateCurrency: p.intermediateCurrency,
    fee: p.fee,
    tickSpacing: p.tickSpacing,
    hooks: p.hooks,
    hookData: p.hookData
  }));
  return coder.encode([tupleType], [value]);
}

export function toBytes32PoolIdFromPoolKey(poolKey: {
  currency0: string;
  currency1: string;
  fee: number;
  tickSpacing: number;
  hooks: string;
}): string {
  // PoolId in v4 core is keccak256(abi.encode(PoolKey)).
  const coder = ethers.AbiCoder.defaultAbiCoder();
  const encoded = coder.encode(
    ["tuple(address currency0,address currency1,uint24 fee,int24 tickSpacing,address hooks)"],
    [
      {
        currency0: poolKey.currency0,
        currency1: poolKey.currency1,
        fee: poolKey.fee,
        tickSpacing: poolKey.tickSpacing,
        hooks: poolKey.hooks
      }
    ]
  );
  return ethers.keccak256(encoded);
}

