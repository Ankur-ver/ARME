# Verification Plan

## 1. Two-Tier Verification Architecture

1. **Tier 1 — Open-Source Self-Checking SystemVerilog (`tests/`):**
   - `tests/tb_async_fifo.sv`: Directed & randomized CDC stress testbench for `async_fifo`.
   - `tests/tb_top.sv`: Full-subsystem self-checking testbench with independent reference scoreboard, latency/throughput measurement, protocol stability monitors, and CSV trace export.
   - Executed locally via **Icarus Verilog 13.0** (`iverilog`/`vvp`) and linted via **Verilator 5.050** (`--lint-only -Wall`).
2. **Tier 2 — UVM 1.2 + SVA + Functional Coverage (`tb/uvm/` & `tb/assertions/`):**
   - Reusable UVM agents (`source_agent`, `destination_agent`), `virtual_sequencer`, independent `rate_reference_model`, `rate_scoreboard`, `rate_coverage`, and 15 UVM test classes.
   - Bound SVA module `rate_engine_sva` (`tb/assertions/assertions.sv`).
   - Targets IEEE 1800.2 UVM-capable simulators (Questa / VCS / Xcelium).

## 2. Test Scenarios & Matrix

| Test Name | Target Verification Goal |
|---|---|
| `smoke_test` | Basic packet flow across 100/80 MHz clocks |
| `basic_transfer_test` | Single-beat (`sop && eop`) and variable-length packets |
| `burst_test` | Short bursts, long bursts (up to 600+ beats), idle gaps |
| `backpressure_test` | Randomized `N`-on/`M`-off `dst_ready` + `dst_valid` stability |
| `source_faster_test` | 100 MHz -> 80 MHz sustained mismatch |
| `destination_faster_test` | 80 MHz -> 100 MHz fast drain |
| `equal_rate_test` | 100 MHz -> 100 MHz phase-offset CDC |
| `extreme_rate_mismatch_test` | 150 MHz -> 75 MHz (2:1) and 125 MHz -> 83 MHz (non-integer) |
| `fifo_boundary_test` | Fill to watermarks and depth boundary, drain to empty |
| `congestion_test` | Full hysteresis cycle: `NORMAL -> THROTTLE -> CONGESTION -> RECOVERY -> NORMAL` |
| `starvation_test` | Slow producer / fast consumer -> `CTRL_STARVATION_WARNING` |
| `reset_test` | Independent `src_rst_n` and `dst_rst_n` assertions & recovery |
| `reset_during_packet_test` | Mid-packet reset assertion & clean post-reset restart |
| `error_injection_test` | Malformed SOP/EOP sequence -> `packet_error` assertion & `clr_errors` |
| `random_stress_test` | Thousands of randomized beats across hundreds of packets |
