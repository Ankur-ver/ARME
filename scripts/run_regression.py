#!/usr/bin/env python3
"""
Automated SystemVerilog regression runner for the Adaptive Rate-Matching Engine.
Compiles RTL + tb_top with Icarus Verilog, generates random seeds, runs tests,
captures logs, detects PASS/FAIL, and summarizes results + failing seeds.
"""

import argparse
import csv
import os
import random
import shutil
import subprocess
import sys
import time
from pathlib import Path

ALL_TESTS = [
    "smoke_test",
    "basic_transfer_test",
    "burst_test",
    "backpressure_test",
    "source_faster_test",
    "destination_faster_test",
    "equal_rate_test",
    "extreme_rate_mismatch_test",
    "fifo_boundary_test",
    "congestion_test",
    "starvation_test",
    "reset_test",
    "reset_during_packet_test",
    "error_injection_test",
    "random_stress_test",
]

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
    raise FileNotFoundError(f"Required tool '{name}' not found on PATH or MSYS2.")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Adaptive Rate-Matching Engine regression")
    parser.add_argument("--tests", default="all", help="Comma-separated tests or 'all'")
    parser.add_argument("--runs", type=int, default=15, help="Total test runs across selected tests")
    parser.add_argument("--master-seed", type=int, default=20261110, help="Master seed for seed generation")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    os.chdir(repo_root)

    iverilog = find_tool("iverilog")
    vvp = find_tool("vvp")
    tool_env = os.environ.copy()
    tool_dir = str(Path(iverilog).parent)
    tool_env["PATH"] = tool_dir + os.pathsep + tool_env.get("PATH", "")

    sim_build = repo_root / "sim" / "build"
    runs_dir = repo_root / "results" / "runs"
    sim_build.mkdir(parents=True, exist_ok=True)
    runs_dir.mkdir(parents=True, exist_ok=True)

    vvp_bin = sim_build / "tb_top_reg.vvp"
    compile_cmd = [
        iverilog, "-g2012", "-Wall", "-I", "rtl", "-s", "tb_top",
        "-o", str(vvp_bin), *RTL_FILES, "tests/tb_top.sv"
    ]
    comp = subprocess.run(compile_cmd, env=tool_env, capture_output=True, text=True)
    if comp.returncode != 0:
        print("COMPILE FAILED:")
        print(comp.stdout)
        print(comp.stderr)
        return 1

    selected = ALL_TESTS if args.tests == "all" else [t.strip() for t in args.tests.split(",") if t.strip()]
    rng = random.Random(args.master_seed)

    schedule = []
    if args.runs <= len(selected) and args.tests == "all":
        for i in range(args.runs):
            schedule.append((selected[i], rng.randint(100000, 999999)))
    else:
        for i in range(args.runs):
            tname = selected[i % len(selected)]
            schedule.append((tname, rng.randint(100000, 999999)))

    passed = 0
    failed_list = []
    rows = []

    t0 = time.time()
    for idx, (tname, seed) in enumerate(schedule, start=1):
        log_path = runs_dir / f"{idx:03d}_{tname}_seed{seed}.log"
        metrics_path = runs_dir / f"{idx:03d}_{tname}_seed{seed}_metrics.csv"
        cmd = [
            vvp, str(vvp_bin),
            f"+TEST={tname}",
            f"+SEED={seed}",
            f"+METRICS_CSV={metrics_path.as_posix()}",
        ]
        res = subprocess.run(cmd, env=tool_env, capture_output=True, text=True)
        full_log = res.stdout + ("\n" + res.stderr if res.stderr else "")
        log_path.write_text(full_log, encoding="utf-8")

        ok = (res.returncode == 0) and ("OVERALL STATUS: PASS" in res.stdout)
        status_str = "PASS" if ok else "FAIL"
        if ok:
            passed += 1
        else:
            failed_list.append((tname, seed, str(log_path)))

        rows.append({
            "run": idx,
            "test": tname,
            "seed": seed,
            "status": status_str,
            "log": str(log_path.relative_to(repo_root)),
        })

    elapsed = time.time() - t0
    summary_csv = repo_root / "results" / "regression_summary.csv"
    with summary_csv.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["run", "test", "seed", "status", "log"])
        writer.writeheader()
        writer.writerows(rows)

    print("===============================")
    print("ADAPTIVE RATE ENGINE REGRESSION")
    print("===============================")
    print(f"Total tests:       {len(schedule)}")
    print(f"Passed:            {passed}")
    print(f"Failed:            {len(failed_list)}")
    print(f"Elapsed (s):       {elapsed:.2f}")
    if failed_list:
        print("\nFailed:")
        for tname, seed, lpath in failed_list:
            print(f"  {tname:<26} seed={seed} ({lpath})")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

