// =============================================================================
// File        : rtl/top.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : Top-level synthesizable integration of the Adaptive
//               Rate-Matching Engine ASIC subsystem across two asynchronous
//               clock domains (src_clk and dst_clk).
// =============================================================================

`timescale 1ns/1ps

module top
    import rate_engine_pkg::*;
#(
    parameter int DATA_WIDTH           = DEFAULT_DATA_WIDTH,
    parameter int KEEP_WIDTH           = (DATA_WIDTH / 8),
    parameter int FIFO_DEPTH           = DEFAULT_FIFO_DEPTH,
    parameter int SYNC_STAGES          = DEFAULT_SYNC_STAGES,
    parameter int CRIT_LOW_WATERMARK   = (FIFO_DEPTH / 16),
    parameter int LOW_WATERMARK        = (FIFO_DEPTH / 4),
    parameter int RECOVERY_WATERMARK   = (FIFO_DEPTH / 2),
    parameter int HIGH_WATERMARK       = ((FIFO_DEPTH * 3) / 4),
    parameter int CRIT_HIGH_WATERMARK  = ((FIFO_DEPTH * 29) / 32),
    parameter bit DROP_MALFORMED_BEATS = 1'b0,
    localparam int PTR_WIDTH           = $clog2(FIFO_DEPTH) + 1
) (
    // Source Clock Domain Stream Interface
    input  logic                  src_clk,
    input  logic                  src_rst_n,
    input  logic [DATA_WIDTH-1:0] src_data,
    input  logic [KEEP_WIDTH-1:0] src_keep,
    input  logic                  src_valid,
    output logic                  src_ready,
    input  logic                  src_packet_start,
    input  logic                  src_packet_end,

    // Destination Clock Domain Stream Interface
    input  logic                  dst_clk,
    input  logic                  dst_rst_n,
    output logic [DATA_WIDTH-1:0] dst_data,
    output logic [KEEP_WIDTH-1:0] dst_keep,
    output logic                  dst_valid,
    input  logic                  dst_ready,
    output logic                  dst_packet_start,
    output logic                  dst_packet_end,

    // Control & Configuration (Source Clock Domain)
    input  logic [1:0]            adapt_mode,
    input  logic                  clr_stats,
    input  logic                  clr_errors,

    // Status & Monitoring Outputs
    output logic                  fifo_full,
    output logic                  fifo_empty,
    output logic                  almost_full,
    output logic                  almost_empty,
    output logic                  congestion,
    output logic                  starvation_warning,
    output logic                  high_watermark_hit,
    output logic                  low_watermark_hit,
    output logic                  overflow_error,
    output logic                  underflow_error,
    output logic                  packet_error,
    output logic [31:0]           overflow_count,
    output logic [31:0]           underflow_count,
    output logic [31:0]           packets_started,
    output logic [31:0]           packets_completed,
    output ctrl_state_e           current_state,
    output logic [PTR_WIDTH-1:0]  src_occupancy,
    output logic [PTR_WIDTH-1:0]  dst_occupancy,
    output logic [PTR_WIDTH-1:0]  max_occupancy,
    output logic [PTR_WIDTH-1:0]  min_occupancy,
    output logic                  reset_busy_src,
    output logic                  reset_busy_dst
);

    localparam int PAYLOAD_WIDTH = DATA_WIDTH + KEEP_WIDTH + 2;

    // Reference default constants from package so package defaults are exercised
    localparam int unsigned _pkg_ref_crit_low = DEFAULT_CRIT_LOW_WATERMARK;
    localparam int unsigned _pkg_ref_low      = DEFAULT_LOW_WATERMARK;
    localparam int unsigned _pkg_ref_rec      = DEFAULT_RECOVERY_WATERMARK;
    localparam int unsigned _pkg_ref_high     = DEFAULT_HIGH_WATERMARK;
    localparam int unsigned _pkg_ref_chigh    = DEFAULT_CRIT_HIGH_WATERMARK;
    localparam int unsigned _pkg_ref_keep     = DEFAULT_KEEP_WIDTH;
    // Silence unused localparam checks cleanly
    logic _unused_pkg_refs;
    assign _unused_pkg_refs = (_pkg_ref_crit_low == 0) && (_pkg_ref_low == 0) &&
                              (_pkg_ref_rec == 0) && (_pkg_ref_high == 0) &&
                              (_pkg_ref_chigh == 0) && (_pkg_ref_keep == 0);

    // -------------------------------------------------------------------------
    // Internal Interconnects
    // -------------------------------------------------------------------------
    logic                     src_rst_sync_n;
    logic                     dst_rst_sync_n;

    logic                     pkt_fwd_valid;
    logic                     in_packet;
    logic                     packet_error_pulse;

    logic                     flow_enable;

    logic                     fifo_wr_en;
    logic [PAYLOAD_WIDTH-1:0] fifo_wr_data;
    logic                     fifo_wr_overflow;

    logic                     fifo_rd_en;
    logic [PAYLOAD_WIDTH-1:0] fifo_rd_data;
    logic                     fifo_rd_underflow;

    // Silence intentionally exposed internal signals if only probed by SVA
    logic _unused_internal;
    assign _unused_internal = in_packet & packet_error_pulse & _unused_pkg_refs;

    // -------------------------------------------------------------------------
    // Reset Controller
    // -------------------------------------------------------------------------
    reset_controller #(
        .SYNC_STAGES (SYNC_STAGES)
    ) u_reset_controller (
        .src_clk        (src_clk),
        .src_rst_n      (src_rst_n),
        .dst_clk        (dst_clk),
        .dst_rst_n      (dst_rst_n),
        .src_rst_sync_n (src_rst_sync_n),
        .dst_rst_sync_n (dst_rst_sync_n),
        .reset_busy_src (reset_busy_src),
        .reset_busy_dst (reset_busy_dst)
    );

    // -------------------------------------------------------------------------
    // Source-Domain Packet Protocol Checker
    // -------------------------------------------------------------------------
    packet_controller #(
        .DROP_MALFORMED_BEATS (DROP_MALFORMED_BEATS)
    ) u_packet_controller (
        .clk                (src_clk),
        .rst_n              (src_rst_sync_n),
        .clr_errors         (clr_errors),
        .beat_valid         (src_valid),
        .beat_ready         (src_ready),
        .packet_start       (src_packet_start),
        .packet_end         (src_packet_end),
        .fwd_valid          (pkt_fwd_valid),
        .in_packet          (in_packet),
        .packet_error_pulse (packet_error_pulse),
        .packet_error       (packet_error),
        .packets_started    (packets_started),
        .packets_completed  (packets_completed)
    );

    // -------------------------------------------------------------------------
    // Stream Adapter (Ingress Write + Egress 2-Entry Skid Output Controller)
    // -------------------------------------------------------------------------
    stream_adapter #(
        .DATA_WIDTH (DATA_WIDTH),
        .KEEP_WIDTH (KEEP_WIDTH)
    ) u_stream_adapter (
        .src_clk          (src_clk),
        .src_rst_n        (src_rst_sync_n),
        .flow_enable      (flow_enable),
        .reset_busy_src   (reset_busy_src),
        .src_data         (src_data),
        .src_keep         (src_keep),
        .src_valid        (src_valid),
        .src_ready        (src_ready),
        .src_packet_start (src_packet_start),
        .src_packet_end   (src_packet_end),
        .pkt_fwd_valid    (pkt_fwd_valid),
        .fifo_wr_en       (fifo_wr_en),
        .fifo_wr_data     (fifo_wr_data),
        .fifo_wr_full     (fifo_full),

        .dst_clk          (dst_clk),
        .dst_rst_n        (dst_rst_sync_n),
        .reset_busy_dst   (reset_busy_dst),
        .fifo_rd_en       (fifo_rd_en),
        .fifo_rd_data     (fifo_rd_data),
        .fifo_rd_empty    (fifo_empty),
        .dst_data         (dst_data),
        .dst_keep         (dst_keep),
        .dst_valid        (dst_valid),
        .dst_ready        (dst_ready),
        .dst_packet_start (dst_packet_start),
        .dst_packet_end   (dst_packet_end)
    );

    // -------------------------------------------------------------------------
    // Asynchronous Dual-Clock FIFO (CDC Boundary)
    // -------------------------------------------------------------------------
    async_fifo #(
        .DATA_WIDTH  (PAYLOAD_WIDTH),
        .FIFO_DEPTH  (FIFO_DEPTH),
        .SYNC_STAGES (SYNC_STAGES)
    ) u_async_fifo (
        .wr_clk       (src_clk),
        .wr_rst_n     (src_rst_sync_n),
        .wr_en        (fifo_wr_en),
        .wr_data      (fifo_wr_data),
        .wr_full      (fifo_full),
        .wr_overflow  (fifo_wr_overflow),
        .wr_occupancy (src_occupancy),

        .rd_clk       (dst_clk),
        .rd_rst_n     (dst_rst_sync_n),
        .rd_en        (fifo_rd_en),
        .rd_data      (fifo_rd_data),
        .rd_empty     (fifo_empty),
        .rd_underflow (fifo_rd_underflow),
        .rd_occupancy (dst_occupancy)
    );

    // -------------------------------------------------------------------------
    // Occupancy, Watermark & Error Monitor
    // -------------------------------------------------------------------------
    fifo_monitor #(
        .FIFO_DEPTH  (FIFO_DEPTH),
        .SYNC_STAGES (SYNC_STAGES)
    ) u_fifo_monitor (
        .wr_clk             (src_clk),
        .wr_rst_n           (src_rst_sync_n),
        .clr_stats          (clr_stats),
        .wr_occupancy       (src_occupancy),
        .wr_full            (fifo_full),
        .wr_overflow        (fifo_wr_overflow),

        .rd_clk             (dst_clk),
        .rd_rst_n           (dst_rst_sync_n),
        .rd_occupancy       (dst_occupancy),
        .rd_empty           (fifo_empty),
        .rd_underflow       (fifo_rd_underflow),

        .low_wm             (LOW_WATERMARK[PTR_WIDTH-1:0]),
        .high_wm            (HIGH_WATERMARK[PTR_WIDTH-1:0]),

        .almost_full        (almost_full),
        .high_watermark_hit (high_watermark_hit),
        .overflow_error     (overflow_error),
        .overflow_count     (overflow_count),
        .max_occupancy      (max_occupancy),
        .min_occupancy      (min_occupancy),

        .almost_empty       (almost_empty),
        .low_watermark_hit  (low_watermark_hit),
        .underflow_error    (underflow_error),
        .underflow_count    (underflow_count)
    );

    // -------------------------------------------------------------------------
    // Adaptive Rate Controller (Hysteresis Flow-Control FSM)
    // -------------------------------------------------------------------------
    rate_controller #(
        .FIFO_DEPTH (FIFO_DEPTH)
    ) u_rate_controller (
        .clk                (src_clk),
        .rst_n              (src_rst_sync_n),
        .adapt_mode         (adapt_mode),
        .occupancy          (src_occupancy),
        .fifo_full          (fifo_full),
        .crit_low_wm        (CRIT_LOW_WATERMARK[PTR_WIDTH-1:0]),
        .low_wm             (LOW_WATERMARK[PTR_WIDTH-1:0]),
        .recovery_wm        (RECOVERY_WATERMARK[PTR_WIDTH-1:0]),
        .high_wm            (HIGH_WATERMARK[PTR_WIDTH-1:0]),
        .crit_high_wm       (CRIT_HIGH_WATERMARK[PTR_WIDTH-1:0]),
        .current_state      (current_state),
        .flow_enable        (flow_enable),
        .congestion         (congestion),
        .starvation_warning (starvation_warning)
    );

endmodule : top
