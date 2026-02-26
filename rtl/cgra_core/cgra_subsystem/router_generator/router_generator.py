#!/usr/bin/env python3
"""
Configurable Router RTL Generator (with per-track overload & selmap JSON)
=========================================================================

Run:
  python3 router_generator.py router.config [outdir]
    - outdir defaults to ./output
    - emits:
        <outdir>/<module_name>.sv
        <outdir>/<module_name>_selmap.json

Key features:
- Asymmetric per-port input/output track counts
- Cross-track connectivity (fully connected or customized map)
- Per-(out port, out track) register control
- Per-(out port, out track) overload with 2-bit handshake:
    overload_en_<PORT>_t<k> & overload_ctrl_<PORT>_t<k> → force source L_in_t0
  (Only L[0] is supported as the overload source.)
- Writes a JSON select map describing the select encoding for each output
"""

from __future__ import annotations
from dataclasses import dataclass
from typing import Dict, List, Tuple, Union, Optional
from pathlib import Path
import json, math, sys, re


# -----------------------------
# Utilities
# -----------------------------

def clog2(n: int) -> int:
    return max(1, math.ceil(math.log2(max(2, n))))

def strip_line_comments(text: str) -> str:
    out = []
    for line in text.splitlines():
        if '//' in line:
            line = line.split('//', 1)[0]
        out.append(line)
    return '\n'.join(out)


# -----------------------------
# Config structures
# -----------------------------

@dataclass
class RouterConfig:
    module_name: str
    ports: List[str]                         # ["N","E","S","W","L"]
    in_tracks: Dict[str, int]                # per-port input track count
    out_tracks: Dict[str, int]               # per-port output track count
    track_widths: Union[int, Dict[str, Union[int, List[int]]], List[int]]
    topology: Dict                           # {"name": "fully connected"| "customized", ...}
    overload_enabled: bool = False           # when true, overload mux to L_in_t0 is generated
    expose_config_if: bool = True
    include_reset: bool = True
    add_clock: bool = True

    def __post_init__(self):
        if not self.ports:
            raise ValueError("ports must be non-empty")
        for p in self.ports:
            if not p.isidentifier():
                raise ValueError(f"Invalid port name: {p}")
            if p not in self.in_tracks or p not in self.out_tracks:
                raise ValueError(f"Missing track counts for port {p}")
            if self.in_tracks[p] <= 0 or self.out_tracks[p] <= 0:
                raise ValueError(f"in/out track counts must be >=1 for port {p}")
        if self.overload_enabled:
            if "L" not in self.ports:
                raise ValueError("overload requires port 'L' present")
            if self.in_tracks.get("L", 0) < 1:
                raise ValueError("overload requires L to have at least 1 input track (L[0])")


# -----------------------------
# Width resolution
# -----------------------------

def resolve_width(width_spec: Union[int, Dict[str, Union[int, List[int]]], List[int]],
                  port: str, track_idx: int) -> int:
    """
    Supported forms:
      - int -> uniform width
      - list[int] -> index by track_idx (shared across ports)
      - dict:
          { "default": 32, "L": 16 }               -> per-port scalar with fallback
          { "N":[32,32], "E":[32,32], ... }        -> per-port, per-track list
    """
    if isinstance(width_spec, int):
        return int(width_spec)
    if isinstance(width_spec, list):
        if track_idx < 0 or track_idx >= len(width_spec):
            raise ValueError(f"track_widths list too short for track {track_idx}")
        return int(width_spec[track_idx])
    if isinstance(width_spec, dict):
        if port in width_spec:
            v = width_spec[port]
            if isinstance(v, int):
                return int(v)
            if isinstance(v, list):
                if track_idx < 0 or track_idx >= len(v):
                    raise ValueError(f"track_widths[{port}] list too short for track {track_idx}")
                return int(v[track_idx])
        if "default" in width_spec:
            return int(width_spec["default"])
    raise ValueError(f"Cannot resolve width for port={port}, track={track_idx} from {width_spec}")


# -----------------------------
# Topology builders
# -----------------------------

def all_input_pairs(ports: List[str], in_tracks: Dict[str, int]) -> List[Tuple[str, int]]:
    pairs: List[Tuple[str,int]] = []
    for ip in ports:
        for ti in range(in_tracks[ip]):
            pairs.append((ip, ti))
    return pairs

def parse_out_key(key: str) -> Tuple[str, int]:
    m = re.fullmatch(r'([A-Za-z_]\w*)\[(\d+)\]', key.strip())
    if not m:
        raise ValueError(f"Invalid outputs_allowed_inputs key '{key}'. Use 'PORT[idx]' e.g. 'N[0]'.")
    return m.group(1), int(m.group(2))

