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
  cov_report/             urg merged-coverage output (see Coverage below)
```

## Build

VCS commands assume you are in `tb/mini_dice/verification/`.

DPI runtime: `../../cgra_core/dice_core/dpi_dice_core_runtime.cpp`

The DPI lives under `tb/cgra_core/` because it was originally authored for
the dora team's standalone `dice_core` unit-level testbench. It loads the
kernel `.mem` files (cta_desc / metadata / bitstream), parses the runtime
JSON to build the expected-store list, and exposes
`dice_core_tb_init` / `dice_core_tb_get_csr` / `dice_core_tb_check_done`
to SystemVerilog. The chip-level UVM env reuses it unchanged — the
load-and-diff logic is identical whether the DUT is the bare core, the
core inside `mini_dice_top`, or the core inside `chip_top` + pad ring.

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

Stress binaries (add `+define+SKIP_AXI_DEMUX_ASSERTS`, needed for
`mini_dice_chip_oor_empirical_test`):

```
# FAST stress  -> ../simv_stress
vcs ... +define+SKIP_AXI_DEMUX_ASSERTS -f filelist.f -top tb_top \
    -o ../simv_stress ... -l c_stress.log

# CHIP stress  -> ../simv_chip_stress
vcs ... +define+SKIP_AXI_DEMUX_ASSERTS -f filelist_chip.f -top tb_chip \
    -o ../simv_chip_stress ... -l c_chip_stress.log
```

Coverage build adds:

```
-cm line+cond+fsm+tgl+assert+branch -cm_name cov
```

## Run

Each test file has a `Run (fast):` / `Run (chip):` line in its header. The
general form is:

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
- `+TEST_VECTOR=<name>` — override the default test vector name
- `+TEST_VECTOR_DIR=<path>` — override the vector directory
- `-l <file>` — VCS log file

## Tests

All tests extend `mini_dice_chip_base_test` (which owns the env and provides
`load_collateral`, `program_and_launch`, `wait_for_complete`).

### Smoke / canonical
- `mini_dice_chip_full_mul_array_test` — canonical 5-eblock MUL kernel, 64 stores.
- `mini_dice_chip_add_array_test` — same shape but with ADD ALU op.
- `mini_dice_chip_simple_branching_test` — 7-eblock divergent kernel (tid 0 ADD path, others MUL).
- `mini_dice_chip_csr_smoke_test` — CSR-only writes, no CTA launch.
- `mini_dice_chip_csr_readback_test` — write+read each of 8 CSRs through the link.

### Dispatcher / scheduler
- `mini_dice_chip_partial_thread_test` — thread_count=9 (non-power-of-two).
- `mini_dice_chip_port_contention_test` — all 4 mem ports collide on same address.
- `mini_dice_chip_sequential_cta_test` — two dispatches through the single CTA slot. *(slot reuse only; no kernel switch)*
- `mini_dice_chip_sequential_cta_random_test` — two CTAs with independent random configs. *(mixed-op pairs bail after CTA0)*
- `mini_dice_chip_endurance_test` — N back-to-back full_mul_array launches (default 50).

### Error injection
- `mini_dice_chip_axil_error_test` — SLVERR on one A-load address.
- `mini_dice_chip_decerr_test` — DECERR on one A-load address.
- `mini_dice_chip_multi_error_test` — SLVERR on all 4 A-loads of tid 0.
- `mini_dice_chip_branch_axil_error_test` — SLVERR composed with simple_branching.
- `mini_dice_chip_meta_error_test` — SLVERR on eblock-0 metadata fetch burst.
- `mini_dice_chip_bs_error_test` — SLVERR on eblock-0 bitstream fetch burst.

### Reset
- `mini_dice_chip_cgra_reset_test` — pulses CTRL.CGRA_RESET, then launches.
- `mini_dice_chip_mid_reset_test` — asserts reset mid-kernel (FAST only; CHIP skips). *(CHIP-mode reset logic not yet figured out)*

### Performance / latency
- `mini_dice_chip_fetch_latency_test` — `response_delay_cyc = 32`.
- `mini_dice_chip_link_backpressure_test` — `response_delay_cyc = 64`.
- `mini_dice_chip_random_seed_test` — randomized delay + settle.

### Random / coverage
- `mini_dice_chip_mul_random_data_test` — randomized A/B for full_mul_array.
- `mini_dice_chip_random_regression_test` — random tcount/err/lat with `cg_random`.
- `mini_dice_chip_random_dag_test` — random kernel/tcount/CSRs/data/err/lat with `cg_dag`.

### Boundaries / placeholders
- `mini_dice_chip_eblock8_test` — documents the 3-bit e_block_id limit (8 eblocks max). *(placeholder; 8-eblock kernel not actually run)*
- `mini_dice_chip_out_of_range_test` — placeholder; points at oor_empirical. *(passes but doesn't exercise anything)*
- `mini_dice_chip_oor_empirical_test` — empirical OOR write diagnostic (see below). *(fails by design; diagnostic only)*

## Tests that do NOT pass cleanly

| Test                                | Status                                                                                       |
|-------------------------------------|----------------------------------------------------------------------------------------------|
| `mini_dice_chip_oor_empirical_test` | Fires UVM_ERROR by design — OOR writes corrupt later CSR reads. Diagnostic, not regression.  |
| `mini_dice_chip_mid_reset_test`     | FAST passes; CHIP logs-and-exits (a real chip-mode mid-reset would trip cnt_underflow).      |
| `mini_dice_chip_eblock8_test`       | Passes trivially. Does not actually run an 8-eblock kernel — blocked on a dora-compiled binary. |
| `mini_dice_chip_out_of_range_test`  | Passes trivially. Placeholder; the real OOR diagnostic is `mini_dice_chip_oor_empirical_test`. |

Per design, the FPGA host driver is required to never issue OOR writes, so
`oor_empirical` documents observed behavior rather than a chip bug.

## Known limitations

- CHIP-mode mid-reset is not exercised (would need the full bsg_link bringup
  replayed inside a UVM task; currently lives in `tb_chip.sv` initial block).
- 8-eblock kernels are not actively run; the boundary is documented only.
- Sequential-CTA tests do not exercise kernel switching between CTAs.
  Both `mini_dice_chip_sequential_cta_test` (same kernel twice) and
  `mini_dice_chip_sequential_cta_random_test` (same-op pairs only)
  cover slot reuse and CTRL.START re-pulsing, but the more interesting
  case, CTA1 using a different bitstream + metadata than CTA0 — is
  blocked on a DPI re-init API that does not exist yet. The DPI
  (`dpi_dice_core_runtime.cpp`) loads one set of `.mem` files at init
  and has no entry point to swap them mid-simulation. (currently working on this)
