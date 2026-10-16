// Convert a stream of 32-bit DMA words into a stream of 24-bit RGB pixels.
//
// Assumption used by this design:
//   dma_data[31:24], [23:16], [15:8], [7:0] are four consecutive bytes
//   in the RGB byte stream.  Therefore 32'h01_02_03_04 produces bytes
//   01,02,03,04 and the next DMA word continues the same byte stream.
//
// The fourth byte of one DMA word may belong to the next RGB pixel.  The
// three-byte packer below deliberately retains that byte across words.
// The unpacker keeps a byte reservoir so a complete RGB pixel can be emitted
// every clock once the reservoir is primed.  Data is held while rgb_ready=0.

module dma32_to_rgb24 #(
    parameter MSB_FIRST = 1'b1
) (
    input  wire        clk,
    input  wire        rst,

    input  wire [31:0] dma_data,
    input  wire        dma_valid,
    output wire        dma_ready,

    output wire [23:0] rgb_data,
    output wire        rgb_valid,
    input  wire        rgb_ready
);

    // Valid bytes are kept left-aligned in the reservoir.  byte_count is the
    // number of valid bytes in byte_reservoir[63:64-byte_count*8].
    reg [63:0] byte_reservoir;
    reg [3:0]  byte_count;
    reg [63:0] next_reservoir;
    reg [3:0]  next_count;
    wire [31:0] ordered_dma_data = MSB_FIRST ? dma_data :
                                    {dma_data[7:0], dma_data[15:8],
                                     dma_data[23:16], dma_data[31:24]};

    wire output_valid = (byte_count >= 4'd3);
    wire output_pop   = output_valid && rgb_ready;

    // Four new bytes can be accepted if there are at most four bytes already
    // buffered.  With a simultaneous output pop, counts 5..7 also have room.
    assign dma_ready = (byte_count <= 4'd4) ||
                       ((byte_count <= 4'd7) && rgb_ready);
    assign rgb_data  = byte_reservoir[63:40];
    assign rgb_valid = output_valid;

    always @(posedge clk) begin
        if (rst) begin
            byte_reservoir <= 64'd0;
            byte_count     <= 4'd0;
        end else begin
            next_reservoir = byte_reservoir;
            next_count     = byte_count;

            if (output_pop) begin
                next_reservoir = next_reservoir << 24;
                next_count     = next_count - 4'd3;
            end

            if (dma_valid && dma_ready) begin
                // Append the new MSB-first word after the bytes left in the
                // reservoir.  The ready equation guarantees next_count<=4.
                case (next_count)
                    4'd0: next_reservoir = {ordered_dma_data, 32'd0};
                    4'd1: next_reservoir = {next_reservoir[63:56], ordered_dma_data, 24'd0};
                    4'd2: next_reservoir = {next_reservoir[63:48], ordered_dma_data, 16'd0};
                    4'd3: next_reservoir = {next_reservoir[63:40], ordered_dma_data, 8'd0};
                    default: next_reservoir = {next_reservoir[63:32], ordered_dma_data};
                endcase
                next_count = next_count + 4'd4;
            end

            byte_reservoir <= next_reservoir;
            byte_count     <= next_count;
        end
    end

endmodule
