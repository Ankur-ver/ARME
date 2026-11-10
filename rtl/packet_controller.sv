// =============================================================================
// File        : rtl/packet_controller.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : Source-domain packet protocol checker and framing monitor.
//               Validates packet_start (SOP) and packet_end (EOP) sequencing on
//               accepted beats (valid && ready), tracks active packet state,
//               counts started/completed packets, and flags protocol violations.
//
// Expected Error Behavior:
//   - Illegal SOP/EOP (e.g. EOP without prior SOP, body beat outside packet,
//     or new SOP while already inside an unclosed packet):
//       1. Asserts packet_error_pulse for 1 src_clk cycle.
//       2. Latches sticky packet_error until reset or clr_errors.
//       3. If DROP_MALFORMED_BEATS == 1, suppresses downstream forwarding of
//          the offending beat; if 0 (default), forwards beat with error flagged.
//   - Reset during active packet:
//       in_packet is exposed so reset_controller/assertions can observe mid-
//       packet reset; internal framing state resets cleanly to idle (in_packet=0).
// =============================================================================

`timescale 1ns/1ps

module packet_controller #(
    parameter bit DROP_MALFORMED_BEATS = 1'b0
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        clr_errors,

    // Source Stream Handshake Observation
    input  logic        beat_valid,
    input  logic        beat_ready,
    input  logic        packet_start,
    input  logic        packet_end,

    // Qualified Downstream Write Control
    output logic        fwd_valid,
    output logic        in_packet,
    output logic        packet_error_pulse,
    output logic        packet_error,
    output logic [31:0] packets_started,
    output logic [31:0] packets_completed
);

    logic beat_accept;
    logic malformed_now;
    logic next_in_packet;

    assign beat_accept = beat_valid && beat_ready;

    // Protocol check on accepted beat:
    //   - Outside packet (!in_packet): must assert packet_start.
    //   - Inside packet  ( in_packet): must NOT assert packet_start.
    always_comb begin
        malformed_now  = 1'b0;
        next_in_packet = in_packet;

        if (beat_accept) begin
            if (!in_packet) begin
                if (!packet_start) begin
                    // Body beat or orphan packet_end without packet_start
                    malformed_now = 1'b1;
                end else begin
                    // Legal SOP (single-beat if packet_end also high)
                    next_in_packet = !packet_end;
                end
            end else begin
                if (packet_start) begin
                    // New packet_start before previous packet ended
                    malformed_now  = 1'b1;
                    next_in_packet = !packet_end;
                end else if (packet_end) begin
                    // Normal EOP closes packet
                    next_in_packet = 1'b0;
                end
            end
        end
    end

    assign fwd_valid = beat_accept && !(DROP_MALFORMED_BEATS && malformed_now);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_packet          <= 1'b0;
            packet_error_pulse <= 1'b0;
            packet_error       <= 1'b0;
            packets_started    <= 32'd0;
            packets_completed  <= 32'd0;
        end else begin
            in_packet          <= next_in_packet;
            packet_error_pulse <= malformed_now;

            if (clr_errors) begin
                packet_error <= malformed_now;
            end else if (malformed_now) begin
                packet_error <= 1'b1;
            end

            if (beat_accept && packet_start && !malformed_now) begin
                packets_started <= packets_started + 32'd1;
            end
            if (beat_accept && packet_end && !malformed_now) begin
                packets_completed <= packets_completed + 32'd1;
            end
        end
    end

endmodule : packet_controller

