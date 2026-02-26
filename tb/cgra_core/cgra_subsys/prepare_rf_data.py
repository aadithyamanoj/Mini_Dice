#!/usr/bin/env python3
import os
import argparse
import random
from typing import Callable

# ===============================================================
# Utility
# ===============================================================
def int_to_bin_str(value, width=32):
    """Convert integer to MSB-first binary string."""
    return format(value & ((1 << width) - 1), f"0{width}b")

# ===============================================================
# Pattern examples (you can define your own!)
# ===============================================================
def pattern_random(prefix, port, addr, width):
    return random.getrandbits(width)

def pattern_increment(prefix, port, addr, width):
    return addr + port * 1000

def pattern_checkerboard(prefix, port, addr, width):
    return 0xAAAAAAAA if (addr % 2 == 0) else 0x55555555

def pattern_weighted(prefix, port, addr, width):
    return (addr * 13 + port * 7) & ((1 << width) - 1)


# ===============================================================
# Generator
# ===============================================================
def generate_rf_data(
    prefix: str,
    num_ports: int,
    depth: int,
    width: int,
    outdir: str,
    pattern_func: Callable[[str, int, int, int], int],
):
    """
    Generate register file data for CGRA simulation.
    prefix = 'r' (GPRF) or 'p' (PredRF)
    """
    os.makedirs(outdir, exist_ok=True)
    for port in range(num_ports):
        fname = os.path.join(outdir, f"{prefix}{port}_in.txt")
        with open(fname, "w") as f:
            for addr in range(depth):
                val = pattern_func(prefix, port, addr, width)
                f.write(int_to_bin_str(val, width) + "\n")
        print(f"[INFO] Generated {fname}")
    print(f"[DONE] {num_ports} files written in {outdir}/")

# ===============================================================
# Main CLI
# ===============================================================
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate CGRA RF input data files.")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--gprf", action="store_true", help="Generate GPRF (r*) input files")
    group.add_argument("--predrf", action="store_true", help="Generate PredRF (p*) input files")
    parser.add_argument("--num_ports", type=int, default=16)
    parser.add_argument("--depth", type=int, default=512)
    parser.add_argument("--width", type=int, default=32)
    parser.add_argument("--outdir", default="rf_input")
    parser.add_argument("--mode", default="random",
                        choices=["random", "increment", "checkerboard", "weighted"],
                        help="Pattern mode")
    parser.add_argument("--seed", type=int, default=0)
    args = parser.parse_args()

    random.seed(args.seed)

    # Select prefix
    prefix = "r" if args.gprf else "p"

    # Choose pattern
    if args.mode == "random":
        pattern_func = pattern_random
    elif args.mode == "increment":
        pattern_func = pattern_increment
    elif args.mode == "checkerboard":
        pattern_func = pattern_checkerboard
    elif args.mode == "weighted":
        pattern_func = pattern_weighted
    else:
        raise ValueError("Unknown pattern mode")

    generate_rf_data(prefix, args.num_ports, args.depth, args.width, args.outdir, pattern_func)
