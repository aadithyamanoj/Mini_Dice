#!/usr/bin/env python3
"""
gen_memfile.py — Convert JSON test vectors into dice_core test collateral.

Emits:
  - `*_cta_desc.mem`
  - `*_meta.mem`
  - `*_bitstream.mem`
  - `*_runtime.json`

The `.mem` files are `$readmemh`-compatible and match the current
SystemVerilog packed struct bit layout. The runtime sidecar carries the
remaining non-readmem collateral needed by `dice_core.sv`, namely mandatory
CSR launch values and optional expected AXI writes.

Usage:
    python3 gen_memfile.py kernel_simple.json [--mem-data-width 2048] [--output-dir .]
    python3 gen_memfile.py full_mul_array_test_vector.json --nopred
"""

import argparse
import json
import math
import re
import sys
from pathlib import Path
from typing import Any


SCRIPT_PATH = Path(__file__).resolve()
REPO_ROOT = SCRIPT_PATH.parents[2]
RTL_ROOT = REPO_ROOT / "rtl"
RTL_INCLUDE_ROOT = RTL_ROOT / "includes"
MINI_DICE_TRAD_BUILD_DIR = (
    REPO_ROOT
    / "dora"
    / "examples"
    / "devices"
    / "dice-isca"
    / "mini_dice"
    / "build"
)
MINI_DICE_NOPRED_BUILD_DIR = MINI_DICE_TRAD_BUILD_DIR.with_name("build_nopred")
MINI_DICE_BUILD_DIR = MINI_DICE_TRAD_BUILD_DIR
PREFER_SELECTED_BUILD_DIR = False


def _resolve_existing_path(description: str, *candidates: Path) -> Path:
    seen: set[Path] = set()
    for candidate in candidates:
        if candidate in seen:
            continue
        seen.add(candidate)
        if candidate.exists():
            return candidate

    rendered_candidates = "\n".join(f"  - {candidate}" for candidate in candidates)
    raise FileNotFoundError(
        f"Could not locate {description}. Checked:\n{rendered_candidates}"
    )


def _resolve_repo_artifact_path(
    raw_path: str | None,
    *,
    kernel: str | None = None,
    expected_suffix: str | None = None,
) -> Path | None:
    candidates: list[Path] = []

    selected_build_candidates: list[Path] = []
    if kernel and expected_suffix:
        selected_build_candidates.append(
            MINI_DICE_BUILD_DIR / f"mini_dice_{kernel}{expected_suffix}"
        )

    if isinstance(raw_path, str) and raw_path != "":
        candidate = Path(raw_path).expanduser()
        if PREFER_SELECTED_BUILD_DIR:
            selected_build_candidates.append(MINI_DICE_BUILD_DIR / candidate.name)
            candidates.extend(selected_build_candidates)

        candidates.append(candidate)

        if not candidate.is_absolute():
            candidates.append(REPO_ROOT / candidate)

        if "Mini_Dice" in candidate.parts:
            mini_dice_idx = candidate.parts.index("Mini_Dice")
            repo_relative = Path(*candidate.parts[mini_dice_idx + 1 :])
            candidates.append(REPO_ROOT / repo_relative)

        candidates.append(MINI_DICE_BUILD_DIR / candidate.name)

    if PREFER_SELECTED_BUILD_DIR and not candidates:
        candidates.extend(selected_build_candidates)
    elif not PREFER_SELECTED_BUILD_DIR:
        candidates.extend(selected_build_candidates)

    seen: set[Path] = set()
    for candidate in candidates:
        if candidate in seen:
            continue
        seen.add(candidate)
        if candidate.exists():
            return candidate

    return None


def sv_clog2(value: int) -> int:
    if value <= 1:
        return 0
    return math.ceil(math.log2(value))


def _strip_sv_comment(text: str) -> str:
    return text.split("//", 1)[0].strip()


