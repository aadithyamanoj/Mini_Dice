#!/usr/bin/env python3
"""
gen_fdr_metadata.py — Emit mini_dice pgraph metadata collateral for staged kernels.

This script generates JSON payloads whose `pgraph_meta_t` object mirrors the
fields in `rtl/dice_frontend_pkg.sv`. It is intended for TB/runtime collateral
generation, separate from the Dora build/bitgen flow.

Usage:
    python3 gen_fdr_metadata.py --kernel full_mul_array
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

NUM_GPRS = 8
NUM_CONSTS = 8
NUM_PREDS = 2
UNUSED_LD_DEST_REG = 31

SCRIPT_PATH = Path(__file__).resolve()
REPO_ROOT = SCRIPT_PATH.parents[2]
DEFAULT_BUILD_DIR = (
    REPO_ROOT / "dora" / "examples" / "devices" / "dice-isca" / "mini_dice" / "build"
)
DEFAULT_OUTPUT_DIR = SCRIPT_PATH.parent
DEFAULT_START_PC = 0x1000
DEFAULT_PC_STRIDE = 0x0100
DEFAULT_BITSTREAM_BASE = 0x0000
DEFAULT_BITSTREAM_STRIDE = 0x0200
DEFAULT_THREAD_COUNT = 16
DEFAULT_AFFINE_CSR_VALUES = {
    "csrX0": 0x0100,
    "csrX1": 0x0200,
    "csrX2": 0x0300,
    "csrX3": 0x0008,
    "csrX4": 0x0000,
    "csrX5": 0x0001,
    "csrX6": 0x0002,
    "csrX7": 0x0003,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate mini_dice pgraph metadata JSON collateral"
    )
    parser.add_argument(
        "--kernel",
        choices=("full_mul_array",) + FULL_MUL_ARRAY_KERNEL_STAGES,
        default="full_mul_array",
        help="Kernel or staged bundle to emit metadata for",
    )
    parser.add_argument(
        "--build-dir",
        type=Path,
        default=DEFAULT_BUILD_DIR,
        help="mini_dice build directory containing compile reports",
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
        help="CTA thread_count to place in dice_cta_desc_t (default: 16)",
    )
    return parser.parse_args()


def _bitmap_from_indices(*indices: int) -> int:
    bitmap = 0
    for idx in indices:
        bitmap |= 1 << idx
    return bitmap


def _no_branch_meta() -> dict[str, int]:
    """Return a pgraph branch_meta_t payload for straight-line execution.

    For these staged mul-array kernels there is no control-flow operation, so
    `branch_ena=0` cleanly disables the branch handler semantics. The remaining
    fields are set to zero as benign don't-care values.
    """
    return {
        "branch_ena": 0,
        "branch_uni": 0,
        "branch_pred_reg": 0,
        "branch_neg_pred": 0,
        "is_return": 0,
        "branch_jump_target_offset": 0,
        "branch_reconv_offset": 0,
    }


def _stage_spec(kernel: str) -> dict[str, Any]:
    if kernel == "load_mul_array_a":
        return {
            "in_regs_bitmap": 0,
            "out_regs_bitmap": 0,
            "ld_dest_regs": [0, 1, 2, 3],
            "num_stores": 0,
            "unrolling_factor": 0,
            "parameter_load": 0,
            "notes": [
                "A-side load stage for the staged mul-array flow.",
                "Computes affine addresses from csrX0, regS_i_0, csrX3, and csrX4..7.",
                "Memory responses load into GPRs 0..3.",
            ],
        }
    if kernel == "load_mul_array_b":
        return {
            "in_regs_bitmap": 0,
            "out_regs_bitmap": 0,
            "ld_dest_regs": [4, 5, 6, 7],
            "num_stores": 0,
            "unrolling_factor": 0,
            "parameter_load": 0,
            "notes": [
                "B-side load stage for the staged mul-array flow.",
                "Computes affine addresses from csrX1, regS_i_0, csrX3, and csrX4..7.",
                "Memory responses load into GPRs 4..7.",
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
    for kernel in kernels:
        report = _load_compile_report(_report_path(build_dir, kernel))
        runtime_contract = report.get("runtime_contract")
        if not isinstance(runtime_contract, dict):
            continue
        raw_defaults = runtime_contract.get("default_csr_values")
        if not isinstance(raw_defaults, dict):
            continue

        csr_values: dict[str, int] = {}
        for idx in range(8):
            key = f"csrX{idx}"
            value = raw_defaults.get(key)
            if not isinstance(value, int):
                break
            csr_values[key] = value
        else:
            return csr_values

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
            "branch_meta": _no_branch_meta(),
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
) -> Path:
    payload = _pgraph_payload_for_kernel(
        kernel=kernel,
        build_dir=build_dir,
        bitstream_addr=bitstream_addr,
    )

    output_path = output_dir / f"fdr_meta_{kernel}.json"
    with output_path.open("w", encoding="utf-8") as stream:
        json.dump(payload, stream, indent=2, sort_keys=True)
        stream.write("\n")
    return output_path


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
        stage_payload = _pgraph_payload_for_kernel(
            kernel=kernel,
            build_dir=build_dir,
            bitstream_addr=bitstream_addr,
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
                "expected_writes": [],
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
    bundle_name = "full_mul_array" if len(kernels) > 1 else kernels[0]
    output_path = output_dir / f"{bundle_name}_test_vector.json"
    with output_path.open("w", encoding="utf-8") as stream:
        json.dump(payload, stream, indent=2, sort_keys=True)
        stream.write("\n")
    return output_path


def main() -> None:
    args = parse_args()
    build_dir = args.build_dir.resolve()
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    kernels = (
        FULL_MUL_ARRAY_KERNEL_STAGES
        if args.kernel == "full_mul_array"
        else (args.kernel,)
    )

    print("Generating mini_dice pgraph metadata collateral...")
    print(f"  Build dir: {build_dir}")
    print(f"  Output dir: {output_dir}")

    for idx, kernel in enumerate(kernels):
        output_path = _emit_metadata_for_kernel(
            kernel=kernel,
            build_dir=build_dir,
            output_dir=output_dir,
            bitstream_addr=args.bitstream_base + idx * args.bitstream_stride,
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
