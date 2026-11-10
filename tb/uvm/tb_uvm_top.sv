// =============================================================================
// File        : tb/uvm/tb_uvm_top.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : Top-level UVM testbench module connecting DUT, stream_if
//               instances, bound SVA module, and UVM config_db.
// =============================================================================

`timescale 1ns/1ps

module tb_uvm_top;
    import uvm_pkg::*;
    import rate_engine_pkg::*;
    import rate_uvm_pkg::*;

    logic src_clk = 1'b0;
    logic dst_clk = 1'b0;
    logic src_rst_n = 1'b0;
    logic dst_rst_n = 1'b0;

    real src_half_ns = 5.0;   // 100 MHz
    real dst_half_ns = 6.25;  // 80 MHz

    always #(src_half_ns) src_clk = ~src_clk;
    always #(dst_half_ns) dst_clk = ~dst_clk;

    stream_if #(64) src_if (.clk(src_clk), .rst_n(src_rst_n));
    stream_if #(64) dst_if (.clk(dst_clk), .rst_n(dst_rst_n));

    logic [1:0]  adapt_mode = 2'd2;
    logic        clr_stats  = 1'b0;
    logic        clr_errors = 1'b0;
    logic        fifo_full, fifo_empty, almost_full, almost_empty;
    logic        congestion, starvation_warning, high_watermark_hit, low_watermark_hit;
    logic        overflow_error, underflow_error, packet_error;
    logic [31:0] overflow_count, underflow_count, packets_started, packets_completed;
    ctrl_state_e current_state;
    logic [10:0] src_occupancy, dst_occupancy, max_occupancy, min_occupancy;
    logic        reset_busy_src, reset_busy_dst;

    top dut (
        .src_clk            (src_clk),
        .src_rst_n          (src_rst_n),
        .src_data           (src_if.data),
        .src_keep           (src_if.keep),
        .src_valid          (src_if.valid),
        .src_ready          (src_if.ready),
        .src_packet_start   (src_if.packet_start),
        .src_packet_end     (src_if.packet_end),
        .dst_clk            (dst_clk),
        .dst_rst_n          (dst_rst_n),
        .dst_data           (dst_if.data),
        .dst_keep           (dst_if.keep),
        .dst_valid          (dst_if.valid),
        .dst_ready          (dst_if.ready),
        .dst_packet_start   (dst_if.packet_start),
        .dst_packet_end     (dst_if.packet_end),
        .adapt_mode         (adapt_mode),
        .clr_stats          (clr_stats),
        .clr_errors         (clr_errors),
        .fifo_full          (fifo_full),
        .fifo_empty         (fifo_empty),
        .almost_full        (almost_full),
        .almost_empty       (almost_empty),
        .congestion         (congestion),
        .starvation_warning (starvation_warning),
        .high_watermark_hit (high_watermark_hit),
        .low_watermark_hit  (low_watermark_hit),
        .overflow_error     (overflow_error),
        .underflow_error    (underflow_error),
        .packet_error       (packet_error),
        .overflow_count     (overflow_count),
        .underflow_count    (underflow_count),
        .packets_started    (packets_started),
        .packets_completed  (packets_completed),
        .current_state      (current_state),
        .src_occupancy      (src_occupancy),
        .dst_occupancy      (dst_occupancy),
        .max_occupancy      (max_occupancy),
        .min_occupancy      (min_occupancy),
        .reset_busy_src     (reset_busy_src),
        .reset_busy_dst     (reset_busy_dst)
    );

    initial begin
        void'($value$plusargs("SRC_HALF_NS=%f", src_half_ns));
        void'($value$plusargs("DST_HALF_NS=%f", dst_half_ns));

        uvm_config_db#(virtual stream_if #(64))::set(null, "*", "src_vif", src_if);
        uvm_config_db#(virtual stream_if #(64))::set(null, "*", "dst_vif", dst_if);

        run_test();
    end

    initial begin
        src_rst_n = 1'b0;
        dst_rst_n = 1'b0;
        #50ns;
        src_rst_n = 1'b1;
        dst_rst_n = 1'b1;
    end
endmodule