def _load_sv_defines(path: Path) -> dict[str, int]:
    defines: dict[str, int] = {}
    define_re = re.compile(r"^\s*`define\s+(\w+)\s+(.+?)\s*$")

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = _strip_sv_comment(raw_line)
        if not line:
            continue
        match = define_re.match(line)
        if not match:
            continue
        name, value_text = match.groups()
        defines[name] = int(value_text.strip(), 0)

    return defines


def _load_pkg_parameter(path: Path, name: str) -> int:
    param_re = re.compile(
        rf"\bparameter\s+int\s+{re.escape(name)}\s*=\s*([^;]+);"
    )
    text = path.read_text(encoding="utf-8")
    match = param_re.search(text)
    if not match:
        raise KeyError(f"Could not find parameter {name} in {path}")
    return int(_strip_sv_comment(match.group(1)), 0)


DICE_CONFIG_VH = _resolve_existing_path(
    "dice_config.vh",
    RTL_INCLUDE_ROOT / "dice_config.vh",
    RTL_ROOT / "dice_config.vh",
)
DICE_PKG_SV = _resolve_existing_path(
    "dice_pkg.sv",
    RTL_INCLUDE_ROOT / "dice_pkg.sv",
    RTL_ROOT / "dice_pkg.sv",
)

RTL_DEFINES = _load_sv_defines(DICE_CONFIG_VH)

# =====================================================================
# Bit-width constants (sourced from current RTL package/include files instead
# of being hard-coded)
# =====================================================================
DICE_ADDR_WIDTH = RTL_DEFINES["DICE_ADDR_WIDTH"]
DICE_MAX_GRID_SIZE = RTL_DEFINES["DICE_MAX_GRID_SIZE"]
DICE_NUM_MAX_THREADS_PER_CORE = RTL_DEFINES["DICE_NUM_MAX_THREADS_PER_CORE"]
DICE_GPR_NUM = RTL_DEFINES["DICE_GPR_NUM"]
DICE_PR_NUM = RTL_DEFINES["DICE_PR_NUM"]
DICE_CR_NUM = RTL_DEFINES["DICE_CR_NUM"]
DICE_CGRA_MEM_PORTS = RTL_DEFINES["DICE_CGRA_MEM_PORTS"]
DICE_MAX_PGRAPHS = RTL_DEFINES["DICE_MAX_PGRAPHS"]

DICE_CTA_ID_WIDTH = sv_clog2(DICE_MAX_GRID_SIZE)
DICE_TID_WIDTH = sv_clog2(DICE_NUM_MAX_THREADS_PER_CORE)
PR_INDEX_WIDTH = sv_clog2(DICE_PR_NUM)
PGRAPH_OFFSET_WIDTH = sv_clog2(DICE_MAX_PGRAPHS)
BITSTREAM_LENGTH_WIDTH = 8
REG_NUM = DICE_GPR_NUM + DICE_PR_NUM + DICE_CR_NUM
REG_INDEX_WIDTH = sv_clog2(REG_NUM)
LD_DEST_COUNT = DICE_CGRA_MEM_PORTS
NUM_STORES_WIDTH = sv_clog2(DICE_CGRA_MEM_PORTS + 1)
THREAD_COUNT_WIDTH = DICE_TID_WIDTH + 1

# Memory configuration from current TB / RTL
# Metadata local memory uses WORD_SIZE=256 bytes in tb_dice_core.sv.
METADATA_MEM_DATA_WIDTH  = 256 * 8
# Bitstream fetch/load uses AxiDataWidth=32 in axi4_full_crossbar.sv.
BITSTREAM_MEM_DATA_WIDTH = 32
# Bitstream payload size from dice_pkg.sv. The CLI may override this from the
# selected generated CGRA compiler_arch.json so traditional and no-pred
# collateral can coexist.
DICE_BITSTREAM_SIZE = _load_pkg_parameter(DICE_PKG_SV, "DICE_BITSTREAM_SIZE")

