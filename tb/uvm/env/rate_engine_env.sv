// =============================================================================
// File        : tb/uvm/env/rate_engine_env.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : Top-level reusable UVM environment instantiating source/dst
//               agents, reference model, scoreboard, coverage, and vsequencer.
// =============================================================================

`ifndef RATE_ENGINE_ENV_SV
`define RATE_ENGINE_ENV_SV

class rate_engine_env extends uvm_env;
    `uvm_component_utils(rate_engine_env)

    source_agent         src_agt;
    destination_agent    dst_agt;
    rate_reference_model ref_model;
    rate_scoreboard      sb;
    rate_coverage        cov;
    virtual_sequencer    vsqr;

    function new(string name = "rate_engine_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        src_agt   = source_agent::type_id::create("src_agt", this);
        dst_agt   = destination_agent::type_id::create("dst_agt", this);
        ref_model = rate_reference_model::type_id::create("ref_model", this);
        sb        = rate_scoreboard::type_id::create("sb", this);
        cov       = rate_coverage::type_id::create("cov", this);
        vsqr      = virtual_sequencer::type_id::create("vsqr", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        src_agt.mon.ap.connect(ref_model.src_imp);
        src_agt.mon.ap.connect(cov.pkt_imp);
        ref_model.exp_ap.connect(sb.exp_imp);
        dst_agt.mon.ap.connect(sb.act_imp);

        vsqr.src_sqr = src_agt.sqr;
        vsqr.dst_sqr = dst_agt.sqr;
    endfunction
endclass

`endif

