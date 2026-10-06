`timescale 1ns/1ps

// AXI4-Lite peripheral crossbar.
// Address map:
//   0x4000_0000 - 0x4000_0FFF : UART
//   0x4000_1000 - 0x4000_1FFF : SPI
//   0x4000_2000 - 0x4000_2FFF : I2C
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
    localparam [1:0] SEL_UART = 2'd0;
    localparam [1:0] SEL_SPI  = 2'd1;
    localparam [1:0] SEL_I2C  = 2'd2;
    localparam [1:0] SEL_NONE = 2'd3;

    wire aw_uart = (S_AXI_AWADDR[31:12] == 20'h40000);
    wire aw_spi  = (S_AXI_AWADDR[31:12] == 20'h40001);
    wire aw_i2c  = (S_AXI_AWADDR[31:12] == 20'h40002);
    wire ar_uart = (S_AXI_ARADDR[31:12] == 20'h40000);
    wire ar_spi  = (S_AXI_ARADDR[31:12] == 20'h40001);
    wire ar_i2c  = (S_AXI_ARADDR[31:12] == 20'h40002);

    reg [1:0] write_sel;
    reg [1:0] read_sel;

    wire [1:0] write_sel_now = aw_uart ? SEL_UART :
                               aw_spi  ? SEL_SPI  :
                               aw_i2c  ? SEL_I2C  : SEL_NONE;
    wire [1:0] read_sel_now  = ar_uart ? SEL_UART :
                               ar_spi  ? SEL_SPI  :
                               ar_i2c  ? SEL_I2C  : SEL_NONE;

    wire uart_awready, uart_wready, uart_bvalid, uart_arready, uart_rvalid;
    wire spi_awready,  spi_wready,  spi_bvalid,  spi_arready,  spi_rvalid;
    wire i2c_awready,  i2c_wready,  i2c_bvalid,  i2c_arready,  i2c_rvalid;
    wire [1:0] uart_bresp, spi_bresp, i2c_bresp;
    wire [1:0] uart_rresp, spi_rresp, i2c_rresp;
    wire [31:0] uart_rdata, spi_rdata, i2c_rdata;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_sel <= SEL_NONE;
            read_sel  <= SEL_NONE;
        end else begin
            if (S_AXI_AWVALID && S_AXI_AWREADY)
                write_sel <= write_sel_now;
            else if (S_AXI_BVALID && S_AXI_BREADY)
                write_sel <= SEL_NONE;

            if (S_AXI_ARVALID && S_AXI_ARREADY)
                read_sel <= read_sel_now;
            else if (S_AXI_RVALID && S_AXI_RREADY)
                read_sel <= SEL_NONE;
        end
    end

    wire [1:0] active_write_sel = (write_sel != SEL_NONE) ? write_sel : write_sel_now;
    wire [1:0] active_read_sel  = (read_sel  != SEL_NONE) ? read_sel  : read_sel_now;

    assign S_AXI_AWREADY = (active_write_sel == SEL_UART) ? uart_awready :
                           (active_write_sel == SEL_SPI)  ? spi_awready  :
                           (active_write_sel == SEL_I2C)  ? i2c_awready  : 1'b0;
    assign S_AXI_WREADY  = (active_write_sel == SEL_UART) ? uart_wready :
                           (active_write_sel == SEL_SPI)  ? spi_wready  :
                           (active_write_sel == SEL_I2C)  ? i2c_wready  : 1'b0;
    assign S_AXI_BVALID  = (active_write_sel == SEL_UART) ? uart_bvalid :
                           (active_write_sel == SEL_SPI)  ? spi_bvalid  :
                           (active_write_sel == SEL_I2C)  ? i2c_bvalid  : 1'b0;
    assign S_AXI_BRESP   = (active_write_sel == SEL_UART) ? uart_bresp :
                           (active_write_sel == SEL_SPI)  ? spi_bresp  :
                           (active_write_sel == SEL_I2C)  ? i2c_bresp  : 2'b11;

    assign S_AXI_ARREADY = (active_read_sel == SEL_UART) ? uart_arready :
                           (active_read_sel == SEL_SPI)  ? spi_arready  :
                           (active_read_sel == SEL_I2C)  ? i2c_arready  : 1'b0;
    assign S_AXI_RVALID  = (active_read_sel == SEL_UART) ? uart_rvalid :
                           (active_read_sel == SEL_SPI)  ? spi_rvalid  :
                           (active_read_sel == SEL_I2C)  ? i2c_rvalid  : 1'b0;
    assign S_AXI_RDATA   = (active_read_sel == SEL_UART) ? uart_rdata :
                           (active_read_sel == SEL_SPI)  ? spi_rdata  :
                           (active_read_sel == SEL_I2C)  ? i2c_rdata  : 32'h0;
    assign S_AXI_RRESP   = (active_read_sel == SEL_UART) ? uart_rresp :
                           (active_read_sel == SEL_SPI)  ? spi_rresp  :
                           (active_read_sel == SEL_I2C)  ? i2c_rresp  : 2'b11;

    axi_uart_slave #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart (
        .clk(clk), .rst_n(rst_n),
        .S_AXI_AWADDR(S_AXI_AWADDR), .S_AXI_AWVALID(S_AXI_AWVALID && (active_write_sel == SEL_UART)), .S_AXI_AWREADY(uart_awready),
        .S_AXI_WDATA(S_AXI_WDATA), .S_AXI_WSTRB(S_AXI_WSTRB), .S_AXI_WVALID(S_AXI_WVALID && (active_write_sel == SEL_UART)), .S_AXI_WREADY(uart_wready),
        .S_AXI_BRESP(uart_bresp), .S_AXI_BVALID(uart_bvalid), .S_AXI_BREADY(S_AXI_BREADY && (active_write_sel == SEL_UART)),
        .S_AXI_ARADDR(S_AXI_ARADDR), .S_AXI_ARVALID(S_AXI_ARVALID && (active_read_sel == SEL_UART)), .S_AXI_ARREADY(uart_arready),
        .S_AXI_RDATA(uart_rdata), .S_AXI_RRESP(uart_rresp), .S_AXI_RVALID(uart_rvalid), .S_AXI_RREADY(S_AXI_RREADY && (active_read_sel == SEL_UART)),
        .uart_tx(uart_tx), .uart_rx(uart_rx)
    );

    axi_spi_slave u_spi (
        .clk(clk), .rst_n(rst_n),
        .S_AXI_AWADDR(S_AXI_AWADDR), .S_AXI_AWVALID(S_AXI_AWVALID && (active_write_sel == SEL_SPI)), .S_AXI_AWREADY(spi_awready),
        .S_AXI_WDATA(S_AXI_WDATA), .S_AXI_WSTRB(S_AXI_WSTRB), .S_AXI_WVALID(S_AXI_WVALID && (active_write_sel == SEL_SPI)), .S_AXI_WREADY(spi_wready),
        .S_AXI_BRESP(spi_bresp), .S_AXI_BVALID(spi_bvalid), .S_AXI_BREADY(S_AXI_BREADY && (active_write_sel == SEL_SPI)),
        .S_AXI_ARADDR(S_AXI_ARADDR), .S_AXI_ARVALID(S_AXI_ARVALID && (active_read_sel == SEL_SPI)), .S_AXI_ARREADY(spi_arready),
        .S_AXI_RDATA(spi_rdata), .S_AXI_RRESP(spi_rresp), .S_AXI_RVALID(spi_rvalid), .S_AXI_RREADY(S_AXI_RREADY && (active_read_sel == SEL_SPI)),
        .spi_sclk(spi_sclk), .spi_mosi(spi_mosi), .spi_miso(spi_miso), .spi_cs(spi_cs)
    );

    axi_i2c_slave u_i2c (
        .clk(clk), .rst_n(rst_n),
        .S_AXI_AWADDR(S_AXI_AWADDR), .S_AXI_AWVALID(S_AXI_AWVALID && (active_write_sel == SEL_I2C)), .S_AXI_AWREADY(i2c_awready),
        .S_AXI_WDATA(S_AXI_WDATA), .S_AXI_WSTRB(S_AXI_WSTRB), .S_AXI_WVALID(S_AXI_WVALID && (active_write_sel == SEL_I2C)), .S_AXI_WREADY(i2c_wready),
        .S_AXI_BRESP(i2c_bresp), .S_AXI_BVALID(i2c_bvalid), .S_AXI_BREADY(S_AXI_BREADY && (active_write_sel == SEL_I2C)),
        .S_AXI_ARADDR(S_AXI_ARADDR), .S_AXI_ARVALID(S_AXI_ARVALID && (active_read_sel == SEL_I2C)), .S_AXI_ARREADY(i2c_arready),
        .S_AXI_RDATA(i2c_rdata), .S_AXI_RRESP(i2c_rresp), .S_AXI_RVALID(i2c_rvalid), .S_AXI_RREADY(S_AXI_RREADY && (active_read_sel == SEL_I2C)),
        .scl_out(scl_out), .sda_out(sda_out), .sda_oe(sda_oe), .sda_in(sda_in)
    );
endmodule
