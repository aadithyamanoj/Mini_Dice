# Mini-DICE Chip-Level UVM Verification

UVM environment for the Mini-DICE chip. Runs the same test set against two
DUT configurations:

- **FAST mode** — `tb_top.sv` instantiates `mini_dice_top` directly. The
  DUT still includes the compute core (`dice_core`), the IO link
  (`cgra_io_axi4_top`: axi_link_tx/rx + AXI crossbar), and the CSR slave
  (`cgra_io_csr`). What is skipped is the off-chip layer: the bsg_link DDR
  serializer and the pad ring. The TB drives flits directly on the
  AXI-link wires.
- **CHIP mode** — `tb_chip.sv` wraps the pad ring and bsg_link DDR around
  `chip_top` (which in turn wraps `mini_dice_top`). Traffic goes through
  the full off-chip stack — async crossings, DDR (de)serialization, and
  the bsg_link bringup sequence — before reaching the same internal logic
  exercised by FAST mode.

Both DUTs share the same `chip_env`, sequences, scoreboard, mem_responder,
and tests; only the top-level testbench differs.

## Layout

```
verification/
  tb_top.sv               FAST top (mini_dice_top instantiated directly)
  tb_chip.sv              CHIP top (chip_top + pad ring + bsg_link DDR)
  mini_dice_chip_pkg.sv   UVM env, agents, sequences, scoreboard, mem_responder
  mini_dice_chip_vif.sv   Interface used by the agents
  chip_stubs.sv           Stub shims for chip-mode-only signals
  filelist.f              FAST-mode source list
  filelist_chip.f         CHIP-mode source list (adds pad ring, bsg_link)
  tests/                  All UVM tests (one .sv per test class)
```

## Kernels

Active dora-compiled test vectors under `tb/test_vectors/`:

| Kernel | Eblocks | CTAs | ALU ops | Notes |
|---|---|---|---|---|
| `full_mul_array` | 5  | 1 | MUL          | canonical smoke kernel |
| `simple_branching` | 7 | 1 | MUL + ADD    | SIMT divergence: tid 0 takes ADD path, others MUL |
| `gemm`           | 14 | 4 | MUL, MAC     | multi-pass matmul with accumulation across k0..k3 |
| `nn_cuda`        | 5  | 4 | MUL, distsq  | classic CUDA k-nearest-neighbor benchmark |

The chip has a single CTA slot. `gemm` and `nn_cuda` have grids of 4
CTAs that the TB pushes through that slot sequentially via the
`run_grid` path (per-CTA CSR overrides + REG_STATUS[0] sticky-complete
polling between dispatches). `full_mul_array` and `simple_branching`
are single-CTA grids and use the legacy program-and-launch path. Both
flows live in `mini_dice_chip_base_test` and the appropriate one is
picked automatically based on `num_ctas` parsed from runtime.json.

## Build

VCS commands assume you are in `tb/mini_dice/verification/`.

DPI runtime: `../../cgra_core/dice_core/dpi_dice_core_runtime.cpp`

The DPI lives under `tb/cgra_core/`. It loads the
kernel `.mem` files (cta_desc / metadata / bitstream), parses the runtime
JSON to build the expected-store list, and exposes
`dice_core_tb_init` / `dice_core_tb_get_csr` /
`dice_core_tb_num_ctas` / `dice_core_tb_get_per_cta_csr` /
`dice_core_tb_check_done` to SystemVerilog. The chip-level UVM env reuses
it unchanged.

FAST mode binary (`./simv`):

```
vcs -sverilog -full64 -timescale=1ns/1ps -ntb_opts uvm \
    -f filelist.f -top tb_top +error+50 \
    ../../cgra_core/dice_core/dpi_dice_core_runtime.cpp -l c.log
```

CHIP mode binary (`../simv_chip`):

```
vcs -sverilog -full64 -timescale=1ns/1ps -ntb_opts uvm \
    -f filelist_chip.f -top tb_chip +error+50 -o ../simv_chip \
    ../../cgra_core/dice_core/dpi_dice_core_runtime.cpp -l c_chip.log
```

Coverage build adds:

```
-cm line+cond+fsm+tgl+assert+branch -cm_name cov
```

## Run

Each test file has a `Run (fast):` / `Run (chip):` line in its header.
The general form is:

```
# FAST
cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=<test_class>

# CHIP
cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=<test_class>
```

Common plusargs:

