// =============================================================================
// File        : tb/uvm/reference_model/rate_reference_model.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : Independent transaction-level reference model (does not mirror
//               DUT RTL internals). Models packet framing, ordering, boundary
//               invariants, and expected stream output given source handshakes.
// =============================================================================

`ifndef RATE_REFERENCE_MODEL_SV
`define RATE_REFERENCE_MODEL_SV

class rate_reference_model extends uvm_component;
    `uvm_component_utils(rate_reference_model)

    uvm_analysis_imp #(stream_beat_item, rate_reference_model) src_imp;
    uvm_analysis_port #(stream_beat_item)                      exp_ap;

    bit          drop_malformed_beats = 1'b0;
    bit          in_packet            = 1'b0;
    int unsigned expected_pkt_id      = 1;
    int unsigned expected_beat_idx    = 0;
    int unsigned detected_proto_errs  = 0;

    function new(string name = "rate_reference_model", uvm_component parent = null);
        super.new(name, parent);
        src_imp = new("src_imp", this);
        exp_ap  = new("exp_ap", this);
    endfunction

    function void reset_model();
        in_packet         = 1'b0;
        expected_beat_idx = 0;
    endfunction

    function void write(stream_beat_item t);
        bit malformed = 1'b0;
        stream_beat_item exp_item;

        if (!in_packet) begin
            if (!t.packet_start) begin
                malformed = 1'b1;
            end else begin
                expected_beat_idx = 0;
                in_packet = !t.packet_end;
            end
        end else begin
            if (t.packet_start) begin
                malformed = 1'b1;
                expected_beat_idx = 0;
                in_packet = !t.packet_end;
            end else begin
                expected_beat_idx++;
                if (t.packet_end) in_packet = 1'b0;
            end
        end

        if (malformed) begin
            detected_proto_errs++;
            `uvm_info("REF_MODEL", $sformatf(
                "Observed source protocol violation pkt=%0d beat=%0d sop=%0b eop=%0b",
                t.packet_id, t.beat_idx, t.packet_start, t.packet_end), UVM_MEDIUM)
            if (drop_malformed_beats) return;
        end

        exp_item = stream_beat_item::type_id::create("exp_beat");
        exp_item.copy(t);
        exp_item.packet_id = expected_pkt_id;
        exp_item.beat_idx  = expected_beat_idx;
        exp_ap.write(exp_item);

        if (t.packet_end) begin
            expected_pkt_id++;
            expected_beat_idx = 0;
        end
    endfunction
endclass

`endif
