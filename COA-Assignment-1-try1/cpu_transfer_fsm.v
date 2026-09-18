// ============================================================================
// cpu_transfer_fsm.v
// Models "Scenario A" from the assignment: the CPU moves every word itself,
// with no DMA assistant. Each word costs one LOAD cycle and one STORE cycle,
// and "cpu_busy" is held HIGH for the entire operation -- the CPU cannot do
// anything else (like configuring or supervising the accelerator) while
// this runs. Compare its busy-cycle count directly against dma_engine.v's,
// which only needs a couple of cycles of CPU time regardless of length.
// ============================================================================
module cpu_transfer_fsm #(
    parameter ADDR_W = 10,
    parameter DATA_W = 8,
    parameter LEN_W  = 8
)(
    input  wire                        clk,
    input  wire                        rst,
    input  wire                        start,
    input  wire [ADDR_W-1:0]           src_addr,
    input  wire [ADDR_W-1:0]           dst_addr,
    input  wire [LEN_W-1:0]            length,
    output reg                         cpu_busy,  // HIGH for the whole transfer
    output reg                         done,

    output reg  [ADDR_W-1:0]           src_rd_addr,
    input  wire signed [DATA_W-1:0]    src_rd_data,

    output reg                         dst_we,
    output reg  [ADDR_W-1:0]           dst_wr_addr,
    output reg  signed [DATA_W-1:0]    dst_wr_data
);

    localparam S_IDLE  = 2'd0,
               S_LOAD   = 2'd1,
               S_STORE  = 2'd2,
               S_DONE   = 2'd3;

    reg [1:0]        state;
    reg [LEN_W:0]    idx;
    reg [ADDR_W-1:0] base_src, base_dst;
    reg [LEN_W-1:0]  len_reg;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state    <= S_IDLE;
            cpu_busy <= 1'b0;
            done     <= 1'b0;
            dst_we   <= 1'b0;
            idx      <= {LEN_W+1{1'b0}};
        end else begin
            done   <= 1'b0;
            dst_we <= 1'b0;

            case (state)
                S_IDLE: begin
                    cpu_busy <= 1'b0;
                    if (start) begin
                        base_src <= src_addr;
                        base_dst <= dst_addr;
                        len_reg  <= length;
                        idx      <= {LEN_W+1{1'b0}};
                        cpu_busy <= 1'b1;
                        state    <= (length == 0) ? S_DONE : S_LOAD;
                    end
                end

                S_LOAD: begin
                    // "LOAD" cycle: CPU issues a load instruction for word idx
                    src_rd_addr <= base_src + idx[ADDR_W-1:0];
                    state       <= S_STORE;
                end

                S_STORE: begin
                    // "STORE" cycle: CPU writes back the word it just loaded
                    dst_we      <= 1'b1;
                    dst_wr_addr <= base_dst + idx[ADDR_W-1:0];
                    dst_wr_data <= src_rd_data;

                    if (idx == len_reg - 1'b1) begin
                        state <= S_DONE;
                    end else begin
                        idx   <= idx + 1'b1;
                        state <= S_LOAD;
                    end
                end

                S_DONE: begin
                    cpu_busy <= 1'b0;
                    done     <= 1'b1;
                    state    <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