- `+ntb_random_seed=<N>` — seed for randomized tests
- `+UVM_VERBOSITY=UVM_LOW|UVM_NONE` — log verbosity
- `+SETTLE=<cycles>` — override the per-test settle window
- `+ITERS=<N>` — endurance iteration count
- `+RD_DELAY=<N>` — mem_responder read response delay
- `+TEST_VECTOR=<name>` — override the default test vector name
- `+TEST_VECTOR_DIR=<path>` — override the vector directory
- `-l <file>` — VCS log file

## Tests

All tests extend `mini_dice_chip_base_test`, which provides `load_collateral`,
`program_and_launch` (single-shot), `run_grid` (sequential per-CTA dispatch
through the single slot), and `finalize_grid_check` (DPI diff). The
default `run_phase` dispatches the right flow based on `num_ctas`.

### Single-CTA smoke / canonical
- `mini_dice_chip_full_mul_array_test` — canonical 5-eblock MUL kernel, 64 stores.
- `mini_dice_chip_simple_branching_test` — 7-eblock divergent kernel.
- `mini_dice_chip_csr_smoke_test` — CSR-only writes, no CTA launch.
- `mini_dice_chip_csr_readback_test` — write + read each of 8 CSRs through the link.

### Multi-CTA dora kernels (4 CTAs each)
- `mini_dice_chip_gemm_smoke_test` — 14-eblock gemm; full DPI diff verification.
- `mini_dice_chip_nn_cuda_smoke_test` — 5-eblock nearest-neighbor; full DPI diff verification.

### Multi-CTA stress combinations
- `mini_dice_chip_gemm_axil_error_test` — gemm + SLVERR on CTA 0's A-load (no-deadlock check).
- `mini_dice_chip_gemm_fetch_latency_test` — gemm under elevated `response_delay_cyc` (default 32).
- `mini_dice_chip_gemm_endurance_test` — N back-to-back gemm grids (default 10).
- `mini_dice_chip_gemm_cgra_reset_test` — pulse `CTRL.CGRA_RESET` between CTA 1 and CTA 2.
- `mini_dice_chip_nn_cuda_axil_error_test` — nn_cuda + SLVERR on CTA 0's load.
- `mini_dice_chip_nn_cuda_fetch_latency_test` — nn_cuda under elevated `response_delay_cyc` (default 32).

### Single-CTA dispatcher / scheduler
- `mini_dice_chip_partial_thread_test` — thread_count = 9 (non-power-of-two).
- `mini_dice_chip_port_contention_test` — all 4 mem ports collide on same address.
- `mini_dice_chip_sequential_cta_random_test` — two `full_mul_array` dispatches with independent random CSRs / data (the only test exercising slot reuse under randomized stimulus).
- `mini_dice_chip_endurance_test` — N back-to-back `full_mul_array` launches (default 50).

### Error injection
- `mini_dice_chip_axil_error_test` — SLVERR on one A-load address.
- `mini_dice_chip_decerr_test` — DECERR on one A-load address.
- `mini_dice_chip_multi_error_test` — SLVERR on all 4 A-loads of tid 0.
- `mini_dice_chip_branch_axil_error_test` — SLVERR composed with `simple_branching`.
- `mini_dice_chip_meta_error_test` — SLVERR on eblock-0 metadata fetch burst.
- `mini_dice_chip_bs_error_test` — SLVERR on eblock-0 bitstream fetch burst.

### Reset
- `mini_dice_chip_cgra_reset_test` — pulses `CTRL.CGRA_RESET`, then launches.
- `mini_dice_chip_mid_reset_test` — asserts reset mid-kernel and re-launches. FAST uses the vif `force_rst_*` hooks; CHIP pulses `vif.force_bringup`, which triggers `tb_chip.bsg_link_bringup()` to re-handshake both sides of the link.

### Performance / latency
- `mini_dice_chip_fetch_latency_test` — `response_delay_cyc = 32`.
- `mini_dice_chip_link_backpressure_test` — `response_delay_cyc = 64`.
- `mini_dice_chip_random_seed_test` — randomized delay + settle.

### Random / coverage
- `mini_dice_chip_mul_random_data_test` — randomized A/B for `full_mul_array`.
- `mini_dice_chip_random_regression_test` — random tcount / err / lat with `cg_random`.
- `mini_dice_chip_random_dag_test` — random tcount / CSRs / data / err / lat on `full_mul_array`, with `cg_dag` covergroup.

## Pass status

**All 30 tests pass cleanly in both FAST and CHIP modes**
