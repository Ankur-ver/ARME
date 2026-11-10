// =============================================================================
// File        : rtl/fifo_monitor.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : CDC-safe FIFO occupancy, watermark, and error monitor.
//               Consumes local Gray-derived occupancy vectors (wr_occupancy in
//               wr_clk domain, rd_occupancy in rd_clk domain) without sampling
//               unsynchronized multi-bit remote counters.
//               Cross-domain statistics clear (clr_stats) uses a toggle-pulse
//               synchronizer from wr_clk to rd_clk.
// =============================================================================

`timescale 1ns/1ps

module fifo_monitor #(
    parameter int FIFO_DEPTH  = 1024,
    parameter int SYNC_STAGES = 2,
    localparam int PTR_WIDTH  = $clog2(FIFO_DEPTH) + 1
) (
    // Write Clock Domain
    input  logic                 wr_clk,
    input  logic                 wr_rst_n,
    input  logic                 clr_stats,
    input  logic [PTR_WIDTH-1:0] wr_occupancy,
    input  logic                 wr_full,
    input  logic                 wr_overflow,

    // Read Clock Domain
    input  logic                 rd_clk,
    input  logic                 rd_rst_n,
    input  logic [PTR_WIDTH-1:0] rd_occupancy,
    input  logic                 rd_empty,
    input  logic                 rd_underflow,

    // Configurable Watermarks
    input  logic [PTR_WIDTH-1:0] low_wm,
    input  logic [PTR_WIDTH-1:0] high_wm,

    // Write-Domain Status Outputs
    output logic                 almost_full,
    output logic                 high_watermark_hit,
    output logic                 overflow_error,
    output logic [31:0]          overflow_count,
    output logic [PTR_WIDTH-1:0] max_occupancy,
    output logic [PTR_WIDTH-1:0] min_occupancy,

    // Read-Domain Status Outputs
    output logic                 almost_empty,
    output logic                 low_watermark_hit,
    output logic                 underflow_error,
    output logic [31:0]          underflow_count
);

    localparam logic [PTR_WIDTH-1:0] DEPTH_VAL = FIFO_DEPTH[PTR_WIDTH-1:0];

    // -------------------------------------------------------------------------
    // Write-Domain Monitoring & Toggle Clear Generation
    // -------------------------------------------------------------------------
    logic seen_traffic;
    logic clr_toggle_wr;

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            almost_full        <= 1'b0;
            high_watermark_hit <= 1'b0;
            overflow_error     <= 1'b0;
            overflow_count     <= 32'd0;
            max_occupancy      <= '0;
            min_occupancy      <= DEPTH_VAL;
            seen_traffic       <= 1'b0;
            clr_toggle_wr      <= 1'b0;
        end else begin
            almost_full <= (wr_occupancy >= high_wm) || wr_full;

            if (clr_stats) begin
                clr_toggle_wr      <= ~clr_toggle_wr;
                high_watermark_hit <= (wr_occupancy >= high_wm);
                overflow_error     <= wr_overflow;
                overflow_count     <= wr_overflow ? 32'd1 : 32'd0;
                max_occupancy      <= wr_occupancy;
                min_occupancy      <= (wr_occupancy > '0) ? wr_occupancy : DEPTH_VAL;
                seen_traffic       <= (wr_occupancy > '0);
            end else begin
                if (wr_occupancy >= high_wm) begin
                    high_watermark_hit <= 1'b1;
                end

                if (wr_overflow) begin
                    overflow_error <= 1'b1;
                    overflow_count <= overflow_count + 32'd1;
                end

                if (wr_occupancy > max_occupancy) begin
                    max_occupancy <= wr_occupancy;
                end

                if (wr_occupancy > '0) begin
                    seen_traffic <= 1'b1;
                    if (!seen_traffic || (wr_occupancy < min_occupancy)) begin
                        min_occupancy <= wr_occupancy;
                    end
                end else if (seen_traffic) begin
                    min_occupancy <= '0;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // CDC Toggle Synchronizer for clr_stats (wr_clk -> rd_clk)
    // -------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *)
    logic [SYNC_STAGES-1:0] clr_sync_pipe;
    logic                   clr_sync_prev;
    logic                   clr_pulse_rd;

    assign clr_pulse_rd = clr_sync_pipe[SYNC_STAGES-1] ^ clr_sync_prev;

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            clr_sync_pipe <= '0;
            clr_sync_prev <= 1'b0;
        end else begin
            clr_sync_pipe <= {clr_sync_pipe[SYNC_STAGES-2:0], clr_toggle_wr};
            clr_sync_prev <= clr_sync_pipe[SYNC_STAGES-1];
        end
    end

    // -------------------------------------------------------------------------
    // Read-Domain Monitoring
    // -------------------------------------------------------------------------
    logic seen_read_nonempty;

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            almost_empty       <= 1'b1;
            low_watermark_hit  <= 1'b0;
            underflow_error    <= 1'b0;
            underflow_count    <= 32'd0;
            seen_read_nonempty <= 1'b0;
        end else begin
            almost_empty <= (rd_occupancy <= low_wm) || rd_empty;

            if (rd_occupancy > '0) begin
                seen_read_nonempty <= 1'b1;
            end

            if (clr_pulse_rd) begin
                low_watermark_hit  <= seen_read_nonempty && (rd_occupancy <= low_wm);
                underflow_error    <= rd_underflow;
                underflow_count    <= rd_underflow ? 32'd1 : 32'd0;
                seen_read_nonempty <= (rd_occupancy > '0);
            end else begin
                if (seen_read_nonempty && (rd_occupancy <= low_wm)) begin
                    low_watermark_hit <= 1'b1;
                end

                if (rd_underflow) begin
                    underflow_error <= 1'b1;
                    underflow_count <= underflow_count + 32'd1;
                end
            end
        end
    end

endmodule : fifo_monitor