# Packed struct widths from current packages
BRANCH_META_WIDTH = 1 + 1 + PR_INDEX_WIDTH + 1 + 1 + PGRAPH_OFFSET_WIDTH + PGRAPH_OFFSET_WIDTH
PGRAPH_META_WIDTH = (
    DICE_ADDR_WIDTH
    + BITSTREAM_LENGTH_WIDTH
    + 2
    + 8
    + REG_NUM
    + REG_NUM
    + (LD_DEST_COUNT * REG_INDEX_WIDTH)
    + NUM_STORES_WIDTH
    + BRANCH_META_WIDTH
    + 1
    + 1
)
GRID_SIZE_WIDTH = 3 * (DICE_CTA_ID_WIDTH + 1)
CTA_ID_WIDTH_TOTAL = 3 * DICE_CTA_ID_WIDTH
KERNEL_DESC_WIDTH = GRID_SIZE_WIDTH + THREAD_COUNT_WIDTH + DICE_ADDR_WIDTH
CTA_DESC_WIDTH = KERNEL_DESC_WIDTH + CTA_ID_WIDTH_TOTAL


def parse_int(val):
    """Parse a value that may be int, bool, or hex string."""
    if isinstance(val, bool):
        return int(val)
    if isinstance(val, int):
        return val
    if isinstance(val, str):
        return int(val, 0)
    raise ValueError(f"Cannot parse {val!r} as int")


class BitPacker:
    """Packs fields MSB-first into a big integer, matching SV packed struct order."""

    def __init__(self):
        self.value = 0
        self.total_bits = 0

    def push(self, val, width):
        """Append `width` bits of `val` (MSB-first, i.e., first field goes to MSB)."""
        mask = (1 << width) - 1
        val = val & mask
        self.value = (self.value << width) | val
        self.total_bits += width

    def to_hex(self, pad_width=None):
        """Return hex string, zero-padded to pad_width bits."""
        width = pad_width or self.total_bits
        # LSB-aligned: struct in lower bits, matching SV truncation cast
        # pgraph_meta_t'(data) takes the lower bits of the memory word
        padded = self.value
        hex_chars = (width + 3) // 4
        return format(padded, f'0{hex_chars}x')


# =====================================================================
# Struct packers — field order matches SV packed struct (MSB first)
# =====================================================================

def pack_branch_meta(bm):
    """Pack current branch_meta_t."""
    p = BitPacker()
    p.push(parse_int(bm["branch_ena"]),              1)
    p.push(parse_int(bm["branch_uni"]),              1)
    p.push(parse_int(bm["branch_pred_reg"]),         PR_INDEX_WIDTH)
    p.push(parse_int(bm["branch_neg_pred"]),         1)
    p.push(parse_int(bm["is_return"]),               1)
    p.push(parse_int(bm["branch_jump_target_offset"]), PGRAPH_OFFSET_WIDTH)
    p.push(parse_int(bm["branch_reconv_offset"]),    PGRAPH_OFFSET_WIDTH)
    return p


def pack_pgraph_meta(meta):
    """Pack current pgraph_meta_t."""
    p = BitPacker()
    p.push(parse_int(meta["bitstream_addr"]),    DICE_ADDR_WIDTH)
    p.push(parse_int(meta["bitstream_length"]),  BITSTREAM_LENGTH_WIDTH)
    p.push(parse_int(meta["unrolling_factor"]),  2)
    p.push(parse_int(meta["lat"]),               8)
    p.push(parse_int(meta["in_regs_bitmap"]),    REG_NUM)
    p.push(parse_int(meta["out_regs_bitmap"]),   REG_NUM)

    # ld_dest_regs: packed [3:0][REG_INDEX_WIDTH-1:0] = 4 entries
    ld_regs = meta["ld_dest_regs"]
    for i in range(LD_DEST_COUNT):
        val = parse_int(ld_regs[i]) if i < len(ld_regs) else 0
        p.push(val, REG_INDEX_WIDTH)

    p.push(parse_int(meta["num_stores"]),        NUM_STORES_WIDTH)

    # branch_meta sub-struct
    bm = pack_branch_meta(meta["branch_meta"])
    p.push(bm.value, bm.total_bits)

    p.push(parse_int(meta["barrier"]),           1)
    p.push(parse_int(meta["parameter_load"]),    1)

    return p


