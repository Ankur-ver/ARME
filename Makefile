# ==============================================================================
# Adaptive Rate-Matching Engine - Build, Lint, Simulation & Regression Makefile
# ==============================================================================

SHELL       := /bin/bash
PYTHON      ?= python
SIM         ?= iverilog

RTL_DIR     := rtl
TB_DIR      := tb
TESTS_DIR   := tests
BUILD_DIR   := sim/build
RESULTS_DIR := results

RTL_SRCS    := $(RTL_DIR)/rate_engine_pkg.sv \
               $(RTL_DIR)/reset_controller.sv \
               $(RTL_DIR)/packet_controller.sv \
               $(RTL_DIR)/stream_adapter.sv \
               $(RTL_DIR)/async_fifo.sv \
               $(RTL_DIR)/fifo_monitor.sv \
               $(RTL_DIR)/rate_controller.sv \
               $(RTL_DIR)/top.sv

IF_SRCS     := $(TB_DIR)/interfaces/stream_if.sv

.PHONY: all help dirs lint compile test-fifo test uvm regression coverage synth analyze clean

all: help

help:
	@echo "Adaptive Rate-Matching Engine - Makefile Targets"
	@echo "  make lint        - Run Verilator RTL lint checks (-Wall)"
	@echo "  make compile     - Compile full RTL + stream_if with $(SIM)"
	@echo "  make test-fifo   - Run standalone async_fifo CDC unit testbench"
	@echo "  make test        - Run full-subsystem self-checking SV testbench"
	@echo "  make uvm         - Run UVM + SVA testbench (requires Questa/VCS/Xcelium)"
	@echo "  make regression  - Run 30-seed Python RTL regression suite"
	@echo "  make synth       - Run Yosys synthesis and resource report"
	@echo "  make analyze     - Run Experiments A-E and generate PNG plots"
	@echo "  make clean       - Clean build and temporary files"

dirs:
	@mkdir -p $(BUILD_DIR) $(RESULTS_DIR)

lint: dirs
	verilator --lint-only -Wall -I$(RTL_DIR) --top-module top $(RTL_SRCS)

compile: dirs
ifeq ($(SIM),iverilog)
	iverilog -g2012 -Wall -I$(RTL_DIR) -s top -o $(BUILD_DIR)/top.vvp $(RTL_SRCS)
else ifeq ($(SIM),verilator)
	verilator --lint-only -Wall -I$(RTL_DIR) --top-module top $(RTL_SRCS)
else
	@echo "Unsupported SIM=$(SIM). Use SIM=iverilog or SIM=verilator."
	@exit 1
endif

test-fifo: dirs
	iverilog -g2012 -Wall -I$(RTL_DIR) -o $(BUILD_DIR)/tb_async_fifo.vvp \
		$(RTL_DIR)/async_fifo.sv $(TESTS_DIR)/tb_async_fifo.sv
	vvp $(BUILD_DIR)/tb_async_fifo.vvp

test: dirs
	iverilog -g2012 -Wall -I$(RTL_DIR) -s tb_top -o $(BUILD_DIR)/tb_top.vvp \
		$(RTL_SRCS) $(TESTS_DIR)/tb_top.sv
	vvp $(BUILD_DIR)/tb_top.vvp +TEST=all +SEED=20261110

uvm:
	@echo "UVM 1.2 + SVA + covergroups require Questa/VCS/Xcelium."
	@echo "Example (Questa):"
	@echo "  vlog -sv +incdir+tb/uvm/sequences+tb/uvm/agents+tb/uvm/reference_model+tb/uvm/scoreboard+tb/uvm/coverage+tb/uvm/env+tb/uvm/tests \\"
	@echo "    $(RTL_SRCS) $(IF_SRCS) tb/assertions/assertions.sv tb/uvm/rate_uvm_pkg.sv tb/uvm/tb_uvm_top.sv"
	@echo "  vsim -c tb_uvm_top +UVM_TESTNAME=random_stress_test -do \"run -all; quit\""

regression: dirs
	$(PYTHON) scripts/run_regression.py --tests all --runs 30

coverage:
	@echo "See docs/coverage_closure.md for Tier 1 regression & Tier 2 UVM UCDB closure instructions."

synth:
	yosys -s synthesis/synth_yosys.ys

analyze: dirs
	$(PYTHON) scripts/analyze_results.py
	$(PYTHON) scripts/plot_results.py

clean:
	rm -rf $(BUILD_DIR) obj_dir work transcript vsim.wlf *.vvp *.vcd *.fst
