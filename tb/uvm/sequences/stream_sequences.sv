// =============================================================================
// File        : tb/uvm/sequences/stream_sequences.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : Reusable UVM sequences for directed, burst, backpressure,
//               boundary, error-injection, and thousands-of-beats stress runs.
// =============================================================================

`ifndef STREAM_SEQUENCES_SV
`define STREAM_SEQUENCES_SV

class base_stream_seq extends uvm_sequence #(stream_transaction);
    `uvm_object_utils(base_stream_seq)

    rand int unsigned num_packets = 10;
    pkt_profile_e     fixed_profile = PKT_MEDIUM;
    bit               use_random_profile = 1'b0;
    bit               force_malformed = 1'b0;

    function new(string name = "base_stream_seq");
        super.new(name);
    endfunction

    task body();
        for (int p = 0; p < num_packets; p++) begin
            stream_transaction tr = stream_transaction::type_id::create("tr");
            start_item(tr);
            if (!tr.randomize() with {
                if (force_malformed) {
                    profile == PKT_MALFORMED;
                    inject_malformed == 1'b1;
                } else if (!use_random_profile) {
                    profile == fixed_profile;
                    inject_malformed == 1'b0;
                } else {
                    profile inside {PKT_SINGLE, PKT_SMALL, PKT_MEDIUM, PKT_LARGE, PKT_BURST};
                    inject_malformed == 1'b0;
                }
            }) begin
                `uvm_fatal("SEQ_RAND", "Failed to randomize stream_transaction")
            end
            finish_item(tr);
        end
    endtask
endclass

class bp_profile_seq extends uvm_sequence #(backpressure_transaction);
    `uvm_object_utils(bp_profile_seq)

    int unsigned num_windows = 40;
    bit          always_ready = 1'b0;
    int unsigned min_off = 1;
    int unsigned max_off = 16;

    function new(string name = "bp_profile_seq");
        super.new(name);
    endfunction

    task body();
        for (int i = 0; i < num_windows; i++) begin
            backpressure_transaction tr = backpressure_transaction::type_id::create("bp_tr");
            start_item(tr);
            if (!tr.randomize() with {
                always_ready == local::always_ready;
                if (!local::always_ready) {
                    ready_off_cycles inside {[local::min_off : local::max_off]};
                }
            }) begin
                `uvm_fatal("BP_RAND", "Failed to randomize backpressure_transaction")
            end
            finish_item(tr);
        end
    endtask
endclass

class virtual_traffic_vseq extends uvm_sequence;
    `uvm_object_utils(virtual_traffic_vseq)
    `uvm_declare_p_sequencer(virtual_sequencer)

    int unsigned  num_packets       = 40;
    pkt_profile_e pkt_profile       = PKT_MEDIUM;
    bit           random_profiles   = 1'b1;
    bit           bp_always_ready   = 1'b0;
    int unsigned  bp_min_off        = 1;
    int unsigned  bp_max_off        = 16;
    bit           inject_malformed  = 1'b0;

    function new(string name = "virtual_traffic_vseq");
        super.new(name);
    endfunction

    task body();
        base_stream_seq s_seq = base_stream_seq::type_id::create("s_seq");
        bp_profile_seq  b_seq = bp_profile_seq::type_id::create("b_seq");

        s_seq.num_packets        = num_packets;
        s_seq.fixed_profile      = pkt_profile;
        s_seq.use_random_profile = random_profiles;
        s_seq.force_malformed    = inject_malformed;

        b_seq.num_windows  = num_packets * 2;
        b_seq.always_ready = bp_always_ready;
        b_seq.min_off      = bp_min_off;
        b_seq.max_off      = bp_max_off;

        fork
            s_seq.start(p_sequencer.src_sqr);
            b_seq.start(p_sequencer.dst_sqr);
        join_any
        // Drain final packets with ready high
        begin
            bp_profile_seq drain_bp = bp_profile_seq::type_id::create("drain_bp");
            drain_bp.num_windows  = 20;
            drain_bp.always_ready = 1'b1;
            drain_bp.start(p_sequencer.dst_sqr);
        end
    endtask
endclass

`endif

