// ============================================================================
// shared_mem.v
// Simple single-port synchronous RAM standing in for a BRAM region
// (e.g. the "Input data" / "Weights" / "Output data" regions in Table 1
// of the reference SoC). One read and one write per cycle.
// ============================================================================
module shared_mem #(
    parameter ADDR_W = 10,
    parameter DATA_W = 8
)(
    input  wire                        clk,
    input  wire                        we,
    input  wire [ADDR_W-1:0]           addr,
    input  wire signed [DATA_W-1:0]    din,
    output reg  signed [DATA_W-1:0]    dout
);

    reg signed [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];

    always @(posedge clk) begin
        if (we)
            mem[addr] <= din;
        dout <= mem[addr];
    end

endmodule
