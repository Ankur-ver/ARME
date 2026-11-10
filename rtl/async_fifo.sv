// =============================================================================
// File        : rtl/async_fifo.sv
// Project     : Adaptive Rate-Matching Engine ASIC Subsystem
// Description : Synthesizable dual-clock asynchronous FIFO using Gray-coded
//               pointers, multi-stage flip-flop synchronizers, and conservative
//               local occupancy calculation.
//
// Design Notes:
//   1. Gray Coding: Consecutive pointer increments change exactly 1 bit,
//      preventing multi-bit bus skew corruption across the CDC boundary.
//   2. Synchronizers: SYNC_STAGES (>= 2) flip-flops per pointer direction
//      mitigate metastability propagation (does not guarantee zero MTBF;
//      MTBF depends on technology library tau and clock frequencies).
//   3. Full Detection (wr_clk domain): Pointer MSB and (MSB-1) inverted,
//      remaining lower bits identical between wr_ptr_gray_next and
//      rd_ptr_gray_sync.
//   4. Empty Detection (rd_clk domain): rd_ptr_gray_next == wr_ptr_gray_sync.
//   5. Occupancy: Computed locally in each domain by converting the
//      synchronized Gray pointer back to binary and subtracting modulo 2^(N+1).
//      Because the remote pointer is delayed by SYNC_STAGES cycles:
//        - wr_occupancy >= true_occupancy (conservative against overflow)
//        - rd_occupancy <= true_occupancy (conservative against underflow)
//   6. Read Data Timing: Synchronous registered read on rd_clk (cleanly
//      infers dual-port SRAM/register file in ASIC/FPGA synthesis).
// =============================================================================

module async_fifo #(
    parameter int DATA_WIDTH  = 64,
    parameter int FIFO_DEPTH  = 1024,
    parameter int SYNC_STAGES = 2,
    localparam int ADDR_WIDTH = $clog2(FIFO_DEPTH),
    localparam int PTR_WIDTH  = ADDR_WIDTH + 1
) (
    // Write Clock Domain
    input  logic                    wr_clk,
    input  logic                    wr_rst_n,
    input  logic                    wr_en,
    input  logic [DATA_WIDTH-1:0]   wr_data,
    output logic                    wr_full,
    output logic                    wr_overflow,
    output logic [PTR_WIDTH-1:0]    wr_occupancy,

    // Read Clock Domain
    input  logic                    rd_clk,
    input  logic                    rd_rst_n,
    input  logic                    rd_en,
    output logic [DATA_WIDTH-1:0]   rd_data,
    output logic                    rd_empty,
    output logic                    rd_underflow,
    output logic [PTR_WIDTH-1:0]    rd_occupancy
);

    // -------------------------------------------------------------------------
    // Elaboration-Time Parameter Validation (Simulation / Lint Guard)
    // -------------------------------------------------------------------------
