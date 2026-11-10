// =============================================================================
// File        : rtl/stream_adapter.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : Bridges valid/ready packetized streams to/from async_fifo.
//               - Ingress (src_clk): Packs {packet_start, packet_end, keep, data}
//                 into a single atomic FIFO word and drives src_ready without
//                 combinational dependence on src_valid.
//               - Egress (dst_clk): 2-entry registered prefetch/skid buffer
//                 compensating for async_fifo's 1-cycle synchronous read latency,
//                 delivering 1 beat/cycle peak throughput while holding dst_*
//                 outputs strictly stable whenever (dst_valid && !dst_ready).
// =============================================================================

`timescale 1ns/1ps

module stream_adapter #(
    parameter int DATA_WIDTH    = 64,
    parameter int KEEP_WIDTH    = (DATA_WIDTH / 8),
    localparam int PAYLOAD_WIDTH = DATA_WIDTH + KEEP_WIDTH + 2
) (
    // -------------------------------------------------------------------------
    // Source Domain (Ingress)
    // -------------------------------------------------------------------------
    input  logic                     src_clk,
    input  logic                     src_rst_n,
    input  logic                     flow_enable,
    input  logic                     reset_busy_src,

    input  logic [DATA_WIDTH-1:0]    src_data,
    input  logic [KEEP_WIDTH-1:0]    src_keep,
    input  logic                     src_valid,
    output logic                     src_ready,
    input  logic                     src_packet_start,
    input  logic                     src_packet_end,
    input  logic                     pkt_fwd_valid,

    output logic                     fifo_wr_en,
    output logic [PAYLOAD_WIDTH-1:0] fifo_wr_data,
    input  logic                     fifo_wr_full,

    // -------------------------------------------------------------------------
    // Destination Domain (Egress)
    // -------------------------------------------------------------------------
    input  logic                     dst_clk,
    input  logic                     dst_rst_n,
    input  logic                     reset_busy_dst,

    output logic                     fifo_rd_en,
    input  logic [PAYLOAD_WIDTH-1:0] fifo_rd_data,
    input  logic                     fifo_rd_empty,

    output logic [DATA_WIDTH-1:0]    dst_data,
    output logic [KEEP_WIDTH-1:0]    dst_keep,
    output logic                     dst_valid,
    input  logic                     dst_ready,
    output logic                     dst_packet_start,
    output logic                     dst_packet_end
);

    // -------------------------------------------------------------------------
    // Ingress Bridge (src_clk)
    // -------------------------------------------------------------------------
    // Note: src_ready has NO combinational dependence on src_valid.
    assign src_ready = src_rst_n && !reset_busy_src && !fifo_wr_full && flow_enable;

    // Pack control metadata atomically with beat data
    assign fifo_wr_data = {src_packet_start, src_packet_end, src_keep, src_data};
    assign fifo_wr_en   = pkt_fwd_valid && !fifo_wr_full && !reset_busy_src;

    // Unused warning guard if src_clk not directly needed for combinational ingress
    logic _unused_src_clk;
    assign _unused_src_clk = src_clk & src_valid;

    // -------------------------------------------------------------------------
    // Egress 2-Entry Skid / Prefetch Buffer (dst_clk)
    // -------------------------------------------------------------------------
    logic [PAYLOAD_WIDTH-1:0] skid_mem [0:1];
    logic [1:0]               skid_count;
    logic                     rd_pipe_valid;

    logic push_from_fifo;
    logic pop_to_dst;
    logic [2:0] inflight_after_pop;

    assign dst_valid = (skid_count != 2'd0) && !reset_busy_dst;

    // Unpack head-of-skid entry
    assign {dst_packet_start, dst_packet_end, dst_keep, dst_data} = skid_mem[0];

    assign push_from_fifo = rd_pipe_valid;
    assign pop_to_dst     = dst_valid && dst_ready;

    // In-flight entries that will remain in skid after any concurrent pop
    assign inflight_after_pop = {1'b0, skid_count}
                              + {2'b0, push_from_fifo}
                              - {2'b0, pop_to_dst};

    // Prefetch next FIFO word whenever fewer than 2 slots will be occupied
    assign fifo_rd_en = dst_rst_n && !reset_busy_dst && !fifo_rd_empty
                      && (inflight_after_pop < 3'd2);

    always_ff @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            skid_mem[0]   <= '0;
            skid_mem[1]   <= '0;
            skid_count    <= 2'd0;
            rd_pipe_valid <= 1'b0;
        end else if (reset_busy_dst) begin
            skid_mem[0]   <= '0;
            skid_mem[1]   <= '0;
            skid_count    <= 2'd0;
            rd_pipe_valid <= 1'b0;
        end else begin
            rd_pipe_valid <= fifo_rd_en && !fifo_rd_empty;

            case ({push_from_fifo, pop_to_dst})
                2'b10: begin
                    // Push only: place at current tail (skid_count is 0 or 1)
                    if (skid_count == 2'd0) begin
                        skid_mem[0] <= fifo_rd_data;
                    end else begin
                        skid_mem[1] <= fifo_rd_data;
                    end
                    skid_count <= skid_count + 2'd1;
                end
                2'b01: begin
                    // Pop only: shift entry 1 -> 0
                    skid_mem[0] <= skid_mem[1];
                    skid_count  <= skid_count - 2'd1;
                end
                2'b11: begin
                    // Simultaneous push and pop: count unchanged
                    if (skid_count == 2'd1) begin
                        skid_mem[0] <= fifo_rd_data;
                    end else begin
                        // skid_count == 2: shift [1]->[0], store new into [1]
                        skid_mem[0] <= skid_mem[1];
                        skid_mem[1] <= fifo_rd_data;
                    end
                end
                default: begin
                    // Hold steady
                end
            endcase
        end
    end

endmodule : stream_adapter
