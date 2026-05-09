#!/usr/bin/env python3
"""Encode a pgraph_meta_t JSON description into the 16-word mfetch image
the test loads via env.mfetch_agnt.load_mem(base, mfetch_words).

Bit layout (per dice_frontend_pkg.sv pgraph_meta_t, MSB→LSB):
  [109:94]  bitstream_addr      (16 bits, DICE_ADDR_WIDTH)
  [ 93:86]  bitstream_length    ( 8 bits, BITSTREAM_LENGTH_WIDTH; bytes!)
  [ 85:84]  unrolling_factor    ( 2 bits)
  [ 83:76]  lat                 ( 8 bits)
  [ 75:58]  in_regs_bitmap      (18 bits, REG_NUM = GPR8 + PR2 + CR8)
  [ 57:40]  out_regs_bitmap     (18 bits)
  [ 39:20]  ld_dest_regs[3..0]  (4×5 bits; port 3 at high bits, port 0 at low)
  [ 19:17]  num_stores          ( 3 bits, $clog2(MEM_PORTS+1))
  [ 16:2]   branch_meta         (15 bits):
            [ 16]    branch_ena
            [ 15]    branch_uni
            [ 14]    branch_pred_reg          (PR_INDEX_WIDTH = 1)
            [ 13]    branch_neg_pred
            [ 12]    is_return
            [11:7]   branch_jump_target_offset ( 5 bits)
            [ 6:2]   branch_reconv_offset      ( 5 bits)
  [   1]    barrier
  [   0]    parameter_load
The whole 110-bit struct sits in bits [109:0] of a 256-bit metadata frame;
bits [255:110] are zero padding.

Usage:
    python3 meta_to_sv.py <fdr_meta_*.json> [<var_name>]
"""

import json
import sys
from pathlib import Path


def encode(meta: dict) -> int:
    """Return the 110-bit packed value as a Python int."""
    bm = meta["branch_meta"]
    ld = meta["ld_dest_regs"]

    val = 0
    val |= (meta["bitstream_addr"]   & 0xFFFF) << 94
    val |= (meta["bitstream_length"] & 0xFF)   << 86
    val |= (meta["unrolling_factor"] & 0x3)    << 84
    val |= (meta["lat"]              & 0xFF)   << 76
    val |= (meta["in_regs_bitmap"]   & ((1 << 18) - 1)) << 58
    val |= (meta["out_regs_bitmap"]  & ((1 << 18) - 1)) << 40
    # ld_dest_regs[i] at bits [20+5*i +: 5]; port 0 at LSB, port 3 at MSB
    for i in range(4):
        val |= (ld[i] & 0x1F) << (20 + 5 * i)
    val |= (meta["num_stores"]       & 0x7)    << 17
    val |= (bm["branch_ena"]         & 0x1)    << 16
    val |= (bm["branch_uni"]         & 0x1)    << 15
    val |= (bm["branch_pred_reg"]    & 0x1)    << 14
    val |= (bm["branch_neg_pred"]    & 0x1)    << 13
    val |= (bm["is_return"]          & 0x1)    << 12
    val |= (bm["branch_jump_target_offset"] & 0x1F) << 7
    val |= (bm["branch_reconv_offset"]      & 0x1F) << 2
    val |= (meta["barrier"]          & 0x1)    << 1
    val |= (meta["parameter_load"]   & 0x1)    << 0
    return val


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(1)
    path = Path(sys.argv[1])
    if not path.exists():
        print(f"error: {path} not found", file=sys.stderr)
        sys.exit(1)

    var_name = sys.argv[2] if len(sys.argv) > 2 else "mfetch_words"
    payload = json.loads(path.read_text())
    meta = payload.get("pgraph_meta_t") or payload.get("pgraph_metadata", [{}])[0].get("meta")
    if meta is None:
        print(f"error: no pgraph_meta_t / pgraph_metadata.meta in {path}",
              file=sys.stderr)
        sys.exit(1)

    val = encode(meta)
    print(f"// Auto-generated from {path.name} (kernel={payload.get('kernel','?')}).")
    print(f"// pgraph_meta_t = 110 bits, padded to 256-bit metadata frame.")
    print(f"logic [15:0] {var_name} [16];")
    for w in range(16):
        word = (val >> (16 * w)) & 0xFFFF
        print(f"{var_name}[{w:2d}] = 16'h{word:04X};")


if __name__ == "__main__":
    main()
