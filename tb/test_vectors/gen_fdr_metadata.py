#!/usr/bin/env python3
"""
gen_fdr_metadata.py — Emit mini_dice pgraph metadata collateral for staged kernels.

This script generates JSON payloads whose `pgraph_meta_t` object mirrors the
fields in `rtl/dice_frontend_pkg.sv`. It is intended for TB/runtime collateral
generation, separate from the Dora build/bitgen flow.

Usage:
    python3 gen_fdr_metadata.py --kernel full_mul_array
    python3 gen_fdr_metadata.py --kernel full_mul_array --pred
    python3 gen_fdr_metadata.py --kernel load_mul_array_a --build-dir <path>
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


FULL_MUL_ARRAY_KERNEL_STAGES = (
    "load_mul_array_a",
    "load_mul_array_b",
    "mul_array",
    "compute_store_addrs",
    "store_mul_array",
)
SIMPLE_BRANCHING_KERNEL_STAGES = (
    "load_mul_array_a",
    "load_mul_array_b",
    "gen_tid_nonzero_pred",
    "mul_array",
    "add_array",
    "compute_store_addrs",
    "store_mul_array",
)

NUM_GPRS = 8
NUM_CONSTS = 8
NUM_PREDS = 2
UNUSED_LD_DEST_REG = 31

SCRIPT_PATH = Path(__file__).resolve()
REPO_ROOT = SCRIPT_PATH.parents[2]
DEFAULT_BUILD_DIR = (
    REPO_ROOT / "dora" / "examples" / "devices" / "dice-isca" / "mini_dice" / "build"
)
DEFAULT_NOPRED_BUILD_DIR = DEFAULT_BUILD_DIR.with_name("build_nopred")
DEFAULT_OUTPUT_DIR = SCRIPT_PATH.parent
DEFAULT_START_PC = 0x1000
DEFAULT_PC_STRIDE = 0x0100
DEFAULT_BITSTREAM_BASE = 0x0000
DEFAULT_BITSTREAM_STRIDE = 0x0200


def _rtl_define_int(name: str, fallback: int) -> int:
    config_path = REPO_ROOT / "rtl" / "includes" / "dice_config.vh"
    try:
        lines = config_path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return fallback

    for line in lines:
        fields = line.split("//", 1)[0].split()
        if len(fields) >= 3 and fields[0] == "`define" and fields[1] == name:
            return int(fields[2], 0)
    return fallback


DEFAULT_THREAD_COUNT = _rtl_define_int("DICE_NUM_MAX_THREADS_PER_CORE", 16)
DEFAULT_AFFINE_CSR_VALUES = {
    "csrX0": 1,       # A-side base
    "csrX1": 128,     # B-side base
    "csrX2": 256,     # C-side (store) base
    "csrX3": 4,       # thread stride
    "csrX4": 0,       # lane 0 offset
    "csrX5": 1,       # lane 1 offset
    "csrX6": 2,       # lane 2 offset
    "csrX7": 3,       # lane 3 offset
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate mini_dice pgraph metadata JSON collateral"
    )
    parser.add_argument(
        "--kernel",
        choices=("full_mul_array", "simple-branching") + SIMPLE_BRANCHING_KERNEL_STAGES,
        default="full_mul_array",
        help="Kernel or staged bundle to emit metadata for",
    )
    parser.add_argument(
        "--nopred",
        action="store_true",
        help="Use no-predicate build_nopred collateral (default)",
    )
    parser.add_argument(
        "--pred",
        action="store_true",
        help="Use traditional predicate-network build collateral when --build-dir is not set",
    )
    parser.add_argument(
        "--build-dir",
        type=Path,
        default=None,
        help="mini_dice build directory containing compile reports "
             "(default: build_nopred, or build with --pred)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help="Directory for generated metadata JSONs (default: tb/test_vectors)",
    )
    parser.add_argument(
        "--start-pc",
        type=lambda value: int(value, 0),
        default=DEFAULT_START_PC,
        help="Base PC for the first pgraph metadata entry (default: 0x1000)",
    )
    parser.add_argument(
        "--pc-stride",
        type=lambda value: int(value, 0),
        default=DEFAULT_PC_STRIDE,
        help="Byte stride between pgraph metadata PCs (default: 0x100)",
    )
    parser.add_argument(
        "--bitstream-base",
        type=lambda value: int(value, 0),
        default=DEFAULT_BITSTREAM_BASE,
        help="Base bitstream byte address for the first stage (default: 0x0)",
    )
    parser.add_argument(
        "--bitstream-stride",
        type=lambda value: int(value, 0),
        default=DEFAULT_BITSTREAM_STRIDE,
        help="Byte stride between staged bitstream images (default: 0x200)",
    )
    parser.add_argument(
        "--thread-count",
        type=int,
        default=DEFAULT_THREAD_COUNT,
        help=f"CTA thread_count to place in dice_cta_desc_t (default: {DEFAULT_THREAD_COUNT})",
    )
    return parser.parse_args()


def _bitmap_from_indices(*indices: int) -> int:
    bitmap = 0
    for idx in indices:
        bitmap |= 1 << idx
    return bitmap


def _no_branch_meta(*, is_return: bool = False) -> dict[str, int]:
    """Return a pgraph branch_meta_t payload for straight-line execution.

    For these staged mul-array kernels there is no control-flow operation, so
    `branch_ena=0` cleanly disables the branch handler semantics. The remaining
    fields are set to zero as benign don't-care values.

    The last eblock in a kernel must set ``is_return=True`` so the CTA
    scheduler knows the kernel is complete.
    """
    return {
        "branch_ena": 0,
        "branch_uni": 0,
        "branch_pred_reg": 0,
        "branch_neg_pred": 0,
        "is_return": int(is_return),
        "branch_jump_target_offset": 0,
        "branch_reconv_offset": 0,
    }


def _simple_branch_meta() -> dict[str, int]:
    """Branch on PR0 so only tid 0 takes the add target."""
    return {
        "branch_ena": 1,
        "branch_uni": 0,
        "branch_pred_reg": 0,
        "branch_neg_pred": 1,
        "is_return": 0,
        "branch_jump_target_offset": 2,
        "branch_reconv_offset": 3,
    }


def _simple_branch_mul_skip_meta() -> dict[str, int]:
    """Unconditionally skip the taken add pgraph after the not-taken mul path."""
    return {
        "branch_ena": 1,
        "branch_uni": 1,
        "branch_pred_reg": 0,
        "branch_neg_pred": 0,
        "is_return": 0,
        "branch_jump_target_offset": 2,
        "branch_reconv_offset": 0,
    }


def _simple_branching_branch_meta_for_kernel(kernel: str) -> dict[str, int] | None:
    if kernel == "gen_tid_nonzero_pred":
        return _simple_branch_meta()
    if kernel == "mul_array":
        return _simple_branch_mul_skip_meta()
    return None


def _stage_spec(kernel: str) -> dict[str, Any]:
    if kernel == "load_mul_array_a":
        return {
            "in_regs_bitmap": 0,
            "out_regs_bitmap": 0,
            "ld_dest_regs": [3, 2, 1, 0],
            "num_stores": 0,
            "unrolling_factor": 0,
            "parameter_load": 0,
            "notes": [
                "A-side load stage for the staged mul-array flow.",
                "Computes affine addresses from csrX0, regS_i_0, csrX3, and csrX4..7.",
                "Memory responses load into GPRs 0..3 after SV packed-array reversal.",
            ],
        }
    if kernel == "load_mul_array_b":
        return {
            "in_regs_bitmap": 0,
            "out_regs_bitmap": 0,
            "ld_dest_regs": [7, 6, 5, 4],
            "num_stores": 0,
            "unrolling_factor": 0,
            "parameter_load": 0,
            "notes": [
                "B-side load stage for the staged mul-array flow.",
                "Computes affine addresses from csrX1, regS_i_0, csrX3, and csrX4..7.",
                "Memory responses load into GPRs 4..7 after SV packed-array reversal.",
            ],
        }
    if kernel == "mul_array":
        return {
            "in_regs_bitmap": _bitmap_from_indices(0, 1, 2, 3, 4, 5, 6, 7),
            "out_regs_bitmap": _bitmap_from_indices(0, 1, 2, 3),
            "ld_dest_regs": [UNUSED_LD_DEST_REG] * 4,
            "num_stores": 0,
            "unrolling_factor": 0,
            "parameter_load": 0,
            "notes": [
                "Consumes GPRs 0..7 as mul operands.",
                "Assumes result writeback targets GPRs 0..3.",
            ],
        }
    if kernel == "add_array":
        return {
            "in_regs_bitmap": _bitmap_from_indices(0, 1, 2, 3, 4, 5, 6, 7),
            "out_regs_bitmap": _bitmap_from_indices(0, 1, 2, 3),
            "ld_dest_regs": [UNUSED_LD_DEST_REG] * 4,
            "num_stores": 0,
            "unrolling_factor": 0,
            "parameter_load": 0,
            "notes": [
                "Consumes GPRs 0..7 as add operands.",
                "Assumes result writeback targets GPRs 0..3.",
            ],
        }
    if kernel == "gen_tid_nonzero_pred":
        return {
            "in_regs_bitmap": 0,
            "out_regs_bitmap": _bitmap_from_indices(NUM_GPRS + NUM_CONSTS),
            "ld_dest_regs": [UNUSED_LD_DEST_REG] * 4,
            "num_stores": 0,
            "unrolling_factor": 0,
            "parameter_load": 0,
            "notes": [
                "Computes PR0 = (tid != 0) through ext_pred_o_0.",
                "Carries simple-branching control metadata in the coalesced test vector.",
            ],
        }
    if kernel == "compute_store_addrs":
        return {
            "in_regs_bitmap": 0,
            "out_regs_bitmap": _bitmap_from_indices(4, 5, 6, 7),
            "ld_dest_regs": [UNUSED_LD_DEST_REG] * 4,
            "num_stores": 0,
            "unrolling_factor": 0,
            "parameter_load": 0,
            "notes": [
                "Materializes C-side affine store addresses into GPRs 4..7.",
                "Uses csrX2 as base, regS_i_0 as tid, csrX3 as thread_stride, and csrX4..7 as lane offsets.",
            ],
        }
    if kernel == "store_mul_array":
        return {
            "in_regs_bitmap": _bitmap_from_indices(0, 1, 2, 3, 4, 5, 6, 7),
            "out_regs_bitmap": 0,
            "ld_dest_regs": [UNUSED_LD_DEST_REG] * 4,
            "num_stores": 4,
            "unrolling_factor": 0,
            "parameter_load": 0,
            "notes": [
                "Uses GPRs 0..3 as store data and precomputed GPRs 4..7 as store addresses.",
                "This stage is a pure register-to-memory route and does not recompute affine addresses.",
                "All four memory ports are marked as stores.",
            ],
        }
    raise ValueError(f"Unsupported kernel metadata spec: {kernel}")


def _report_path(build_dir: Path, kernel: str) -> Path:
    return build_dir / f"mini_dice_{kernel}_compile_report.json"


def _default_bin_path(build_dir: Path, kernel: str) -> Path:
    return build_dir / f"mini_dice_{kernel}.bin"


def _load_compile_report(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise FileNotFoundError(
            f"Compile report not found: {path}. "
            "Run the mini_dice build flow first."
        )
    with path.open("r", encoding="utf-8") as stream:
        payload = json.load(stream)
    if not isinstance(payload, dict):
        raise ValueError(f"Expected JSON object in {path}")
    return payload


def _runtime_csr_values_from_reports(
    *,
    kernels: tuple[str, ...],
    build_dir: Path,
) -> dict[str, int]:
    """Return CSR values for the test vector.

    Always uses DEFAULT_AFFINE_CSR_VALUES which are chosen so that all
    multiply products fit in 16 bits without overflow.
    """
    return dict(DEFAULT_AFFINE_CSR_VALUES)


def _bitstream_length_from_report(report: dict[str, Any]) -> int:
    binary_byte_count = report.get("binary_byte_count")
    if isinstance(binary_byte_count, int):
        return binary_byte_count

    config_byte_count = report.get("config_byte_count")
    if isinstance(config_byte_count, int):
        return config_byte_count

    raise ValueError("Compile report is missing binary_byte_count/config_byte_count")


def _latency_from_report(report: dict[str, Any], kernel: str) -> int:
    latency_cycles = report.get("latency_cycles")
    if isinstance(latency_cycles, int) and latency_cycles >= 0:
        return latency_cycles

    raise ValueError(
        f"Compile report is missing latency_cycles for {kernel}"
    )


def _pgraph_payload_for_kernel(
    *,
    kernel: str,
    build_dir: Path,
    bitstream_addr: int,
    is_last_stage: bool = False,
    branch_meta: dict[str, int] | None = None,
) -> dict[str, Any]:
    report_path = _report_path(build_dir, kernel)
    report = _load_compile_report(report_path)
    spec = _stage_spec(kernel)

    binary_output_path = report.get("binary_output_path")
    if not isinstance(binary_output_path, str) or binary_output_path == "":
        binary_output_path = str(_default_bin_path(build_dir, kernel))

    return {
        "kernel": kernel,
        "compile_report_path": str(report_path),
        "fasm_path": report.get("fasm_path"),
        "binary_output_path": binary_output_path,
        "pgraph_meta_t": {
            "bitstream_addr": bitstream_addr,
            "bitstream_length": _bitstream_length_from_report(report),
            "in_regs_bitmap": spec["in_regs_bitmap"],
            "out_regs_bitmap": spec["out_regs_bitmap"],
            "ld_dest_regs": spec["ld_dest_regs"],
            "num_stores": spec["num_stores"],
            "unrolling_factor": spec["unrolling_factor"],
            "lat": _latency_from_report(report, kernel),
            "branch_meta": (
                branch_meta
                if branch_meta is not None
                else _no_branch_meta(is_return=is_last_stage)
            ),
            "barrier": 0,
            "parameter_load": spec["parameter_load"],
        },
        "notes": spec["notes"],
    }


def _emit_metadata_for_kernel(
    *,
    kernel: str,
    build_dir: Path,
    output_dir: Path,
    bitstream_addr: int,
    output_stem: str | None = None,
    branch_meta: dict[str, int] | None = None,
) -> Path:
    payload = _pgraph_payload_for_kernel(
        kernel=kernel,
        build_dir=build_dir,
        bitstream_addr=bitstream_addr,
        is_last_stage=True,
        branch_meta=branch_meta,
    )

    if output_stem is None:
        output_stem = f"fdr_meta_{kernel}"
    output_path = output_dir / f"{output_stem}.json"
    with output_path.open("w", encoding="utf-8") as stream:
        json.dump(payload, stream, indent=2, sort_keys=True)
        stream.write("\n")
    return output_path


NUM_MEM_LANES = 4
DATA_MASK = 0xFFFF


def _axi_read_mock(addr: int) -> int:
    """Mirror the DPI-C ``dice_core_tb_axi_read16`` behaviour."""
    return addr & DATA_MASK


def _compute_full_mul_array_expected_writes(
    *,
    csr_values: dict[str, int],
    thread_count: int,
) -> list[dict[str, int]]:
    """Simulate the staged mul-array kernel and return expected AXI writes.

    Stage semantics (matching the CGRA bitstreams):
      0  load_mul_array_a   : GPR[0..3] = mem[csrX0 + tid*csrX3 + csrX{4..7}]
      1  load_mul_array_b   : GPR[4..7] = mem[csrX1 + tid*csrX3 + csrX{4..7}]
      2  mul_array           : GPR[l]   = GPR[l] * GPR[4+l]  for l in 0..3
      3  compute_store_addrs : GPR[4+l] = csrX2 + tid*csrX3 + csrX{4+l}
      4  store_mul_array     : mem[GPR[4+l]] = GPR[l]         for l in 0..3

    The AXI read mock returns ``addr & 0xFFFF`` for every load, so loaded
    values equal their addresses truncated to 16 bits.
    """
    base_a = csr_values["csrX0"]
    base_b = csr_values["csrX1"]
    base_c = csr_values["csrX2"]
    stride = csr_values["csrX3"]
    lane_offsets = [csr_values[f"csrX{4 + l}"] for l in range(NUM_MEM_LANES)]

    writes: list[dict[str, int]] = []
    for tid in range(thread_count):
        for lane in range(NUM_MEM_LANES):
            a_addr = base_a + tid * stride + lane_offsets[lane]
            b_addr = base_b + tid * stride + lane_offsets[lane]
            a_val = _axi_read_mock(a_addr)
            b_val = _axi_read_mock(b_addr)
            product = (a_val * b_val) & DATA_MASK
            store_addr = base_c + tid * stride + lane_offsets[lane]
            writes.append({"addr": store_addr, "data": product, "strb": 3})

    return writes


def _compute_simple_branching_expected_writes(
    *,
    csr_values: dict[str, int],
    thread_count: int,
) -> list[dict[str, int]]:
    """Expected writes for if (tid == 0) add else multiply."""
    base_a = csr_values["csrX0"]
    base_b = csr_values["csrX1"]
    base_c = csr_values["csrX2"]
    stride = csr_values["csrX3"]
    lane_offsets = [csr_values[f"csrX{4 + l}"] for l in range(NUM_MEM_LANES)]

    writes: list[dict[str, int]] = []
    for tid in range(thread_count):
        for lane in range(NUM_MEM_LANES):
            a_addr = base_a + tid * stride + lane_offsets[lane]
            b_addr = base_b + tid * stride + lane_offsets[lane]
            a_val = _axi_read_mock(a_addr)
            b_val = _axi_read_mock(b_addr)
            if tid == 0:
                data = (a_val + b_val) & DATA_MASK
            else:
                data = (a_val * b_val) & DATA_MASK
            store_addr = base_c + tid * stride + lane_offsets[lane]
            writes.append({"addr": store_addr, "data": data, "strb": 3})

    return writes


def _build_coalesced_test_vector(
    *,
    kernels: tuple[str, ...],
    build_dir: Path,
    start_pc: int,
    pc_stride: int,
    bitstream_base: int,
    bitstream_stride: int,
    thread_count: int,
) -> dict[str, Any]:
    pgraph_metadata = []
    stage_artifacts = []
    runtime_csr_values = _runtime_csr_values_from_reports(
        kernels=kernels,
        build_dir=build_dir,
    )

    for idx, kernel in enumerate(kernels):
        bitstream_addr = bitstream_base + idx * bitstream_stride
        branch_meta = (
            _simple_branching_branch_meta_for_kernel(kernel)
            if kernels == SIMPLE_BRANCHING_KERNEL_STAGES
            else None
        )
        stage_payload = _pgraph_payload_for_kernel(
            kernel=kernel,
            build_dir=build_dir,
            bitstream_addr=bitstream_addr,
            is_last_stage=(idx == len(kernels) - 1),
            branch_meta=branch_meta,
        )
        stage_artifacts.append(
            {
                "kernel": kernel,
                "compile_report_path": stage_payload["compile_report_path"],
                "fasm_path": stage_payload["fasm_path"],
                "binary_output_path": stage_payload["binary_output_path"],
                "notes": stage_payload["notes"],
            }
        )
        pgraph_metadata.append(
            {
                "pc": start_pc + idx * pc_stride,
                "meta": stage_payload["pgraph_meta_t"],
            }
        )

    expected_writes: list[dict[str, int]] = []
    if kernels == FULL_MUL_ARRAY_KERNEL_STAGES:
        expected_writes = _compute_full_mul_array_expected_writes(
            csr_values=runtime_csr_values,
            thread_count=thread_count,
        )
    elif kernels == SIMPLE_BRANCHING_KERNEL_STAGES:
        expected_writes = _compute_simple_branching_expected_writes(
            csr_values=runtime_csr_values,
            thread_count=thread_count,
        )

    return {
        "dice_cta_desc": {
            "kernel_desc": {
                "grid_size": {
                    "x": 1,
                    "y": 1,
                    "z": 1,
                },
                "thread_count": thread_count,
                "start_pc": start_pc,
            },
            "cta_id": {
                "x": 0,
                "y": 0,
                "z": 0,
            },
        },
        "pgraph_metadata": pgraph_metadata,
        "runtime": {
            "csr_values": runtime_csr_values,
            "axi": {
                "expected_writes": expected_writes,
            },
        },
        "stage_artifacts": stage_artifacts,
    }


def _emit_coalesced_test_vector(
    *,
    kernels: tuple[str, ...],
    build_dir: Path,
    output_dir: Path,
    start_pc: int,
    pc_stride: int,
    bitstream_base: int,
    bitstream_stride: int,
    thread_count: int,
) -> Path:
    payload = _build_coalesced_test_vector(
        kernels=kernels,
        build_dir=build_dir,
        start_pc=start_pc,
        pc_stride=pc_stride,
        bitstream_base=bitstream_base,
        bitstream_stride=bitstream_stride,
        thread_count=thread_count,
    )
    if kernels == FULL_MUL_ARRAY_KERNEL_STAGES:
        bundle_name = "full_mul_array"
    elif kernels == SIMPLE_BRANCHING_KERNEL_STAGES:
        bundle_name = "simple_branching"
    else:
        bundle_name = kernels[0]
    output_path = output_dir / f"{bundle_name}_test_vector.json"
    with output_path.open("w", encoding="utf-8") as stream:
        json.dump(payload, stream, indent=2, sort_keys=True)
        stream.write("\n")

    runtime_payload = payload["runtime"]
    runtime_path = output_dir / f"{bundle_name}_test_vector_runtime.json"
    with runtime_path.open("w", encoding="utf-8") as stream:
        json.dump(runtime_payload, stream, indent=2, sort_keys=True)
        stream.write("\n")

    return output_path


def main() -> None:
    args = parse_args()
    build_dir = (
        args.build_dir
        if args.build_dir is not None
        else (DEFAULT_BUILD_DIR if args.pred else DEFAULT_NOPRED_BUILD_DIR)
    ).resolve()
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    kernels = (
        FULL_MUL_ARRAY_KERNEL_STAGES
        if args.kernel == "full_mul_array"
        else SIMPLE_BRANCHING_KERNEL_STAGES
        if args.kernel == "simple-branching"
        else (args.kernel,)
    )

    print("Generating mini_dice pgraph metadata collateral...")
    print(f"  Build dir: {build_dir}")
    print(f"  Output dir: {output_dir}")

    for idx, kernel in enumerate(kernels):
        output_stem = (
            f"fdr_meta_simple_branching_{kernel}"
            if args.kernel == "simple-branching"
            else None
        )
        output_path = _emit_metadata_for_kernel(
            kernel=kernel,
            build_dir=build_dir,
            output_dir=output_dir,
            bitstream_addr=args.bitstream_base + idx * args.bitstream_stride,
            output_stem=output_stem,
            branch_meta=(
                _simple_branching_branch_meta_for_kernel(kernel)
                if args.kernel == "simple-branching"
                else None
            ),
        )
        print(f"  {kernel}: {output_path}")

    test_vector_path = _emit_coalesced_test_vector(
        kernels=kernels,
        build_dir=build_dir,
        output_dir=output_dir,
        start_pc=args.start_pc,
        pc_stride=args.pc_stride,
        bitstream_base=args.bitstream_base,
        bitstream_stride=args.bitstream_stride,
        thread_count=args.thread_count,
    )
    print(f"  coalesced test vector: {test_vector_path}")

    print("Done.")


if __name__ == "__main__":
    main()