def expand_input_token(tok: str, ports: List[str], in_tracks: Dict[str, int]) -> List[Tuple[str,int]]:
    tok = tok.strip()
    if tok.upper() == "ALL":
        return all_input_pairs(ports, in_tracks)
    m = re.fullmatch(r'([A-Za-z_]\w*)\[(\*|\d+)\]', tok)
    if m:
        ip = m.group(1)
        if ip not in ports:
            raise ValueError(f"Unknown input port '{ip}' in outputs_allowed_inputs")
        idx = m.group(2)
        if idx == '*':
            return [(ip, ti) for ti in range(in_tracks[ip])]
        ti = int(idx)
        if ti < 0 or ti >= in_tracks[ip]:
            raise ValueError(f"Input track index {ti} out of range for port {ip}")
        return [(ip, ti)]
    if tok in ports:  # bare port name -> all its tracks
        return [(tok, ti) for ti in range(in_tracks[tok])]
    # support compact "L0"
    m2 = re.fullmatch(r'([A-Za-z_]\w*)(\d+)', tok)
    if m2:
        ip = m2.group(1)
        ti = int(m2.group(2))
        if ip not in ports:
            raise ValueError(f"Unknown input port '{ip}' in token '{tok}'")
        if ti < 0 or ti >= in_tracks[ip]:
            raise ValueError(f"Input track index {ti} out of range for port {ip}")
        return [(ip, ti)]
    raise ValueError(f"Bad input token '{tok}'. Use 'ALL', 'PORT[*]', 'PORT[idx]', 'PORT', or 'PORTidx' (e.g., L0).")

def build_allowed_map(ports: List[str],
                      in_tracks: Dict[str, int],
                      out_tracks: Dict[str, int],
                      topology: Dict) -> Dict[Tuple[str, int], List[Tuple[str, int]]]:
    """
    Returns mapping: (out_port, out_track) -> list[(in_port, in_track)]
    Topology forms:
      { "name": "fully connected" }
      { "name": "customized", "outputs_allowed_inputs": { "N[0]": ["ALL"], "L[2]":["E[*]","W[0]"] } }
    """
    name = topology.get("name", "").strip().lower()
    allowed: Dict[Tuple[str,int], List[Tuple[str,int]]] = {}

    if name in ("fully connected", "fully_connected", "crossbar"):
        full = all_input_pairs(ports, in_tracks)
        for op in ports:
            for to in range(out_tracks[op]):
                allowed[(op, to)] = list(full)
        return allowed

    if name in ("customized", "custom"):
        oai = topology.get("outputs_allowed_inputs", {})
        # Initialize all outputs with empty list
        for op in ports:
            for to in range(out_tracks[op]):
                allowed[(op, to)] = []
        # Fill based on the provided map
        for out_key, tok_list in oai.items():
            op, to = parse_out_key(out_key)
            if op not in ports:
                raise ValueError(f"Unknown output port '{op}' in outputs_allowed_inputs")
            if to < 0 or to >= out_tracks[op]:
                raise ValueError(f"Output track {to} out of range for port {op}")
            srcs: List[Tuple[str,int]] = []
            for tok in tok_list:
                srcs.extend(expand_input_token(tok, ports, in_tracks))
            # Deduplicate preserving order
            seen = set()
            uniq = []
            for s in srcs:
                if s not in seen:
                    seen.add(s)
                    uniq.append(s)
            allowed[(op, to)] = uniq
        return allowed

    raise ValueError(f"Unknown topology name '{name}'. Use 'fully connected' or 'customized'.")


# -----------------------------
# SV generator + selmap writer
# -----------------------------

