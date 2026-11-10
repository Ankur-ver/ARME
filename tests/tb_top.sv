// =============================================================================
// File        : tests/tb_top.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : Phase 7 self-checking full-subsystem SystemVerilog testbench.
//               Supports directed, constrained-random, clock-mismatch,
//               backpressure, hysteresis, reset, error-injection, and
//               CSV-instrumented performance experiments via plusargs:
//                 +TEST=<name|all>
//                 +SEED=<int>
//                 +ADAPT_MODE=<0|1|2>
//                 +SRC_MHZ=<real> +DST_MHZ=<real>
//                 +TRACE_CSV=<path> +METRICS_CSV=<path>
// =============================================================================

`timescale 1ns/1ps

module tb_top;
    import rate_engine_pkg::*;

    // -------------------------------------------------------------------------
    // Overridable Parameters (Use -P tb_top.P_FIFO_DEPTH=... for Exp E)
    // -------------------------------------------------------------------------
    parameter int P_DATA_WIDTH = 64;
    parameter int P_KEEP_WIDTH = (P_DATA_WIDTH / 8);
    parameter int P_FIFO_DEPTH = 1024;
    parameter int P_SYNC_STAGES = 2;

    localparam int PTR_WIDTH = $clog2(P_FIFO_DEPTH) + 1;
    localparam int REF_CAP   = 65536;

    // -------------------------------------------------------------------------
    // Clocks & Resets
    // -------------------------------------------------------------------------
    logic src_clk = 1'b0;
    logic dst_clk = 1'b0;
    real  src_half_ns = 5.0;   // 100 MHz default
    real  dst_half_ns = 6.25;  // 80 MHz default

    always #(src_half_ns) src_clk = ~src_clk;
    always #(dst_half_ns) dst_clk = ~dst_clk;

    logic src_rst_n = 1'b0;
    logic dst_rst_n = 1'b0;

    // -------------------------------------------------------------------------
    // Stream & Control Signals
    // -------------------------------------------------------------------------
    logic [P_DATA_WIDTH-1:0] src_data = '0;
    logic [P_KEEP_WIDTH-1:0] src_keep = '0;
    logic                    src_valid = 1'b0;
    logic                    src_ready;
    logic                    src_packet_start = 1'b0;
    logic                    src_packet_end   = 1'b0;

    logic [P_DATA_WIDTH-1:0] dst_data;
    logic [P_KEEP_WIDTH-1:0] dst_keep;
    logic                    dst_valid;
    logic                    dst_ready = 1'b1;
    logic                    dst_packet_start;
    logic                    dst_packet_end;

    logic [1:0]              adapt_mode = 2'd2;
    logic                    clr_stats  = 1'b0;
    logic                    clr_errors = 1'b0;

    // Status Outputs
    logic                    fifo_full;
    logic                    fifo_empty;
    logic                    almost_full;
    logic                    almost_empty;
    logic                    congestion;
    logic                    starvation_warning;
    logic                    high_watermark_hit;
    logic                    low_watermark_hit;
    logic                    overflow_error;
    logic                    underflow_error;
    logic                    packet_error;
    logic [31:0]             overflow_count;
    logic [31:0]             underflow_count;
    logic [31:0]             packets_started;
    logic [31:0]             packets_completed;
    ctrl_state_e             current_state;
    logic [PTR_WIDTH-1:0]    src_occupancy;
    logic [PTR_WIDTH-1:0]    dst_occupancy;
    logic [PTR_WIDTH-1:0]    max_occupancy;
    logic [PTR_WIDTH-1:0]    min_occupancy;
    logic                    reset_busy_src;
    logic                    reset_busy_dst;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    top #(
        .DATA_WIDTH  (P_DATA_WIDTH),
        .KEEP_WIDTH  (P_KEEP_WIDTH),
        .FIFO_DEPTH  (P_FIFO_DEPTH),
        .SYNC_STAGES (P_SYNC_STAGES)
    ) dut (
        .src_clk            (src_clk),
        .src_rst_n          (src_rst_n),
        .src_data           (src_data),
        .src_keep           (src_keep),
        .src_valid          (src_valid),
        .src_ready          (src_ready),
        .src_packet_start   (src_packet_start),
        .src_packet_end     (src_packet_end),
        .dst_clk            (dst_clk),
        .dst_rst_n          (dst_rst_n),
        .dst_data           (dst_data),
        .dst_keep           (dst_keep),
        .dst_valid          (dst_valid),
        .dst_ready          (dst_ready),
        .dst_packet_start   (dst_packet_start),
        .dst_packet_end     (dst_packet_end),
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

    // -------------------------------------------------------------------------
    // Scoreboard & Latency Tracking
    // -------------------------------------------------------------------------
    logic [P_DATA_WIDTH-1:0] exp_data_mem [0:REF_CAP-1];
    logic [P_KEEP_WIDTH-1:0] exp_keep_mem [0:REF_CAP-1];
    logic                    exp_sop_mem  [0:REF_CAP-1];
    logic                    exp_eop_mem  [0:REF_CAP-1];
    real                     exp_time_mem [0:REF_CAP-1];
    int                      exp_pkt_mem  [0:REF_CAP-1];
    int                      exp_beat_mem [0:REF_CAP-1];

    int  exp_head        = 0;
    int  exp_tail        = 0;
    int  exp_count       = 0;
    int  sb_beats_in     = 0;
    int  sb_beats_out    = 0;
    int  sb_pkts_in      = 0;
    int  sb_pkts_out     = 0;
    int  sb_discarded    = 0;
    int  err_count       = 0;
    bit  sb_enable       = 1'b0;
    bit  allow_pkt_err   = 1'b0;

    real latency_sum_ns  = 0.0;
    real latency_max_ns  = 0.0;
    int  latency_samples = 0;

    // FSM observation trackers
    bit seen_normal     = 1'b0;
    bit seen_starve     = 1'b0;
    bit seen_throttle   = 1'b0;
    bit seen_congestion = 1'b0;
    bit seen_recovery   = 1'b0;

    // Optional CSV handles
    int  trace_fd   = 0;
    bit  trace_open = 1'b0;
    real sim_start_ns = 0.0;
    real sim_end_ns   = 0.0;

    // Protocol stability check on DUT output (dst_valid && !dst_ready)
    logic                    prev_dst_stall = 1'b0;
    logic [P_DATA_WIDTH-1:0] prev_dst_data  = '0;
    logic [P_KEEP_WIDTH-1:0] prev_dst_keep  = '0;
    logic                    prev_dst_sop   = 1'b0;
    logic                    prev_dst_eop   = 1'b0;

    always @(posedge dst_clk) begin
        if (!dst_rst_n || reset_busy_dst) begin
            prev_dst_stall <= 1'b0;
        end else begin
            if (prev_dst_stall) begin
                if (!dst_valid) begin
                    $display("[FAIL] Protocol violation: dst_valid dropped before dst_ready at %0t", $time);
                    err_count++;
                end else if (dst_data !== prev_dst_data || dst_keep !== prev_dst_keep ||
                             dst_packet_start !== prev_dst_sop || dst_packet_end !== prev_dst_eop) begin
                    $display("[FAIL] Protocol violation: dst payload/control changed while !dst_ready at %0t", $time);
                    err_count++;
                end
            end
            prev_dst_stall <= (dst_valid && !dst_ready);
            prev_dst_data  <= dst_data;
            prev_dst_keep  <= dst_keep;
            prev_dst_sop   <= dst_packet_start;
            prev_dst_eop   <= dst_packet_end;
        end
    end

    // Source scoreboard capture & trace sampling
    int cur_in_pkt_id  = 1;
    int cur_in_beat_id = 0;

    always @(posedge src_clk) begin
        if (src_rst_n && !reset_busy_src && sb_enable) begin
            case (current_state)
                CTRL_NORMAL:             seen_normal     <= 1'b1;
                CTRL_STARVATION_WARNING: seen_starve     <= 1'b1;
                CTRL_THROTTLE:           seen_throttle   <= 1'b1;
                CTRL_CONGESTION:         seen_congestion <= 1'b1;
                CTRL_RECOVERY:           seen_recovery   <= 1'b1;
                default: ;
            endcase

            if (trace_open) begin
                $fwrite(trace_fd, "%.3f,%0d,%0d,%0d,%0d,%0d\n",
                        $realtime, src_occupancy, current_state,
                        src_valid && src_ready, dst_valid && dst_ready, fifo_full);
            end

            if (src_valid && src_ready) begin
                if (src_packet_start) begin
                    cur_in_beat_id = 0;
                end
                exp_data_mem[exp_tail] = src_data;
                exp_keep_mem[exp_tail] = src_keep;
                exp_sop_mem[exp_tail]  = src_packet_start;
                exp_eop_mem[exp_tail]  = src_packet_end;
                exp_time_mem[exp_tail] = $realtime;
                exp_pkt_mem[exp_tail]  = cur_in_pkt_id;
                exp_beat_mem[exp_tail] = cur_in_beat_id;
                exp_tail = (exp_tail + 1) % REF_CAP;
                exp_count++;
                sb_beats_in++;
                if (src_packet_end) begin
                    sb_pkts_in++;
                    cur_in_pkt_id++;
                    cur_in_beat_id = 0;
                end else begin
                    cur_in_beat_id++;
                end
            end

            if (packet_error && !allow_pkt_err) begin
                $display("[FAIL] Unexpected packet_error asserted at %0t", $time);
                err_count++;
            end
        end
    end

    // Destination scoreboard comparison
    always @(posedge dst_clk) begin
        if (dst_rst_n && !reset_busy_dst && sb_enable) begin
            if (dst_valid && dst_ready) begin
                if (exp_count <= 0) begin
                    $display("[FAIL] Unexpected dst beat data=0x%016h when scoreboard empty at %0t",
                             dst_data, $time);
                    err_count++;
                end else begin
                    logic [P_DATA_WIDTH-1:0] ed;
                    logic [P_KEEP_WIDTH-1:0] ek;
                    logic esop, eeop;
                    real  lat;
                    int   pid, bid;

                    ed   = exp_data_mem[exp_head];
                    ek   = exp_keep_mem[exp_head];
                    esop = exp_sop_mem[exp_head];
                    eeop = exp_eop_mem[exp_head];
                    pid  = exp_pkt_mem[exp_head];
                    bid  = exp_beat_mem[exp_head];
                    lat  = $realtime - exp_time_mem[exp_head];

                    exp_head = (exp_head + 1) % REF_CAP;
                    exp_count--;
                    sb_beats_out++;
                    if (eeop) sb_pkts_out++;

                    latency_sum_ns += lat;
                    latency_samples++;
                    if (lat > latency_max_ns) latency_max_ns = lat;

                    if (dst_data !== ed || dst_keep !== ek ||
                        dst_packet_start !== esop || dst_packet_end !== eeop) begin
                        $display("[FAIL] Scoreboard mismatch pkt=%0d beat=%0d at %0t:", pid, bid, $time);
                        $display("       EXP: data=0x%016h keep=0x%02h sop=%0b eop=%0b", ed, ek, esop, eeop);
                        $display("       ACT: data=0x%016h keep=0x%02h sop=%0b eop=%0b",
                                 dst_data, dst_keep, dst_packet_start, dst_packet_end);
                        err_count++;
                    end
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Helper Tasks
    // -------------------------------------------------------------------------
    int seed = 32'h1357_2468;
    bit bp_enable = 1'b0;
    int bp_on_min = 1, bp_on_max = 8;
    int bp_off_min = 0, bp_off_max = 0;

    // Background backpressure driver
    always begin
        @(negedge dst_clk);
        if (!dst_rst_n || reset_busy_dst) begin
            dst_ready <= 1'b0;
        end else if (!bp_enable) begin
            dst_ready <= 1'b1;
        end else begin
            int on_cyc, off_cyc;
            on_cyc  = bp_on_min  + ($urandom(seed) % (bp_on_max  - bp_on_min  + 1));
            off_cyc = bp_off_min + ($urandom(seed) % (bp_off_max - bp_off_min + 1));
            dst_ready <= 1'b1;
            repeat (on_cyc) begin
                @(negedge dst_clk);
                if (!bp_enable) break;
            end
            if (off_cyc > 0 && bp_enable) begin
                dst_ready <= 1'b0;
                repeat (off_cyc) begin
                    @(negedge dst_clk);
                    if (!bp_enable) break;
                end
            end
        end
    end

    task automatic reset_dut(input bit reset_stats = 1'b1);
        sb_enable        <= 1'b0;
        bp_enable         = 1'b0;
        src_valid        <= 1'b0;
        src_data         <= '0;
        src_keep         <= '0;
        src_packet_start <= 1'b0;
        src_packet_end   <= 1'b0;
        src_rst_n        <= 1'b0;
        dst_rst_n        <= 1'b0;
        repeat (6) @(posedge src_clk);
        repeat (6) @(posedge dst_clk);
        @(negedge src_clk);
        src_rst_n <= 1'b1;
        @(negedge dst_clk);
        dst_rst_n <= 1'b1;
        while (reset_busy_src || reset_busy_dst) begin
            @(posedge src_clk);
        end
        repeat (4) @(posedge src_clk);
        sb_discarded += exp_count;
        exp_head  = 0;
        exp_tail  = 0;
        exp_count = 0;
        if (reset_stats) begin
            seen_normal     = 1'b0;
            seen_starve     = 1'b0;
            seen_throttle   = 1'b0;
            seen_congestion = 1'b0;
            seen_recovery   = 1'b0;
        end
        sb_enable <= 1'b1;
    endtask

    task automatic set_clocks_mhz(input real s_mhz, input real d_mhz);
        src_half_ns = 500.0 / s_mhz;
        dst_half_ns = 500.0 / d_mhz;
    endtask

    task automatic send_packet(input int num_beats, input int ipg_cycles);
        for (int b = 0; b < num_beats; b++) begin
            @(negedge src_clk);
            src_valid        <= 1'b1;
            src_data         <= {32'hA500_0000 + cur_in_pkt_id[31:0], $urandom(seed)};
            src_keep         <= (b == num_beats - 1) ? {{(P_KEEP_WIDTH-1){1'b1}}, 1'b1} : {P_KEEP_WIDTH{1'b1}};
            src_packet_start <= (b == 0);
            src_packet_end   <= (b == num_beats - 1);
            // Hold valid/data stable until accepted on posedge src_clk
            do begin
                @(posedge src_clk);
            end while (!src_ready);
        end
        @(negedge src_clk);
        src_valid        <= 1'b0;
        src_packet_start <= 1'b0;
        src_packet_end   <= 1'b0;
        repeat (ipg_cycles) @(posedge src_clk);
    endtask

    task automatic wait_drain(input int max_dst_cycles);
        int w = 0;
        bp_enable = 1'b0;
        while ((exp_count > 0 || !fifo_empty) && w < max_dst_cycles) begin
            @(posedge dst_clk);
            w++;
        end
        repeat (10) @(posedge dst_clk);
        if (exp_count !== 0) begin
            $display("[FAIL] Drain timeout: %0d beats left in scoreboard!", exp_count);
            err_count++;
        end
    endtask

    // -------------------------------------------------------------------------
    // Named Test Procedures
    // -------------------------------------------------------------------------
    task automatic run_smoke_test();
        $display("[TEST] smoke_test");
        set_clocks_mhz(100.0, 80.0);
        reset_dut();
        repeat (5) send_packet(4, 2);
        wait_drain(500);
    endtask

    task automatic run_basic_transfer_test();
        $display("[TEST] basic_transfer_test");
        set_clocks_mhz(100.0, 100.0);
        reset_dut();
        send_packet(1, 0);   // single-beat packet
        send_packet(2, 1);
        send_packet(8, 0);
        send_packet(32, 3);
        send_packet(1, 1);
        wait_drain(500);
    endtask

    task automatic run_burst_test();
        $display("[TEST] burst_test");
        set_clocks_mhz(120.0, 90.0);
        reset_dut();
        // Short bursts + idle + long bursts
        for (int p = 0; p < 15; p++) send_packet(1 + ($urandom(seed) % 8), 0);
        repeat (40) @(posedge src_clk);
        send_packet(400, 0);
        repeat (20) @(posedge src_clk);
        send_packet(600, 5);
        wait_drain(4000);
    endtask

    task automatic run_backpressure_test();
        $display("[TEST] backpressure_test");
        set_clocks_mhz(100.0, 100.0);
        reset_dut();
        bp_on_min = 1; bp_on_max = 5; bp_off_min = 1; bp_off_max = 12;
        bp_enable = 1'b1;
        for (int p = 0; p < 30; p++) begin
            send_packet(2 + ($urandom(seed) % 24), $urandom(seed) % 4);
        end
        wait_drain(5000);
    endtask

    task automatic run_clock_ratio_test(input string name, input real smhz, input real dmhz, input int pkts);
        $display("[TEST] %s (src=%.1f MHz, dst=%.1f MHz)", name, smhz, dmhz);
        set_clocks_mhz(smhz, dmhz);
        reset_dut();
        bp_on_min = 2; bp_on_max = 10; bp_off_min = 0; bp_off_max = 3;
        bp_enable = 1'b1;
        for (int p = 0; p < pkts; p++) begin
            send_packet(4 + ($urandom(seed) % 32), $urandom(seed) % 3);
        end
        wait_drain(6000);
    endtask

    task automatic run_congestion_hysteresis_test();
        int stall_cycles;
        $display("[TEST] congestion_test (full throttle -> congestion -> recovery -> normal)");
        set_clocks_mhz(125.0, 80.0);
        reset_dut();
        // Force destination stall until FIFO fills past CRIT_HIGH_WATERMARK
        bp_on_min = 1; bp_on_max = 1; bp_off_min = 2000; bp_off_max = 2000;
        bp_enable = 1'b1;
        // Manually stall dst_ready low while blasting packets
        bp_enable = 1'b0;
        @(negedge dst_clk);
        // Hold dst_ready = 0 by temporarily driving via force-free wait:
        // Use bp_enable with 0 on_cyc? Easier: set bp_on=1, bp_off=1500
        bp_on_min = 1; bp_on_max = 1; bp_off_min = 1400; bp_off_max = 1400;
        bp_enable = 1'b1;
        stall_cycles = 0;
        for (int p = 0; p < 25; p++) begin
            send_packet(45, 0);
            stall_cycles += 45;
            if (seen_congestion && seen_throttle) break;
        end
        wait_drain(8000);
        if (!seen_throttle || !seen_congestion || !seen_recovery || !seen_normal) begin
            $display("[FAIL] congestion_test missed FSM states: norm=%0b throt=%0b cong=%0b rec=%0b",
                     seen_normal, seen_throttle, seen_congestion, seen_recovery);
            err_count++;
        end
    endtask

    task automatic run_starvation_test();
        $display("[TEST] starvation_test");
        set_clocks_mhz(50.0, 125.0);
        reset_dut();
        for (int p = 0; p < 10; p++) begin
            send_packet(4, 25);
        end
        wait_drain(2000);
        if (!seen_starve) begin
            $display("[FAIL] starvation_test did not observe CTRL_STARVATION_WARNING");
            err_count++;
        end
    endtask

    task automatic run_reset_tests();
        $display("[TEST] reset_test + reset_during_packet_test");
        set_clocks_mhz(100.0, 83.0);
        reset_dut();
        // Start sending a packet and assert src_rst_n mid-packet (cycle 10)
        for (int b = 0; b < 12; b++) begin
            @(negedge src_clk);
            src_valid        <= 1'b1;
            src_data         <= 64'hDEAD_0000 + {32'h0, b};
            src_keep         <= {P_KEEP_WIDTH{1'b1}};
            src_packet_start <= (b == 0);
            src_packet_end   <= 1'b0;
            @(posedge src_clk);
            if (b == 9) begin
                sb_enable <= 1'b0;
                src_rst_n <= 1'b0;
            end
        end
        repeat (5) @(posedge src_clk);
        src_valid        <= 1'b0;
        src_packet_start <= 1'b0;
        src_packet_end   <= 1'b0;

        // Also test dst_rst_n independent assertion
        reset_dut();
        send_packet(16, 2);
        @(negedge dst_clk);
        sb_enable <= 1'b0;
        dst_rst_n <= 1'b0;
        repeat (5) @(posedge dst_clk);
        reset_dut();

        // Verify clean traffic after resets
        repeat (10) send_packet(8, 1);
        wait_drain(2000);
    endtask

    task automatic run_error_injection_test();
        $display("[TEST] error_injection_test");
        set_clocks_mhz(100.0, 100.0);
        reset_dut();
        allow_pkt_err = 1'b1;
        // Inject illegal EOP without prior SOP
        @(negedge src_clk);
        src_valid        <= 1'b1;
        src_data         <= 64'hBAD0_0001_0000_0001;
        src_keep         <= {P_KEEP_WIDTH{1'b1}};
        src_packet_start <= 1'b0;
        src_packet_end   <= 1'b1;
        do @(posedge src_clk); while (!src_ready);
        @(negedge src_clk);
        src_valid        <= 1'b0;
        src_packet_end   <= 1'b0;
        repeat (3) @(posedge src_clk);
        if (!packet_error) begin
            $display("[FAIL] error_injection_test: packet_error did not assert on orphan EOP!");
            err_count++;
        end
        // Clear errors and verify recovery
        @(negedge src_clk);
        clr_errors <= 1'b1;
        @(posedge src_clk);
        @(negedge src_clk);
        clr_errors <= 1'b0;
        allow_pkt_err = 1'b0;
        wait_drain(500);
        send_packet(4, 1);
        wait_drain(500);
    endtask

    task automatic run_random_stress_test();
        int num_pkts = 160;
        $display("[TEST] random_stress_test (%0d randomized packets, ~2500+ beats)", num_pkts);
        set_clocks_mhz(125.0, 83.0);
        reset_dut();
        bp_on_min = 1; bp_on_max = 12; bp_off_min = 0; bp_off_max = 6;
        bp_enable = 1'b1;
        for (int p = 0; p < num_pkts; p++) begin
            int plen = 1 + ($urandom(seed) % 32);
            int ipg  = (($urandom(seed) % 10) < 3) ? ($urandom(seed) % 6) : 0;
            send_packet(plen, ipg);
        end
        wait_drain(15000);
    endtask

    // -------------------------------------------------------------------------
    // Experiment Workload (Used by Python Performance Benchmark Runner)
    // -------------------------------------------------------------------------
    task automatic run_experiment_workload(
        input real smhz,
        input real dmhz,
        input int  total_beats,
        input int  bp_on,
        input int  bp_off
    );
        int sent = 0;
        set_clocks_mhz(smhz, dmhz);
        reset_dut();
        sim_start_ns = $realtime;
        if (bp_off > 0) begin
            bp_on_min = bp_on; bp_on_max = bp_on;
            bp_off_min = bp_off; bp_off_max = bp_off;
            bp_enable = 1'b1;
        end else begin
            bp_enable = 1'b0;
        end
        while (sent < total_beats) begin
            int plen = (total_beats - sent >= 32) ? 32 : (total_beats - sent);
            send_packet(plen, 0);
            sent += plen;
        end
        wait_drain(total_beats * 10 + 2000);
        sim_end_ns = $realtime;
    endtask

    // -------------------------------------------------------------------------
    // Main Entrypoint
    // -------------------------------------------------------------------------
    string test_name = "all";
    string trace_csv = "";
    string metrics_csv = "";
    int    mode_arg = 2;
    real   arg_smhz = 100.0;
    real   arg_dmhz = 80.0;
    int    arg_beats = 1500;
    int    arg_bp_on = 10;
    int    arg_bp_off = 0;

    initial begin
        if ($value$plusargs("SEED=%d", seed))         $display("[CFG] SEED=%0d", seed);
        if ($value$plusargs("TEST=%s", test_name))    $display("[CFG] TEST=%s", test_name);
        if ($value$plusargs("ADAPT_MODE=%d", mode_arg)) adapt_mode = mode_arg[1:0];
        void'($value$plusargs("SRC_MHZ=%f", arg_smhz));
        void'($value$plusargs("DST_MHZ=%f", arg_dmhz));
        void'($value$plusargs("BEATS=%d", arg_beats));
        void'($value$plusargs("BP_ON=%d", arg_bp_on));
        void'($value$plusargs("BP_OFF=%d", arg_bp_off));

        if ($value$plusargs("TRACE_CSV=%s", trace_csv)) begin
            trace_fd = $fopen(trace_csv, "w");
            if (trace_fd != 0) begin
                trace_open = 1'b1;
                $fwrite(trace_fd, "time_ns,occupancy,state,src_fire,dst_fire,fifo_full\n");
            end
        end

        sim_start_ns = $realtime;

        if (test_name == "all") begin
            run_smoke_test();
            run_basic_transfer_test();
            run_burst_test();
            run_backpressure_test();
            run_clock_ratio_test("source_faster_test", 100.0, 80.0, 30);
            run_clock_ratio_test("destination_faster_test", 80.0, 100.0, 30);
            run_clock_ratio_test("equal_rate_test", 100.0, 100.0, 30);
            run_clock_ratio_test("extreme_rate_mismatch_test", 150.0, 75.0, 40);
            run_congestion_hysteresis_test();
            run_starvation_test();
            run_reset_tests();
            run_error_injection_test();
            run_random_stress_test();
        end else if (test_name == "smoke_test") begin
            run_smoke_test();
        end else if (test_name == "basic_transfer_test") begin
            run_basic_transfer_test();
        end else if (test_name == "burst_test") begin
            run_burst_test();
        end else if (test_name == "backpressure_test") begin
            run_backpressure_test();
        end else if (test_name == "source_faster_test") begin
            run_clock_ratio_test("source_faster_test", 100.0, 80.0, 40);
        end else if (test_name == "destination_faster_test") begin
            run_clock_ratio_test("destination_faster_test", 80.0, 100.0, 40);
        end else if (test_name == "equal_rate_test") begin
            run_clock_ratio_test("equal_rate_test", 100.0, 100.0, 40);
        end else if (test_name == "extreme_rate_mismatch_test") begin
            run_clock_ratio_test("extreme_rate_mismatch_test", 150.0, 75.0, 50);
        end else if (test_name == "fifo_boundary_test" || test_name == "congestion_test") begin
            run_congestion_hysteresis_test();
        end else if (test_name == "starvation_test") begin
            run_starvation_test();
        end else if (test_name == "reset_test" || test_name == "reset_during_packet_test") begin
            run_reset_tests();
        end else if (test_name == "error_injection_test") begin
            run_error_injection_test();
        end else if (test_name == "random_stress_test") begin
            run_random_stress_test();
        end else if (test_name == "experiment") begin
            run_experiment_workload(arg_smhz, arg_dmhz, arg_beats, arg_bp_on, arg_bp_off);
        end else begin
            $display("[FAIL] Unknown TEST=%s", test_name);
            err_count++;
        end

        if (sim_end_ns <= sim_start_ns) sim_end_ns = $realtime;

        if (trace_open) $fclose(trace_fd);

        if ($value$plusargs("METRICS_CSV=%s", metrics_csv)) begin
            int mfd;
            real dur_us, avg_lat, tput_mbps;
            dur_us    = (sim_end_ns - sim_start_ns) / 1000.0;
            avg_lat   = (latency_samples > 0) ? (latency_sum_ns / latency_samples) : 0.0;
            tput_mbps = (dur_us > 0.0) ? ((sb_beats_out * P_DATA_WIDTH) / dur_us) : 0.0;
            mfd = $fopen(metrics_csv, "w");
            if (mfd != 0) begin
                $fwrite(mfd, "test,seed,fifo_depth,adapt_mode,src_mhz,dst_mhz,beats_in,beats_out,pkts_in,pkts_out,avg_lat_ns,max_lat_ns,max_occ,overflow_cnt,underflow_cnt,tput_mbps,errors\n");
                $fwrite(mfd, "%s,%0d,%0d,%0d,%.2f,%.2f,%0d,%0d,%0d,%0d,%.3f,%.3f,%0d,%0d,%0d,%.3f,%0d\n",
                        test_name, seed, P_FIFO_DEPTH, adapt_mode, arg_smhz, arg_dmhz,
                        sb_beats_in, sb_beats_out, sb_pkts_in, sb_pkts_out,
                        avg_lat, latency_max_ns, max_occupancy, overflow_count, underflow_count,
                        tput_mbps, err_count);
                $fclose(mfd);
            end
        end

        $display("==============================================================");
        $display("TB_TOP SUMMARY: TEST=%s SEED=%0d", test_name, seed);
        $display("  Beats In=%0d  Beats Out=%0d  ResetDiscarded=%0d", sb_beats_in, sb_beats_out, sb_discarded);
        $display("  Pkts  In=%0d  Pkts  Out=%0d", sb_pkts_in, sb_pkts_out);
        $display("  MaxOcc=%0d/%0d  AvgLat=%.2fns  MaxLat=%.2fns",
                 max_occupancy, P_FIFO_DEPTH,
                 (latency_samples > 0) ? (latency_sum_ns / latency_samples) : 0.0,
                 latency_max_ns);
        $display("  OverflowCnt=%0d  UnderflowCnt=%0d  Errors=%0d",
                 overflow_count, underflow_count, err_count);
        $display("==============================================================");

        if (err_count == 0 && sb_beats_in > 0 &&
            sb_beats_in == (sb_beats_out + sb_discarded)) begin
            $display("OVERALL STATUS: PASS");
            $finish(0);
        end else begin
            $display("OVERALL STATUS: FAIL");
            $fatal(1, "tb_top failed with %0d errors", err_count);
        end
    end

endmodule : tb_top
