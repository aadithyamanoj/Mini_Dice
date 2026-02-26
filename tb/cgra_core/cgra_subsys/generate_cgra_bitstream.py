#!/usr/bin/env python3
import argparse
import json
import os
import re
from collections import defaultdict

PORT_ORDER = ["N", "E", "S", "W", "L"]

def load_json(path):
    with open(path, "r") as f:
        return json.load(f)

def detect_track(tag):
    """
    Extract track suffix (e.g., 't0', 't1', 't2', ...) from a key like 'sel_N_t0'.
    Returns ('N','t0') for that example.
    """
    m = re.match(r".*_(N|E|S|W|L)_(t\d+)$", tag)
    if not m:
        return None, None
    return m.group(1), m.group(2)

def bits_from_int(value, width):
    if value < 0:
        raise ValueError(f"Negative value {value} cannot be encoded in {width} bits")
    b = format(value, f"0{width}b")
    if len(b) > width:
        raise ValueError(f"Value {value} overflows {width} bits")
    return b

def encode_sel_list(sel_list, selmap, outlet_key):
    """
    Encode a list of sources like ["N[0]", "E[1]", ""] into concatenated binary bits.
    Empty string "" means "no connection" and encodes as all-zero bits.
    """
    if outlet_key not in selmap:
        raise KeyError(f"Outlet '{outlet_key}' not found in selmap keys: {list(selmap.keys())[:6]}...")
    sel_bits = selmap[outlet_key]["sel_bits"]
    sources = selmap[outlet_key]["sources"]
    src_to_idx = {s: i for i, s in enumerate(sources)}

    out = []
    for src in sel_list:
        # Allow empty source ("no connect")
        if src == "" or src is None:
            out.append("0" * sel_bits)
            continue
        if src not in src_to_idx:
            raise KeyError(
                f"Source '{src}' not valid for outlet '{outlet_key}'. "
                f"Allowed: {sources + ['(empty)']}"
            )
        out.append(bits_from_int(src_to_idx[src], sel_bits))
    return "".join(out), sel_bits * len(sel_list)

def collect_tracks(block_dict, prefix):
    """
    For a given block ('dice_2_1_router' or 'dice_2_32_router'), collect tracks per port that appear
    among keys like 'sel_N_t0', 'registered_mode_N_t0', 'overload_en_N_t0', etc.
    Returns { port: sorted list of tracks }.
    """
    per_port_tracks = defaultdict(set)
    for k in block_dict.keys():
        if not k.startswith(prefix):
            continue
        # k pattern like 'sel_N_t0' OR 'registered_mode_W_t1' OR 'overload_en_E_t0'
        # We only want to parse names that contain a port and a track.
        # Find port, track:
        port, track = detect_track(k)
        if port and track:
            per_port_tracks[port].add(track)
    # sort tracks by numeric
    sorted_tracks = {}
    for p in per_port_tracks:
        sorted_tracks[p] = sorted(per_port_tracks[p], key=lambda t: int(t[1:]))
    return sorted_tracks

def append_bits(accum_bits, label_breakdown, label, bits):
    accum_bits.append(bits)
    label_breakdown.append((label, len(bits)))
    return accum_bits, label_breakdown

