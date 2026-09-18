// ============================================================================
// ctrl_regs.v
// A simplified stand-in for the AXI4-Lite register interface described in
// the reference design (Table 2 of the paper). Real hardware would expose
// these as memory addresses reachable with ordinary LW/SW instructions; here
// they are modelled as a small synchronous register file with a select line,
// which is enough to demonstrate the "just a few register writes" idea for
// this assignment without implementing the full AXI4-Lite protocol.
// ============================================================================
module ctrl_regs #(
    parameter ADDR_W = 10,
    parameter LEN_W  = 8
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              wr_en,
    input  wire [3:0]        wr_sel,
    input  wire [15:0]       wr_data,

    output reg                 start_pulse,  // -> DMA / accelerator START
    output reg [ADDR_W-1:0]    src_a,
    output reg [ADDR_W-1:0]    src_b,
    output reg [ADDR_W-1:0]    dst_c,
    output reg [LEN_W-1:0]     length,
    output reg [3:0]           dim
);

    localparam SEL_CTRL  = 4'd0,
               SEL_SRC_A = 4'd1,
               SEL_SRC_B = 4'd2,
               SEL_DST_C = 4'd3,
               SEL_LEN   = 4'd4,
               SEL_DIM   = 4'd5;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            start_pulse <= 1'b0;
            src_a       <= {ADDR_W{1'b0}};
            src_b       <= {ADDR_W{1'b0}};
            dst_c       <= {ADDR_W{1'b0}};
            length      <= {LEN_W{1'b0}};
            dim         <= 4'd0;
        end else begin
            start_pulse <= 1'b0;
            if (wr_en) begin
                case (wr_sel)
                    SEL_CTRL:  start_pulse <= wr_data[0];
                    SEL_SRC_A: src_a       <= wr_data[ADDR_W-1:0];
                    SEL_SRC_B: src_b       <= wr_data[ADDR_W-1:0];
                    SEL_DST_C: dst_c       <= wr_data[ADDR_W-1:0];
                    SEL_LEN:   length      <= wr_data[LEN_W-1:0];
                    SEL_DIM:   dim         <= wr_data[3:0];
                    default:   ;
                endcase
            end
        end
    end

endmodule
