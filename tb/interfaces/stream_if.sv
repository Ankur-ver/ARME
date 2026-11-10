// =============================================================================
// File        : tb/interfaces/stream_if.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : Reusable valid/ready packetized streaming interface.
//
// Protocol Contract:
//   1. A beat transfer occurs strictly on rising clk edge when (valid && ready).
//   2. When (valid && !ready), the producer MUST hold data, keep, packet_start,
//      and packet_end stable until ready is sampled high.
//   3. packet_start marks the first beat of a packet; packet_end marks the
//      final beat of a packet. Single-beat packets assert both simultaneously.
//   4. During reset (!rst_n), valid and ready are deasserted.
// =============================================================================

interface stream_if #(
    parameter int DATA_WIDTH = 64,
    parameter int KEEP_WIDTH = (DATA_WIDTH / 8)
) (
    input logic clk,
    input logic rst_n
);

    logic [DATA_WIDTH-1:0] data;
    logic [KEEP_WIDTH-1:0] keep;
    logic                  valid;
    logic                  ready;
    logic                  packet_start;
    logic                  packet_end;

    // -------------------------------------------------------------------------
    // Synthesizable Modports
    // -------------------------------------------------------------------------
    modport source (
        input  clk,
        input  rst_n,
        input  ready,
        output data,
        output keep,
        output valid,
        output packet_start,
        output packet_end
    );

    modport sink (
        input  clk,
        input  rst_n,
        input  data,
        input  keep,
        input  valid,
        input  packet_start,
        input  packet_end,
        output ready
    );

    modport monitor (
        input clk,
        input rst_n,
        input data,
        input keep,
        input valid,
        input ready,
        input packet_start,
        input packet_end
    );

    // -------------------------------------------------------------------------
    // Simulation Clocking Blocks (Excluded from Synthesis & Icarus Verilog)
    // -------------------------------------------------------------------------
`ifndef SYNTHESIS
`ifndef __ICARUS__
    clocking drv_cb @(posedge clk);
        default input #1step output #1ns;
        output data, keep, valid, packet_start, packet_end;
        input  ready, rst_n;
    endclocking

    clocking sink_cb @(posedge clk);
        default input #1step output #1ns;
        input  data, keep, valid, packet_start, packet_end, rst_n;
        output ready;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1step;
        input data, keep, valid, ready, packet_start, packet_end, rst_n;
    endclocking
`endif
`endif

endinterface : stream_if

