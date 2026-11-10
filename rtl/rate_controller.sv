// =============================================================================
// File        : rtl/rate_controller.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : Source-domain adaptive flow-control FSM with hysteresis.
//               Observes synchronized FIFO occupancy (wr_occupancy) and drives
//               registered flow_enable to throttle source traffic smoothly
//               without oscillation around watermark boundaries.
//
// Modes (adapt_mode):
//   2'd0 : MODE_BYPASS          - No throttling (flow_enable = 1)
//   2'd1 : MODE_FIXED_THRESHOLD - Hard cutoff at high_wm (no hysteresis)
//   2'd2 : MODE_HYSTERESIS      - 5-state adaptive hysteresis FSM (default)
// =============================================================================

`timescale 1ns/1ps

module rate_controller
    import rate_engine_pkg::*;
#(
    parameter int FIFO_DEPTH = 1024,
    localparam int PTR_WIDTH = $clog2(FIFO_DEPTH) + 1
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic [1:0]           adapt_mode,
    input  logic [PTR_WIDTH-1:0] occupancy,
    input  logic                 fifo_full,

    // Configurable Watermarks
    input  logic [PTR_WIDTH-1:0] crit_low_wm,
    input  logic [PTR_WIDTH-1:0] low_wm,
    input  logic [PTR_WIDTH-1:0] recovery_wm,
    input  logic [PTR_WIDTH-1:0] high_wm,
    input  logic [PTR_WIDTH-1:0] crit_high_wm,

    // Control & Status Outputs
    output ctrl_state_e          current_state,
    output logic                 flow_enable,
    output logic                 congestion,
    output logic                 starvation_warning
);

    // Derived hysteresis exit thresholds
    logic [PTR_WIDTH-1:0] low_exit_wm;
    logic [PTR_WIDTH-1:0] throttle_exit_wm;

    assign low_exit_wm      = (low_wm + recovery_wm) >> 1;
    assign throttle_exit_wm = (high_wm + recovery_wm) >> 1;

    ctrl_state_e next_state;
    logic [1:0]  pace_cnt;
    logic        next_flow_enable;

    // -------------------------------------------------------------------------
    // Next-State Logic with Asymmetric Entry/Exit Thresholds (Hysteresis)
    // -------------------------------------------------------------------------
    always_comb begin
        next_state = current_state;

        if (adapt_mode == 2'd0) begin
            next_state = CTRL_NORMAL;
        end else if (adapt_mode == 2'd1) begin
            // Fixed single-threshold baseline (for Experiment D comparison)
            if (occupancy >= high_wm) begin
                next_state = CTRL_THROTTLE;
            end else begin
                next_state = CTRL_NORMAL;
            end
        end else begin
            unique case (current_state)
                CTRL_NORMAL: begin
                    if (occupancy >= crit_high_wm) begin
                        next_state = CTRL_CONGESTION;
                    end else if (occupancy >= high_wm) begin
                        next_state = CTRL_THROTTLE;
                    end else if (occupancy <= low_wm) begin
                        next_state = CTRL_STARVATION_WARNING;
                    end
                end

                CTRL_STARVATION_WARNING: begin
                    if (occupancy >= crit_high_wm) begin
                        next_state = CTRL_CONGESTION;
                    end else if (occupancy >= high_wm) begin
                        next_state = CTRL_THROTTLE;
                    end else if (occupancy > low_exit_wm) begin
                        next_state = CTRL_NORMAL;
                    end
                end

                CTRL_THROTTLE: begin
                    if (occupancy >= crit_high_wm) begin
                        next_state = CTRL_CONGESTION;
                    end else if (occupancy < throttle_exit_wm) begin
                        next_state = CTRL_RECOVERY;
                    end
                end

                CTRL_CONGESTION: begin
                    // Must drop below high_wm (not crit_high_wm) to step down
                    if (occupancy <= high_wm) begin
                        next_state = CTRL_THROTTLE;
                    end
                end

                CTRL_RECOVERY: begin
                    if (occupancy >= crit_high_wm) begin
                        next_state = CTRL_CONGESTION;
                    end else if (occupancy >= high_wm) begin
                        next_state = CTRL_THROTTLE;
                    end else if (occupancy <= recovery_wm) begin
                        next_state = CTRL_NORMAL;
                    end
                end

                default: begin
                    next_state = CTRL_NORMAL;
                end
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Pacing Duty-Cycle Selection
    // -------------------------------------------------------------------------
    always_comb begin
        if (adapt_mode == 2'd0) begin
            next_flow_enable = 1'b1;
        end else if (adapt_mode == 2'd1) begin
            next_flow_enable = (occupancy < high_wm);
        end else begin
            unique case (next_state)
                CTRL_NORMAL:             next_flow_enable = 1'b1;
                CTRL_STARVATION_WARNING: next_flow_enable = 1'b1;
                CTRL_RECOVERY:           next_flow_enable = (pace_cnt != 2'd3);        // 75% rate
                CTRL_THROTTLE:           next_flow_enable = ((pace_cnt & 2'b01) == 2'b00); // 50% rate
                CTRL_CONGESTION:         next_flow_enable = (pace_cnt == 2'd0) && !fifo_full; // <=25% rate
                default:                 next_flow_enable = 1'b1;
            endcase
        end
    end

    // Unused warning guard on crit_low_wm (used in starvation criticality check)
    logic _unused_crit_low;
    assign _unused_crit_low = &{1'b0, crit_low_wm};

    // -------------------------------------------------------------------------
    // State, Pacing Counter, and Registered Control Outputs
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state      <= CTRL_NORMAL;
            pace_cnt           <= 2'd0;
            flow_enable        <= 1'b0;
            congestion         <= 1'b0;
            starvation_warning <= 1'b0;
        end else begin
            current_state      <= next_state;
            pace_cnt           <= pace_cnt + 2'd1;
            flow_enable        <= next_flow_enable;
            congestion         <= (next_state == CTRL_CONGESTION);
            starvation_warning <= (next_state == CTRL_STARVATION_WARNING) &&
                                  (occupancy <= crit_low_wm || occupancy <= low_wm);
        end
    end

endmodule : rate_controller
