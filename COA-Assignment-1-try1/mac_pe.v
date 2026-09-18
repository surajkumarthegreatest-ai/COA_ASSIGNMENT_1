// ============================================================================
// mac_pe.v
// One Multiply-Accumulate (MAC) Processing Element (PE) for the systolic
// array. Each PE:
//   - multiplies the activation coming from the WEST by the weight coming
//     from the NORTH,
//   - adds the product into a local running accumulator (output-stationary
//     dataflow: the accumulator "stays" in this PE for the whole tile),
//   - forwards the unmodified activation to the EAST neighbour and the
//     unmodified weight to the SOUTH neighbour, one cycle later.
// ============================================================================
module mac_pe #(
    parameter DATA_W = 8,   // width of one operand (INT8-style)
    parameter ACC_W  = 32   // width of the accumulator
)(
    input  wire                        clk,
    input  wire                        rst,
    input  wire                        en,         // advance one MAC step
    input  wire                        clear_acc,  // reset accumulator (new tile)
    input  wire signed [DATA_W-1:0]    west_in,    // activation in
    input  wire signed [DATA_W-1:0]    north_in,   // weight in
    output reg  signed [DATA_W-1:0]    east_out,   // activation out (to next column)
    output reg  signed [DATA_W-1:0]    south_out,  // weight out (to next row)
    output reg  signed [ACC_W-1:0]     acc         // partial / final result
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            east_out  <= {DATA_W{1'b0}};
            south_out <= {DATA_W{1'b0}};
            acc       <= {ACC_W{1'b0}};
        end else begin
            // Systolic forwarding happens every cycle regardless of "en",
            // so operands keep moving through the grid.
            east_out  <= west_in;
            south_out <= north_in;

            if (clear_acc)
                acc <= {ACC_W{1'b0}};
            else if (en)
                acc <= acc + (west_in * north_in);
        end
    end

endmodule
