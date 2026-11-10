#!/usr/bin/env python3
"""
Executes controlled RTL simulation experiments A-E via Icarus Verilog and
collects authentic cycle-accurate metrics into CSV files under results/.
"""

import csv
import os
import shutil
import subprocess
import sys
from pathlib import Path

RTL_FILES = [
    "rtl/rate_engine_pkg.sv",
    "rtl/reset_controller.sv",
    "rtl/packet_controller.sv",
    "rtl/stream_adapter.sv",
    "rtl/async_fifo.sv",
    "rtl/fifo_monitor.sv",
    "rtl/rate_controller.sv",
    "rtl/top.sv",
]


def find_tool(name: str) -> str:
    found = shutil.which(name)
    if found:
        return found
    for candidate_dir in [r"C:\msys64\ucrt64\bin", r"C:\msys64\mingw64\bin"]:
        exe = os.path.join(candidate_dir, f"{name}.exe")
        if os.path.exists(exe):
            return exe
    raise FileNotFoundError(f"Required tool '{name}' not found.")


def compile_tb(iverilog: str, env: dict, out_vvp: Path, fifo_depth: int = 1024) -> None:
    cmd = [
        iverilog, "-g2012", "-Wall", "-I", "rtl", "-s", "tb_top",
        f"-Ptb_top.P_FIFO_DEPTH={fifo_depth}",
        "-o", str(out_vvp), *RTL_FILES, "tests/tb_top.sv",
    ]
    res = subprocess.run(cmd, env=env, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"Compile failed for FIFO_DEPTH={fifo_depth}:\n{res.stdout}\n{res.stderr}")


def run_exp(vvp: str, env: dict, vvp_bin: Path, metrics_csv: Path,
            src_mhz: float, dst_mhz: float, beats: int = 1500,
            adapt_mode: int = 2, bp_on: int = 10, bp_off: int = 0,
            seed: int = 424242, trace_csv: Path = None) -> dict:
    cmd = [
        vvp, str(vvp_bin),
        "+TEST=experiment",
        f"+SEED={seed}",
        f"+ADAPT_MODE={adapt_mode}",
        f"+SRC_MHZ={src_mhz}",
        f"+DST_MHZ={dst_mhz}",
        f"+BEATS={beats}",
        f"+BP_ON={bp_on}",
        f"+BP_OFF={bp_off}",
        f"+METRICS_CSV={metrics_csv.as_posix()}",
    ]
    if trace_csv is not None:
        cmd.append(f"+TRACE_CSV={trace_csv.as_posix()}")

    res = subprocess.run(cmd, env=env, capture_output=True, text=True)
    if res.returncode != 0 or "OVERALL STATUS: PASS" not in res.stdout:
        raise RuntimeError(f"Experiment run failed:\n{res.stdout}\n{res.stderr}")

    with metrics_csv.open("r", encoding="utf-8") as f:
        row = next(csv.DictReader(f))
    return row


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    os.chdir(repo_root)

    iverilog = find_tool("iverilog")
    vvp = find_tool("vvp")
    env = os.environ.copy()
    env["PATH"] = str(Path(iverilog).parent) + os.pathsep + env.get("PATH", "")

    build_dir = repo_root / "sim" / "build"
    res_dir = repo_root / "results"
    build_dir.mkdir(parents=True, exist_ok=True)
    res_dir.mkdir(parents=True, exist_ok=True)

    vvp_1024 = build_dir / "tb_exp_1024.vvp"
    compile_tb(iverilog, env, vvp_1024, fifo_depth=1024)

    tmp_m = build_dir / "tmp_metrics.csv"

    # Experiment A: Increasing source rate vs fixed 80 MHz destination
    exp_a = []
    for smhz in [60.0, 80.0, 100.0, 125.0, 150.0, 180.0]:
        r = run_exp(vvp, env, vvp_1024, tmp_m, src_mhz=smhz, dst_mhz=80.0, beats=1500)
        r["experiment"] = "A_src_rate_sweep"
        exp_a.append(r)

    # Experiment B: Increasing destination rate vs fixed 125 MHz source
    exp_b = []
    for dmhz in [60.0, 80.0, 100.0, 125.0, 150.0]:
        r = run_exp(vvp, env, vvp_1024, tmp_m, src_mhz=125.0, dst_mhz=dmhz, beats=1500)
        r["experiment"] = "B_dst_rate_sweep"
        exp_b.append(r)

    # Experiment C: Long backpressure stalls + full trace for occupancy vs time
    exp_c = []
    for idx, bp_off in enumerate([0, 5, 15, 30, 60]):
        trace_file = (res_dir / "exp_c_trace.csv") if bp_off == 30 else None
        r = run_exp(vvp, env, vvp_1024, tmp_m, src_mhz=125.0, dst_mhz=80.0,
                    beats=1600, bp_on=8, bp_off=bp_off, trace_csv=trace_file)
        r["bp_off"] = str(bp_off)
        r["experiment"] = "C_backpressure_sweep"
        exp_c.append(r)

    # Experiment D: Compare adapt_mode 0 (bypass), 1 (fixed), 2 (hysteresis)
    exp_d = []
    for mode, label in [(0, "no_adaptation"), (1, "fixed_threshold"), (2, "adaptive_hysteresis")]:
        trace_file = res_dir / f"exp_d_trace_mode{mode}.csv"
        r = run_exp(vvp, env, vvp_1024, tmp_m, src_mhz=135.0, dst_mhz=75.0,
                    beats=2000, adapt_mode=mode, bp_on=6, bp_off=10, trace_csv=trace_file)
        r["mode_name"] = label
        r["experiment"] = "D_controller_comparison"
        exp_d.append(r)

    # Experiment E: FIFO depth scaling (64, 128, 256, 512, 1024)
    exp_e = []
    for depth in [64, 128, 256, 512, 1024]:
        vvp_d = build_dir / f"tb_exp_{depth}.vvp"
        compile_tb(iverilog, env, vvp_d, fifo_depth=depth)
        r = run_exp(vvp, env, vvp_d, tmp_m, src_mhz=125.0, dst_mhz=80.0,
                    beats=1500, bp_on=8, bp_off=12)
        r["experiment"] = "E_fifo_depth_sweep"
        exp_e.append(r)

    def save_csv(path: Path, rows: list):
        keys = list(rows[0].keys())
        with path.open("w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=keys)
            w.writeheader()
            w.writerows(rows)

    save_csv(res_dir / "exp_a_src_rate.csv", exp_a)
    save_csv(res_dir / "exp_b_dst_rate.csv", exp_b)
    save_csv(res_dir / "exp_c_backpressure.csv", exp_c)
    save_csv(res_dir / "exp_d_modes.csv", exp_d)
    save_csv(res_dir / "exp_e_depths.csv", exp_e)

    print("All experiments A-E completed using real RTL simulation.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

