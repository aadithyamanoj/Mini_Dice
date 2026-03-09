// Copyright 2020 ETH Zurich and University of Bologna.
//
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Author: Florian Zaruba <zarubaf@iis.ee.ethz.ch>

`ifndef COMMON_CELLS_ASSERTIONS_SVH
`define COMMON_CELLS_ASSERTIONS_SVH
`define ASSERT_STRINGIFY(__x) `"__x`"
`define ASSERT_RPT(__name, __desc)
`define ASSERT_I(__name, __prop, __desc)
`define ASSERT_INIT(__name, __prop, __desc)
`define ASSERT_FINAL(__name, __prop, __desc)
`define ASSERT(__name, __prop, __clk, __rst, __desc)
`define ASSERT_NEVER(__name, __prop, __clk, __rst, __desc)
`define ASSERT_KNOWN(__name, __sig, __clk, __rst, __desc)
`define ASSERT_PULSE(__name, __sig, __clk, __rst, __desc)
`define ASSERT_IF(__name, __prop, __enable, __clk, __rst, __desc)
`define ASSERT_KNOWN_IF(__name, __sig, __enable, __clk, __rst, __desc)
`define ASSERT_STABLE(__name, __valid, __ready, __data, __mask, __clk, __rst, __desc)
`define COVER(__name, __prop, __clk, __rst)
`define ASSUME(__name, __prop, __clk, __rst, __desc)
`define ASSUME_I(__name, __prop, __desc)
`define ASSUME_FPV(__name, __prop, __clk, __rst, __desc)
`define ASSUME_I_FPV(__name, __prop, __desc)
`define COVER_FPV(__name, __prop, __clk, __rst)
`endif

/// A stream interface with custom payload of type `payload_t`.
/// Handshaking rules as defined in the AXI standard.
interface STREAM_DV #(
  /// Custom payload type.
  parameter type payload_t = logic
)(
  /// Interface clock.
  input logic clk_i
);
  payload_t data;
  logic valid;
  logic ready;

  modport In (
    output ready,
    input valid, data
  );

  modport Out (
    output valid, data,
    input ready
  );

  /// Passive modport for scoreboard and monitors.
  modport Passive (
    input valid, ready, data
  );

  // Make sure that the handshake and payload is stable
  `ifndef COMMON_CELLS_ASSERTS_OFF
  `ASSERT(data_unstable, (valid && !ready |=> $stable(data)), clk_i, 1'b0)
  `ASSERT(valid_unstable, (valid && !ready |=> valid), clk_i, 1'b0)
  `endif
endinterface