def pack_grid_size(gs):
    """Pack dice_grid_size_t."""
    p = BitPacker()
    p.push(parse_int(gs["x"]), DICE_CTA_ID_WIDTH + 1)
    p.push(parse_int(gs["y"]), DICE_CTA_ID_WIDTH + 1)
    p.push(parse_int(gs["z"]), DICE_CTA_ID_WIDTH + 1)
    return p


def pack_cta_id(cid):
    """Pack dice_cta_id_t."""
    p = BitPacker()
    p.push(parse_int(cid["x"]), DICE_CTA_ID_WIDTH)
    p.push(parse_int(cid["y"]), DICE_CTA_ID_WIDTH)
    p.push(parse_int(cid["z"]), DICE_CTA_ID_WIDTH)
    return p


def pack_kernel_desc(kd):
    """Pack current dice_kernel_desc_t.

    Current package shape:
      - grid_size
      - thread_count
      - start_pc

    For compatibility with older JSON vectors, if `thread_count` is absent and
    `cta_size` is present, we derive `thread_count = x * y * z`.
    """
    p = BitPacker()
    gs = pack_grid_size(kd["grid_size"])
    p.push(gs.value, gs.total_bits)
    if "thread_count" in kd:
        thread_count = parse_int(kd["thread_count"])
    elif "cta_size" in kd:
        cta_size = kd["cta_size"]
        thread_count = (
            parse_int(cta_size["x"])
            * parse_int(cta_size["y"])
            * parse_int(cta_size["z"])
        )
    else:
        raise KeyError("kernel_desc must provide 'thread_count' or legacy 'cta_size'")
    p.push(thread_count, THREAD_COUNT_WIDTH)
    p.push(parse_int(kd["start_pc"]), DICE_ADDR_WIDTH)
    return p


def pack_cta_desc(desc):
    """Pack current dice_cta_desc_t."""
    p = BitPacker()

    kd = pack_kernel_desc(desc["kernel_desc"])
    p.push(kd.value, kd.total_bits)

    cid = pack_cta_id(desc["cta_id"])
    p.push(cid.value, cid.total_bits)

    return p


# =====================================================================
# Memory file generation
# =====================================================================

def compute_mem_addr(pc, mem_data_width):
    """Compute the memory word address from a byte PC.

    meta_fetch.sv does: addr = pc >> $clog2(METADATA_MEM_DATA_WIDTH / 8)
    where METADATA_MEM_DATA_WIDTH is in bits and the shift converts byte-address
    to word-address.
    """
    word_bytes = mem_data_width // 8
    return pc // word_bytes


def generate_meta_mem(pgraph_list, mem_data_width, output_path):
    """Generate meta.mem file with @ADDR lines."""
    with open(output_path, 'w') as f:
        f.write(f"// Auto-generated metadata memory file\n")
        f.write(f"// Memory data width: {mem_data_width} bits\n")
        f.write(f"// pgraph_meta_t packed width: {PGRAPH_META_WIDTH} bits\n\n")

        for entry in pgraph_list:
            pc = parse_int(entry["pc"])
            addr = compute_mem_addr(pc, mem_data_width)
            packed = pack_pgraph_meta(entry["meta"])
            hex_data = packed.to_hex(pad_width=mem_data_width)
            f.write(f"@{addr:08x} {hex_data}\n")

    print(f"  Wrote {output_path} ({len(pgraph_list)} entries)")


