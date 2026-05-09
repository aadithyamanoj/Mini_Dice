#!/usr/bin/env python3
"""Decode a Dora-compiled .bin scan-chain image into SV bs_words[] entries.

Output is suitable for pasting into a UVM test that loads the bitstream
into bsfetch via env.bsfetch_agnt.load_mem(base, bs_words).

Encoding (verified against the old cgra-v0 mul_array test that worked
bit-exact on the chain probe):
  - .bin stores scan-chain bits LSB-first within each byte.
  - 16-bit bsfetch word k = bytes [2k, 2k+1] interpreted little-endian.
  - File size is rounded up to a whole byte; total stored bits
    (config_bit_count rounded to byte) sets the file size.

Usage:
    python3 bin_to_sv.py <kernel.bin> [<var_name>]

Example:
    python3 bin_to_sv.py mini_dice_mul_array.bin bs > mul_array.svh
"""

import sys
from pathlib import Path


def decode(path: Path, var_name: str = "bs") -> str:
    raw = path.read_bytes()
    n_bits = len(raw) * 8
    n_words = (len(raw) + 1) // 2  # 16-bit words; pad odd byte with 0 high

    lines = [
        f"// Auto-generated from {path.name} ({len(raw)} bytes = {n_bits} bits, "
        f"{n_words} × 16-bit words).",
        f"logic [15:0] {var_name} [{n_words}];",
    ]

    # Pack bytes into 16-bit words, little-endian
    for k in range(n_words):
        lo = raw[2 * k]
        hi = raw[2 * k + 1] if 2 * k + 1 < len(raw) else 0
        word = (hi << 8) | lo
        lines.append(f"{var_name}[{k:3d}] = 16'h{word:04X};")

    return "\n".join(lines)


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    path = Path(sys.argv[1])
    if not path.exists():
        print(f"error: {path} not found", file=sys.stderr)
        sys.exit(1)

    var_name = sys.argv[2] if len(sys.argv) > 2 else "bs"
    print(decode(path, var_name))


if __name__ == "__main__":
    main()
