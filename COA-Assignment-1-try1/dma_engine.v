// ============================================================================
// dma_engine.v
// A minimal single-channel DMA engine. The CPU writes a short descriptor
// (source address, destination address, length) and pulses "start" once;
// after that the CPU is completely free while this engine autonomously
// bursts every word across, one word per cycle (after a 1-cycle pipeline
// fill), and raises "done" when finished.
//
// This is the hardware "assistant" described in the assignment: the CPU's
// only job is the single descriptor-write + start (modelled here as one
// cycle), never the per-word copy loop.
// ============================================================================
module dma_engine #(
    parameter ADDR_W = 10,
    parameter DATA_W = 8,
    parameter LEN_W  = 8
)(
    input  wire                        clk,
    input  wire                        rst,
    input  wire                        start,       // one-cycle pulse from CPU
    input  wire [ADDR_W-1:0]           src_addr,
    input  wire [ADDR_W-1:0]           dst_addr,
    input  wire [LEN_W-1:0]            length,      // number of words to move
    output reg                         busy,
    output reg                         done,        // one-cycle pulse on completion

    // Source memory read port
    output reg  [ADDR_W-1:0]           src_rd_addr,
    input  wire signed [DATA_W-1:0]    src_rd_data,

    // Destination memory write port
    output reg                         dst_we,
    output reg  [ADDR_W-1:0]           dst_wr_addr,
    output reg  signed [DATA_W-1:0]    dst_wr_data
);

    reg [LEN_W:0]     count;     // words for which a read has been issued
    reg [LEN_W:0]     wcount;    // words actually written back
    reg [ADDR_W-1:0]  base_src, base_dst;
    reg [LEN_W-1:0]   len_reg;
    reg               rd_valid;  // a read was issued on the previous cycle

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy        <= 1'b0;
            done        <= 1'b0;
            count       <= {LEN_W+1{1'b0}};
            wcount      <= {LEN_W+1{1'b0}};
            rd_valid    <= 1'b0;
            dst_we      <= 1'b0;
            src_rd_addr <= {ADDR_W{1'b0}};
        end else begin
            done   <= 1'b0;
            dst_we <= 1'b0;

            if (start && !busy) begin
                busy     <= 1'b1;
                base_src <= src_addr;
                base_dst <= dst_addr;
                len_reg  <= length;
                count    <= {LEN_W+1{1'b0}};
                wcount   <= {LEN_W+1{1'b0}};
                rd_valid <= 1'b0;

                if (length == 0) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end else if (busy) begin
                // Issue the next read
                if (count < len_reg) begin
                    src_rd_addr <= base_src + count[ADDR_W-1:0];
                    rd_valid    <= 1'b1;
                    count       <= count + 1'b1;
                end else begin
                    rd_valid <= 1'b0;
                end

                // Write back the word that was read one cycle earlier
                if (rd_valid) begin
                    dst_we      <= 1'b1;
                    dst_wr_addr <= base_dst + wcount[ADDR_W-1:0];
                    dst_wr_data <= src_rd_data;
                    wcount      <= wcount + 1'b1;

                    if (wcount + 1'b1 == len_reg) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