def generate_cta_desc_mem(cta_desc, output_path):
    """Generate cta_desc.mem file — $readmemh-compatible, single entry at address 0.

    The testbench loads this into a 1-deep array of packed bits via $readmemh,
    then casts the bit-vector to dice_cta_desc_t.
    """
    packed = pack_cta_desc(cta_desc)
    # Pad to a nice nibble-aligned width for $readmemh
    pad_width = ((packed.total_bits + 3) // 4) * 4  # round up to multiple of 4
    hex_data = packed.to_hex(pad_width=pad_width)

    kd = cta_desc["kernel_desc"]
    cid = cta_desc["cta_id"]

    with open(output_path, 'w') as f:
        f.write(f"// Auto-generated CTA descriptor ($readmemh format)\n")
        f.write(f"// dice_cta_desc_t packed width: {packed.total_bits} bits "
                f"(padded to {pad_width} bits)\n")
        if "thread_count" in kd:
            thread_count = kd["thread_count"]
        else:
            cta_size = kd.get("cta_size", {"x": 1, "y": 1, "z": 1})
            thread_count = (
                parse_int(cta_size["x"])
                * parse_int(cta_size["y"])
                * parse_int(cta_size["z"])
            )
        f.write(f"// grid_size=({kd['grid_size']['x']},{kd['grid_size']['y']},{kd['grid_size']['z']}), "
                f"thread_count={thread_count}, start_pc={kd['start_pc']}\n")
        f.write(f"// cta_id=({cid['x']},{cid['y']},{cid['z']})\n\n")
        f.write(f"@00000000 {hex_data}\n")

    print(f"  Wrote {output_path} ({packed.total_bits} bits, padded to {pad_width})")


def _load_compiler_bitstream_size(build_dir: Path) -> int | None:
    compiler_arch_path = build_dir / "compiler_arch.json"
    if not compiler_arch_path.exists():
        return None

    with compiler_arch_path.open("r", encoding="utf-8") as stream:
        compiler_arch = json.load(stream)

    bitstream_size = compiler_arch.get("bitstream_size")
    if isinstance(bitstream_size, int) and bitstream_size > 0:
        return bitstream_size
    return None


def _selected_bitstream_size(build_dir: Path) -> int:
    return _load_compiler_bitstream_size(build_dir) or DICE_BITSTREAM_SIZE


def generate_bitstream_mem(pgraph_list, stage_artifacts, output_path, bitstream_size):
    """Generate bitstream.mem file with test-pattern data.

    For each pgraph entry, writes NUM_CHUNKS memory words at consecutive
    addresses starting from bitstream_addr.  The memory word width matches
    BITSTREAM_MEM_DATA_WIDTH (currently 32 bits), matching the frontend
    bitstream-fetch AXI data width.

    If a pgraph entry has a "bitstream_data" list (hex strings), those are
    used verbatim.  Otherwise an incremental counting pattern is generated.
    """
    word_bytes = BITSTREAM_MEM_DATA_WIDTH // 8
    num_chunks = (bitstream_size + BITSTREAM_MEM_DATA_WIDTH - 1) // BITSTREAM_MEM_DATA_WIDTH

    with open(output_path, 'w') as f:
        f.write(f"// Auto-generated bitstream memory file\n")
        f.write(f"// Memory word width: {BITSTREAM_MEM_DATA_WIDTH} bits "
                f"({word_bytes} bytes)\n")
        f.write(f"// Bitstream payload size: {bitstream_size} bits\n")
        f.write(f"// Chunks per bitstream: {num_chunks}\n\n")

        for entry_idx, entry in enumerate(pgraph_list):
            bs_addr = parse_int(entry["meta"]["bitstream_addr"])
            bs_len = parse_int(entry["meta"]["bitstream_length"])
            explicit_data = entry["meta"].get("bitstream_data", None)
            stage_binary_words = _load_stage_bitstream_words(stage_artifacts, entry_idx)

            # Word address = byte address / word_bytes
            base_word_addr = bs_addr // word_bytes

            f.write(f"// pgraph[{entry_idx}]: bitstream_addr=0x{bs_addr:08x}, "
                    f"length={bs_len}, base_word_addr=0x{base_word_addr:08x}\n")

            for chunk_idx in range(num_chunks):
                word_addr = base_word_addr + chunk_idx

                if explicit_data and chunk_idx < len(explicit_data):
                    # Use explicit hex data from JSON
                    raw = explicit_data[chunk_idx].replace("0x", "").replace("0X", "")
                    hex_chars = BITSTREAM_MEM_DATA_WIDTH // 4
                    hex_data = raw.zfill(hex_chars)[-hex_chars:]
                elif stage_binary_words and chunk_idx < len(stage_binary_words):
                    hex_data = stage_binary_words[chunk_idx]
                else:
                    # Generate counting pattern:
                    # Each memory word carries a compact deterministic pattern.
                    pattern = 0
                    pattern_word = ((entry_idx & 0xFF) << 8) | (chunk_idx & 0xFF)
                    for _ in range(max(1, word_bytes // 2)):
                        pattern = (pattern << 16) | pattern_word
                    hex_chars = BITSTREAM_MEM_DATA_WIDTH // 4
                    hex_data = format(pattern, f'0{hex_chars}x')

                f.write(f"@{word_addr:08x} {hex_data}\n")

            f.write(f"\n")

    print(f"  Wrote {output_path} ({len(pgraph_list)} entries, "
          f"{num_chunks} chunks each)")


def _load_stage_bitstream_words(stage_artifacts: Any, stage_idx: int) -> list[str] | None:
    if not isinstance(stage_artifacts, list) or stage_idx >= len(stage_artifacts):
        return None

    stage_info = stage_artifacts[stage_idx]
    if not isinstance(stage_info, dict):
        return None

    kernel = stage_info.get("kernel")
    if not isinstance(kernel, str) or kernel == "":
        kernel = None

    binary_path = _resolve_repo_artifact_path(
        stage_info.get("binary_output_path"),
        kernel=kernel,
        expected_suffix=".bin",
    )
    if binary_path is None:
        compile_report_path = _resolve_repo_artifact_path(
            stage_info.get("compile_report_path"),
            kernel=kernel,
            expected_suffix="_compile_report.json",
        )
        if compile_report_path is not None:
            with compile_report_path.open("r", encoding="utf-8") as stream:
                compile_report = json.load(stream)
            report_binary_path = compile_report.get("binary_output_path")
            binary_path = _resolve_repo_artifact_path(
                report_binary_path if isinstance(report_binary_path, str) else None,
                kernel=kernel,
                expected_suffix=".bin",
            )
    if binary_path is None:
        return None

    raw_bytes = binary_path.read_bytes()
    words = []
    word_bytes = BITSTREAM_MEM_DATA_WIDTH // 8
    hex_chars = BITSTREAM_MEM_DATA_WIDTH // 4
    for byte_idx in range(0, len(raw_bytes), word_bytes):
        word = 0
        for offset in range(word_bytes):
            if byte_idx + offset < len(raw_bytes):
                word |= raw_bytes[byte_idx + offset] << (8 * offset)
        words.append(f"{word:0{hex_chars}x}")
    return words


def _normalize_csr_values(raw_values: Any) -> dict[str, int]:
    if raw_values is None:
        raise ValueError("runtime.csr_values is required and must provide csrX0..csrX7")
    if not isinstance(raw_values, dict):
        raise ValueError("runtime.csr_values must be a JSON object")

    normalized: dict[str, int] = {}
    for idx in range(8):
        key = f"csrX{idx}"
        if key not in raw_values:
            raise ValueError(f"runtime.csr_values is missing required key '{key}'")
        normalized[key] = parse_int(raw_values[key])
    return normalized


def _normalize_mem_entries(entries: Any) -> list[dict[str, int]]:
    if entries is None:
        return []
    if not isinstance(entries, list):
        raise ValueError("AXI memory entry list must be a JSON array")

    normalized: list[dict[str, int]] = []
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError("Each AXI memory entry must be a JSON object")
        if "addr" not in entry or "data" not in entry:
            raise ValueError("Each AXI memory entry must include 'addr' and 'data'")
        normalized_entry = {
            "addr": parse_int(entry["addr"]),
            "data": parse_int(entry["data"]),
        }
        if "strb" in entry:
            normalized_entry["strb"] = parse_int(entry["strb"])
        if "count" in entry:
            normalized_entry["count"] = parse_int(entry["count"])
        normalized.append(normalized_entry)
    return normalized


def generate_runtime_sidecar(data: dict[str, Any], output_path: Path) -> None:
    """Generate sidecar JSON for dice_core runtime inputs and expectations."""
    runtime = data.get("runtime", {})
    if runtime is None:
        runtime = {}
    if not isinstance(runtime, dict):
        raise ValueError("runtime must be a JSON object when present")

    axi = runtime.get("axi", {})
    if axi is None:
        axi = {}
    if not isinstance(axi, dict):
        raise ValueError("runtime.axi must be a JSON object when present")

    payload = {
        "csr_values": _normalize_csr_values(runtime.get("csr_values")),
        "axi": {
            "expected_writes": _normalize_mem_entries(axi.get("expected_writes")),
        },
    }

    with output_path.open("w", encoding="utf-8") as stream:
        json.dump(payload, stream, indent=2, sort_keys=True)
        stream.write("\n")

    print(f"  Wrote {output_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Convert JSON test vectors to $readmemh .mem files")
    parser.add_argument("json_file", help="Input JSON test vector file")
    parser.add_argument("--output-dir", type=str, default=None,
                        help="Output directory (default: same as JSON file)")
    parser.add_argument(
        "--nopred",
        action="store_true",
        help="Prefer build_nopred CGRA binaries and bitstream sizing",
    )
    parser.add_argument(
        "--build-dir",
        type=Path,
        default=None,
        help="Override mini_dice build directory used for fallback binaries and "
             "bitstream sizing (default: build, or build_nopred with --nopred)",
    )
    args = parser.parse_args()

    global MINI_DICE_BUILD_DIR, PREFER_SELECTED_BUILD_DIR
    MINI_DICE_BUILD_DIR = (
        args.build_dir
        if args.build_dir is not None
        else (MINI_DICE_NOPRED_BUILD_DIR if args.nopred else MINI_DICE_TRAD_BUILD_DIR)
    ).resolve()
    PREFER_SELECTED_BUILD_DIR = args.nopred or args.build_dir is not None
    bitstream_size = _selected_bitstream_size(MINI_DICE_BUILD_DIR)

    # Metadata local memory width is fixed by tb_dice_core.sv.
    mem_data_width = METADATA_MEM_DATA_WIDTH

    json_path = Path(args.json_file)
    if not json_path.exists():
        print(f"Error: {json_path} not found", file=sys.stderr)
        sys.exit(1)

    output_dir = Path(args.output_dir) if args.output_dir else json_path.parent
    output_dir.mkdir(parents=True, exist_ok=True)

    with open(json_path) as f:
        data = json.load(f)

    stem = json_path.stem  # e.g., "kernel_simple"
    print(f"Processing {json_path.name} (mem_data_width={mem_data_width} bits)")
    print(f"  mini_dice build dir: {MINI_DICE_BUILD_DIR}")
    print(f"  bitstream size: {bitstream_size} bits")

    # Generate metadata memory file
    if "pgraph_metadata" in data:
        meta_path = output_dir / f"{stem}_meta.mem"
        generate_meta_mem(data["pgraph_metadata"], mem_data_width, meta_path)

    # Generate CTA descriptor reference file
    if "dice_cta_desc" in data:
        cta_path = output_dir / f"{stem}_cta_desc.mem"
        generate_cta_desc_mem(data["dice_cta_desc"], cta_path)

    # Generate bitstream memory file
    if "pgraph_metadata" in data:
        bs_path = output_dir / f"{stem}_bitstream.mem"
        generate_bitstream_mem(
            data["pgraph_metadata"],
            data.get("stage_artifacts"),
            bs_path,
            bitstream_size,
        )

    # Generate runtime sidecar for CSR and AXI collateral.
    runtime_path = output_dir / f"{stem}_runtime.json"
    generate_runtime_sidecar(data, runtime_path)

    print("Done.")


if __name__ == "__main__":
    main()
