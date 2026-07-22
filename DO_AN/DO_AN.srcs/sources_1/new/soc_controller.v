// Top-level controller for FemtoRV32 Quark + RAM + existing APB peripherals.
//
// Uses the existing files:
//   femtorv32_quark.v
//   femtosoc.v
//   apb_top.v
//   apb_uart_slave.v
//   apb_spi_slave.v
//   apb_i2c_slave.v
//
// Address map:
//   0x0000_0000 .. RAM_BYTES-1 : RAM
//   0x4000_0000 .. 0x4000_0FFF : UART
//   0x4000_1000 .. 0x4000_1FFF : SPI
//   0x4000_2000 .. 0x4000_2FFF : I2C

`default_nettype none

module soc_controller #(
   parameter integer RAM_BYTES = 32 * 1024,
   parameter         INIT_FILE = "",
   parameter [31:0]  RESET_ADDR = 32'h00000000,
   parameter integer ADDR_WIDTH = 32,
   parameter integer CLK_FREQ = 50_000_000,
   parameter integer BAUD_RATE = 115200
) (
   input  wire        clk,
   input  wire        reset,

   input  wire [31:0] gpio_in,
   output wire [31:0] gpio_out,
   output wire [31:0] gpio_oe,

   input  wire        uart_rx,
   output wire        uart_tx,

   output wire        spi_sck,
   output wire        spi_mosi,
   input  wire        spi_miso,
   output wire        spi_cs_n,

   output wire        i2c_scl,
   inout  wire        i2c_sda
);

   wire [31:0] cpu_mem_addr;
   wire [31:0] cpu_mem_wdata;
   wire [31:0] cpu_mem_rdata;
   wire [3:0]  cpu_mem_wmask;
   wire        cpu_mem_rstrb;
   wire        cpu_mem_rbusy;
   wire        cpu_mem_wbusy;

   wire [31:0] ram_mem_rdata;
   wire        ram_mem_rbusy;
   wire        ram_mem_wbusy;

   wire [31:0] apb_mem_rdata;
   wire        apb_mem_rbusy;
   wire        apb_mem_wbusy;

   wire [31:0] PADDR;
   wire        PWRITE;
   wire        PSEL;
   wire        PENABLE;
   wire [31:0] PWDATA;
   wire [31:0] PRDATA;
   wire        PREADY;
   wire        PSLVERR;

   wire ram_sel = (cpu_mem_addr < RAM_BYTES);
   wire apb_sel = (cpu_mem_addr[31:14] == 18'h10000) &&
                  (cpu_mem_addr[13:12] != 2'b11);

   assign cpu_mem_rdata =
      ram_sel ? ram_mem_rdata :
      apb_sel ? apb_mem_rdata :
                32'hdeadbeef;

   assign cpu_mem_rbusy =
      ram_sel ? ram_mem_rbusy :
      apb_sel ? apb_mem_rbusy :
                1'b0;

   assign cpu_mem_wbusy =
      ram_sel ? ram_mem_wbusy :
      apb_sel ? apb_mem_wbusy :
                1'b0;

   assign gpio_out = 32'h00000000;
   assign gpio_oe  = 32'h00000000;

   FemtoRV32 #(
      .RESET_ADDR(RESET_ADDR),
      .ADDR_WIDTH(ADDR_WIDTH)
   ) cpu (
      .clk(clk),
      .mem_addr(cpu_mem_addr),
      .mem_wdata(cpu_mem_wdata),
      .mem_wmask(cpu_mem_wmask),
      .mem_rdata(cpu_mem_rdata),
      .mem_rstrb(cpu_mem_rstrb),
      .mem_rbusy(cpu_mem_rbusy),
      .mem_wbusy(cpu_mem_wbusy),
      .reset(reset)
   );

   femto_ram #(
      .RAM_BYTES(RAM_BYTES),
      .INIT_FILE(INIT_FILE)
   ) ram (
      .clk(clk),
      .ram_sel(ram_sel),
      .mem_addr(cpu_mem_addr),
      .mem_wdata(cpu_mem_wdata),
      .mem_wmask(cpu_mem_wmask),
      .mem_rstrb(cpu_mem_rstrb),
      .mem_rdata(ram_mem_rdata),
      .mem_rbusy(ram_mem_rbusy),
      .mem_wbusy(ram_mem_wbusy)
   );

   wire i2c_sda_out;
   wire i2c_sda_oe;
   wire unused_pslverr = PSLVERR;
   wire [31:0] unused_gpio_in = gpio_in;

   assign i2c_sda = i2c_sda_oe ? i2c_sda_out : 1'bz;

   apb_bridge apb_bus_bridge (
      .clk(clk),
      .resetn(reset),
      .bus_sel(apb_sel),
      .mem_addr(cpu_mem_addr),
      .mem_wdata(cpu_mem_wdata),
      .mem_wmask(cpu_mem_wmask),
      .mem_rstrb(cpu_mem_rstrb),
      .mem_rdata(apb_mem_rdata),
      .mem_rbusy(apb_mem_rbusy),
      .mem_wbusy(apb_mem_wbusy),
      .PADDR(PADDR),
      .PWRITE(PWRITE),
      .PSEL(PSEL),
      .PENABLE(PENABLE),
      .PWDATA(PWDATA),
      .PRDATA(PRDATA),
      .PREADY(PREADY),
      .PSLVERR(PSLVERR)
   );

   apb_top #(
      .CLK_FREQ(CLK_FREQ),
      .BAUD_RATE(BAUD_RATE)
   ) apb_peripherals (
      .clk(clk),
      .rst_n(reset),
      .PADDR(PADDR),
      .PSEL(PSEL),
      .PWRITE(PWRITE),
      .PENABLE(PENABLE),
      .PWDATA(PWDATA),
      .PRDATA(PRDATA),
      .PREADY(PREADY),
      .PSLVERR(PSLVERR),
      .uart_tx(uart_tx),
      .uart_rx(uart_rx),
      .spi_sclk(spi_sck),
      .spi_mosi(spi_mosi),
      .spi_miso(spi_miso),
      .spi_cs(spi_cs_n),
      .scl_out(i2c_scl),
      .sda_out(i2c_sda_out),
      .sda_oe(i2c_sda_oe),
      .sda_in(i2c_sda)
   );
endmodule

`default_nettype wire