`ifndef SYNTHESIS
    initial begin
        if (FIFO_DEPTH < 4 || (FIFO_DEPTH & (FIFO_DEPTH - 1)) != 0) begin
            $fatal(1, "async_fifo: FIFO_DEPTH (%0d) must be a power of 2 and >= 4", FIFO_DEPTH);
        end
        if (SYNC_STAGES < 2) begin
            $fatal(1, "async_fifo: SYNC_STAGES (%0d) must be >= 2", SYNC_STAGES);
        end
    end
`endif

    // -------------------------------------------------------------------------
    // Dual-Port Storage Memory
    // -------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];

    // -------------------------------------------------------------------------
    // Write Domain Signals
    // -------------------------------------------------------------------------
    logic [PTR_WIDTH-1:0]  wr_ptr_bin;
    logic [PTR_WIDTH-1:0]  wr_ptr_bin_next;
    logic [PTR_WIDTH-1:0]  wr_ptr_gray;
    logic [PTR_WIDTH-1:0]  wr_ptr_gray_next;
    logic [ADDR_WIDTH-1:0] wr_addr;
    logic                  wr_inc;
    logic                  wr_full_next;

    // Synchronized read pointer in write clock domain
    (* ASYNC_REG = "TRUE" *)
    logic [PTR_WIDTH-1:0]  rd_ptr_gray_sync_pipe [0:SYNC_STAGES-1];
    logic [PTR_WIDTH-1:0]  rd_ptr_gray_sync;
    logic [PTR_WIDTH-1:0]  rd_ptr_bin_sync;

    // -------------------------------------------------------------------------
    // Read Domain Signals
    // -------------------------------------------------------------------------
    logic [PTR_WIDTH-1:0]  rd_ptr_bin;
    logic [PTR_WIDTH-1:0]  rd_ptr_bin_next;
    logic [PTR_WIDTH-1:0]  rd_ptr_gray;
    logic [PTR_WIDTH-1:0]  rd_ptr_gray_next;
    logic [ADDR_WIDTH-1:0] rd_addr;
    logic                  rd_inc;
    logic                  rd_empty_next;

    // Synchronized write pointer in read clock domain
    (* ASYNC_REG = "TRUE" *)
    logic [PTR_WIDTH-1:0]  wr_ptr_gray_sync_pipe [0:SYNC_STAGES-1];
    logic [PTR_WIDTH-1:0]  wr_ptr_gray_sync;
    logic [PTR_WIDTH-1:0]  wr_ptr_bin_sync;

    // -------------------------------------------------------------------------
    // Write-Side Pointer, Full, Overflow & Memory Write Logic
    // -------------------------------------------------------------------------
    assign wr_inc           = wr_en && !wr_full;
    assign wr_addr          = wr_ptr_bin[ADDR_WIDTH-1:0];
    assign wr_ptr_bin_next  = wr_ptr_bin + {{(PTR_WIDTH-1){1'b0}}, wr_inc};
    assign wr_ptr_gray_next = wr_ptr_bin_next ^ (wr_ptr_bin_next >> 1);

    assign rd_ptr_gray_sync = rd_ptr_gray_sync_pipe[SYNC_STAGES-1];

    // Full condition: MSBs (top 2 bits) inverted, lower (PTR_WIDTH-2) bits equal
    assign wr_full_next = (wr_ptr_gray_next == {
        ~rd_ptr_gray_sync[PTR_WIDTH-1 : PTR_WIDTH-2],
         rd_ptr_gray_sync[PTR_WIDTH-3 : 0]
    });

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr_bin  <= '0;
            wr_ptr_gray <= '0;
            wr_full     <= 1'b0;
            wr_overflow <= 1'b0;
        end else begin
            wr_ptr_bin  <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;
            wr_full     <= wr_full_next;
            wr_overflow <= (wr_en && wr_full);
        end
    end

    always_ff @(posedge wr_clk) begin
        if (wr_inc) begin
            mem[wr_addr] <= wr_data;
        end
    end

    // Synchronize rd_ptr_gray into wr_clk domain
    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            for (int s = 0; s < SYNC_STAGES; s++) begin
                rd_ptr_gray_sync_pipe[s] <= '0;
            end
        end else begin
            rd_ptr_gray_sync_pipe[0] <= rd_ptr_gray;
            for (int s = 1; s < SYNC_STAGES; s++) begin
                rd_ptr_gray_sync_pipe[s] <= rd_ptr_gray_sync_pipe[s-1];
            end
        end
    end

    // Convert synchronized Gray read pointer to binary for write-side occupancy
    assign rd_ptr_bin_sync[PTR_WIDTH-1] = rd_ptr_gray_sync[PTR_WIDTH-1];
    genvar gi_wr;
    generate
        for (gi_wr = PTR_WIDTH - 2; gi_wr >= 0; gi_wr--) begin : gen_rd_gray2bin
            assign rd_ptr_bin_sync[gi_wr] = rd_ptr_bin_sync[gi_wr+1] ^ rd_ptr_gray_sync[gi_wr];
        end
    endgenerate

    assign wr_occupancy = wr_ptr_bin - rd_ptr_bin_sync;

    // -------------------------------------------------------------------------
    // Read-Side Pointer, Empty, Underflow & Synchronous Memory Read Logic
    // -------------------------------------------------------------------------
    assign rd_inc           = rd_en && !rd_empty;
    assign rd_addr          = rd_ptr_bin[ADDR_WIDTH-1:0];
    assign rd_ptr_bin_next  = rd_ptr_bin + {{(PTR_WIDTH-1){1'b0}}, rd_inc};
    assign rd_ptr_gray_next = rd_ptr_bin_next ^ (rd_ptr_bin_next >> 1);

    assign wr_ptr_gray_sync = wr_ptr_gray_sync_pipe[SYNC_STAGES-1];
    assign rd_empty_next    = (rd_ptr_gray_next == wr_ptr_gray_sync);

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr_bin   <= '0;
            rd_ptr_gray  <= '0;
            rd_empty     <= 1'b1;
            rd_underflow <= 1'b0;
        end else begin
            rd_ptr_bin   <= rd_ptr_bin_next;
            rd_ptr_gray  <= rd_ptr_gray_next;
            rd_empty     <= rd_empty_next;
            rd_underflow <= (rd_en && rd_empty);
        end
    end

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_data <= '0;
        end else if (rd_inc) begin
            rd_data <= mem[rd_addr];
        end
    end

    // Synchronize wr_ptr_gray into rd_clk domain
    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            for (int s = 0; s < SYNC_STAGES; s++) begin
                wr_ptr_gray_sync_pipe[s] <= '0;
            end
        end else begin
            wr_ptr_gray_sync_pipe[0] <= wr_ptr_gray;
            for (int s = 1; s < SYNC_STAGES; s++) begin
                wr_ptr_gray_sync_pipe[s] <= wr_ptr_gray_sync_pipe[s-1];
            end
        end
    end

    // Convert synchronized Gray write pointer to binary for read-side occupancy
    assign wr_ptr_bin_sync[PTR_WIDTH-1] = wr_ptr_gray_sync[PTR_WIDTH-1];
    genvar gi_rd;
    generate
        for (gi_rd = PTR_WIDTH - 2; gi_rd >= 0; gi_rd--) begin : gen_wr_gray2bin
            assign wr_ptr_bin_sync[gi_rd] = wr_ptr_bin_sync[gi_rd+1] ^ wr_ptr_gray_sync[gi_rd];
        end
    endgenerate

    assign rd_occupancy = wr_ptr_bin_sync - rd_ptr_bin;

endmodule : async_fifo
