// =============================================================================
// File        : tb/uvm/coverage/rate_coverage.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : Functional coverage collector covering clock ratios, FIFO
//               occupancy, controller FSM states, packet sizes, backpressure
//               regimes, reset scenarios, and architectural cross coverage.
// =============================================================================

`ifndef RATE_COVERAGE_SV
`define RATE_COVERAGE_SV

typedef enum {
    RST_IDLE,
    RST_DURING_TRAFFIC,
    RST_DURING_PACKET,
    RST_NEAR_BOUNDARY
} reset_scenario_e;

class rate_coverage extends uvm_component;
    `uvm_component_utils(rate_coverage)

    uvm_analysis_imp #(stream_beat_item, rate_coverage) pkt_imp;

    // Sampled architectural variables
    clk_ratio_e                 s_clk_ratio;
    int unsigned                s_occupancy;
    rate_engine_pkg::ctrl_state_e s_ctrl_state;
    int unsigned                s_packet_len;
    int unsigned                s_bp_off_cyc;
    bit                         s_congestion;
    reset_scenario_e            s_rst_scenario;

    covergroup cg_arch_state;
        cp_clk_ratio: coverpoint s_clk_ratio {
            bins src_faster       = {CLK_SRC_FASTER};
            bins dst_faster       = {CLK_DST_FASTER};
            bins equal            = {CLK_EQUAL};
            bins extreme_mismatch = {CLK_EXTREME_MISMATCH};
            bins non_integer      = {CLK_NON_INTEGER};
        }

        cp_occupancy: coverpoint s_occupancy {
            bins empty  = {0};
            bins low    = {[1:256]};
            bins medium = {[257:767]};
            bins high   = {[768:1023]};
            bins full   = {1024};
        }

        cp_ctrl_state: coverpoint s_ctrl_state {
            bins normal     = {rate_engine_pkg::CTRL_NORMAL};
            bins starvation = {rate_engine_pkg::CTRL_STARVATION_WARNING};
            bins throttle   = {rate_engine_pkg::CTRL_THROTTLE};
            bins congestion = {rate_engine_pkg::CTRL_CONGESTION};
            bins recovery   = {rate_engine_pkg::CTRL_RECOVERY};
        }

        cx_occ_x_state: cross cp_occupancy, cp_ctrl_state {
            // Physically unreachable combinations excluded cleanly
            ignore_bins empty_congestion = binsof(cp_occupancy.empty) && binsof(cp_ctrl_state.congestion);
        }

        cx_clk_x_state: cross cp_clk_ratio, cp_ctrl_state;
    endgroup

    covergroup cg_traffic_bp;
        cp_pkt_size: coverpoint s_packet_len {
            bins minimum = {1};
            bins small   = {[2:8]};
            bins medium  = {[9:64]};
            bins large   = {[65:256]};
            bins maximum = {[257:1024]};
        }

        cp_backpressure: coverpoint s_bp_off_cyc {
            bins none   = {0};
            bins short  = {[1:4]};
            bins medium = {[5:16]};
            bins long   = {[17:128]};
        }

        cp_congestion: coverpoint s_congestion {
            bins inactive = {1'b0};
            bins active   = {1'b1};
        }

        cx_pkt_x_bp:   cross cp_pkt_size, cp_backpressure;
        cx_cong_x_pkt: cross cp_congestion, cp_pkt_size;
    endgroup

    covergroup cg_reset;
        cp_reset_scenario: coverpoint s_rst_scenario {
            bins idle          = {RST_IDLE};
            bins during_traf   = {RST_DURING_TRAFFIC};
            bins during_packet = {RST_DURING_PACKET};
            bins near_boundary = {RST_NEAR_BOUNDARY};
        }
    endgroup

    function new(string name = "rate_coverage", uvm_component parent = null);
        super.new(name, parent);
        pkt_imp       = new("pkt_imp", this);
        cg_arch_state = new();
        cg_traffic_bp = new();
        cg_reset      = new();
    endfunction

    function void sample_arch(
        clk_ratio_e                   ratio,
        int unsigned                  occ,
        rate_engine_pkg::ctrl_state_e st,
        bit                           cong
    );
        s_clk_ratio  = ratio;
        s_occupancy  = occ;
        s_ctrl_state = st;
        s_congestion = cong;
        cg_arch_state.sample();
    endfunction

    function void sample_traffic(int unsigned plen, int unsigned bp_off, bit cong);
        s_packet_len = plen;
        s_bp_off_cyc = bp_off;
        s_congestion = cong;
        cg_traffic_bp.sample();
    endfunction

    function void sample_reset(reset_scenario_e scen);
        s_rst_scenario = scen;
        cg_reset.sample();
    endfunction

    function void write(stream_beat_item t);
        if (t.packet_end) begin
            s_packet_len = t.beat_idx + 1;
            cg_traffic_bp.sample();
        end
    endfunction
endclass

`endif