def build_tile_bits(
    tile_obj,
    selmap_2_1,
    selmap_2_32,
    opcode_map,
    expected_tile_bits=156,
    verbose=False,
):
    """
    tile_obj is a list like:
      [
        {"dice_2_1_router":[{...}]},
        {"dice_2_32_router":[{...}]},
        {"dice_pe":[{...}]}
      ]
    """
    bits_out = []
    breakdown = []

    # --- 1) dice_2_1_router ---
    block = next((x.get("dice_2_1_router") for x in tile_obj if "dice_2_1_router" in x), None)
    if block:
        router = block[0]
        # tracks per port present under 'sel_' OR 'registered_mode_' keys
        tracks_per_port = {}
        # We just look at keys starting with these prefixes to discover tracks:
        for prefix in ["sel_", "registered_mode_"]:
            d = collect_tracks(router, prefix)
            for k, v in d.items():
                tracks_per_port.setdefault(k, set()).update(v)
        # determinize tracks order
        for k in list(tracks_per_port.keys()):
            tracks_per_port[k] = sorted(tracks_per_port[k], key=lambda t: int(t[1:]))

        for port in PORT_ORDER:
            if port not in tracks_per_port:
                continue
            for track in tracks_per_port[port]:
                # 1. registered_mode
                reg_key = f"registered_mode_{port}_{track}"
                if reg_key in router:
                    reg_list = router[reg_key]
                    # each item is 1 bit
                    reg_bits = "".join("1" if int(x) else "0" for x in reg_list)
                    bits_out, breakdown = append_bits(bits_out, breakdown, f"2_1:{reg_key}", reg_bits)
                # 2. sel
                sel_key = f"sel_{port}_{track}"
                if sel_key in router:
                    sel_list = router[sel_key]
                    # outlet hint = port with an index (common outlet names in selmap: e.g., "N[0]", "N[1]", ...)
                    # We need an outlet key from the 2_1 selmap for the *track*. For 2_1, outlets are commonly N[0],N[1],E[0],E[1],S[0],S[1],W[0],W[1],L[0]...
                    # Infer outlet name from sel_key's port and from the sel_list length:
                    # If track name (t0/t1) implies outlet index, try both and fallback to the first matching.
                    # Heuristic: prefer outlet names with same port and the smallest index that exists.
                    available_outlets = [k for k in selmap_2_1.keys() if k.startswith(f"{port}[")]
                    # stable by numeric index
                    available_outlets.sort(key=lambda x: int(re.search(r"\[(\d+)\]", x).group(1)))
                    if not available_outlets:
                        raise KeyError(f"No outlets for port '{port}' in 2_1 selmap")
                    outlet_key = available_outlets[0]
                    enc_bits, used = encode_sel_list(sel_list, selmap_2_1, outlet_key)
                    bits_out, breakdown = append_bits(bits_out, breakdown, f"2_1:{sel_key}", enc_bits)

    # --- 2) dice_2_32_router ---
    block = next((x.get("dice_2_32_router") for x in tile_obj if "dice_2_32_router" in x), None)
    if block:
        router = block[0]
        # discover tracks per port from three families
        tracks_per_port = {}
        for prefix in ["overload_en_", "registered_mode_", "sel_"]:
            d = collect_tracks(router, prefix)
            for k, v in d.items():
                tracks_per_port.setdefault(k, set()).update(v)
        for k in list(tracks_per_port.keys()):
            tracks_per_port[k] = sorted(tracks_per_port[k], key=lambda t: int(t[1:]))

        for port in PORT_ORDER:
            if port not in tracks_per_port:
                continue
            for track in tracks_per_port[port]:
                # 1. overload_en
                ov_key = f"overload_en_{port}_{track}"
                if ov_key in router:
                    ov_list = router[ov_key]
                    ov_bits = "".join("1" if int(x) else "0" for x in ov_list)
                    bits_out, breakdown = append_bits(bits_out, breakdown, f"2_32:{ov_key}", ov_bits)
                # 2. registered_mode
                reg_key = f"registered_mode_{port}_{track}"
                if reg_key in router:
                    reg_list = router[reg_key]
                    reg_bits = "".join("1" if int(x) else "0" for x in reg_list)
                    bits_out, breakdown = append_bits(bits_out, breakdown, f"2_32:{reg_key}", reg_bits)
                # 3. sel
                sel_key = f"sel_{port}_{track}"
                if sel_key in router:
                    sel_list = router[sel_key]
                    available_outlets = [k for k in selmap_2_32.keys() if k.startswith(f"{port}[")]
                    available_outlets.sort(key=lambda x: int(re.search(r"\[(\d+)\]", x).group(1)))
                    if not available_outlets:
                        raise KeyError(f"No outlets for port '{port}' in 2_32 selmap")
                    outlet_key = available_outlets[0]
                    enc_bits, used = encode_sel_list(sel_list, selmap_2_32, outlet_key)
                    bits_out, breakdown = append_bits(bits_out, breakdown, f"2_32:{sel_key}", enc_bits)

    # --- 3) dice_pe ---
    block = next((x.get("dice_pe") for x in tile_obj if "dice_pe" in x), None)
    if block:
        pe = block[0]
        # opcode (use first; warn if differ)
        if "opcode" in pe:
            op_list = pe["opcode"]
            if not op_list:
                raise ValueError("dice_pe.opcode list is empty")
            if any(op != op_list[0] for op in op_list):
                print("[WARN] dice_pe.opcode has multiple distinct entries; using the first one.")
            op_name = op_list[0]
            if op_name not in opcode_map:
                raise KeyError(f"Opcode '{op_name}' not found in opcode map")
            op_val = int(opcode_map[op_name])
            bits = bits_from_int(op_val, 32)
            bits_out, breakdown = append_bits(bits_out, breakdown, "pe:opcode", bits)
        else:
            raise KeyError("dice_pe.opcode missing")

        # out_sel (use first; warn if differ)
        if "out_sel" in pe:
            os_list = pe["out_sel"]
            if not os_list:
                raise ValueError("dice_pe.out_sel list is empty")
            if any(int(x) != int(os_list[0]) for x in os_list):
                print("[WARN] dice_pe.out_sel has multiple distinct entries; using the first one.")
            bit = "1" if int(os_list[0]) else "0"
            bits_out, breakdown = append_bits(bits_out, breakdown, "pe:out_sel", bit)
        else:
            raise KeyError("dice_pe.out_sel missing")

    tile_bits = "".join(bits_out)
    if len(tile_bits) != expected_tile_bits:
        # Provide a nice breakdown to help debug mismatches
        print(f"[ERROR] Tile produced {len(tile_bits)} bits, expected {expected_tile_bits}. Breakdown:")
        total = 0
        for label, n in breakdown:
            total += n
            print(f"  - {label:24s}: {n:4d}  (running {total})")
        raise ValueError(f"Bit-length mismatch: got {len(tile_bits)}, expected {expected_tile_bits}")

    return tile_bits

