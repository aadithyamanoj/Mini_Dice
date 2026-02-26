#!/usr/bin/env python3
import json
from copy import deepcopy

# ================================================================
# Default building blocks
# ================================================================

def make_default_2_1_router():
    """Generate default dice_2_1_router block."""
    router = {}
    ports = ["N", "E", "S", "W", "L"]
    tracks = {"N": 2, "E": 2, "S": 2, "W": 2, "L": 3}
    for p in ports:
        for t in range(tracks[p]):
            router[f"sel_{p}_t{t}"] = [""]
            router[f"registered_mode_{p}_t{t}"] = [0]
    return router


def make_default_2_32_router():
    """Generate default dice_2_32_router block with overload signals."""
    router = {}
    ports = ["N", "E", "S", "W"]
    tracks = 2
    for p in ports:
        for t in range(tracks):
            router[f"sel_{p}_t{t}"] = [""]
            router[f"registered_mode_{p}_t{t}"] = [0]
            router[f"overload_en_{p}_t{t}"] = [0]
    for t in range(4):  # L has 4 tracks
        router[f"sel_L_t{t}"] = [""]
        router[f"registered_mode_L_t{t}"] = [0]
    return router


def make_default_pe():
    """Generate default dice_pe block."""
    return {
        "opcode": [""],
        "out_sel": [0],
    }

# ================================================================
# Top-level CGRA config generator
# ================================================================

def generate_cgra_config(num_tiles=16):
    """Generate full default config for CGRA with `num_tiles` tiles."""
    config = {}

    for tile_id in range(num_tiles):
        tile_name = f"dice_tile_{tile_id}"
        config[tile_name] = [
            {"dice_2_1_router": [make_default_2_1_router()]},
            {"dice_2_32_router": [make_default_2_32_router()]},
            {"dice_pe": [make_default_pe()]},
        ]

    return config

# ================================================================
# Example custom modifications
# ================================================================

def apply_custom_modifications(config):
    """
    Example: show how to modify specific tiles easily.
    You can write your own loops or conditionals here.
    """

    # Example 1: Set tile 0’s 2_32 router E_t0 = "W[0]" and S_t1 = "N[1]"
    # t0_r2 = config["dice_tile_0"][1]["dice_2_32_router"][0]
    # t0_r2["sel_E_t0"] = ["W[0]"]
    # t0_r2["registered_mode_E_t0"] = [1]
    # t0_r2["sel_S_t1"] = ["N[1]"]
    # t0_r2["registered_mode_S_t1"] = [1]

    # Example 2: Assign tile 0’s PE opcode to MAD_U32
    # assign all tiles PE opcode to MAD_U32 and register output
    for tile in config.values():
        tile[2]["dice_pe"][0]["opcode"] = ["MAD_U32"]
        tile[2]["dice_pe"][0]["out_sel"] = [1]

    # Example 3: Make tile_1’s all routers use N[0]
    # for block in config["dice_tile_1"]:
    #     if "dice_2_1_router" in block:
    #         for key in block["dice_2_1_router"][0].keys():
    #             if key.startswith("sel_") and key.endswith(tuple("t0t1t2")):
    #                 block["dice_2_1_router"][0][key] = ["N[0]"]
    
    # predicate router configuration for systolic array
    tile_index = 0
    for tile in config.values():
        tile[0]["dice_2_1_router"][0]["sel_S_t0"] = ["N[0]"]
        tile[0]["dice_2_1_router"][0]["registered_mode_S_t0"] = [1]
        tile[0]["dice_2_1_router"][0]["sel_L_t1"] = ["N[0]"] #t1 is dff_latench_enable
        tile[0]["dice_2_1_router"][0]["sel_L_t2"] = ["N[0]"] #override signal for output latch
        if(tile_index % 4 == 0):
            tile[0]["dice_2_1_router"][0]["sel_S_t1"] = ["N[1]"]
            tile[0]["dice_2_1_router"][0]["registered_mode_S_t1"] = [1]
            tile[0]["dice_2_1_router"][0]["sel_E_t0"] = ["N[1]"]
            tile[0]["dice_2_1_router"][0]["registered_mode_E_t0"] = [1]
            tile[0]["dice_2_1_router"][0]["sel_W_t1"] = ["W[1]"]
            tile[0]["dice_2_1_router"][0]["registered_mode_W_t1"] = [1]
            tile[0]["dice_2_1_router"][0]["sel_L_t0"] = ["N[1]"] # t0 is dff_input_mode, goes diagnally
            tile[0]["dice_2_1_router"][0]["registered_mode_L_t0"] = [0]
        else:
            tile[0]["dice_2_1_router"][0]["sel_E_t0"] = ["W[0]"]
            tile[0]["dice_2_1_router"][0]["registered_mode_E_t0"] = [1]
            tile[0]["dice_2_1_router"][0]["sel_L_t0"] = ["W[0]"]
            tile[0]["dice_2_1_router"][0]["registered_mode_L_t0"] = [0]
        tile_index += 1

    # data router configuration for systolic array
    tile_index = 0
    for tile in config.values():
        # B input from north to south
        tile[1]["dice_2_32_router"][0]["sel_S_t0"] = ["N[0]"]
        tile[1]["dice_2_32_router"][0]["registered_mode_S_t0"] = [1]
        # A input from west to east
        tile[1]["dice_2_32_router"][0]["sel_E_t0"] = ["W[0]"]
        tile[1]["dice_2_32_router"][0]["registered_mode_E_t0"] = [1]
        # Local
        tile[1]["dice_2_32_router"][0]["sel_W_t1"] = ["E[1]"] # result to west
        tile[1]["dice_2_32_router"][0]["sel_L_t0"] = ["W[0]"] # A input from west
        tile[1]["dice_2_32_router"][0]["registered_mode_L_t0"] = [0]
        tile[1]["dice_2_32_router"][0]["sel_L_t1"] = ["N[0]"] # B input from north
        tile[1]["dice_2_32_router"][0]["registered_mode_L_t1"] = [0]
        tile[1]["dice_2_32_router"][0]["sel_L_t2"] = ["L[1]"] # C input from local
        tile[1]["dice_2_32_router"][0]["registered_mode_L_t2"] = [0]
        tile[1]["dice_2_32_router"][0]["sel_L_t3"] = ["E[1]"] # C/dff-in input from east
        tile[1]["dice_2_32_router"][0]["registered_mode_L_t3"] = [0]
        # D output to west/ C flow to west
        tile[1]["dice_2_32_router"][0]["sel_W_t1"] = ["E[1]"] # dff-out to west
        tile[1]["dice_2_32_router"][0]["registered_mode_W_t1"] = [1]
        tile[1]["dice_2_32_router"][0]["overload_en_W_t1"] = [1]

        tile_index += 1
    return config

# ================================================================
# Main entry point
# ================================================================

if __name__ == "__main__":
    cfg = generate_cgra_config(num_tiles=16)
    cfg = apply_custom_modifications(cfg)

    out_file = "cgra_systolic_config.json"
    with open(out_file, "w") as f:
        json.dump(cfg, f, indent=2)
    print(f"[OK] Generated {out_file} with {len(cfg)} tiles.")
# ================================================================