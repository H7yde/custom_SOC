`timescale 1ns/1ps

// AXI4-Lite peripheral fabric for the UART, SPI and I2C blocks.
// Address map:
//   0x4000_0000 - 0x4000_0FFF : UART
//   0x4000_1000 - 0x4000_1FFF : SPI
//   0x4000_2000 - 0x4000_2FFF : I2C
//
// The individual slaves only use the low byte of the address for their
// registers.  This module is therefore responsible for the high-address
// decode and for returning only the selected slave's handshake signals.
module soc_axi_top #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire [31:0] S_AXI_AWADDR,
    input  wire        S_AXI_AWVALID,
    output wire        S_AXI_AWREADY,
    input  wire [31:0] S_AXI_WDATA,
    input  wire [ 3:0] S_AXI_WSTRB,
    input  wire        S_AXI_WVALID,
    output wire        S_AXI_WREADY,
    output wire [ 1:0] S_AXI_BRESP,
    output wire        S_AXI_BVALID,
    input  wire        S_AXI_BREADY,
    input  wire [31:0] S_AXI_ARADDR,
    input  wire        S_AXI_ARVALID,
    output wire        S_AXI_ARREADY,
    output wire [31:0] S_AXI_RDATA,
    output wire [ 1:0] S_AXI_RRESP,
    output wire        S_AXI_RVALID,
    input  wire        S_AXI_RREADY,

    output wire        uart_tx,
    input  wire        uart_rx,
    output wire        spi_sclk,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire        spi_cs,
    output wire        scl_out,
    output wire        sda_out,
    output wire        sda_oe,
    input  wire        sda_in
);
    wire sel_uart_w = (S_AXI_AWADDR[31:12] == 20'h40000);
    wire sel_spi_w  = (S_AXI_AWADDR[31:12] == 20'h40001);
    wire sel_i2c_w  = (S_AXI_AWADDR[31:12] == 20'h40002);
    wire sel_uart_r = (S_AXI_ARADDR[31:12] == 20'h40000);
    wire sel_spi_r  = (S_AXI_ARADDR[31:12] == 20'h40001);
    wire sel_i2c_r  = (S_AXI_ARADDR[31:12] == 20'h40002);

    wire uart_awready, uart_wready, uart_bvalid, uart_arready, uart_rvalid;
    wire spi_awready,  spi_wready,  spi_bvalid,  spi_arready,  spi_rvalid;
    wire i2c_awready,  i2c_wready,  i2c_bvalid,  i2c_arready,  i2c_rvalid;
    wire [1:0] uart_bresp, uart_rresp, spi_bresp, spi_rresp, i2c_bresp, i2c_rresp;
    wire [31:0] uart_rdata, spi_rdata, i2c_rdata;

    assign S_AXI_AWREADY = (sel_uart_w ? uart_awready : 1'b0) |
                           (sel_spi_w  ? spi_awready  : 1'b0) |
                           (sel_i2c_w  ? i2c_awready  : 1'b0);
    assign S_AXI_WREADY  = (sel_uart_w ? uart_wready : 1'b0) |
                           (sel_spi_w  ? spi_wready  : 1'b0) |
                           (sel_i2c_w  ? i2c_wready  : 1'b0);
    assign S_AXI_BVALID  = (sel_uart_w ? uart_bvalid : 1'b0) |
                           (sel_spi_w  ? spi_bvalid  : 1'b0) |
                           (sel_i2c_w  ? i2c_bvalid  : 1'b0);
    assign S_AXI_BRESP   = sel_uart_w ? uart_bresp :
                           sel_spi_w  ? spi_bresp  :
                           sel_i2c_w  ? i2c_bresp  : 2'b11;

    assign S_AXI_ARREADY = (sel_uart_r ? uart_arready : 1'b0) |
                           (sel_spi_r  ? spi_arready  : 1'b0) |
                           (sel_i2c_r  ? i2c_arready  : 1'b0);
    assign S_AXI_RVALID  = (sel_uart_r ? uart_rvalid : 1'b0) |
                           (sel_spi_r  ? spi_rvalid  : 1'b0) |
                           (sel_i2c_r  ? i2c_rvalid  : 1'b0);
    assign S_AXI_RDATA   = sel_uart_r ? uart_rdata :
                           sel_spi_r  ? spi_rdata  :
                           sel_i2c_r  ? i2c_rdata  : 32'h0;
    assign S_AXI_RRESP   = sel_uart_r ? uart_rresp :
                           sel_spi_r  ? spi_rresp  :
                           sel_i2c_r  ? i2c_rresp  : 2'b11;

    axi_uart_slave #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_uart (
        .clk(clk), .rst_n(rst_n),
        .S_AXI_AWADDR(S_AXI_AWADDR), .S_AXI_AWVALID(S_AXI_AWVALID & sel_uart_w), .S_AXI_AWREADY(uart_awready),
        .S_AXI_WDATA(S_AXI_WDATA), .S_AXI_WSTRB(S_AXI_WSTRB), .S_AXI_WVALID(S_AXI_WVALID & sel_uart_w), .S_AXI_WREADY(uart_wready),
        .S_AXI_BRESP(uart_bresp), .S_AXI_BVALID(uart_bvalid), .S_AXI_BREADY(S_AXI_BREADY & sel_uart_w),
        .S_AXI_ARADDR(S_AXI_ARADDR), .S_AXI_ARVALID(S_AXI_ARVALID & sel_uart_r), .S_AXI_ARREADY(uart_arready),
        .S_AXI_RDATA(uart_rdata), .S_AXI_RRESP(uart_rresp), .S_AXI_RVALID(uart_rvalid), .S_AXI_RREADY(S_AXI_RREADY & sel_uart_r),
        .uart_tx(uart_tx), .uart_rx(uart_rx)
    );

    axi_spi_slave u_spi (
        .clk(clk), .rst_n(rst_n),
        .S_AXI_AWADDR(S_AXI_AWADDR), .S_AXI_AWVALID(S_AXI_AWVALID & sel_spi_w), .S_AXI_AWREADY(spi_awready),
        .S_AXI_WDATA(S_AXI_WDATA), .S_AXI_WSTRB(S_AXI_WSTRB), .S_AXI_WVALID(S_AXI_WVALID & sel_spi_w), .S_AXI_WREADY(spi_wready),
        .S_AXI_BRESP(spi_bresp), .S_AXI_BVALID(spi_bvalid), .S_AXI_BREADY(S_AXI_BREADY & sel_spi_w),
        .S_AXI_ARADDR(S_AXI_ARADDR), .S_AXI_ARVALID(S_AXI_ARVALID & sel_spi_r), .S_AXI_ARREADY(spi_arready),
        .S_AXI_RDATA(spi_rdata), .S_AXI_RRESP(spi_rresp), .S_AXI_RVALID(spi_rvalid), .S_AXI_RREADY(S_AXI_RREADY & sel_spi_r),
        .spi_sclk(spi_sclk), .spi_mosi(spi_mosi), .spi_miso(spi_miso), .spi_cs(spi_cs)
    );

    axi_i2c_slave u_i2c (
        .clk(clk), .rst_n(rst_n),
        .S_AXI_AWADDR(S_AXI_AWADDR), .S_AXI_AWVALID(S_AXI_AWVALID & sel_i2c_w), .S_AXI_AWREADY(i2c_awready),
        .S_AXI_WDATA(S_AXI_WDATA), .S_AXI_WSTRB(S_AXI_WSTRB), .S_AXI_WVALID(S_AXI_WVALID & sel_i2c_w), .S_AXI_WREADY(i2c_wready),
        .S_AXI_BRESP(i2c_bresp), .S_AXI_BVALID(i2c_bvalid), .S_AXI_BREADY(S_AXI_BREADY & sel_i2c_w),
        .S_AXI_ARADDR(S_AXI_ARADDR), .S_AXI_ARVALID(S_AXI_ARVALID & sel_i2c_r), .S_AXI_ARREADY(i2c_arready),
        .S_AXI_RDATA(i2c_rdata), .S_AXI_RRESP(i2c_rresp), .S_AXI_RVALID(i2c_rvalid), .S_AXI_RREADY(S_AXI_RREADY & sel_i2c_r),
        .scl_out(scl_out), .sda_out(sda_out), .sda_oe(sda_oe), .sda_in(sda_in)
    );
endmodule
