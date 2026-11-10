// =============================================================================
// File        : tb/uvm/env/virtual_sequencer.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : Coordinates source packet sequences and destination backpressure.
// =============================================================================

`ifndef VIRTUAL_SEQUENCER_SV
`define VIRTUAL_SEQUENCER_SV

class virtual_sequencer extends uvm_sequencer;
    `uvm_component_utils(virtual_sequencer)

    source_sequencer      src_sqr;
    destination_sequencer dst_sqr;

    function new(string name = "virtual_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass

`endif
