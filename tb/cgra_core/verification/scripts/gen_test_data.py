#!/usr/bin/env python3
"""Generate the SV test-data block for a staged 5-eblock test on cgra-nopred.

Reads:
  - tb/test_vectors/<vector>.json                     (CTA, runtime, expected,
                                                       and per-eblock metadata)
  - dora/.../build_nopred/mini_dice_<kernel>.bin      (per-eblock bitstream, ×5)

Emits SV that matches the parent test's expectation: 5 mfetch + 5 bsfetch
load_mem blocks, expect_bitstream calls, expect_store calls, CSR setup.

Usage:
    python3 gen_test_data.py
        [--vector tb/test_vectors/full_mul_array_test_vector.json]
        [--stages load_mul_array_a,load_mul_array_b,mul_array,compute_store_addrs,store_mul_array]

  Stage names map to bin filenames as mini_dice_<stage>.bin in build_nopred/.
  Defaults reproduce the full_mul_array_test_vector configuration.

Output is written to stdout — redirect to the desired .svh path.
"""

import argparse
import json
import sys
from pathlib import Path

REPO   = Path(__file__).resolve().parents[4]            # → Mini_Dice/
NOPRED = REPO / "dora/examples/devices/dice-isca/mini_dice/build_nopred"
TVEC   = REPO / "tb/test_vectors"

# Default stage order for the full_mul_array pipeline.
DEFAULT_STAGES = (
    "load_mul_array_a",
    "load_mul_array_b",
    "mul_array",
    "compute_store_addrs",
    "store_mul_array",
)
DEFAULT_VECTOR = TVEC / "full_mul_array_test_vector.json"

# Each pgraph_metadata entry is also at a specific mfetch byte address, set
# by start_pc and the number of eblocks that came before. start_pc=0x1000
# from the test vector; eblocks are 0x100 apart in mfetch (one cache line).
MFETCH_BASE   = 0x1000
MFETCH_STRIDE = 0x0100


def encode_meta(meta: dict) -> int:
    bm = meta["branch_meta"]
    ld = meta["ld_dest_regs"]
    val = 0
    val |= (meta["bitstream_addr"]   & 0xFFFF) << 94
    val |= (meta["bitstream_length"] & 0xFF)   << 86
    val |= (meta["unrolling_factor"] & 0x3)    << 84
    val |= (meta["lat"]              & 0xFF)   << 76
    val |= (meta["in_regs_bitmap"]   & ((1 << 18) - 1)) << 58
    val |= (meta["out_regs_bitmap"]  & ((1 << 18) - 1)) << 40
    for i in range(4):
        val |= (ld[i] & 0x1F) << (20 + 5 * i)
    val |= (meta["num_stores"]   & 0x7) << 17
    val |= (bm["branch_ena"]     & 0x1) << 16
    val |= (bm["branch_uni"]     & 0x1) << 15
    val |= (bm["branch_pred_reg"]    & 0x1) << 14
    val |= (bm["branch_neg_pred"]    & 0x1) << 13
    val |= (bm["is_return"]          & 0x1) << 12
    val |= (bm["branch_jump_target_offset"] & 0x1F) << 7
    val |= (bm["branch_reconv_offset"]      & 0x1F) << 2
    val |= (meta["barrier"]        & 0x1) << 1
    val |= (meta["parameter_load"] & 0x1) << 0
    return val


def emit_meta_block(stage_idx: int, meta: dict, stages: tuple) -> str:
    base = MFETCH_BASE + stage_idx * MFETCH_STRIDE
    val  = encode_meta(meta)
    lines = [
        f"    // ---- mfetch metadata: eblock {stage_idx} ({stages[stage_idx]}) @ 0x{base:04X} ----",
        f"    begin",
        f"      logic [15:0] mfetch_words [16];",
    ]
    for w in range(16):
        word = (val >> (16 * w)) & 0xFFFF
        lines.append(f"      mfetch_words[{w:2d}] = 16'h{word:04X};")
    lines += [
        f"      env.mfetch_agnt.load_mem(16'h{base:04X}, mfetch_words);",
        f"      env.sb.expect_mfetch(16'h{base:04X});",
        f"    end",
        "",
    ]
    return "\n".join(lines)


def emit_bitstream_block(stage_idx: int, bitstream_addr: int, stages: tuple) -> str:
    stage = stages[stage_idx]
    bin_path = NOPRED / f"mini_dice_{stage}.bin"
    raw = bin_path.read_bytes()
    n_words = (len(raw) + 1) // 2
    lines = [
        f"    // ---- bsfetch bitstream: eblock {stage_idx} ({stage}) @ 0x{bitstream_addr:04X} ({len(raw)} bytes, {n_words} words) ----",
        f"    begin",
        f"      logic [15:0] bs [{n_words}];",
    ]
    for k in range(n_words):
        lo = raw[2 * k]
        hi = raw[2 * k + 1] if 2 * k + 1 < len(raw) else 0
        word = (hi << 8) | lo
        lines.append(f"      bs[{k:3d}] = 16'h{word:04X};")
    lines += [
        f"      env.bsfetch_agnt.load_mem(16'h{bitstream_addr:04X}, bs);",
        f"      env.sb.expect_bitstream(bs);",
        f"      env.sb.expect_bsfetch(16'h{bitstream_addr:04X});",
        f"    end",
        "",
    ]
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--vector", default=str(DEFAULT_VECTOR),
                    help="path to test vector JSON")
    ap.add_argument("--stages", default=",".join(DEFAULT_STAGES),
                    help="comma-separated stage names (5 entries)")
    args = ap.parse_args()

    stages = tuple(args.stages.split(","))
    vector_path = Path(args.vector).resolve()
    tv  = json.loads(vector_path.read_text())
    csr = tv["runtime"]["csr_values"]
    ew  = tv["runtime"]["axi"]["expected_writes"]
    pmeta = tv["pgraph_metadata"]
    assert len(pmeta) == len(stages), \
        f"expected {len(stages)} eblocks, got {len(pmeta)}"

    out = []
    out.append("// ============================================================")
    out.append("// AUTO-GENERATED by scripts/gen_test_data.py")
    out.append(f"// Source: {vector_path.relative_to(REPO)}")
    out.append("//         dora/.../build_nopred/mini_dice_<kernel>.bin")
    out.append(f"// Stages: {', '.join(stages)}")
    out.append("// ============================================================")
    out.append("")

    for i, p in enumerate(pmeta):
        out.append(emit_meta_block(i, p["meta"], stages))

    for i, p in enumerate(pmeta):
        out.append(emit_bitstream_block(i, p["meta"]["bitstream_addr"], stages))

    # AXI-Lite read_mem: convention mem[i] = i (matches expected_writes pattern)
    out.append("    // ---- AXI-Lite read_mem (convention: mem[i] = i) ----")
    out.append("    for (int unsigned i = 0; i < 16'h0200; i++) begin")
    out.append("      env.axil_agnt.drv.read_mem[16'(i)] = 16'(i);")
    out.append("    end")
    out.append("")

    # Expected stores
    out.append(f"    // ---- Expected stores ({len(ew)} from test vector) ----")
    for w in ew:
        out.append(f"    env.sb.expect_store(16'h{w['addr']:04X}, 16'h{w['data']:04X});")
    out.append("")

    # CSRs
    out.append("    // ---- CSRs ----")
    for k in range(8):
        out.append(f"    env.cta_agnt.drv.vif.csrX[{k}] = 16'd{csr[f'csrX{k}']};")
    out.append("")

    print("\n".join(out))


if __name__ == "__main__":
    main()
