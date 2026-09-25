// Integration block:
//   32-bit DMA stream -> RGB unpacker -> input FIFO -> CNN pixel stream
//
// pixel_ready is normally connected to the CNN's ready_out.  It is allowed
// to remain low for an arbitrary number of cycles; the FIFO then backpressures
// the unpacker and finally dma_ready.

module cnn_input_frontend #(
    parameter FIFO_DEPTH = 64,
    parameter MSB_FIRST  = 1'b1
) (
    input  wire        clk,
    input  wire        rst,

    input  wire [31:0] dma_data,
    input  wire        dma_valid,
    output wire        dma_ready,

    output wire [23:0] pixel_data,
    output wire        pixel_valid,
    input  wire        pixel_ready,

    output wire        fifo_full,
    output wire        fifo_empty
);

    wire [23:0] unpacked_data;
    wire        unpacked_valid;
    wire        unpacked_ready;

    dma32_to_rgb24 #(
        .MSB_FIRST(MSB_FIRST)
    ) u_dma32_to_rgb24 (
        .clk       (clk),
        .rst       (rst),
        .dma_data  (dma_data),
        .dma_valid (dma_valid),
        .dma_ready (dma_ready),
        .rgb_data  (unpacked_data),
        .rgb_valid (unpacked_valid),
        .rgb_ready (unpacked_ready)
    );

    input_fifo_rgb #(
        .DATA_WIDTH(24),
        .DEPTH     (FIFO_DEPTH)
    ) u_input_fifo_rgb (
        .clk       (clk),
        .rst       (rst),
        .in_data   (unpacked_data),
        .in_valid  (unpacked_valid),
        .in_ready  (unpacked_ready),
        .out_data  (pixel_data),
        .out_valid (pixel_valid),
        .out_ready (pixel_ready),
        .full      (fifo_full),
        .empty     (fifo_empty)
    );

endmodule
