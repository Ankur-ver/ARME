// =============================================================================
// File        : tb/uvm/rate_uvm_pkg.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : UVM package aggregating sequence items, agents, reference
//               model, scoreboard, coverage, environment, and tests.
// =============================================================================

`ifndef RATE_UVM_PKG_SV
`define RATE_UVM_PKG_SV

`include "uvm_macros.svh"

package rate_uvm_pkg;
    import uvm_pkg::*;
    import rate_engine_pkg::*;

    `include "stream_transaction.sv"
    `include "source_agent.sv"
    `include "destination_agent.sv"
    `include "rate_reference_model.sv"
    `include "rate_scoreboard.sv"
    `include "rate_coverage.sv"
    `include "virtual_sequencer.sv"
    `include "rate_engine_env.sv"
    `include "stream_sequences.sv"
    `include "rate_engine_tests.sv"
endpackage

`endif

