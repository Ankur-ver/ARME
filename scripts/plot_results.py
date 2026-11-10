#!/usr/bin/env python3
"""
Generates performance plots from real RTL simulation CSV outputs in results/.
"""

import csv
import os
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def read_csv(path: Path) -> list:
    with path.open("r", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    res_dir = repo_root / "results"
    os.chdir(repo_root)

    # 1. FIFO Occupancy vs Time (Experiment C trace)
    trace_rows = read_csv(res_dir / "exp_c_trace.csv")
    times_us = [float(r["time_ns"]) / 1000.0 for r in trace_rows]
    occs = [int(r["occupancy"]) for r in trace_rows]
    states = [int(r["state"]) for r in trace_rows]

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 6), sharex=True, gridspec_kw={"height_ratios": [3, 1]})
    ax1.plot(times_us, occs, linewidth=1.2, label="Synchronized Source Occupancy")
    ax1.axhline(768, color="orange", linestyle="--", linewidth=1, label="HIGH_WATERMARK (768)")
    ax1.axhline(928, color="red", linestyle="--", linewidth=1, label="CRIT_HIGH_WATERMARK (928)")
    ax1.axhline(512, color="green", linestyle=":", linewidth=1, label="RECOVERY_WATERMARK (512)")
    ax1.set_ylabel("FIFO Occupancy (beats)")
    ax1.set_title("FIFO Occupancy & Controller State vs Time (125->80 MHz, Backpressure 8-on/30-off)")
    ax1.legend(loc="upper right", fontsize=8)
    ax1.grid(True, alpha=0.3)

    ax2.step(times_us, states, where="post", color="purple", linewidth=1.2)
    ax2.set_yticks([0, 1, 2, 3, 4])
    ax2.set_yticklabels(["NORMAL", "STARVE", "THROT", "CONG", "RECOV"], fontsize=8)
    ax2.set_xlabel("Simulation Time (us)")
    ax2.set_ylabel("FSM State")
    ax2.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(res_dir / "fifo_occupancy_vs_time.png", dpi=150)
    plt.close()

    # 2. Throughput vs Clock Ratio (Experiments A & B)
    exp_a = read_csv(res_dir / "exp_a_src_rate.csv")
    exp_b = read_csv(res_dir / "exp_b_dst_rate.csv")

    ratios_a = [float(r["src_mhz"]) / float(r["dst_mhz"]) for r in exp_a]
    tput_a = [float(r["tput_mbps"]) / 1000.0 for r in exp_a]
    ratios_b = [float(r["src_mhz"]) / float(r["dst_mhz"]) for r in exp_b]
    tput_b = [float(r["tput_mbps"]) / 1000.0 for r in exp_b]

    plt.figure(figsize=(8, 4.8))
    plt.plot(ratios_a, tput_a, "o-", label="Exp A: Sweep Src Rate (Dst=80 MHz)")
    plt.plot(ratios_b, tput_b, "s--", label="Exp B: Sweep Dst Rate (Src=125 MHz)")
    plt.xlabel("Clock Ratio (src_clk / dst_clk)")
    plt.ylabel("Sustained Egress Throughput (Gbps)")
    plt.title("Measured Throughput vs Clock-Rate Ratio")
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.tight_layout()
    plt.savefig(res_dir / "throughput_vs_clock_ratio.png", dpi=150)
    plt.close()

    # 3. Latency vs Congestion / Backpressure (Experiment C)
    exp_c = read_csv(res_dir / "exp_c_backpressure.csv")
    bp_offs = [int(r["bp_off"]) for r in exp_c]
    avg_lats = [float(r["avg_lat_ns"]) / 1000.0 for r in exp_c]
    max_lats = [float(r["max_lat_ns"]) / 1000.0 for r in exp_c]

    plt.figure(figsize=(8, 4.8))
    plt.plot(bp_offs, avg_lats, "o-", label="Average Latency (us)")
    plt.plot(bp_offs, max_lats, "s--", label="Max Latency (us)")
    plt.xlabel("Destination Stall Window (dst_clk cycles per 8 ready cycles)")
    plt.ylabel("End-to-End Beat Latency (us)")
    plt.title("Latency vs Destination Backpressure Intensity")
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.tight_layout()
    plt.savefig(res_dir / "latency_vs_congestion.png", dpi=150)
    plt.close()

    # 4. Adaptation Mode Comparison (Experiment D)
    exp_d = read_csv(res_dir / "exp_d_modes.csv")
    modes = [r["mode_name"] for r in exp_d]
    mode_lat = [float(r["avg_lat_ns"]) / 1000.0 for r in exp_d]
    mode_occ = [int(r["max_occ"]) for r in exp_d]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(10, 4.2))
    ax1.bar(modes, mode_occ, color=["#d9534f", "#f0ad4e", "#5cb85c"])
    ax1.set_title("Peak FIFO Occupancy by Mode")
    ax1.set_ylabel("Peak Occupancy (beats)")
    ax1.tick_params(axis="x", rotation=15)

    ax2.bar(modes, mode_lat, color=["#d9534f", "#f0ad4e", "#5cb85c"])
    ax2.set_title("Average Latency by Mode")
    ax2.set_ylabel("Average Latency (us)")
    ax2.tick_params(axis="x", rotation=15)
    plt.tight_layout()
    plt.savefig(res_dir / "adaptation_mode_comparison.png", dpi=150)
    plt.close()

    # 5. FIFO Depth Scaling (Experiment E)
    exp_e = read_csv(res_dir / "exp_e_depths.csv")
    depths = [int(r["fifo_depth"]) for r in exp_e]
    e_tput = [float(r["tput_mbps"]) / 1000.0 for r in exp_e]
    e_lat = [float(r["avg_lat_ns"]) / 1000.0 for r in exp_e]

    fig, ax1 = plt.subplots(figsize=(8, 4.8))
    ax2 = ax1.twinx()
    ax1.plot(depths, e_tput, "o-", color="tab:blue", label="Throughput (Gbps)")
    ax2.plot(depths, e_lat, "s--", color="tab:red", label="Avg Latency (us)")
    ax1.set_xlabel("FIFO Depth (beats)")
    ax1.set_ylabel("Throughput (Gbps)", color="tab:blue")
    ax2.set_ylabel("Average Latency (us)", color="tab:red")
    ax1.set_title("Throughput & Latency vs FIFO Depth (125->80 MHz, Backpressure 8/12)")
    ax1.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(res_dir / "depth_scaling_analysis.png", dpi=150)
    plt.close()

    print("Generated 5 real-data PNG plots under results/.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

