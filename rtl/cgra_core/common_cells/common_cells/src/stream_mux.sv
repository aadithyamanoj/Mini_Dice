// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

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

/// Stream multiplexer: connects the output to one of `N_INP` data streams with valid-ready
/// handshaking.

module stream_mux #(
  parameter type DATA_T = logic,  // Vivado requires a default value for type parameters.
  parameter integer N_INP = 0,    // Synopsys DC requires a default value for value parameters.
  /// Dependent parameters, DO NOT OVERRIDE!
  parameter integer LOG_N_INP = $clog2(N_INP)
) (
  input  DATA_T [N_INP-1:0]     inp_data_i,
  input  logic  [N_INP-1:0]     inp_valid_i,
  output logic  [N_INP-1:0]     inp_ready_o,

  input  logic  [LOG_N_INP-1:0] inp_sel_i,

  output DATA_T                 oup_data_o,
  output logic                  oup_valid_o,
  input  logic                  oup_ready_i
);

  always_comb begin
    inp_ready_o = '0;
    inp_ready_o[inp_sel_i] = oup_ready_i;
  end
  assign oup_data_o   = inp_data_i[inp_sel_i];
  assign oup_valid_o  = inp_valid_i[inp_sel_i];

`ifndef COMMON_CELLS_ASSERTS_OFF
  `ASSERT_INIT(n_inp_0, N_INP >= 1, "The number of inputs must be at least 1!")
`endif

endmodule
