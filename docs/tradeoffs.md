# Architectural Design Tradeoffs

## 1. FIFO Depth vs. Silicon Area & Power
- **In this design:** Default `FIFO_DEPTH = 1024` with `PAYLOAD_WIDTH = 74` bits (`64 data + 8 keep + SOP + EOP`) requires `75,776` storage bits (1 dual-port SRAM macro `$mem_v2` in Yosys).
- **Tradeoff:** Experiment E shows scaling depth from `64` to `1024` raises burst-absorption throughput from `1,991.65 Mbps` to `3,148.70 Mbps` (+58%) under heavy egress stalls, but scales memory footprint 16× and increases pointer/comparator width (`7 -> 11` bits).

## 2. Latency vs. Elastic Buffering
- **In this design:** Under matched/fast-drain clocks (`125 -> 150 MHz`), latency is just `36.6 ns` (2-stage Gray pointer sync + 2-entry egress skid). Under sustained stalls (`bp_off = 60`), queuing inside the 1024-deep buffer grows average latency to `40.75 us`.
- **Tradeoff:** Deep buffering prevents upstream stalls during short microbursts, but increases worst-case head-of-line queueing delay (bufferbloat) when downstream stalls persist.

## 3. Throughput vs. Backpressure
- **In this design:** `stream_adapter` asserts `src_ready = 0` when `fifo_wr_full` or when `rate_controller` duty-cycles `flow_enable`.
- **Tradeoff:** Early throttling preserves buffer headroom for high-priority bursts or downstream jitter, whereas aggressive hard cutoffs starve the pipe when downstream drains rapidly (demonstrated in Experiment D).

## 4. Watermark Threshold Selection
- **In this design:** Defaults are `CRIT_LOW=64`, `LOW=256`, `RECOVERY=512`, `HIGH=768`, `CRIT_HIGH=928`.
- **Tradeoff:** Setting `HIGH_WATERMARK` too low under-utilizes the FIFO; setting `CRIT_HIGH_WATERMARK` too close to `FIFO_DEPTH` leaves insufficient margin to absorb in-flight beats during the 2-cycle `rd_ptr_gray` synchronization delay (`SYNC_STAGES`).

## 5. Hysteresis vs. Responsiveness
- **In this design:** Entering `CTRL_THROTTLE` occurs at `HIGH_WATERMARK (768)`, while exiting down to `CTRL_NORMAL` requires stepping through `CTRL_RECOVERY` down to `RECOVERY_WATERMARK (512)`.
- **Tradeoff:** Hysteresis eliminates binary chatter—Experiment D proved fixed-threshold mode lost **10.9% throughput** (`2,245.75` vs `2,519.87 Mbps`)—at the expense of slightly slower ramp-back to 100% rate after congestion clears.

## 6. Gray-Code Async FIFO vs. Req/Ack Handshake CDC
- **In this design:** Gray-coded `async_fifo` sustains **1 beat/cycle** peak throughput once pipelines fill.
- **Tradeoff:** A 4-phase or 2-phase req/ack handshake CDC uses minimal area (a single holding register instead of SRAM) but caps throughput to 1 transfer every `2 * SYNC_STAGES + 2` cycles (~6–8× slower). Streaming networking datapaths require Gray-coded async FIFOs; handshake CDC is reserved for slow control registers (`clr_toggle_wr` in `fifo_monitor.sv`).

## 7. Fixed-Rate vs. Adaptive Flow Control
- **In this design:** `rate_controller.sv` smoothly steps ingress duty cycle (`100% -> 50% -> 25% -> 75% -> 100%`) using `pace_cnt[1:0]`.
- **Tradeoff:** Fixed-rate divider pacing wastes bandwidth during transient bursts when downstream is fast; occupancy-driven adaptive pacing achieves full `dst_clk` bandwidth when clear while smoothly backing off during saturation.

## 8. Round-Robin vs. Priority Scheduling (Future Multi-Stream Extension)
- **Architectural context:** The current subsystem services a single ingress/egress packet stream. Extending to multi-queue ingress (e.g., QoS traffic classes) introduces the classic scheduler tradeoff:
  - **Strict Priority** minimizes tail latency for control/expedited traffic but risks starvation of lower-priority queues under congestion.
  - **Weighted Round-Robin / Deficit Round-Robin (DRR)** guarantees bounded fairness and starvation freedom across variable-length packets (`packet_start`/`packet_end` boundaries), at the cost of per-queue deficit counters and slightly higher arbitration logic depth.