def generate_router_sv_and_selmap(cfg: RouterConfig, outdir: Path) -> str:
    ports = cfg.ports
    in_tracks = cfg.in_tracks
    out_tracks = cfg.out_tracks

    allowed = build_allowed_map(ports, in_tracks, out_tracks, cfg.topology)

    # --- Prepare JSON select map (consistent with RTL ordering) ---
    selmap: Dict[str, dict] = {}
    for op in ports:
        for to in range(out_tracks[op]):
            key = f"{op}[{to}]"
            srcs = allowed[(op, to)]
            sources_str = [f"{ip}[{ti}]" for (ip, ti) in srcs]
            k = len(srcs)
            sel_bits = 0 if k <= 1 else clog2(k)
            entry = {
                "sel_bits": sel_bits,
                "sources": sources_str,
                "default_selected_index": 0
            }
            if cfg.overload_enabled:
                entry["overload_forces"] = "L[0]"
            selmap[key] = entry

    # Write selmap JSON alongside the SV
    selmap_path = outdir / f"{cfg.module_name}_selmap.json"
    selmap_path.write_text(json.dumps(selmap, indent=2))

    # --- Generate RTL ---
    lines: List[str] = []
    mn = cfg.module_name

    # Module header
    lines.append(f"module {mn} (")

    port_decls: List[str] = []

    if cfg.add_clock:
        port_decls.append("input  logic clk")
    if cfg.include_reset:
        port_decls.append("input  logic rst_n")

    # Overload handshake per (out_port,out_track) if enabled: overload_en_*, overload_ctrl_*
    if cfg.overload_enabled:
        for op in ports:
            for to in range(out_tracks[op]):
                port_decls.append(f"input  logic overload_en_{op}_t{to}")
                port_decls.append(f"input  logic overload_ctrl_{op}_t{to}")

    # Per-(out_port,out_track) register mode bit
    for op in ports:
        for to in range(out_tracks[op]):
            port_decls.append(f"input  logic registered_mode_{op}_t{to}")

    # Data inputs per (in_port, in_track)
    for ip in ports:
        for ti in range(in_tracks[ip]):
            w = resolve_width(cfg.track_widths, ip, ti)
            port_decls.append(f"input  logic [{w-1}:0] {ip}_in_t{ti}")

    # Data outputs per (out_port, out_track)
    for op in ports:
        for to in range(out_tracks[op]):
            w = resolve_width(cfg.track_widths, op, to)
            port_decls.append(f"output logic [{w-1}:0] {op}_out_t{to}")

    # Optional select per (out_port,out_track)
    if cfg.expose_config_if:
        for op in ports:
            for to in range(out_tracks[op]):
                k = len(allowed[(op, to)])
                if k > 1:
                    sb = clog2(k)
                    port_decls.append(f"input  logic [{sb-1}:0] sel_{op}_t{to}")

    lines.append("    " + ",\n    ".join(port_decls))
    lines.append(");\n")

    # Internals: selection + (overload) mux + register path
    for op in ports:
        for to in range(out_tracks[op]):
            w = resolve_width(cfg.track_widths, op, to)
            lines.append(f"  logic [{w-1}:0] {op}_sel_t{to};")
            lines.append(f"  logic [{w-1}:0] {op}_mux_t{to};")
            lines.append(f"  logic [{w-1}:0] {op}_reg_t{to};")
    lines.append("")

    # Pre-overload selection (normal allowed sources)
    for op in ports:
        for to in range(out_tracks[op]):
            w_out = resolve_width(cfg.track_widths, op, to)
            srcs = allowed[(op, to)]
            # Width check for allowed sources
            for (ip, ti) in srcs:
                w_in = resolve_width(cfg.track_widths, ip, ti)
                if w_in != w_out:
                    raise ValueError(f"Width mismatch: {op}[{to}] width {w_out} vs {ip}[{ti}] width {w_in}")
            if len(srcs) == 0:
                lines.append(f"  assign {op}_sel_t{to} = '0; // no allowed inputs")
            elif len(srcs) == 1:
                ip, ti = srcs[0]
                lines.append(f"  assign {op}_sel_t{to} = {ip}_in_t{ti};")
            else:
                sb = clog2(len(srcs))
                if cfg.expose_config_if:
                    sel = f"sel_{op}_t{to}"
                    lines.append("  always_comb begin")
                    lines.append(f"    unique case ({sel})")
                    for idx, (ip, ti) in enumerate(srcs):
                        lines.append(f"      {sb}'d{idx}: {op}_sel_t{to} = {ip}_in_t{ti};")
                    lines.append(f"      default: {op}_sel_t{to} = '0;")
                    lines.append("    endcase")
                    lines.append("  end")
                else:
                    ip, ti = srcs[0]
                    lines.append(f"  assign {op}_sel_t{to} = {ip}_in_t{ti};")
    lines.append("")

    # Overload mux (force to L_in_t0 per track if enabled and both handshake bits = 1)
    if cfg.overload_enabled:
        # Validate presence and width of L[0]
        w_L0 = resolve_width(cfg.track_widths, "L", 0)
        for op in ports:
            for to in range(out_tracks[op]):
                w_out = resolve_width(cfg.track_widths, op, to)
                if w_out != w_L0:
                    raise ValueError(f"Overload width mismatch for {op}[{to}]: out={w_out} vs L[0]={w_L0}")
                lines.append(
                    f"  assign {op}_mux_t{to} = "
                    f"(overload_en_{op}_t{to} & overload_ctrl_{op}_t{to}) ? L_in_t0 : {op}_sel_t{to};"
                )
        lines.append("")
    else:
        for op in ports:
            for to in range(out_tracks[op]):
                lines.append(f"  assign {op}_mux_t{to} = {op}_sel_t{to};")
        lines.append("")

    # Registers
    if cfg.add_clock and cfg.include_reset:
        lines.append("  always_ff @(posedge clk or negedge rst_n) begin")
        lines.append("    if (!rst_n) begin")
        for op in ports:
            for to in range(out_tracks[op]):
                lines.append(f"      {op}_reg_t{to} <= '0;")
        lines.append("    end else begin")
        for op in ports:
            for to in range(out_tracks[op]):
                lines.append(f"      {op}_reg_t{to} <= {op}_mux_t{to};")
        lines.append("    end")
        lines.append("  end\n")

    # Output select via register mode
    for op in ports:
        for to in range(out_tracks[op]):
            lines.append(f"  assign {op}_out_t{to} = "
                         f"registered_mode_{op}_t{to} ? {op}_reg_t{to} : {op}_mux_t{to};")

    lines.append(f"\nendmodule : {mn}\n")
    return "\n".join(lines)


