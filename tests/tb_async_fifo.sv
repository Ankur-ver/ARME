// =============================================================================
// File        : tests/tb_async_fifo.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : Phase 3 standalone self-checking CDC testbench for async_fifo.
//               Tests reset state, full/overflow, empty/underflow, pointer
//               wrap-around, Gray-code single-bit transitions, conservative
//               occupancy bounds, mid-traffic reset, and multiple clock ratios
//               (100/80, 80/100, 150/75, and 125/83 MHz non-integer).
// =============================================================================

`timescale 1ns/1ps

module tb_async_fifo;

    localparam int DATA_WIDTH  = 64;
    localparam int FIFO_DEPTH  = 16;
    localparam int SYNC_STAGES = 2;
    localparam int PTR_WIDTH   = $clog2(FIFO_DEPTH) + 1;
    localparam int REF_CAP     = 16384;

    // -------------------------------------------------------------------------
    // Clocks & Resets
    // -------------------------------------------------------------------------
    logic wr_clk = 1'b0;
    logic rd_clk = 1'b0;
    real  wr_half_period_ns = 5.0;   // 100 MHz default
    real  rd_half_period_ns = 6.25;  // 80 MHz default

    always #(wr_half_period_ns) wr_clk = ~wr_clk;
    always #(rd_half_period_ns) rd_clk = ~rd_clk;

    logic wr_rst_n = 1'b0;
    logic rd_rst_n = 1'b0;

    // -------------------------------------------------------------------------
    // DUT Interface Signals
    // -------------------------------------------------------------------------
    logic                  wr_en   = 1'b0;
    logic [DATA_WIDTH-1:0] wr_data = '0;
    logic                  wr_full;
    logic                  wr_overflow;
    logic [PTR_WIDTH-1:0]  wr_occupancy;

    logic                  rd_en   = 1'b0;
    logic [DATA_WIDTH-1:0] rd_data;
    logic                  rd_empty;
    logic                  rd_underflow;
    logic [PTR_WIDTH-1:0]  rd_occupancy;

    async_fifo #(
        .DATA_WIDTH  (DATA_WIDTH),
        .FIFO_DEPTH  (FIFO_DEPTH),
        .SYNC_STAGES (SYNC_STAGES)
    ) dut (
        .wr_clk       (wr_clk),
        .wr_rst_n     (wr_rst_n),
        .wr_en        (wr_en),
        .wr_data      (wr_data),
        .wr_full      (wr_full),
        .wr_overflow  (wr_overflow),
        .wr_occupancy (wr_occupancy),
        .rd_clk       (rd_clk),
        .rd_rst_n     (rd_rst_n),
        .rd_en        (rd_en),
        .rd_data      (rd_data),
        .rd_empty     (rd_empty),
        .rd_underflow (rd_underflow),
        .rd_occupancy (rd_occupancy)
    );

    // -------------------------------------------------------------------------
    // Scoreboard Ring Buffer & Counters
    // -------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] ref_mem [0:REF_CAP-1];
    int ref_head  = 0;
    int ref_tail  = 0;
    int ref_count = 0;

    int total_written            = 0;
    int total_read               = 0;
    int total_discarded_by_reset = 0;
    int err_count                = 0;
    int seed          = 32'h2026_1110;

    // Track Gray-code single-bit transition invariant
    logic [PTR_WIDTH-1:0] prev_wr_gray = '0;
    logic [PTR_WIDTH-1:0] prev_rd_gray = '0;
    logic                 wr_gray_init = 1'b0;
    logic                 rd_gray_init = 1'b0;

    always @(posedge wr_clk) begin
        if (!wr_rst_n) begin
            wr_gray_init <= 1'b0;
            prev_wr_gray <= '0;
        end else begin
            if (wr_gray_init) begin
                logic [PTR_WIDTH-1:0] diff;
                int ones;
                diff = dut.wr_ptr_gray ^ prev_wr_gray;
                ones = $countones(diff);
                if (ones > 1) begin
                    $display("[FAIL] Write Gray pointer changed %0d bits: %b -> %b at %0t",
                             ones, prev_wr_gray, dut.wr_ptr_gray, $time);
                    err_count++;
                end
            end
            prev_wr_gray <= dut.wr_ptr_gray;
            wr_gray_init <= 1'b1;

            if (wr_occupancy > FIFO_DEPTH[PTR_WIDTH-1:0]) begin
                $display("[FAIL] wr_occupancy (%0d) exceeded FIFO_DEPTH (%0d) at %0t",
                         wr_occupancy, FIFO_DEPTH, $time);
                err_count++;
            end
        end
    end

    always @(posedge rd_clk) begin
        if (!rd_rst_n) begin
            rd_gray_init <= 1'b0;
            prev_rd_gray <= '0;
        end else begin
            if (rd_gray_init) begin
                logic [PTR_WIDTH-1:0] diff;
                int ones;
                diff = dut.rd_ptr_gray ^ prev_rd_gray;
                ones = $countones(diff);
                if (ones > 1) begin
                    $display("[FAIL] Read Gray pointer changed %0d bits: %b -> %b at %0t",
                             ones, prev_rd_gray, dut.rd_ptr_gray, $time);
                    err_count++;
                end
            end
            prev_rd_gray <= dut.rd_ptr_gray;
            rd_gray_init <= 1'b1;

            if (rd_occupancy > FIFO_DEPTH[PTR_WIDTH-1:0]) begin
                $display("[FAIL] rd_occupancy (%0d) exceeded FIFO_DEPTH (%0d) at %0t",
                         rd_occupancy, FIFO_DEPTH, $time);
                err_count++;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Reference Push & Pop Checkers
    // -------------------------------------------------------------------------
    logic rd_valid_q = 1'b0;
    logic monitor_en = 1'b0;

    always @(posedge wr_clk) begin
        if (wr_rst_n && monitor_en) begin
            if (wr_en && !wr_full) begin
                ref_mem[ref_tail] = wr_data;
                ref_tail = (ref_tail + 1) % REF_CAP;
                ref_count++;
                total_written++;
            end
        end
    end

    always @(posedge rd_clk) begin
        if (!rd_rst_n) begin
            rd_valid_q <= 1'b0;
        end else begin
            if (rd_valid_q && monitor_en) begin
                if (ref_count <= 0) begin
                    $display("[FAIL] Spurious read data=0x%016h when ref_count=0 at %0t",
                             rd_data, $time);
                    err_count++;
                end else begin
                    logic [DATA_WIDTH-1:0] exp_data;
                    exp_data = ref_mem[ref_head];
                    ref_head = (ref_head + 1) % REF_CAP;
                    ref_count--;
                    total_read++;
                    if (rd_data !== exp_data) begin
                        $display("[FAIL] Data mismatch beat #%0d: expected=0x%016h actual=0x%016h at %0t",
                                 total_read, exp_data, rd_data, $time);
                        err_count++;
                    end
                end
            end
            rd_valid_q <= (rd_en && !rd_empty && monitor_en);
        end
    end

    // -------------------------------------------------------------------------
    // Helper Tasks
    // -------------------------------------------------------------------------
    task automatic apply_reset();
        monitor_en <= 1'b0;
        wr_en      <= 1'b0;
        rd_en      <= 1'b0;
        wr_data    <= '0;
        wr_rst_n   <= 1'b0;
        rd_rst_n   <= 1'b0;
        repeat (5) @(posedge wr_clk);
        repeat (5) @(posedge rd_clk);
        @(negedge wr_clk);
        wr_rst_n <= 1'b1;
        @(negedge rd_clk);
        rd_rst_n <= 1'b1;
        repeat (4) @(posedge wr_clk);
        repeat (4) @(posedge rd_clk);
        total_discarded_by_reset += ref_count;
        ref_head   = 0;
        ref_tail   = 0;
        ref_count  = 0;
        monitor_en <= 1'b1;
    endtask

    task automatic run_random_cdc(
        input string label,
        input real   w_half_ns,
        input real   r_half_ns,
        input int    num_wr_cycles,
        input int    wr_prob_pct,
        input int    rd_prob_pct
    );
        int wr_active_done = 0;
        logic [63:0] seq_num = 64'h1;

        $display("[INFO] Starting CDC stress '%s' (wr_half=%.3fns, rd_half=%.3fns, cycles=%0d)",
                 label, w_half_ns, r_half_ns, num_wr_cycles);

        wr_half_period_ns = w_half_ns;
        rd_half_period_ns = r_half_ns;
        apply_reset();

        fork
            begin : wr_thread
                for (int c = 0; c < num_wr_cycles; c++) begin
                    @(negedge wr_clk);
                    if (!wr_full && (($urandom(seed) % 100) < wr_prob_pct)) begin
                        wr_en   <= 1'b1;
                        wr_data <= {seq_num[31:0], $urandom(seed)};
                        seq_num++;
                    end else begin
                        wr_en <= 1'b0;
                    end
                end
                @(negedge wr_clk);
                wr_en <= 1'b0;
                wr_active_done = 1;
            end

            begin : rd_thread
                while (!wr_active_done || !rd_empty || ref_count > 0) begin
                    @(negedge rd_clk);
                    if (!rd_empty && (wr_active_done || (($urandom(seed) % 100) < rd_prob_pct))) begin
                        rd_en <= 1'b1;
                    end else begin
                        rd_en <= 1'b0;
                    end
                end
                @(negedge rd_clk);
                rd_en <= 1'b0;
            end
        join

        // Allow final read pipeline cycle to flush
        repeat (4) @(posedge rd_clk);
        if (ref_count !== 0 || !rd_empty) begin
            $display("[FAIL] '%s' did not drain cleanly: ref_count=%0d rd_empty=%0b",
                     label, ref_count, rd_empty);
            err_count++;
        end else begin
            $display("[PASS] '%s' completed cleanly.", label);
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        if ($value$plusargs("SEED=%d", seed)) begin
            $display("[INFO] Using plusarg SEED=%0d", seed);
        end else begin
            $display("[INFO] Using default SEED=%0d", seed);
        end

        // 1. Reset State Verification
        apply_reset();
        if (wr_full !== 1'b0 || rd_empty !== 1'b1 || wr_occupancy !== '0 || rd_occupancy !== '0) begin
            $display("[FAIL] Post-reset flags invalid: full=%0b empty=%0b wr_occ=%0d rd_occ=%0d",
                     wr_full, rd_empty, wr_occupancy, rd_occupancy);
            err_count++;
        end else begin
            $display("[PASS] Test 1: Reset flags and occupancy verified.");
        end

        // 2. Fill to Full & Overflow Protection
        for (int i = 0; i < FIFO_DEPTH; i++) begin
            @(negedge wr_clk);
            wr_en   <= 1'b1;
            wr_data <= 64'hCAFE_0000_0000_0000 + {32'h0, i};
        end
        @(negedge wr_clk);
        wr_en <= 1'b0;
        @(posedge wr_clk);
        if (wr_full !== 1'b1) begin
            $display("[FAIL] Test 2: Expected wr_full=1 after %0d writes, got %0b", FIFO_DEPTH, wr_full);
            err_count++;
        end
        // Attempt 3 illegal writes while full
        for (int i = 0; i < 3; i++) begin
            @(negedge wr_clk);
            wr_en   <= 1'b1;
            wr_data <= 64'hDEAD_BEEF_BAD0_0000 + {32'h0, i};
            @(posedge wr_clk);
        end
        @(posedge wr_clk);
        if (wr_overflow !== 1'b1) begin
            $display("[FAIL] Test 2: Expected wr_overflow=1 when writing full FIFO");
            err_count++;
        end
        @(negedge wr_clk);
        wr_en <= 1'b0;
        repeat (4) @(posedge rd_clk); // Let Gray ptr sync settle
        $display("[PASS] Test 2: Fill-to-full and overflow protection verified.");

        // 3. Drain to Empty & Underflow Protection
        for (int i = 0; i < FIFO_DEPTH; i++) begin
            @(negedge rd_clk);
            rd_en <= 1'b1;
        end
        @(negedge rd_clk);
        rd_en <= 1'b0;
        repeat (3) @(posedge rd_clk);
        if (rd_empty !== 1'b1 || ref_count !== 0) begin
            $display("[FAIL] Test 3: Expected rd_empty=1 and ref_count=0 after drain, got empty=%0b ref=%0d",
                     rd_empty, ref_count);
            err_count++;
        end
        // Attempt illegal read while empty
        @(negedge rd_clk);
        rd_en <= 1'b1;
        @(posedge rd_clk);
        @(posedge rd_clk);
        if (rd_underflow !== 1'b1) begin
            $display("[FAIL] Test 3: Expected rd_underflow=1 when reading empty FIFO");
            err_count++;
        end
        @(negedge rd_clk);
        rd_en <= 1'b0;
        $display("[PASS] Test 3: Drain-to-empty and underflow protection verified.");

        // 4. Multi-Ratio CDC Randomized Stress Tests
        run_random_cdc("Case1_SrcFaster_100M_80M",   5.0,   6.25,  600, 85, 90);
        run_random_cdc("Case2_DstFaster_80M_100M",   6.25,  5.0,   600, 80, 95);
        run_random_cdc("Case3_EqualRate_100M_100M",  5.0,   5.0,   600, 75, 75);
        run_random_cdc("Case4_Extreme_150M_75M",     3.333, 6.667, 600, 90, 85);
        run_random_cdc("Case5_NonInt_125M_83M",      4.0,   6.024, 800, 70, 70);

        // 5. Mid-Operation Reset Recovery Test
        $display("[INFO] Starting Test 5: Mid-operation reset recovery");
        wr_half_period_ns = 5.0;
        rd_half_period_ns = 6.25;
        apply_reset();
        for (int i = 0; i < 10; i++) begin
            @(negedge wr_clk);
            wr_en   <= 1'b1;
            wr_data <= 64'hAAAA_0000 + {32'h0, i};
        end
        @(negedge wr_clk);
        wr_en <= 1'b0;
        // Reset mid-stream and verify clean recovery
        apply_reset();
        run_random_cdc("PostReset_Integrity_Check", 4.5, 5.5, 400, 80, 80);

        // Summary
        $display("==============================================================");
        $display("TB_ASYNC_FIFO SUMMARY: Written=%0d Read=%0d ResetDiscarded=%0d Errors=%0d",
                 total_written, total_read, total_discarded_by_reset, err_count);
        $display("==============================================================");
        if (err_count == 0 && total_written > 0 &&
            total_written == (total_read + total_discarded_by_reset)) begin
            $display("OVERALL STATUS: PASS");
            $finish(0);
        end else begin
            $display("OVERALL STATUS: FAIL");
            $fatal(1, "tb_async_fifo failed with %0d errors", err_count);
        end
    end

endmodule : tb_async_fifo
