`timescale 1ns / 1ps

// Small on-chip memory subsystem used as an AXI-accessible DDR surrogate
// for the CNN DMA path.  The memory is split into two 768-word frame
// buffers.  The CPU fills a buffer through AXI4-Lite and the CNN reads the
// selected buffer through its read-only AXI master port.
//
// Address map (BASE_ADDR = 0x40006000 by default):
//   BASE_ADDR + 0x000 .. 0xBFC : buffer 0 (768 words)
//   BASE_ADDR + 0xC00 .. 0x17FC: buffer 1 (768 words)
//
// This module intentionally keeps the AXI data width at 32 bits so that it
// can be used with the existing AXI4-Lite crossbar.  On a board with a real
// DDR controller, this module can be replaced by an AXI BRAM/DDR slave
// without changing the CNN register interface or DMA master.
module cnn_memory_subsystem #(
    parameter [31:0] BASE_ADDR   = 32'h4000_6000,
    parameter integer BUFFER_WORDS = 768,
    parameter integer TOTAL_WORDS  = 1536
)(
    input  wire        clk,
    input  wire        rst_n,

    // CPU AXI4-Lite slave interface.
    input  wire [31:0] S_AXI_AWADDR,
    input  wire        S_AXI_AWVALID,
    output wire        S_AXI_AWREADY,
    input  wire [31:0] S_AXI_WDATA,
    input  wire [3:0]  S_AXI_WSTRB,
    input  wire        S_AXI_WVALID,
    output wire        S_AXI_WREADY,
    output wire [1:0]  S_AXI_BRESP,
    output wire        S_AXI_BVALID,
    input  wire        S_AXI_BREADY,
    input  wire [31:0] S_AXI_ARADDR,
    input  wire        S_AXI_ARVALID,
    output wire        S_AXI_ARREADY,
    output wire [31:0] S_AXI_RDATA,
    output wire [1:0]  S_AXI_RRESP,
    output wire        S_AXI_RVALID,
    input  wire        S_AXI_RREADY,

    // CNN read-only AXI master channel.
    input  wire [31:0] DMA_ARADDR,
    input  wire        DMA_ARVALID,
    output wire        DMA_ARREADY,
    output wire [31:0] DMA_RDATA,
    output wire        DMA_RVALID,
    input  wire        DMA_RREADY
);
    localparam integer MEM_BYTES = TOTAL_WORDS * 4;

    reg [31:0] mem [0:TOTAL_WORDS-1];

    reg        aw_pending;
    reg        w_pending;
    reg [31:0] awaddr_reg;
    reg [31:0] wdata_reg;
    reg [3:0]  wstrb_reg;
    reg        bvalid_reg;

    reg        rvalid_reg;
    reg [31:0] rdata_reg;
    reg        dma_rvalid_reg;
    reg [31:0] dma_rdata_reg;

    wire [31:0] cpu_write_offset = S_AXI_AWADDR - BASE_ADDR;
    wire [31:0] cpu_read_offset  = S_AXI_ARADDR  - BASE_ADDR;
    wire [31:0] dma_read_offset  = DMA_ARADDR   - BASE_ADDR;
    wire [10:0] cpu_write_index = cpu_write_offset[12:2];
    wire [10:0] cpu_read_index  = cpu_read_offset[12:2];
    wire [10:0] dma_read_index  = dma_read_offset[12:2];

    wire write_fire = aw_pending && w_pending && !bvalid_reg;

    // DMA reads have priority over CPU reads so a CNN transfer cannot be
    // starved by software polling the memory window.
    assign S_AXI_AWREADY = !aw_pending && !bvalid_reg;
    assign S_AXI_WREADY  = !w_pending  && !bvalid_reg;
    assign S_AXI_BRESP   = 2'b00;
    assign S_AXI_BVALID  = bvalid_reg;

    assign DMA_ARREADY   = !dma_rvalid_reg && !rvalid_reg && !S_AXI_ARVALID;
    assign S_AXI_ARREADY = !rvalid_reg && !dma_rvalid_reg && !DMA_ARVALID;
    assign S_AXI_RDATA   = rdata_reg;
    assign S_AXI_RRESP   = 2'b00;
    assign S_AXI_RVALID  = rvalid_reg;
    assign DMA_RDATA     = dma_rdata_reg;
    assign DMA_RVALID    = dma_rvalid_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            aw_pending    <= 1'b0;
            w_pending     <= 1'b0;
            awaddr_reg    <= 32'd0;
            wdata_reg     <= 32'd0;
            wstrb_reg     <= 4'd0;
            bvalid_reg    <= 1'b0;
            rvalid_reg    <= 1'b0;
            rdata_reg     <= 32'd0;
            dma_rvalid_reg<= 1'b0;
            dma_rdata_reg <= 32'd0;
        end else begin
            if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                awaddr_reg <= S_AXI_AWADDR;
                aw_pending <= 1'b1;
            end
            if (S_AXI_WVALID && S_AXI_WREADY) begin
                wdata_reg <= S_AXI_WDATA;
                wstrb_reg <= S_AXI_WSTRB;
                w_pending  <= 1'b1;
            end

            if (write_fire) begin
                aw_pending <= 1'b0;
                w_pending  <= 1'b0;
                bvalid_reg <= 1'b1;
                if ((cpu_write_offset < MEM_BYTES) &&
                    (cpu_write_index < TOTAL_WORDS)) begin
                    if (wstrb_reg[0]) mem[cpu_write_index][7:0]   <= wdata_reg[7:0];
                    if (wstrb_reg[1]) mem[cpu_write_index][15:8]  <= wdata_reg[15:8];
                    if (wstrb_reg[2]) mem[cpu_write_index][23:16] <= wdata_reg[23:16];
                    if (wstrb_reg[3]) mem[cpu_write_index][31:24] <= wdata_reg[31:24];
                end
            end

            if (bvalid_reg && S_AXI_BREADY)
                bvalid_reg <= 1'b0;

            if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                rvalid_reg <= 1'b1;
                if ((cpu_read_offset < MEM_BYTES) &&
                    (cpu_read_index < TOTAL_WORDS))
                    rdata_reg <= mem[cpu_read_index];
                else
                    rdata_reg <= 32'h0000_0000;
            end else if (rvalid_reg && S_AXI_RREADY) begin
                rvalid_reg <= 1'b0;
            end

            if (DMA_ARVALID && DMA_ARREADY) begin
                dma_rvalid_reg <= 1'b1;
                if ((dma_read_offset < MEM_BYTES) &&
                    (dma_read_index < TOTAL_WORDS))
                    dma_rdata_reg <= mem[dma_read_index];
                else
                    dma_rdata_reg <= 32'h0000_0000;
            end else if (dma_rvalid_reg && DMA_RREADY) begin
                dma_rvalid_reg <= 1'b0;
            end
        end
    end
endmodule
