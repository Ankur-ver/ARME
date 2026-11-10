// =============================================================================
// File        : rtl/reset_controller.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : Dual-domain reset synchronizer and cross-domain release
//               coordinator.
//
// Reset Strategy:
//   1. Coordinated Assertion: Asserting either src_rst_n or dst_rst_n forces
//      comb_rst_n low asynchronously so both sides of async_fifo reset
//      together (preventing single-sided pointer corruption).
//   2. Synchronous Deassertion: Each domain releases its synchronized reset
//      (src_rst_sync_n, dst_rst_sync_n) via a SYNC_STAGES flip-flop chain
//      clocked by its own clock, avoiding recovery/removal metastability.
//   3. Cross-Domain Busy Masking: reset_busy_src and reset_busy_dst remain
//      asserted until the opposite domain's reset release is observed through
//      a 2-stage synchronizer, preventing premature traffic before both halves
//      of the CDC boundary are operational.
// =============================================================================

`timescale 1ns/1ps

module reset_controller #(
    parameter int SYNC_STAGES = 2
) (
    input  logic src_clk,
    input  logic src_rst_n,
    input  logic dst_clk,
    input  logic dst_rst_n,

    output logic src_rst_sync_n,
    output logic dst_rst_sync_n,
    output logic reset_busy_src,
    output logic reset_busy_dst
);

    logic comb_rst_n;
    assign comb_rst_n = src_rst_n & dst_rst_n;

    // -------------------------------------------------------------------------
    // Per-Domain Async-Assert, Sync-Deassert Reset Synchronizers
    // -------------------------------------------------------------------------
    // Keep final output flop separate from shift stages so the async reset
    // tree net is never read as a synchronous data input.
    (* ASYNC_REG = "TRUE" *)
    logic [SYNC_STAGES-2:0] src_rst_pipe;
    (* ASYNC_REG = "TRUE" *)
    logic                   src_rst_sync_q;
    (* ASYNC_REG = "TRUE" *)
    logic [SYNC_STAGES-2:0] dst_rst_pipe;
    (* ASYNC_REG = "TRUE" *)
    logic                   dst_rst_sync_q;

    generate
        if (SYNC_STAGES > 2) begin : gen_multi_rst_sync
            always_ff @(posedge src_clk or negedge comb_rst_n) begin
                if (!comb_rst_n) begin
                    src_rst_pipe   <= '0;
                    src_rst_sync_q <= 1'b0;
                end else begin
                    src_rst_pipe   <= {src_rst_pipe[SYNC_STAGES-3:0], 1'b1};
                    src_rst_sync_q <= src_rst_pipe[SYNC_STAGES-2];
                end
            end

            always_ff @(posedge dst_clk or negedge comb_rst_n) begin
                if (!comb_rst_n) begin
                    dst_rst_pipe   <= '0;
                    dst_rst_sync_q <= 1'b0;
                end else begin
                    dst_rst_pipe   <= {dst_rst_pipe[SYNC_STAGES-3:0], 1'b1};
                    dst_rst_sync_q <= dst_rst_pipe[SYNC_STAGES-2];
                end
            end
        end else begin : gen_2ff_rst_sync
            always_ff @(posedge src_clk or negedge comb_rst_n) begin
                if (!comb_rst_n) begin
                    src_rst_pipe   <= '0;
                    src_rst_sync_q <= 1'b0;
                end else begin
                    src_rst_pipe   <= 1'b1;
                    src_rst_sync_q <= src_rst_pipe[0];
                end
            end

            always_ff @(posedge dst_clk or negedge comb_rst_n) begin
                if (!comb_rst_n) begin
                    dst_rst_pipe   <= '0;
                    dst_rst_sync_q <= 1'b0;
                end else begin
                    dst_rst_pipe   <= 1'b1;
                    dst_rst_sync_q <= dst_rst_pipe[0];
                end
            end
        end
    endgenerate

    assign src_rst_sync_n = src_rst_sync_q;
    assign dst_rst_sync_n = dst_rst_sync_q;

    // -------------------------------------------------------------------------
    // Cross-Domain Release Observation (Prevent Half-Reset Traffic)
    // -------------------------------------------------------------------------
    // Separate 'done' registers avoid using the async-reset net directly as
    // synchronous data, keeping reset trees cleanly separated from data paths.
    logic src_rst_done;
    logic dst_rst_done;

    always_ff @(posedge src_clk or negedge src_rst_sync_n) begin
        if (!src_rst_sync_n) begin
            src_rst_done <= 1'b0;
        end else begin
            src_rst_done <= 1'b1;
        end
    end

    always_ff @(posedge dst_clk or negedge dst_rst_sync_n) begin
        if (!dst_rst_sync_n) begin
            dst_rst_done <= 1'b0;
        end else begin
            dst_rst_done <= 1'b1;
        end
    end

    (* ASYNC_REG = "TRUE" *)
    logic [SYNC_STAGES-1:0] dst_rel_in_src_pipe;
    (* ASYNC_REG = "TRUE" *)
    logic [SYNC_STAGES-1:0] src_rel_in_dst_pipe;

    always_ff @(posedge src_clk or negedge src_rst_sync_n) begin
        if (!src_rst_sync_n) begin
            dst_rel_in_src_pipe <= '0;
        end else begin
            dst_rel_in_src_pipe <= {dst_rel_in_src_pipe[SYNC_STAGES-2:0], dst_rst_done};
        end
    end

    always_ff @(posedge dst_clk or negedge dst_rst_sync_n) begin
        if (!dst_rst_sync_n) begin
            src_rel_in_dst_pipe <= '0;
        end else begin
            src_rel_in_dst_pipe <= {src_rel_in_dst_pipe[SYNC_STAGES-2:0], src_rst_done};
        end
    end

    assign reset_busy_src = !src_rst_sync_n || !dst_rel_in_src_pipe[SYNC_STAGES-1];
    assign reset_busy_dst = !dst_rst_sync_n || !src_rel_in_dst_pipe[SYNC_STAGES-1];

endmodule : reset_controller
