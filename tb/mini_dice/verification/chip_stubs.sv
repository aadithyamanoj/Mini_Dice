// =============================================================================
// chip_stubs.sv — behavioral stubs for TSMC IO pad cells used by chip_top.
//
// The real cells live in the TSMC PDK and aren't redistributable. These stubs
// give correct logical behavior for RTL simulation only:
//   * PDDW1216CDG — bidirectional IO pad with output enable + drive strength
//                   (DS / IE / PE are ignored; signal logic is preserved).
//   * BUFFD0BWP7T — combinational buffer.
//   * PVDD2POC / PVSS2CDG / PVDD1CDG / PVDD2CDG — power/ground supply pads
//                                                 (no logic).
//
// Silicon will use the real cells via tech-library swap; functional sim
// uses these.
// =============================================================================

`timescale 1ns / 1ps

// ----- Bidirectional IO pad ------------------------------------------------
module PDDW1216CDG (
    inout  wire PAD,
    output wire C,
    input  wire I,
    input  wire OEN,  // active-low output enable
    input  wire DS,
    input  wire PE,
    input  wire IE
);
  // Drive PAD when OEN=0; otherwise high-Z (let TB or other driver own it).
  assign PAD = (OEN === 1'b0) ? I : 1'bz;
  // Input receiver always observes the pad regardless of IE (matches the
  // sim-friendly defaults — gate-level netlists will obey IE).
  assign C = PAD;
endmodule

// ----- Combinational buffer -------------------------------------------------
module BUFFD0BWP7T (
    input  wire I,
    output wire Z
);
  assign Z = I;
endmodule

// ----- Power / ground pad stubs --------------------------------------------
// These have a single supply pin in the real library; the stubs just absorb
// the connection. No timing, no logic.
module PVDD2POC (inout wire VDDPST); endmodule
module PVSS2CDG (inout wire VSSPST); endmodule
module PVDD1CDG (inout wire VDD);    endmodule
module PVSS1CDG (inout wire VSS);    endmodule
module PVDD2CDG (inout wire VDDPST); endmodule
