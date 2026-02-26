#!/usr/bin/env python3
import argparse
import json
import math
import os
import sys
from typing import Dict, Any, List, Tuple

def clog2(x: int) -> int:
    if x <= 1: 
        return 0
    return math.ceil(math.log2(x))

def load_json(path: str) -> Dict[str, Any]:
    with open(path, "r") as f:
        return json.load(f)

def gather_port_configs(cfg: Dict[str, Any], num_regs: int) -> List[Dict[str, Any]]:
    """
    Expand reg_config_* groups to a per-port (per-register) config list of length num_regs.
    """
    per_port = [None] * num_regs
    # collect all "reg_config_*" blocks
    for k, v in cfg.items():
        if not k.startswith("reg_config_"):
            continue
        idxs = v.get("reg_index", [])
        if not isinstance(idxs, list):
            raise ValueError(f"{k}.reg_index must be a list")
        for idx in idxs:
            if idx < 0 or idx >= num_regs:
                raise ValueError(f"{k}.reg_index contains out-of-range index {idx} (num_regs={num_regs})")
            per_port[idx] = v

    # fill any uncovered indices with a default (zeros)
    # For pred: rf_rd_en, rf_wr_en, rf_latency_in, rf_latency_out
    # For gprf: rf_rd_en, rf_wr_en, rf_latency_in, rf_latency_out, spec_rd_en, spec_rd_select, 
    #           rd_override_enable, wr_override_enable, rd_override_address, wr_override_address
    # We just set reasonable defaults (0) if not provided.
    for i in range(num_regs):
        if per_port[i] is None:
            per_port[i] = {}
    return per_port

def get_int(field: str, d: Dict[str, Any], default: int = 0) -> int:
    v = d.get(field, default)
    if isinstance(v, str):
        v = v.strip().lower()
        if v.startswith("0b"):
            return int(v, 2)
        elif v.startswith("0x"):
            return int(v, 16)
        elif v.isdigit():
            return int(v, 10)
        else:
            raise ValueError(f"Invalid numeric string for '{field}': {v}")
    elif isinstance(v, (int, float)):
        return int(v)
    else:
        raise ValueError(f"Field '{field}' must be int or str, got {type(v)}")
    return v

def clamp(value: int, bitwidth: int, name: str) -> int:
    maxv = (1 << bitwidth) - 1 if bitwidth > 0 else 1
    if value < 0:
        print(f"[WARN] {name} negative ({value}); clamping to 0")
        return 0
    if bitwidth == 0:
        return 0
    if value > maxv:
        print(f"[WARN] {name} ({value}) exceeds {bitwidth} bits; clamping to {maxv}")
        return maxv
    return value

def bits_from_int(value: int, width: int) -> str:
    if width == 0:
        return ""
    return format(value, f"0{width}b")

def emit_pred_line(port_cfg: Dict[str, Any], io_pipe_sel_w: int) -> Tuple[str, int]:
    """
    Concatenation order (MSB -> LSB) must match your SV:
      { prf_rd_en[1], prf_wr_en[1], prf_latency_in[W], prf_latency_out[W] }
    where W = IO_PIPE_SEL_WIDTH
    """
    prf_rd_en       = clamp(get_int("rf_rd_en", port_cfg, 0), 1, "prf_rd_en")
    prf_wr_en       = clamp(get_int("rf_wr_en", port_cfg, 0), 1, "prf_wr_en")
    prf_latency_in  = clamp(get_int("rf_latency_in", port_cfg, 0), io_pipe_sel_w, "prf_latency_in")
    prf_latency_out = clamp(get_int("rf_latency_out", port_cfg, 0), io_pipe_sel_w, "prf_latency_out")

    fields = [
        bits_from_int(prf_rd_en, 1),
        bits_from_int(prf_wr_en, 1),
        bits_from_int(prf_latency_in,  io_pipe_sel_w),
        bits_from_int(prf_latency_out, io_pipe_sel_w),
    ]
    line = "".join(fields)
    width = 1 + 1 + io_pipe_sel_w + io_pipe_sel_w
    return line, width

