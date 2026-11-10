// =============================================================================
// File        : tb/uvm/sequences/stream_transaction.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : UVM sequence items and environment configuration object.
// =============================================================================

`ifndef STREAM_TRANSACTION_SV
`define STREAM_TRANSACTION_SV

typedef enum {
    PKT_SINGLE,
    PKT_SMALL,
    PKT_MEDIUM,
    PKT_LARGE,
    PKT_MAX,
    PKT_BURST,
    PKT_MALFORMED
} pkt_profile_e;

typedef enum {
    CLK_SRC_FASTER,
    CLK_DST_FASTER,
    CLK_EQUAL,
    CLK_EXTREME_MISMATCH,
    CLK_NON_INTEGER
} clk_ratio_e;

class stream_beat_item extends uvm_sequence_item;
    bit [63:0] data;
    bit [7:0]  keep;
    bit        packet_start;
    bit        packet_end;
    int        packet_id;
    int        beat_idx;
    longint    cycle_stamp;
    realtime   time_stamp;

    `uvm_object_utils_begin(stream_beat_item)
        `uvm_field_int(data, UVM_ALL_ON)
        `uvm_field_int(keep, UVM_ALL_ON)
        `uvm_field_int(packet_start, UVM_ALL_ON)
        `uvm_field_int(packet_end, UVM_ALL_ON)
        `uvm_field_int(packet_id, UVM_ALL_ON)
        `uvm_field_int(beat_idx, UVM_ALL_ON)
        `uvm_field_int(cycle_stamp, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "stream_beat_item");
        super.new(name);
    endfunction
endclass

class stream_transaction extends uvm_sequence_item;
    rand pkt_profile_e profile;
    rand int unsigned  packet_length;
    rand int unsigned  burst_length;
    rand int unsigned  inter_packet_gap;
    rand bit [63:0]    data[];
    rand bit [7:0]     keep[];
    rand bit           inject_malformed;
    rand bit           malformed_orphan_eop;

    constraint c_profile_len {
        if (profile == PKT_SINGLE) {
            packet_length == 1;
        } else if (profile == PKT_SMALL) {
            packet_length inside {[2:8]};
        } else if (profile == PKT_MEDIUM) {
            packet_length inside {[9:64]};
        } else if (profile == PKT_LARGE) {
            packet_length inside {[65:256]};
        } else if (profile == PKT_MAX) {
            packet_length inside {[257:1000]};
        } else if (profile == PKT_BURST) {
            packet_length inside {[16:512]};
        } else {
            packet_length inside {[2:8]};
        }
        burst_length inside {[1:1000]};
        inter_packet_gap inside {[0:32]};
    }

    constraint c_malformed_default {
        soft inject_malformed == (profile == PKT_MALFORMED);
        soft malformed_orphan_eop == 1'b1;
    }

    constraint c_arrays {
        data.size() == packet_length;
        keep.size() == packet_length;
        foreach (keep[i]) {
            if (i < packet_length - 1) keep[i] == 8'hFF;
            else keep[i] inside {8'hFF, 8'h7F, 8'h3F, 8'h1F, 8'h0F, 8'h07, 8'h03, 8'h01};
        }
    }

    `uvm_object_utils_begin(stream_transaction)
        `uvm_field_enum(pkt_profile_e, profile, UVM_ALL_ON)
        `uvm_field_int(packet_length, UVM_ALL_ON)
        `uvm_field_int(burst_length, UVM_ALL_ON)
        `uvm_field_int(inter_packet_gap, UVM_ALL_ON)
        `uvm_field_array_int(data, UVM_ALL_ON)
        `uvm_field_array_int(keep, UVM_ALL_ON)
        `uvm_field_int(inject_malformed, UVM_ALL_ON)
        `uvm_field_int(malformed_orphan_eop, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "stream_transaction");
        super.new(name);
    endfunction
endclass

class backpressure_transaction extends uvm_sequence_item;
    rand int unsigned ready_on_cycles;
    rand int unsigned ready_off_cycles;
    rand bit          always_ready;

    constraint c_bp {
        if (always_ready) {
            ready_on_cycles  inside {[8:64]};
            ready_off_cycles == 0;
        } else {
            ready_on_cycles  inside {[1:32]};
            ready_off_cycles inside {[1:64]};
        }
    }

    `uvm_object_utils_begin(backpressure_transaction)
        `uvm_field_int(ready_on_cycles, UVM_ALL_ON)
        `uvm_field_int(ready_off_cycles, UVM_ALL_ON)
        `uvm_field_int(always_ready, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "backpressure_transaction");
        super.new(name);
    endfunction
endclass

class rate_env_config extends uvm_object;
    virtual stream_if #(64) src_vif;
    virtual stream_if #(64) dst_vif;

    real        src_mhz     = 100.0;
    real        dst_mhz     = 80.0;
    clk_ratio_e clk_profile = CLK_SRC_FASTER;
    bit [1:0]   adapt_mode  = 2'd2;
    bit         allow_packet_errors = 1'b0;

    `uvm_object_utils(rate_env_config)

    function new(string name = "rate_env_config");
        super.new(name);
    endfunction
endclass

`endif

