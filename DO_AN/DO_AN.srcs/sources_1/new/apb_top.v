// ============================================================
//  SOC APB Top-level
//  Ket noi truc tiep voi 3 module goc:
//    - apb_uart_slave  (apb_uart_slave.v)
//    - apb_spi_slave   (apb_spi_slave.v)
//    - apb_i2c_slave   (apb_i2c_slave.v)
//
//  Memory map:
//    0x4000_0000 - 0x4000_0FFF  UART
//    0x4000_1000 - 0x4000_1FFF  SPI
//    0x4000_2000 - 0x4000_2FFF  I2C
// ============================================================

module apb_top #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire        clk,
    input  wire        rst_n,

    // APB master (tu picorv32_apb_bridge)
    input  wire [31:0] PADDR,
    input  wire        PSEL,
    input  wire        PWRITE,
    input  wire        PENABLE,
    input  wire [31:0] PWDATA,
    output reg  [31:0] PRDATA,
    output wire        PREADY,
    output wire        PSLVERR,

    // ── UART ──
    output wire        uart_tx,
    input  wire        uart_rx,
    // (apb_uart_slave khong co IRQ port, khong khai bao)

    // ── SPI ──
    output wire        spi_sclk,   // ten goc: spi_sclk
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire        spi_cs,     // 1-bit, ten goc: spi_cs

    // ── I2C ──
    output wire        scl_out,    // ten goc: scl_out
    output wire        sda_out,    // ten goc: sda_out
    output wire        sda_oe,
    input  wire        sda_in      // ten goc: sda_in
    // (apb_i2c_slave khong co scl_in, FPGA la master nen chi drive SCL)
);

    // --------------------------------------------------------
    // APB Decoder - sinh PSEL cho tung slave
    // --------------------------------------------------------
    wire psel_uart = PSEL && (PADDR[31:12] == 20'h40000);
    wire psel_spi  = PSEL && (PADDR[31:12] == 20'h40001);
    wire psel_i2c  = PSEL && (PADDR[31:12] == 20'h40002);

    // --------------------------------------------------------
    // PRDATA mux
    // --------------------------------------------------------
    wire [31:0] prdata_uart, prdata_spi, prdata_i2c;
    wire        pready_uart, pready_spi, pready_i2c;

    always @(*) begin
        case (1'b1)
            psel_uart: PRDATA = prdata_uart;
            psel_spi:  PRDATA = prdata_spi;
            psel_i2c:  PRDATA = prdata_i2c;
            default:   PRDATA = 32'h0;
        endcase
    end

    assign PREADY  = psel_uart ? pready_uart :
                     psel_spi  ? pready_spi  :
                     psel_i2c  ? pready_i2c  : 1'b1;
    assign PSLVERR = 1'b0;

    // --------------------------------------------------------
    // UART - apb_uart_slave
    //   Port goc: UART_PADDR, UART_PSEL, UART_PENABLE, UART_PWRITE,
    //             UART_PWDATA, UART_PRDATA, UART_PREADY (= PREADY)
    // --------------------------------------------------------
    apb_uart_slave #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart (
        .PCLK        (clk),
        .PRESETn     (rst_n),
        .UART_PADDR  ({24'h0, PADDR[7:0]}),   // chi dung 8-bit offset
        .UART_PSEL   (psel_uart),
        .UART_PENABLE(PENABLE),
        .UART_PWRITE (PWRITE),
        .UART_PWDATA (PWDATA),
        .UART_PRDATA (prdata_uart),
        .UART_PREADY (pready_uart),
        .uart_tx     (uart_tx),
        .uart_rx     (uart_rx)
    );

    // --------------------------------------------------------
    // SPI - apb_spi_slave
    //   Port goc: SPI_PADDR, SPI_PSEL, SPI_PENABLE, SPI_PWRITE,
    //             SPI_PWDATA, SPI_PRDATA, PREADY (= pready_spi)
    //   spi_cs: 1-bit (active low khi =0)
    // --------------------------------------------------------
    apb_spi_slave u_spi (
        .PCLK       (clk),
        .PRESETn    (rst_n),
        .SPI_PADDR  ({24'h0, PADDR[7:0]}),
        .SPI_PSEL   (psel_spi),
        .SPI_PENABLE(PENABLE),
        .SPI_PWRITE (PWRITE),
        .SPI_PWDATA (PWDATA),
        .SPI_PRDATA (prdata_spi),
        .PREADY     (pready_spi),
        .spi_sclk   (spi_sclk),
        .spi_cs     (spi_cs),
        .spi_mosi   (spi_mosi),
        .spi_miso   (spi_miso)
    );

    // --------------------------------------------------------
    // I2C - apb_i2c_slave
    //   Port goc: I2C_PADDR, I2C_PSEL, I2C_PENABLE, I2C_PWRITE,
    //             I2C_PWDATA, I2C_PRDATA, PREADY
    //   scl_out, sda_out, sda_oe, sda_in
    // --------------------------------------------------------
    apb_i2c_slave u_i2c (
        .PCLK       (clk),
        .PRESETn    (rst_n),
        .I2C_PADDR  ({24'h0, PADDR[7:0]}),
        .I2C_PSEL   (psel_i2c),
        .I2C_PENABLE(PENABLE),
        .I2C_PWRITE (PWRITE),
        .I2C_PWDATA (PWDATA),
        .I2C_PRDATA (prdata_i2c),
        .PREADY     (pready_i2c),
        .scl_out    (scl_out),
        .sda_out    (sda_out),
        .sda_oe     (sda_oe),
        .sda_in     (sda_in)
    );

endmodule
