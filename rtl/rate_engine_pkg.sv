// =============================================================================
// File        : rtl/rate_engine_pkg.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : Shared synthesizable types, FSM state encodings, and default
//               architectural parameters for the rate-matching subsystem.
// =============================================================================

`timescale 1ns/1ps

package rate_engine_pkg;

    // -------------------------------------------------------------------------
    // Default Subsystem Parameters
    // -------------------------------------------------------------------------
    localparam int unsigned DEFAULT_DATA_WIDTH             = 64;
    localparam int unsigned DEFAULT_KEEP_WIDTH             = DEFAULT_DATA_WIDTH / 8;
    localparam int unsigned DEFAULT_FIFO_DEPTH             = 1024;
    localparam int unsigned DEFAULT_SYNC_STAGES            = 2;

    // Default watermarks (for FIFO_DEPTH = 1024)
    localparam int unsigned DEFAULT_CRIT_LOW_WATERMARK     = 64;
    localparam int unsigned DEFAULT_LOW_WATERMARK          = 256;
    localparam int unsigned DEFAULT_RECOVERY_WATERMARK     = 512;
    localparam int unsigned DEFAULT_HIGH_WATERMARK         = 768;
    localparam int unsigned DEFAULT_CRIT_HIGH_WATERMARK    = 928;

    // -------------------------------------------------------------------------
    // Adaptive Rate Controller FSM States
    // -------------------------------------------------------------------------
    // Explicit 3-bit binary encoding for predictable synthesis and observability.
    typedef enum logic [2:0] {
        CTRL_NORMAL             = 3'd0, // Occupancy in nominal band; full-rate traffic allowed
        CTRL_STARVATION_WARNING = 3'd1, // Occupancy below low watermark; warn downstream/monitor
        CTRL_THROTTLE           = 3'd2, // Occupancy >= HIGH_WATERMARK; duty-cycled pacing
        CTRL_CONGESTION         = 3'd3, // Occupancy >= CRIT_HIGH_WATERMARK; aggressive throttling
        CTRL_RECOVERY           = 3'd4  // Exiting THROTTLE/CONGESTION; hysteresis ramp-back
    } ctrl_state_e;

    // -------------------------------------------------------------------------
    // Packed Status Summary (Source-Domain Synchronized View)
    // -------------------------------------------------------------------------
    typedef struct packed {
        logic        fifo_full;
        logic        fifo_empty;
        logic        almost_full;
        logic        almost_empty;
        logic        congestion;
        logic        starvation_warning;
        logic        overflow_error;
        logic        underflow_error;
        logic        packet_error;
        ctrl_state_e current_state;
    } rate_status_t;

endpackage : rate_engine_pkg

