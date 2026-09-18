// ============================================================================
// tile_feeder.v
// Once a full N x N tile of A and B has been loaded into on-chip buffers
// (by the DMA engine, or by the CPU one word at a time), this module streams
// one column of A and one row of B into the systolic array per cycle, for N
// cycles. The array's own boundary-skew registers (see systolic_array.v)
// take care of staggering rows/columns correctly from there.
//
// Tile layout: element (r, c) of an N x N matrix is stored at flat index
// r*N + c (row-major).
// ============================================================================
module tile_feeder #(
    parameter N      = 4,
    parameter DATA_W = 8
)(
    input  wire                      clk,
    input  wire                      rst,
    input  wire                      start,           // begin streaming a fresh tile
    input  wire [N*N*DATA_W-1:0]     a_tile_flat,     // full N x N tile of A
    input  wire [N*N*DATA_W-1:0]     b_tile_flat,     // full N x N tile of B

    output reg  [N*DATA_W-1:0]       a_flat,          // -> systolic_array.a_flat
    output reg  [N*DATA_W-1:0]       b_flat,          // -> systolic_array.b_flat
    output reg                       feeding
);

    reg [7:0] t_cnt;   // index of the column/row most recently emitted
    integer   r, c;

    // NOTE on timing: "start" here should be driven by systolic_array's
    // clear_pulse output (one cycle after systolic_array's own "start"),
    // not by the same raw start pulse -- that keeps this feeder's first
    // real data lined up with the array's first real accumulate cycle
    // instead of landing on its accumulator-clear cycle. See tb_compare.v.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            feeding <= 1'b0;
            a_flat  <= {N*DATA_W{1'b0}};
            b_flat  <= {N*DATA_W{1'b0}};
            t_cnt   <= 8'd0;
        end else if (start) begin
            // Emit column/row 0 immediately -- no dependency on the old
            // t_cnt value, so there is no one-cycle "double emit" of
            // column 0 the way there was before this fix.
            feeding <= 1'b1;
            t_cnt   <= 8'd0;
            for (r = 0; r < N; r = r + 1)
                a_flat[(r+1)*DATA_W-1 -: DATA_W] <=
                    a_tile_flat[((r*N + 0)+1)*DATA_W-1 -: DATA_W];
            for (c = 0; c < N; c = c + 1)
                b_flat[(c+1)*DATA_W-1 -: DATA_W] <=
                    b_tile_flat[((0*N + c)+1)*DATA_W-1 -: DATA_W];
        end else if (feeding) begin
            if (t_cnt == N-1) begin
                feeding <= 1'b0;
                a_flat  <= {N*DATA_W{1'b0}};
                b_flat  <= {N*DATA_W{1'b0}};
            end else begin
                t_cnt <= t_cnt + 8'd1;
                for (r = 0; r < N; r = r + 1)
                    a_flat[(r+1)*DATA_W-1 -: DATA_W] <=
                        a_tile_flat[((r*N + (t_cnt+1))+1)*DATA_W-1 -: DATA_W];
                for (c = 0; c < N; c = c + 1)
                    b_flat[(c+1)*DATA_W-1 -: DATA_W] <=
                        b_tile_flat[(((t_cnt+1)*N + c)+1)*DATA_W-1 -: DATA_W];
            end
        end else begin
            a_flat <= {N*DATA_W{1'b0}};
            b_flat <= {N*DATA_W{1'b0}};
        end
    end

endmodule