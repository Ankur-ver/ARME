# ==============================================================================
# Adaptive Rate-Matching Engine - Build, Lint, Simulation & Regression Makefile
# ==============================================================================
# Supported flows:
#   1. Open-source SV simulation: Verilator / Icarus Verilog (unit & SV TB)
#   2. Full UVM + SVA + Functional Coverage: Questa / VCS / Xcelium (or Verilator+UVM)
#   3. Lint & Synthesis: Verilator --lint-only / Yosys
#   4. Regression & Performance Analysis: Python 3
# ==============================================================================

SHELL       := /bin/bash
PYTHON      ?= python3
SIM         ?= verilator
UVM_SIM     ?= questa

RTL_DIR     := rtl
TB_DIR      := tb
BUILD_DIR   := sim/build
WAVE_DIR    := sim/waves
RESULTS_DIR := results

RTL_PKG     := $(RTL_DIR)/rate_engine_pkg.sv
RTL_SRCS    := $(RTL_PKG) \
               $(wildcard $(RTL_DIR)/*.sv)

IF_SRCS     := $(TB_DIR)/interfaces/stream_if.sv

.PHONY: all help dirs lint compile test test-fifo uvm regression coverage synth analyze clean

all: help

help:
	@echo "Adaptive Rate-Matching Engine - Makefile Targets"
	@echo "  make dirs        - Create simulation build directories"
	@echo "  make lint        - Run Verilator RTL lint checks"
	@echo "  make compile     - Compile Phase RTL + interfaces with $(SIM)"
	@echo "  make test-fifo   - Run standalone async_fifo directed/random testbench"
	@echo "  make test        - Run SystemVerilog top-level self-checking testbench"
	@echo "  make uvm         - Compile & run UVM testbench (requires UVM-capable simulator)"
	@echo "  make regression  - Run Python regression runner"
	@echo "  make coverage    - Generate/merge coverage reports (simulator-dependent)"
	@echo "  make synth       - Run Yosys synthesis script (if yosys installed)"
	@echo "  make analyze     - Run Python performance analysis & plotting"
	@echo "  make clean       - Clean build, wave, and temporary files"

dirs:
	@mkdir -p $(BUILD_DIR) $(WAVE_DIR) $(RESULTS_DIR)

lint: dirs
	verilator --lint-only -Wall -Wno-DECLFILENAME \
		-I$(RTL_DIR) $(RTL_PKG) $(IF_SRCS) \
		$(filter-out $(RTL_PKG),$(wildcard $(RTL_DIR)/*.sv))

compile: dirs
ifeq ($(SIM),iverilog)
	iverilog -g2012 -Wall -I$(RTL_DIR) -o $(BUILD_DIR)/compile_check.vvp \
		$(RTL_PKG) $(IF_SRCS)
else ifeq ($(SIM),verilator)
	verilator --lint-only -Wall -I$(RTL_DIR) $(RTL_PKG) $(IF_SRCS)
else
	@echo "Unsupported SIM=$(SIM). Use SIM=verilator or SIM=iverilog."
	@exit 1
endif

test-fifo: dirs
	@echo "Available starting Phase 3 (FIFO unit tests)."

test: dirs
	@echo "Available starting Phase 7 (Top-level SV testbench)."

uvm: dirs
	@echo "Available starting Phase 8 (UVM environment; requires Questa/VCS/Xcelium or UVM-enabled Verilator)."

regression: dirs
	$(PYTHON) scripts/run_regression.py --tests all --runs 20

coverage:
	@echo "Available starting Phase 12 (Functional coverage closure)."

synth:
	@echo "Available when synthesis scripts are added."

analyze:
	$(PYTHON) scripts/analyze_results.py
	$(PYTHON) scripts/plot_results.py

clean:
	rm -rf $(BUILD_DIR) $(WAVE_DIR) obj_dir work transcript vsim.wlf *.vvp *.vcd *.fst
