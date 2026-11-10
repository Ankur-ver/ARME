// =============================================================================
// File        : tb/assertions/assertions.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : Phase 11 SystemVerilog Assertions (SVA) verifying protocol
//               stability, FIFO safety invariants, packet framing rules,
//               reset masking, and adaptive controller hysteresis.
//               Intended to be bound to `top` in SVA-capable simulators
//               (Questa / VCS / Xcelium).
// =============================================================================

`timescale 1ns/1ps

module rate_engine_sva #(
    parameter int DATA_WIDTH          = 64,
    parameter int KEEP_WIDTH          = 8,
    parameter int FIFO_DEPTH          = 1024,
    parameter int HIGH_WATERMARK      = 768,
    parameter int CRIT_HIGH_WATERMARK = 928,
    localparam int PTR_WIDTH          = $clog2(FIFO_DEPTH) + 1
) (
    input logic                              src_clk,
    input logic                              src_rst_sync_n,
    input logic                              reset_busy_src,
    input logic [DATA_WIDTH-1:0]             src_data,
    input logic [KEEP_WIDTH-1:0]             src_keep,
    input logic                              src_valid,
    input logic                              src_ready,
    input logic                              src_packet_start,
    input logic                              src_packet_end,

    input logic                              dst_clk,
    input logic                              dst_rst_sync_n,
    input logic                              reset_busy_dst,
    input logic [DATA_WIDTH-1:0]             dst_data,
    input logic [KEEP_WIDTH-1:0]             dst_keep,
    input logic                              dst_valid,
    input logic                              dst_ready,
    input logic                              dst_packet_start,
    input logic                              dst_packet_end,

    input logic                              fifo_wr_en,
    input logic                              fifo_full,
    input logic                              fifo_rd_en,
    input logic                              fifo_empty,
    input logic [1:0]                        adapt_mode,
    input rate_engine_pkg::ctrl_state_e      current_state,
    input logic [PTR_WIDTH-1:0]              src_occupancy
);
    import rate_engine_pkg::*;

    // -------------------------------------------------------------------------
    // 1. Valid/Ready Payload Stability (Source & Destination)
    // -------------------------------------------------------------------------
    property p_src_hold_stable;
        @(posedge src_clk) disable iff (!src_rst_sync_n)
        (src_valid && !src_ready) |=> (src_valid && $stable(src_data) &&
                                       $stable(src_keep) && $stable(src_packet_start) &&
                                       $stable(src_packet_end));
    endproperty
    ast_src_hold_stable: assert property (p_src_hold_stable)
        else $error("SVA FAIL: Source violated valid/ready hold stability");

    property p_dst_hold_stable;
        @(posedge dst_clk) disable iff (!dst_rst_sync_n || reset_busy_dst)
        (dst_valid && !dst_ready) |=> (dst_valid && $stable(dst_data) &&
                                       $stable(dst_keep) && $stable(dst_packet_start) &&
                                       $stable(dst_packet_end));
    endproperty
    ast_dst_hold_stable: assert property (p_dst_hold_stable)
        else $error("SVA FAIL: Destination DUT violated valid/ready hold stability");

    // -------------------------------------------------------------------------
    // 2. FIFO Safety Invariants (No Write When Full, No Read When Empty)
    // -------------------------------------------------------------------------
    property p_no_fifo_write_when_full;
        @(posedge src_clk) disable iff (!src_rst_sync_n)
        !(fifo_wr_en && fifo_full);
    endproperty
    ast_no_fifo_write_when_full: assert property (p_no_fifo_write_when_full)
        else $error("SVA FAIL: FIFO write attempted while full");

    property p_no_fifo_read_when_empty;
        @(posedge dst_clk) disable iff (!dst_rst_sync_n)
        !(fifo_rd_en && fifo_empty);
    endproperty
    ast_no_fifo_read_when_empty: assert property (p_no_fifo_read_when_empty)
        else $error("SVA FAIL: FIFO read attempted while empty");

    // -------------------------------------------------------------------------
    // 3. Reset Masking Invariants
    // -------------------------------------------------------------------------
    property p_reset_masks_src_ready;
        @(posedge src_clk) reset_busy_src |-> !src_ready;
    endproperty
    ast_reset_masks_src_ready: assert property (p_reset_masks_src_ready)
        else $error("SVA FAIL: src_ready high during reset_busy_src");

    property p_reset_masks_dst_valid;
        @(posedge dst_clk) reset_busy_dst |-> !dst_valid;
    endproperty
    ast_reset_masks_dst_valid: assert property (p_reset_masks_dst_valid)
        else $error("SVA FAIL: dst_valid high during reset_busy_dst");

    // -------------------------------------------------------------------------
    // 4. Adaptive Controller Hysteresis & State Consistency
    // -------------------------------------------------------------------------
    // Congestion must step down through THROTTLE/RECOVERY before reaching NORMAL
    property p_no_direct_congestion_to_normal;
        @(posedge src_clk) disable iff (!src_rst_sync_n || adapt_mode != 2'd2)
        (current_state == CTRL_CONGESTION) |=> (current_state != CTRL_NORMAL);
    endproperty
    ast_no_direct_congestion_to_normal: assert property (p_no_direct_congestion_to_normal)
        else $error("SVA FAIL: Controller jumped directly from CONGESTION to NORMAL");

    // Once congested, remain congested while occupancy stays above HIGH_WATERMARK
    property p_congestion_hysteresis_hold;
        @(posedge src_clk) disable iff (!src_rst_sync_n || adapt_mode != 2'd2)
        (current_state == CTRL_CONGESTION && src_occupancy > HIGH_WATERMARK[PTR_WIDTH-1:0])
        |=> (current_state == CTRL_CONGESTION);
    endproperty
    ast_congestion_hysteresis_hold: assert property (p_congestion_hysteresis_hold)
        else $error("SVA FAIL: Controller left CONGESTION above HIGH_WATERMARK");

    // -------------------------------------------------------------------------
    // 5. Egress Packet Framing Consistency (SOP/EOP)
    // -------------------------------------------------------------------------
    logic dst_in_pkt = 1'b0;
    always_ff @(posedge dst_clk or negedge dst_rst_sync_n) begin
        if (!dst_rst_sync_n || reset_busy_dst) begin
            dst_in_pkt <= 1'b0;
        end else if (dst_valid && dst_ready) begin
            if (dst_packet_start && !dst_packet_end) dst_in_pkt <= 1'b1;
            else if (dst_packet_end)                 dst_in_pkt <= 1'b0;
        end
    end

    property p_dst_sop_when_idle;
        @(posedge dst_clk) disable iff (!dst_rst_sync_n || reset_busy_dst)
        (dst_valid && dst_ready && !dst_in_pkt) |-> dst_packet_start;
    endproperty
    ast_dst_sop_when_idle: assert property (p_dst_sop_when_idle)
        else $error("SVA FAIL: Egress beat outside packet missing packet_start");

endmodule : rate_engine_sva

// Bind statement for SVA-capable simulation runs
bind top rate_engine_sva #(
    .DATA_WIDTH          (DATA_WIDTH),
    .KEEP_WIDTH          (KEEP_WIDTH),
    .FIFO_DEPTH          (FIFO_DEPTH),
    .HIGH_WATERMARK      (HIGH_WATERMARK),
    .CRIT_HIGH_WATERMARK (CRIT_HIGH_WATERMARK)
) u_rate_engine_sva (
    .src_clk          (src_clk),
    .src_rst_sync_n   (src_rst_sync_n),
    .reset_busy_src   (reset_busy_src),
    .src_data         (src_data),
    .src_keep         (src_keep),
    .src_valid        (src_valid),
    .src_ready        (src_ready),
    .src_packet_start (src_packet_start),
    .src_packet_end   (src_packet_end),
    .dst_clk          (dst_clk),
    .dst_rst_sync_n   (dst_rst_sync_n),
    .reset_busy_dst   (reset_busy_dst),
    .dst_data         (dst_data),
    .dst_keep         (dst_keep),
    .dst_valid        (dst_valid),
    .dst_ready        (dst_ready),
    .dst_packet_start (dst_packet_start),
    .dst_packet_end   (dst_packet_end),
    .fifo_wr_en       (fifo_wr_en),
    .fifo_full        (fifo_full),
    .fifo_rd_en       (fifo_rd_en),
    .fifo_empty       (fifo_empty),
    .adapt_mode       (adapt_mode),
    .current_state    (current_state),
    .src_occupancy    (src_occupancy)
);

