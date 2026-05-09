# dice_core UVM verification

UVM test environment for the `dice_core` (cgra-v0 variant). Exercises the
full 5-eblock `mul_array` pipeline end-to-end with bit/word-exact checks on
the bitstream, fetches, and stores.

## Run

`module load vcs/X-2025.06` sets `VCS_HOME`, `PATH`, and `LM_LICENSE_FILE`
in either bash or tcsh. The commands below are program invocations and
work in either shell.

Compile (writes `simv` to the parent dir):

```
vcs -sverilog -full64 -timescale=1ns/1ps -ntb_opts uvm \
    -f filelist.f -top tb_top +error+50 -l compile.log
```

Run a test:

```
./simv +UVM_TESTNAME=<test_name> -l <run.log>
```

Reproducible random:

```
./simv +UVM_TESTNAME=dice_core_mul_random_data_test +ntb_random_seed=42 -l run.log
```

## Tests

| Test | What it verifies |
|---|---|
| `dice_core_full_mul_array_test`   | baseline 4-element multiply (canonical 2..6 inputs); 4 stores + 5 bitstreams |
| `dice_core_multi_cta_test`        | 2 same-single-kernel CTAs; verifies cache-hit corner (1 shared programming) |
| `dice_core_multi_cta_full_test`   | 2 CTAs × 5-eblock pipeline; 8 stores + 10 programmings; cross-CTA isolation |
| `dice_core_fetch_latency_test`    | full pipeline + 8-cycle AXI read latency on both fetch ports |
| `dice_core_mul_edge_data_test`    | multiplier edges: zero, identity, signed -1, overflow (0x8000²) |
| `dice_core_mul_random_data_test`  | `$urandom` A/B; expected = `A[3-k]*B[3-k]` mod 2^16 |
| `dice_core_axil_error_test`       | SLVERR on a load addr; verifies DUT doesn't deadlock |

`dice_core_smoke_test` is the original infra-bring-up; the 7 above replace it for real coverage.

## Scoreboard APIs

Register expectations in `run_body` *before* the dispatch handshake:

```sv
env.sb.expect_store    (addr, data)        // an AXI-Lite write at addr must match data
env.sb.expect_bitstream(words[107])        // an upcoming programming must shift these bits in
env.sb.expect_mfetch   (addr)              // an AR must be issued on mfetch at addr
env.sb.expect_bsfetch  (addr)              // an AR must be issued on bsfetch at addr
env.sb.expect_axil_error(addr)             // tolerate a non-OKAY rresp/bresp at addr
```

The scoreboard counts `expected` vs `seen` and reports any unexpected addresses.


## Coverage status

| Area | Status |
|---|---|
| MUL ALU | end-to-end verified, 5 tests |
| Multiplier edge / overflow / signed | covered |
| Multiplier mid-range bit patterns | covered (random, multiple seeds) |
| 5-eblock pipeline | end-to-end verified |
| Multi-CTA same kernel | covered |
| Multi-CTA different kernels | covered |
| AXI-Lite store correctness | covered |
| Bitstream programming correctness | covered (bit-exact) |
| Fetch addresses | covered |
| Fetch backpressure | covered (8-cycle latency) |
| AXI error response (SLVERR) | covered |
| **ADD / SUB ALU paths** | not covered (no kernel) |
| **Branch / SIMT divergence** | not covered (no kernel) |
| **Multi-thread per CTA (`tcount > 1`)** | not covered (no kernel) |
| AXI-Lite backpressure (LDST FIFO full) | not covered |
| Mid-test reset / reset-during-prog | not covered |
| Long-DAG kernels (10+ eblocks) | not covered |
| ~90% of PEs and most xbar routings | not exercised by current kernels |

## File map

```
tb_top.sv                       DUT instance + vif bridge + hierarchical probes
dice_core_vif.sv                all DUT-facing signals (CTA, mfetch, bsfetch, AXI-Lite, CGRA prog)
dice_core_pkg.sv                package; includes all classes + tests
dice_core_env.sv                wires agents -> scoreboard analysis FIFOs
dice_core_scoreboard.sv         all checkers + expect_* APIs
dice_core_base_test.sv          UVM base class for tests

cta_{driver,monitor,agent,seq_item}.sv    CTA dispatch agent
mem_slave_{driver,monitor,agent}.sv        AXI4 read slave for mfetch/bsfetch
mem_seq_item.sv                            AXI4 fetch txn item
axil_slave_{driver,monitor,agent}.sv       AXI-Lite slave for LDST
axil_seq_item.sv                           AXI-Lite txn item
cgra_prog_monitor.sv                       passive scan-chain observer
cgra_prog_item.sv                          per-bit programming pulse
cgra_bitstream_item.sv                     full epoch's bit array

dice_core_full_mul_array_test.sv           parent test (data hook = setup_thread_inputs_and_expectations)
dice_core_smoke_test.sv                    legacy single-eblock smoke (do NOT extend)
dice_core_*_test.sv                        the 7 working tests
```
