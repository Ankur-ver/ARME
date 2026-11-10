// =============================================================================
// File        : tb/uvm/scoreboard/rate_scoreboard.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : UVM scoreboard comparing independent reference-model expected
//               beats against destination monitor actual beats. Reports packet
//               ID, beat index, expected/actual data, and src/dst cycle stamps.
// =============================================================================

`ifndef RATE_SCOREBOARD_SV
`define RATE_SCOREBOARD_SV

`uvm_analysis_imp_decl(_exp)
`uvm_analysis_imp_decl(_act)

class rate_scoreboard extends uvm_component;
    `uvm_component_utils(rate_scoreboard)

    uvm_analysis_imp_exp #(stream_beat_item, rate_scoreboard) exp_imp;
    uvm_analysis_imp_act #(stream_beat_item, rate_scoreboard) act_imp;

    stream_beat_item exp_q[$];
    int unsigned     matched_beats   = 0;
    int unsigned     matched_packets = 0;
    int unsigned     mismatch_count  = 0;
    int unsigned     discarded_count = 0;
    realtime         total_lat_ns    = 0.0;
    realtime         max_lat_ns      = 0.0;

    function new(string name = "rate_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        exp_imp = new("exp_imp", this);
        act_imp = new("act_imp", this);
    endfunction

    function void flush_on_reset();
        discarded_count += exp_q.size();
        exp_q.delete();
    endfunction

    function void write_exp(stream_beat_item t);
        stream_beat_item clone_item;
        $cast(clone_item, t.clone());
        exp_q.push_back(clone_item);
    endfunction

    function void write_act(stream_beat_item act);
        stream_beat_item exp;
        realtime lat;

        if (exp_q.size() == 0) begin
            mismatch_count++;
            `uvm_error("SB_UNEXPECTED", $sformatf(
                "Unexpected egress beat at dst_cycle=%0d: data=0x%016h sop=%0b eop=%0b",
                act.cycle_stamp, act.data, act.packet_start, act.packet_end))
            return;
        end

        exp = exp_q.pop_front();
        lat = act.time_stamp - exp.time_stamp;
        total_lat_ns += lat;
        if (lat > max_lat_ns) max_lat_ns = lat;

        if (act.data !== exp.data || act.keep !== exp.keep ||
            act.packet_start !== exp.packet_start || act.packet_end !== exp.packet_end) begin
            mismatch_count++;
            `uvm_error("SB_MISMATCH", $sformatf(
                "Mismatch pkt_id=%0d beat=%0d src_cyc=%0d dst_cyc=%0d | EXP(data=0x%016h keep=0x%02h sop=%0b eop=%0b) ACT(data=0x%016h keep=0x%02h sop=%0b eop=%0b)",
                exp.packet_id, exp.beat_idx, exp.cycle_stamp, act.cycle_stamp,
                exp.data, exp.keep, exp.packet_start, exp.packet_end,
                act.data, act.keep, act.packet_start, act.packet_end))
        end else begin
            matched_beats++;
            if (exp.packet_end) matched_packets++;
        end
    endfunction

    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (exp_q.size() != 0) begin
            mismatch_count += exp_q.size();
            `uvm_error("SB_DROPPED", $sformatf(
                "%0d expected beat(s) remained undelivered at end of simulation", exp_q.size()))
        end
    endfunction

    function void report_phase(uvm_phase phase);
        real avg_lat = (matched_beats > 0) ? (total_lat_ns / matched_beats) : 0.0;
        super.report_phase(phase);
        `uvm_info("SB_SUMMARY", $sformatf(
            "MatchedBeats=%0d MatchedPkts=%0d ResetDiscarded=%0d Mismatches=%0d AvgLat=%.2fns MaxLat=%.2fns",
            matched_beats, matched_packets, discarded_count, mismatch_count, avg_lat, max_lat_ns), UVM_NONE)
    endfunction
endclass

`endif
