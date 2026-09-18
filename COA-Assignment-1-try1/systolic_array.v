// ============================================================================
// systolic_array.v
// N x N output-stationary systolic array AI accelerator.
//
// - Each PE(i,j) owns output element C(i,j) and accumulates locally.
// - Row i of matrix A is delayed by i cycles at the west boundary; column j
//   of matrix B is delayed by j cycles at the north boundary. This "boundary
//   skew" makes operand A(i,k) and B(k,j) meet inside PE(i,j) on exactly the
//   right cycle, with no extra control logic needed inside each PE.
// - The whole tile finishes in (3N - 1) clock cycles.
//
// Simplifying assumption for this assignment: a_flat/b_flat must be driven,
// one column of A and one row of B per cycle, by an external feeder (see
// tile_feeder.v) for N cycles starting the same cycle "start" is asserted.
// In the reference SoC this streaming role is played by the DMA engine
// filling a double-buffered input register; here it is a small dedicated
// feeder module to keep the accelerator itself simple and reusable.
// ============================================================================
module systolic_array #(
    parameter N       = 4,
    parameter DATA_W  = 8,
    parameter ACC_W   = 32
)(
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     start,        // pulse: begin a new tile
    input  wire [N*DATA_W-1:0]      a_flat,       // column t of A (one elem/row)
    input  wire [N*DATA_W-1:0]      b_flat,       // row t of B (one elem/col)
    output reg                      done,         // pulses after 3N-1 cycles
    output wire [N*N*ACC_W-1:0]     result_flat,  // N*N accumulator outputs
    output wire                     clear_pulse   // 1 cycle after start: use this
                                                   // to trigger an external feeder
                                                   // (e.g. tile_feeder.v) so its
                                                   // first data lands exactly on
                                                   // the first real accumulate
                                                   // cycle, not the clear cycle
);

    localparam CYCLES = 3*N - 1;

    // ---------------- Cycle counter / control ----------------
    reg               running;
    reg [15:0]        cycle_cnt;
    reg               clear_acc_pulse;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            running         <= 1'b0;
            cycle_cnt       <= 16'd0;
            done            <= 1'b0;
            clear_acc_pulse <= 1'b0;
        end else begin
            clear_acc_pulse <= 1'b0;
            done            <= 1'b0;

            if (start && !running) begin
                running         <= 1'b1;
                cycle_cnt       <= 16'd0;
                clear_acc_pulse <= 1'b1;   // wipe all 16 accumulators
            end else if (running) begin
                if (cycle_cnt == CYCLES - 1) begin
                    running <= 1'b0;
                    done    <= 1'b1;
                end
                    cycle_cnt <= cycle_cnt + 16'd1;
            end
        end
    end

    // Exposed so an external feeder can be started exactly one cycle after
    // "start", i.e. on the same cycle the accumulators are cleared, so its
    // first output lands on the array's first real accumulate cycle.
    assign clear_pulse = clear_acc_pulse;

    // ---------------- Boundary skew registers ----------------
    wire signed [DATA_W-1:0] west_skewed  [0:N-1];
    wire signed [DATA_W-1:0] north_skewed [0:N-1];

    genvar gi, gj;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : ROW_SKEW
            if (gi == 0) begin : NO_DELAY
                assign west_skewed[gi] = a_flat[(gi+1)*DATA_W-1 -: DATA_W];
            end else begin : DELAY_CHAIN
                reg signed [DATA_W-1:0] chain [0:gi-1];
                integer k;
                always @(posedge clk or posedge rst) begin
                    if (rst) begin
                        for (k = 0; k < gi; k = k + 1)
                            chain[k] <= {DATA_W{1'b0}};
                    end else begin
                        chain[0] <= a_flat[(gi+1)*DATA_W-1 -: DATA_W];
                        for (k = 1; k < gi; k = k + 1)
                            chain[k] <= chain[k-1];
                    end
                end
                assign west_skewed[gi] = chain[gi-1];
            end
        end

        for (gj = 0; gj < N; gj = gj + 1) begin : COL_SKEW
            if (gj == 0) begin : NO_DELAY
                assign north_skewed[gj] = b_flat[(gj+1)*DATA_W-1 -: DATA_W];
            end else begin : DELAY_CHAIN
                reg signed [DATA_W-1:0] chain [0:gj-1];
                integer k;
                always @(posedge clk or posedge rst) begin
                    if (rst) begin
                        for (k = 0; k < gj; k = k + 1)
                            chain[k] <= {DATA_W{1'b0}};
                    end else begin
                        chain[0] <= b_flat[(gj+1)*DATA_W-1 -: DATA_W];
                        for (k = 1; k < gj; k = k + 1)
                            chain[k] <= chain[k-1];
                    end
                end
                assign north_skewed[gj] = chain[gj-1];
            end
        end
    endgenerate

    // ---------------- PE grid ----------------
    wire signed [DATA_W-1:0] pe_east  [0:N-1][0:N-1];
    wire signed [DATA_W-1:0] pe_south [0:N-1][0:N-1];
    wire signed [ACC_W-1:0]  pe_acc   [0:N-1][0:N-1];

    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : PE_ROW
            for (gj = 0; gj < N; gj = gj + 1) begin : PE_COL

                wire signed [DATA_W-1:0] w_in;
                wire signed [DATA_W-1:0] n_in;

                // Generate-if (not a ternary) so the out-of-range neighbour
                // index is never even elaborated at the array boundary.
                if (gj == 0)
                    assign w_in = west_skewed[gi];
                else
                    assign w_in = pe_east[gi][gj-1];

                if (gi == 0)
                    assign n_in = north_skewed[gj];
                else
                    assign n_in = pe_south[gi-1][gj];

                mac_pe #(.DATA_W(DATA_W), .ACC_W(ACC_W)) u_pe (
                    .clk       (clk),
                    .rst       (rst),
                    .en        (running),
                    .clear_acc (clear_acc_pulse),
                    .west_in   (w_in),
                    .north_in  (n_in),
                    .east_out  (pe_east[gi][gj]),
                    .south_out (pe_south[gi][gj]),
                    .acc       (pe_acc[gi][gj])
                );

                assign result_flat[((gi*N+gj)+1)*ACC_W-1 -: ACC_W] = pe_acc[gi][gj];
            end
        end
    endgenerate

endmodule