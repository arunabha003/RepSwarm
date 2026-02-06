#!/usr/bin/env python3
import argparse
import json
import sys
import urllib.request
from dataclasses import dataclass

from Crypto.Hash import keccak


def keccak256(b: bytes) -> bytes:
    k = keccak.new(digest_bits=256)
    k.update(b)
    return k.digest()


def zpad32(b: bytes) -> bytes:
    return b.rjust(32, b"\x00")


def hex_to_bytes(h: str) -> bytes:
    h = h.strip()
    if h.startswith("0x"):
        h = h[2:]
    if len(h) % 2:
        h = "0" + h
    return bytes.fromhex(h)


def bytes_to_hex(b: bytes) -> str:
    return "0x" + b.hex()


def addr_to_bytes32(addr: str) -> bytes:
    b = hex_to_bytes(addr)
    if len(b) != 20:
        raise ValueError("address must be 20 bytes")
    return zpad32(b)


def int_to_bytes32(i: int) -> bytes:
    if i < 0:
        raise ValueError("slot index must be non-negative")
    return i.to_bytes(32, byteorder="big")


def int_to_storage_word(v: int) -> str:
    if v < 0:
        raise ValueError("amount must be non-negative")
    return "0x" + v.to_bytes(32, byteorder="big").hex()


def rpc(rpc_url: str, method: str, params):
    payload = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        rpc_url, data=data, headers={"Content-Type": "application/json"}, method="POST"
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read().decode("utf-8")
    j = json.loads(raw)
    if "error" in j:
        raise RuntimeError(f"rpc error: {j['error']}")
    return j["result"]


def encode_balance_of(account: str) -> str:
    # balanceOf(address)
    sel = keccak256(b"balanceOf(address)")[:4]
    data = sel + addr_to_bytes32(account)
    return bytes_to_hex(data)


@dataclass
class SlotTry:
    slot_index: int
    storage_key: str


def main():
    ap = argparse.ArgumentParser(
        description="Set ERC20 balance on anvil fork by scanning for the balances mapping slot."
    )
    ap.add_argument("--rpc", required=True, help="RPC URL, e.g. http://127.0.0.1:8545")
    ap.add_argument("--token", required=True, help="ERC20 token address")
    ap.add_argument("--account", required=True, help="Account address to set balance for")
    ap.add_argument("--amount", required=True, type=int, help="New balance (raw integer)")
    ap.add_argument("--max-slot", type=int, default=20, help="Search mapping slot indices [0..max-slot]")
    args = ap.parse_args()

    rpc_url = args.rpc
    token = args.token
    account = args.account
    amount = args.amount

    # Sanity: eth_call balanceOf (may fail for non-ERC20)
    call_data = encode_balance_of(account)
    try:
        before_hex = rpc(rpc_url, "eth_call", [{"to": token, "data": call_data}, "latest"])
        before = int(before_hex, 16)
    except Exception as e:
        print(f"failed to eth_call balanceOf: {e}", file=sys.stderr)
        return 2

    print(f"balanceOf(before) = {before}")

    desired_word = int_to_storage_word(amount)

    for i in range(args.max_slot + 1):
        storage_key_bytes = keccak256(addr_to_bytes32(account) + int_to_bytes32(i))
        storage_key = bytes_to_hex(storage_key_bytes)

        try:
            old_word = rpc(rpc_url, "eth_getStorageAt", [token, storage_key, "latest"])
            rpc(rpc_url, "anvil_setStorageAt", [token, storage_key, desired_word])
            after_hex = rpc(rpc_url, "eth_call", [{"to": token, "data": call_data}, "latest"])
            after = int(after_hex, 16)
        except Exception as e:
            print(f"slot {i}: rpc failed: {e}", file=sys.stderr)
            return 2

        if after == amount:
            print(f"OK: found balances mapping slot index = {i}")
            print(f"storage key = {storage_key}")
            print(f"balanceOf(after) = {after}")
            return 0

        # restore
        try:
            rpc(rpc_url, "anvil_setStorageAt", [token, storage_key, old_word])
        except Exception as e:
            print(f"slot {i}: failed to restore storage: {e}", file=sys.stderr)
            return 2

    print(f"FAILED: could not find balances mapping slot in [0..{args.max_slot}].", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

