// ============================================================================
// tb_compare.v
// Top-level testbench for the assignment:
//   "Compare CPU-controlled data transfer with DMA-based transfer for
//    matrix multiplication / CNN inference, and calculate processor
//    overhead and throughput."
//
// It runs three experiments on a 100 MHz clock (10 ns period):
//   1) Scenario A: cpu_transfer_fsm moves a 32-word tile (A+B, 4x4 each)
//      itself -> measures how many cycles the CPU is stuck copying data.
//   2) Scenario B: dma_engine moves the same 32-word tile -> measures how
//      many cycles the CPU needs (just the descriptor write + start) versus
//      how many cycles the transfer actually takes in the background.
//   3) The systolic_array + tile_feeder are run once on a small sample
//      4x4 x 4x4 tile to confirm the (3N-1)-cycle compute latency and show
//      a correct result matrix.
//
// It then prints processor-overhead and throughput figures for both
// scenarios, using the same formulas as the reference paper:
//     overhead   = (cycles CPU is busy moving data) / (total cycles) * 100%
//     throughput = (useful operations) / (total time)   [GOPS @ 100 MHz]
// ============================================================================
`timescale 1ns/1ps

module tb_compare;

    // ---------------- Parameters ----------------
    localparam N       = 4;
    localparam DATA_W  = 8;
    localparam ACC_W   = 32;
    localparam ADDR_W  = 10;
    localparam LEN_W   = 8;
    localparam LENGTH  = N*N*2;      // move A tile (16 words) + B tile (16 words)
    localparam CLK_NS  = 10;         // 100 MHz

    // ---------------- Clock / reset ----------------
    reg clk = 0;
    reg rst = 1;
    always #(CLK_NS/2) clk = ~clk;

    // ================================================================
    // Scenario A: CPU-controlled transfer
    // ================================================================
    reg                      cpuA_start;
    reg  [ADDR_W-1:0]        cpuA_src, cpuA_dst;
    reg  [LEN_W-1:0]         cpuA_len;
    wire                     cpuA_busy, cpuA_done;
    wire [ADDR_W-1:0]        cpuA_rd_addr;
    wire signed [DATA_W-1:0] cpuA_rd_data;
    wire                     cpuA_we;
    wire [ADDR_W-1:0]        cpuA_wr_addr;
    wire signed [DATA_W-1:0] cpuA_wr_data;

    shared_mem #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) mem_src (
        .clk(clk), .we(1'b0), .addr(cpuA_rd_addr), .din({DATA_W{1'b0}}), .dout(cpuA_rd_data)
    );

    shared_mem #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) mem_dst_cpu (
        .clk(clk), .we(cpuA_we), .addr(cpuA_wr_addr), .din(cpuA_wr_data), .dout()
    );

    cpu_transfer_fsm #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .LEN_W(LEN_W)) u_cpu (
        .clk(clk), .rst(rst),
        .start(cpuA_start), .src_addr(cpuA_src), .dst_addr(cpuA_dst), .length(cpuA_len),
        .cpu_busy(cpuA_busy), .done(cpuA_done),
        .src_rd_addr(cpuA_rd_addr), .src_rd_data(cpuA_rd_data),
        .dst_we(cpuA_we), .dst_wr_addr(cpuA_wr_addr), .dst_wr_data(cpuA_wr_data)
    );

    // ================================================================
    // Scenario B: DMA-based transfer (shares mem_src above)
    // ================================================================
    reg                      dma_start;
    reg  [ADDR_W-1:0]        dma_src, dma_dst;
    reg  [LEN_W-1:0]         dma_len;
    wire                     dma_busy, dma_done;
    wire [ADDR_W-1:0]        dma_rd_addr;
    wire signed [DATA_W-1:0] dma_rd_data;
    wire                     dma_we;
    wire [ADDR_W-1:0]        dma_wr_addr;
    wire signed [DATA_W-1:0] dma_wr_data;

    shared_mem #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) mem_src2 (
        .clk(clk), .we(1'b0), .addr(dma_rd_addr), .din({DATA_W{1'b0}}), .dout(dma_rd_data)
    );

    shared_mem #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) mem_dst_dma (
        .clk(clk), .we(dma_we), .addr(dma_wr_addr), .din(dma_wr_data), .dout()
    );

    dma_engine #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .LEN_W(LEN_W)) u_dma (
        .clk(clk), .rst(rst),
        .start(dma_start), .src_addr(dma_src), .dst_addr(dma_dst), .length(dma_len),
        .busy(dma_busy), .done(dma_done),
        .src_rd_addr(dma_rd_addr), .src_rd_data(dma_rd_data),
        .dst_we(dma_we), .dst_wr_addr(dma_wr_addr), .dst_wr_data(dma_wr_data)
    );

    // The CPU's own involvement in Scenario B is just writing the descriptor
    // registers and the START bit -- modelled here as one clock cycle.
    localparam integer CPU_DESCRIPTOR_CYCLES = 4; // SRC_A, SRC_B/LEN, DST_C, CTRL.START

    // ================================================================
    // Systolic-array accelerator (compute-latency confirmation)
    // ================================================================
    reg                       acc_start;
    reg  [N*N*DATA_W-1:0]     a_tile, b_tile;
    wire [N*DATA_W-1:0]       feed_a, feed_b;
    wire                      feeding;
    wire                      acc_done;
    wire [N*N*ACC_W-1:0]      result_flat;
    wire                      acc_clear_pulse;

    // IMPORTANT: the feeder is started from the accelerator's own
    // clear_pulse (one cycle after acc_start), NOT from acc_start directly.
    // That one-cycle offset is what lines the feeder's first real data up
    // with the array's first real accumulate cycle instead of its
    // accumulator-clear cycle (see tile_feeder.v / systolic_array.v).
    tile_feeder #(.N(N), .DATA_W(DATA_W)) u_feed (
        .clk(clk), .rst(rst), .start(acc_clear_pulse),
        .a_tile_flat(a_tile), .b_tile_flat(b_tile),
        .a_flat(feed_a), .b_flat(feed_b), .feeding(feeding)
    );

    systolic_array #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)) u_sa (
        .clk(clk), .rst(rst), .start(acc_start),
        .a_flat(feed_a), .b_flat(feed_b),
        .done(acc_done), .result_flat(result_flat),
        .clear_pulse(acc_clear_pulse)
    );

    // ---------------- Readable per-signal breakouts (waveform-viewing only) ----------------
    // These don't change any behaviour -- they just slice the flattened buses
    // into individually-named signals so a waveform viewer (GTKWave, Vivado)
    // shows one row per value, the same way Fig. 5 of the reference paper
    // shows inp_west0..3 / inp_north0..3 / result0..15 as separate rows
    // instead of one unreadable multi-bit bus.
    wire signed [DATA_W-1:0] west0  = feed_a[1*DATA_W-1 -: DATA_W];
    wire signed [DATA_W-1:0] west1  = feed_a[2*DATA_W-1 -: DATA_W];
    wire signed [DATA_W-1:0] west2  = feed_a[3*DATA_W-1 -: DATA_W];
    wire signed [DATA_W-1:0] west3  = feed_a[4*DATA_W-1 -: DATA_W];
    wire signed [DATA_W-1:0] north0 = feed_b[1*DATA_W-1 -: DATA_W];
    wire signed [DATA_W-1:0] north1 = feed_b[2*DATA_W-1 -: DATA_W];
    wire signed [DATA_W-1:0] north2 = feed_b[3*DATA_W-1 -: DATA_W];
    wire signed [DATA_W-1:0] north3 = feed_b[4*DATA_W-1 -: DATA_W];

    wire signed [ACC_W-1:0] result0,  result1,  result2,  result3;
    wire signed [ACC_W-1:0] result4,  result5,  result6,  result7;
    wire signed [ACC_W-1:0] result8,  result9,  result10, result11;
    wire signed [ACC_W-1:0] result12, result13, result14, result15;
    assign result0  = result_flat[1*ACC_W-1  -: ACC_W];
    assign result1  = result_flat[2*ACC_W-1  -: ACC_W];
    assign result2  = result_flat[3*ACC_W-1  -: ACC_W];
    assign result3  = result_flat[4*ACC_W-1  -: ACC_W];
    assign result4  = result_flat[5*ACC_W-1  -: ACC_W];
    assign result5  = result_flat[6*ACC_W-1  -: ACC_W];
    assign result6  = result_flat[7*ACC_W-1  -: ACC_W];
    assign result7  = result_flat[8*ACC_W-1  -: ACC_W];
    assign result8  = result_flat[9*ACC_W-1  -: ACC_W];
    assign result9  = result_flat[10*ACC_W-1 -: ACC_W];
    assign result10 = result_flat[11*ACC_W-1 -: ACC_W];
    assign result11 = result_flat[12*ACC_W-1 -: ACC_W];
    assign result12 = result_flat[13*ACC_W-1 -: ACC_W];
    assign result13 = result_flat[14*ACC_W-1 -: ACC_W];
    assign result14 = result_flat[15*ACC_W-1 -: ACC_W];
    assign result15 = result_flat[16*ACC_W-1 -: ACC_W];

    // ---------------- Cycle counters ----------------
    integer cyc_cpu_transfer, cyc_dma_transfer, cyc_compute;
    integer i, r, c;

    // NOTE on the "#1" below: reading a registered DUT signal (done/busy)
    // in the very same simulation time step as the "@(posedge clk)" that
    // updates it is a classic Verilog race -- the read can see the value
    // from *before* that edge instead of after it, silently inflating
    // every cycle count by one extra loop iteration. The small delay lets
    // all non-blocking updates for that edge settle before we look.

    task run_cpu_scenario;
        begin
            cpuA_src  = 0;
            cpuA_dst  = 100;
            cpuA_len  = LENGTH;
            cpuA_start = 0;
            @(posedge clk); #1;
            cpuA_start = 1;
            cyc_cpu_transfer = 0;
            @(posedge clk); #1;
            cpuA_start = 0;
            while (!cpuA_done) begin
                cyc_cpu_transfer = cyc_cpu_transfer + 1;
                @(posedge clk); #1;
            end
        end
    endtask

    task run_dma_scenario;
        begin
            dma_src  = 0;
            dma_dst  = 200;
            dma_len  = LENGTH;
            dma_start = 0;
            @(posedge clk); #1;
            dma_start = 1;
            cyc_dma_transfer = 0;
            @(posedge clk); #1;
            dma_start = 0;
            while (!dma_done) begin
                cyc_dma_transfer = cyc_dma_transfer + 1;
                @(posedge clk); #1;
            end
        end
    endtask

    task run_accelerator_demo;
        begin
            // Simple sample tile: A(i,k) = i*N + k + 1 ; B(k,j) = 1 for all k,j
            // => C(i,j) = sum_k A(i,k) = 4*(i*N) + (1+2+...+N)
            for (r = 0; r < N; r = r + 1) begin
                for (c = 0; c < N; c = c + 1) begin
                    a_tile[((r*N+c)+1)*DATA_W-1 -: DATA_W] = r*N + c + 1;
                    b_tile[((r*N+c)+1)*DATA_W-1 -: DATA_W] = 1;
                end
            end

            acc_start = 0;
            @(posedge clk); #1;
            acc_start = 1;
            cyc_compute = 0;
            @(posedge clk); #1;
            acc_start = 0;
            while (!acc_done) begin
                cyc_compute = cyc_compute + 1;
                @(posedge clk); #1;
            end
        end
    endtask

    // ---------------- Main sequence ----------------
    real overhead_cpu_pct, overhead_dma_pct;
    real thr_cpu_gops, thr_dma_gops;
    integer total_cpu_cycles, total_dma_cycles;
    integer useful_ops;

    initial begin
        // Dump every signal in this testbench to a waveform file that GTKWave
        // (or any VCD viewer) can open -- this is what lets you produce a
        // screenshot like Fig. 5/6 of the reference paper. See the README
        // for how to view it.
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_compare);

        // Fill the shared source memories with 32 sample words (both copies
        // must match since Scenario A and B are run independently).
        for (i = 0; i < LENGTH; i = i + 1) begin
            mem_src.mem[i]  = i + 1;
            mem_src2.mem[i] = i + 1;
        end

        acc_start  = 0;
        cpuA_start = 0;
        dma_start  = 0;

        #(2*CLK_NS) rst = 0;

        // ---- Scenario A: CPU-controlled ----
        run_cpu_scenario;

        // ---- Scenario B: DMA-based ----
        run_dma_scenario;

        // ---- Accelerator compute-latency confirmation ----
        run_accelerator_demo;

        // ---- Report ----
        useful_ops       = 2 * N * N * N;              // 2*N^3 MACs = ops, N=4 -> 128
        total_cpu_cycles = cyc_cpu_transfer + cyc_compute;
        total_dma_cycles = CPU_DESCRIPTOR_CYCLES + cyc_dma_transfer + cyc_compute;

        overhead_cpu_pct = 100.0 * cyc_cpu_transfer / total_cpu_cycles;
        overhead_dma_pct = 100.0 * CPU_DESCRIPTOR_CYCLES / total_dma_cycles;

        thr_cpu_gops = useful_ops / (total_cpu_cycles * 1.0 * CLK_NS);   // ops/ns = GOPS
        thr_dma_gops = useful_ops / (total_dma_cycles * 1.0 * CLK_NS);

        $display("====================================================================");
        $display(" Sample 4x4 result matrix (from the accelerator demo run)");
        $display("====================================================================");
        for (r = 0; r < N; r = r + 1) begin
            $write(" ");
            for (c = 0; c < N; c = c + 1)
                $write("%6d ", $signed(result_flat[((r*N+c)+1)*ACC_W-1 -: ACC_W]));
            $write("\n");
        end

        $display("====================================================================");
        $display(" Scenario A: CPU-CONTROLLED transfer (no DMA)");
        $display("--------------------------------------------------------------------");
        $display("  Words moved                 : %0d", LENGTH);
        $display("  CPU busy cycles (transfer)   : %0d  (100%% of the transfer)", cyc_cpu_transfer);
        $display("  Compute cycles (3N-1)        : %0d", cyc_compute);
        $display("  Total end-to-end cycles      : %0d", total_cpu_cycles);
        $display("  Processor overhead           : %0.2f %%", overhead_cpu_pct);
        $display("  Throughput                   : %0.4f GOPS", thr_cpu_gops);

        $display("====================================================================");
        $display(" Scenario B: DMA-BASED transfer");
        $display("--------------------------------------------------------------------");
        $display("  Words moved                  : %0d", LENGTH);
        $display("  CPU cycles (descriptor only) : %0d", CPU_DESCRIPTOR_CYCLES);
        $display("  DMA transfer cycles (bg)     : %0d  (CPU free during this time)", cyc_dma_transfer);
        $display("  Compute cycles (3N-1)         : %0d", cyc_compute);
        $display("  Total end-to-end cycles      : %0d", total_dma_cycles);
        $display("  Processor overhead           : %0.2f %%", overhead_dma_pct);
        $display("  Throughput                   : %0.4f GOPS", thr_dma_gops);

        $display("====================================================================");
        $display(" Summary");
        $display("--------------------------------------------------------------------");
        $display("  Overhead reduction  : %0.2f %% -> %0.2f %%", overhead_cpu_pct, overhead_dma_pct);
        $display("  Throughput speed-up : %0.2fx", thr_dma_gops / thr_cpu_gops);
        $display("====================================================================");

        $finish;
    end

endmodule