def expand_tiles(config_dict):
    """
    Flattens grouped tiles into a deterministic list of (tile_name, tile_obj) pairs.
    The input example groups like 'dice_tile_0_3', 'dice_tile_4_7', etc.
    We'll sort by the numeric suffix to get consistent order.
    """
    items = []
    for k, v in config_dict.items():
        if not k.startswith("dice_tile_"):
            continue
        # k like dice_tile_0_3
        nums = re.findall(r"\d+", k)
        group_idx = tuple(int(x) for x in nums) if nums else (999999,)
        items.append((group_idx, k, v))
    items.sort()
    # v is a list holding 3 blocks (2_1_router, 2_32_router, pe)
    return [(k, v) for _, k, v in items]

def main():
    ap = argparse.ArgumentParser(description="Generate 16-tile bitstream (.txt) from config + selmaps + opcode map")
    ap.add_argument("config", help="Path to input config JSON")
    ap.add_argument("--selmap2_1", required=True, help="Path to dice_2_1_router_selmap.json")
    ap.add_argument("--selmap2_32", required=True, help="Path to dice_2_32_router_selmap.json")
    ap.add_argument("--opcode_map", required=True, help="Path to dice_alu_opcodes.json")
    ap.add_argument("-o", "--output", default="bitstream.txt", help="Output .txt file")
    ap.add_argument("--tile_bits", type=int, default=156, help="Expected bits per tile (default 156)")
    args = ap.parse_args()

    cfg = load_json(args.config)
    selmap_2_1 = load_json(args.selmap2_1)
    selmap_2_32 = load_json(args.selmap2_32)
    opcode_map = load_json(args.opcode_map)

    tiles = expand_tiles(cfg)
    if not tiles:
        raise ValueError("No tiles found in config JSON (keys like 'dice_tile_0_3', etc.)")

    # Build per-tile
    per_tile_bits = []
    for tile_key, tile_obj in tiles:
        # tile_obj here is a list of dicts (your format)
        tb = build_tile_bits(
            tile_obj,
            selmap_2_1,
            selmap_2_32,
            opcode_map,
            expected_tile_bits=args.tile_bits,
        )
        per_tile_bits.append((tile_key, tb))

    # Write output:
    with open(args.output, "w") as f:
        #for tile_key, tb in per_tile_bits:
        #    f.write(f"{tile_key}: {tb}\n")
        for _, tb in per_tile_bits:
            f.write(f"{tb}\n")
        #f.write("\n# concatenated_all_tiles\n")
        #f.write("".join(tb for _, tb in per_tile_bits))
        f.write("\n")

    print(f"Wrote {len(per_tile_bits)} tiles to {args.output}")
    total_bits = len(per_tile_bits) * args.tile_bits
    print(f"Total bits: {total_bits}")

if __name__ == "__main__":

    main()
