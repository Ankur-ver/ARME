# Performance Analysis (Measured RTL Simulation Results)

All metrics below were measured directly from **Icarus Verilog 13.0** RTL simulations of `rtl/top.sv` (`DATA_WIDTH = 64`, `FIFO_DEPTH = 1024` unless swept) via `scripts/analyze_results.py` and plotted via `scripts/plot_results.py`.

---

## Experiment A: Source Clock Sweep (Fixed `dst_clk = 80 MHz`, 1,500 beats)

| `src_clk` (MHz) | `dst_clk` (MHz) | Max Occ (beats) | Avg Latency (ns) | Max Latency (ns) | Egress Throughput (Mbps) | Overflows |
|---:|---:|---:|---:|---:|---:|---:|
| 60.0 | 80.0 | 4 | 68.32 | 73.13 | 3,696.28 | 0 |
| 80.0 | 80.0 | 5 | 63.75 | 63.75 | 4,916.46 | 0 |
| 100.0 | 80.0 | 268 | 1,715.61 | 3,358.75 | 5,064.29 | 0 |
| 125.0 | 80.0 | 515 | 3,257.49 | 6,445.75 | 5,065.63 | 0 |
| 150.0 | 80.0 | 679 | 4,284.28 | 8,503.13 | 5,066.96 | 0 |
| 180.0 | 80.0 | 778 | 5,130.47 | 9,738.01 | 5,066.38 | 0 |

**Observation:** Once `src_clk > dst_clk`, egress saturates at the `80 MHz × 64-bit` ceiling (~5,065 Mbps) while FIFO occupancy climbs cleanly (`268 -> 778`, crossing `HIGH_WATERMARK=768` at 180 MHz) with zero overflows.

---

## Experiment B: Destination Clock Sweep (Fixed `src_clk = 125 MHz`, 1,500 beats)

| `src_clk` (MHz) | `dst_clk` (MHz) | Max Occ (beats) | Avg Latency (ns) | Max Latency (ns) | Egress Throughput (Mbps) | Underflows |
|---:|---:|---:|---:|---:|---:|---:|
| 125.0 | 60.0 | 762 | 6,398.23 | 12,708.90 | 3,800.44 | 0 |
| 125.0 | 80.0 | 515 | 3,257.49 | 6,445.75 | 5,065.63 | 0 |
| 125.0 | 100.0 | 268 | 1,372.74 | 2,687.25 | 6,330.26 | 0 |
| 125.0 | 125.0 | 5 | 41.25 | 41.25 | 7,681.69 | 0 |
| 125.0 | 150.0 | 5 | 36.61 | 39.90 | 7,694.78 | 0 |

**Observation:** Increasing `dst_clk` above `src_clk` collapses queueing latency from `6,398 ns` down to `36.6 ns` (pure CDC + skid pipeline latency) and keeps `max_occ` at 5 beats.

---

## Experiment C: Long Backpressure Sweep (`125 -> 80 MHz`, 1,600 beats, 8-ready / M-stall)

| Stall `bp_off` (cycles) | Max Occ (beats) | Avg Latency (ns) | Max Latency (ns) | Throughput (Mbps) | Overflows |
|---:|---:|---:|---:|---:|---:|
| 0 | 549 | 3,470.00 | 6,871.75 | 5,068.99 | 0 |
| 5 | 867 | 8,441.12 | 12,169.75 | 3,781.91 | 0 |
| 15 | 979 | 14,535.50 | 19,842.75 | 2,860.24 | 0 |
| 30 | 1,024 | 23,130.64 | 31,776.75 | 2,127.18 | 0 |
| 60 | 1,024 | 40,745.35 | 58,540.75 | 1,362.81 | 0 |

See generated plots: `results/fifo_occupancy_vs_time.png` and `results/latency_vs_congestion.png`.

---

## Experiment D: Controller Mode Comparison (`135 -> 75 MHz`, `8-on/10-off` backpressure, 2,000 beats)

| `adapt_mode` | Policy | Max Occ | Avg Latency (ns) | Max Latency (ns) | Throughput (Mbps) | Overflows |
|---:|---|---:|---:|---:|---:|---:|
| 0 | No adaptation (bypass) | 1,024 | 19,967.98 | 31,266.22 | 2,519.87 | 0 |
| 1 | Fixed single threshold (`768`) | 769 | 18,509.56 | 29,178.75 | 2,245.75 | 0 |
| 2 | Adaptive hysteresis FSM | 1,024 | 19,468.94 | 29,451.38 | 2,519.87 | 0 |

**Key Finding:** Fixed-threshold hard cutoff (`mode=1`) suffers a **10.9% throughput penalty** (`2,245.75` vs `2,519.87 Mbps`) due to binary on/off chatter around `768`, whereas the adaptive hysteresis controller (`mode=2`) achieves **full egress-limited throughput (`2,519.87 Mbps`)** while reducing average and peak latency relative to unthrottled bypass.

---

## Experiment E: FIFO Depth Scaling (`125 -> 80 MHz`, `8-on/12-off` backpressure, 1,500 beats)

| `FIFO_DEPTH` | Max Occ | Avg Latency (ns) | Max Latency (ns) | Burst Throughput (Mbps) | Overflows |
|---:|---:|---:|---:|---:|---:|
| 64 | 64 | 1,963.71 | 2,138.25 | 1,991.65 | 0 |
| 128 | 128 | 3,759.12 | 4,238.25 | 2,046.85 | 0 |
| 256 | 256 | 6,778.10 | 8,435.75 | 2,166.98 | 0 |
| 512 | 487 | 10,705.12 | 15,639.25 | 2,424.93 | 0 |
| 1024 | 932 | 11,880.76 | 15,956.75 | 3,148.70 | 0 |

**Observation:** Larger `FIFO_DEPTH` absorbs longer ingress bursts before backpressuring the source, increasing effective burst-window throughput by **+58%** from depth 64 to 1024 at the cost of higher queueing latency and SRAM area.