def emit_gprf_line(port_cfg: Dict[str, Any], io_pipe_sel_w: int, addr_w: int) -> Tuple[str, int]:
    """
    Concatenation order (MSB -> LSB) must match your SV:
      {
        rf_rd_en[1],
        rf_wr_en[1],
        rf_latency_in[W],
        rf_latency_out[W],
        spec_rd_en[1],
        spec_rd_select[4],
        rd_override_address[ADDR_W],
        wr_override_address[ADDR_W],
        rd_override_enable[ADDR_W],
        wr_override_enable[ADDR_W]
      }
    NOTE: Your SV slices show enable fields as ADDR_WIDTH wide; we honor that.
    """
    rf_rd_en           = clamp(get_int("rf_rd_en", port_cfg, 0), 1, "rf_rd_en")
    rf_wr_en           = clamp(get_int("rf_wr_en", port_cfg, 0), 1, "rf_wr_en")
    rf_latency_in      = clamp(get_int("rf_latency_in", port_cfg, 0),  io_pipe_sel_w, "rf_latency_in")
    rf_latency_out     = clamp(get_int("rf_latency_out", port_cfg, 0), io_pipe_sel_w, "rf_latency_out")
    spec_rd_en         = clamp(get_int("spec_rd_en", port_cfg, 0), 1, "spec_rd_en")
    spec_rd_select     = clamp(get_int("spec_rd_select", port_cfg, 0), 4, "spec_rd_select")
    rd_override_addr   = clamp(get_int("rd_override_address", port_cfg, 0), addr_w, "rd_override_address")
    wr_override_addr   = clamp(get_int("wr_override_address", port_cfg, 0), addr_w, "wr_override_address")
    # Enable fields are ADDR_WIDTH wide per your SV mapping:
    rd_override_enable = clamp(get_int("rd_override_enable", port_cfg, 0), addr_w, "rd_override_enable")
    wr_override_enable = clamp(get_int("wr_override_enable", port_cfg, 0), addr_w, "wr_override_enable")

    fields = [
        bits_from_int(rf_rd_en, 1),
        bits_from_int(rf_wr_en, 1),
        bits_from_int(rf_latency_in,  io_pipe_sel_w),
        bits_from_int(rf_latency_out, io_pipe_sel_w),
        bits_from_int(spec_rd_en, 1),
        bits_from_int(spec_rd_select, 4),
        bits_from_int(rd_override_addr,   addr_w),
        bits_from_int(wr_override_addr,   addr_w),
        bits_from_int(rd_override_enable, addr_w),
        bits_from_int(wr_override_enable, addr_w),
    ]
    line = "".join(fields)
    width = (1+1) + (io_pipe_sel_w*2) + 1 + 4 + addr_w*4
    return line, width

def main():
    ap = argparse.ArgumentParser(description="Generate predicate/GPRF bitstreams from config JSON")
    ap.add_argument("config", help="Path to gprf_config.json or pred_config.json")
    ap.add_argument("-o", "--output", help="Output file (default: bitstreams/<type>_bitstream.txt)")
    args = ap.parse_args()

    cfg = load_json(args.config)
    cfg_type = cfg.get("type", "").lower()
    if cfg_type not in ("gprf", "pred"):
        raise ValueError("Config 'type' must be 'gprf' or 'pred'")

    num_regs = int(cfg.get("num_regs", 0))
    if num_regs <= 0:
        raise ValueError("num_regs must be > 0")

    max_io_pipe_stages = int(cfg.get("max_io_pipe_stages", 0))
    io_pipe_sel_w = clog2(max_io_pipe_stages + 1)

    max_threads = int(cfg.get("max_threads", 0))

    # We infer ADDR_WIDTH from num_regs:
    addr_w = clog2(max_threads)

    per_port_cfgs = gather_port_configs(cfg, num_regs)

    # Ensure output directory
    default_name = "predrf_bitstream.txt" if cfg_type == "pred" else "gprf_bitstream.txt"
    out_path = args.output or os.path.join("bitstreams", default_name)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    lines: List[str] = []
    widths: List[int] = []

    for i in range(num_regs):
        if cfg_type == "pred":
            line, w = emit_pred_line(per_port_cfgs[i], io_pipe_sel_w)
        else:
            line, w = emit_gprf_line(per_port_cfgs[i], io_pipe_sel_w, addr_w)

        # Sanity: leftmost char is MSB; SV loader maps line[b] -> [WIDTH-1-b]
        if len(line) != w:
            raise RuntimeError(f"Internal width mismatch at port {i}: got {len(line)} vs {w}")
        lines.append(line)
        widths.append(w)

    # Check uniform per-port width for each type (your SV expects a constant PRED_RF_CFG_BITS_PER_PORT / GPRF_CFG_BITS_PER_PORT)
    if len(set(widths)) != 1:
        raise RuntimeError(f"Per-port widths not uniform: {set(widths)}")

    with open(out_path, "w") as f:
        for line in lines:
            f.write(line + "\n")

    print(f"Wrote {len(lines)} lines to {out_path}")
    if cfg_type == "pred":
        print(f"PRED_RF_CFG_BITS_PER_PORT = {widths[0]}  (1 + 1 + 2*IO_PIPE_SEL_WIDTH; IO_PIPE_SEL_WIDTH={io_pipe_sel_w})")
    else:
        print(f"GPRF_CFG_BITS_PER_PORT = {widths[0]}  ( (1+1)+(2*IO_PIPE_SEL_WIDTH)+1+4+4*ADDR_WIDTH; IO_PIPE_SEL_WIDTH={io_pipe_sel_w}, ADDR_WIDTH={addr_w})")

if __name__ == "__main__":
    main()