# -----------------------------
# Load & normalize config
# -----------------------------

def load_config(path: str) -> RouterConfig:
    raw = Path(path).read_text()
    raw = strip_line_comments(raw)
    data = json.loads(raw)

    module_name = data["module_name"]
    ports: List[str] = data["ports"]

    # num_ports aligned with ports:
    #   int n          -> in=n, out=n
    #   [in, out]      -> explicit
    #   {"in":x,"out":y}
    np_field = data["num_ports"]
    if len(np_field) != len(ports):
        raise ValueError("num_ports must have same length as ports")
    in_tracks: Dict[str,int] = {}
    out_tracks: Dict[str,int] = {}
    for p, val in zip(ports, np_field):
        if isinstance(val, int):
            i = o = int(val)
        elif isinstance(val, list) and len(val) == 2:
            i, o = int(val[0]), int(val[1])
        elif isinstance(val, dict):
            i = int(val.get("in", 0))
            o = int(val.get("out", 0))
        else:
            raise ValueError(f"num_ports entry for {p} must be int, [in,out], or {{'in':..,'out':..}}")
        if i <= 0 or o <= 0:
            raise ValueError(f"num_ports for {p} must be >=1")
        in_tracks[p] = i
        out_tracks[p] = o

    track_widths = data.get("track_widths", 32)
    topologies = data.get("topologies", [])
    if not topologies:
        raise ValueError("topologies must have at least one entry")
    topology = topologies[0]  # use the first entry

    # Overload enabled only if overload_port_input present and == "L0" or "L[0]"
    overload_enabled = False
    if "overload_port_input" in data and data["overload_port_input"] is not None:
        tok = str(data["overload_port_input"]).strip()
        if tok in ("L0", "L[0]"):
            overload_enabled = True
        else:
            raise ValueError("Only 'L0' or 'L[0]' is supported for overload_port_input")

    return RouterConfig(
        module_name = module_name,
        ports       = ports,
        in_tracks   = in_tracks,
        out_tracks  = out_tracks,
        track_widths= track_widths,
        topology    = topology,
        overload_enabled = overload_enabled,
        expose_config_if = data.get("expose_config_if", True),
        include_reset    = data.get("include_reset", True),
        add_clock        = data.get("add_clock", True),
    )


# -----------------------------
# CLI (simple argv style)
# -----------------------------

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 router_generator.py <router.config> [outdir]")
        sys.exit(1)

    config_path = sys.argv[1]
    outdir = sys.argv[2] if len(sys.argv) >= 3 else "./output"

    cfg = load_config(config_path)

    outdir_path = Path(outdir)
    outdir_path.mkdir(parents=True, exist_ok=True)

    # Generate SV + write selmap JSON
    sv  = generate_router_sv_and_selmap(cfg, outdir_path)

    # Write SV
    out_path = outdir_path / f"{cfg.module_name}.sv"
    out_path.write_text(sv)

    print(f"[INFO] Router generated: {out_path}")
    print(f"[INFO] Select map written: {outdir_path / (cfg.module_name + '_selmap.json')}")
