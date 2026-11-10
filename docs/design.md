# Detailed RTL Design Specification

## 1. Subsystem Overview

The **Adaptive Rate-Matching Engine** (`rtl/top.sv`) bridges two independent clock domains (`src_clk` and `dst_clk`) over a valid/ready packetized streaming interface without manipulating physical clock frequencies.

### Submodules
- **`rate_engine_pkg.sv`**: Defines `ctrl_state_e`, `rate_status_t`, and default subsystem parameters.
- **`reset_controller.sv`**: Coordinated async-assert, sync-deassert reset synchronizers and cross-domain release handshaking (`reset_busy_src`, `reset_busy_dst`).
- **`packet_controller.sv`**: Source-domain SOP/EOP protocol checker, active-packet tracker, packet counter, and sticky `packet_error` flag.
- **`stream_adapter.sv`**:
  - **Ingress (`src_clk`)**: Packs `{packet_start, packet_end, keep, data}` into a single `PAYLOAD_WIDTH = DATA_WIDTH + KEEP_WIDTH + 2` FIFO word; drives `src_ready` without combinational dependence on `src_valid`.
  - **Egress (`dst_clk`)**: 2-entry registered prefetch/skid buffer compensating for `async_fifo`'s 1-cycle synchronous read latency to sustain 1 beat/cycle throughput while holding `dst_*` outputs stable during `dst_valid && !dst_ready`.
- **`async_fifo.sv`**: Dual-clock Gray-coded asynchronous FIFO with `SYNC_STAGES` pointer synchronizers, Cummings full/empty detection, overflow/underflow guards, and local conservative occupancy outputs.
- **`fifo_monitor.sv`**: Tracks `almost_full`, `almost_empty`, watermark hits, `max_occupancy`, `min_occupancy`, and `overflow_count` / `underflow_count`.
- **`rate_controller.sv`**: 5-state hysteresis FSM (`CTRL_NORMAL`, `CTRL_STARVATION_WARNING`, `CTRL_THROTTLE`, `CTRL_CONGESTION`, `CTRL_RECOVERY`) plus `adapt_mode` selector (`0=bypass`, `1=fixed_threshold`, `2=hysteresis`).

## 2. Synthesis & Lint Verification

### RTL Linting (`verilator --lint-only -Wall`)
- Tool: Verilator `5.050`
- Result: **0 warnings, 0 errors** across all 9 RTL modules (`top`, `reset_controller`, `packet_controller`, `stream_adapter`, `async_fifo`, `fifo_monitor`, `rate_controller`, and `rate_engine_pkg`).
- Note: An initial `SYNCASYNCNET` warning in `reset_controller.sv` was resolved structurally (without lint waivers) by separating the synchronous reset-release observation flop (`src_rst_done`/`dst_rst_done`) and separating the shift chain from the async-reset driver flop (`src_rst_sync_q`/`dst_rst_sync_q`).

### Synthesis (`yosys 0.66`, `synthesis/synth_yosys.ys`)
- **Full-scale elaboration (`FIFO_DEPTH = 1024`, `DATA_WIDTH = 64`, memory-inferred):**
  - Inferred dual-port memory: **1 `$mem_v2` block (`1024 x 74 = 75,776` bits)**
  - Coarse RTL cells across subsystem: **246 cells** (`50 $adff`, `68 $mux`, `5 $pmux`, `11 $add`, `4 $sub`, `15 $eq`, `1 $ne`, `3 $ge`, `4 $gt`, `5 $le`, `4 $lt`, `1 $mem_v2`, plus boolean logic)
- **Gate-mapped control + storage check (`FIFO_DEPTH = 16`, generic ABC cells):**
  - Total gate cells: **4,353** (`async_fifo`: 3,099, `stream_adapter`: 407, `fifo_monitor`: 404, `rate_controller`: 228, `packet_controller`: 202, `reset_controller`: 13)
  - Note: Yosys generic mapping does not run ASIC standard-cell timing closure; critical path and $F_{\max}$ depend on target PDK/SRAM macro timing and are intentionally not fabricated here.
