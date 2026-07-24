`timescale 1ns / 1ps
`default_nettype none

module tb_apb_top_unit;
   localparam [31:0] UART_BASE = 32'h40000000;
   localparam [31:0] SPI_BASE  = 32'h40001000;
   localparam [31:0] I2C_BASE  = 32'h40002000;

   reg clk = 1'b0;
   reg rst_n = 1'b0;

   reg  [31:0] PADDR = 32'h00000000;
   reg         PSEL = 1'b0;
   reg         PWRITE = 1'b0;
   reg         PENABLE = 1'b0;
   reg  [31:0] PWDATA = 32'h00000000;
   wire [31:0] PRDATA;
   wire        PREADY;
   wire        PSLVERR;

   wire uart_tx;
   reg  uart_rx = 1'b1;
   wire spi_sclk;
   wire spi_mosi;
   reg  spi_miso = 1'b1;
   wire spi_cs;
   wire i2c_scl;
   wire i2c_sda_out;
   wire i2c_sda_oe;
   wire i2c_sda;
   reg  i2c_slave_ack_drive_low = 1'b0;

   always #5 clk = ~clk;

   pullup(i2c_sda);
   assign i2c_sda = i2c_sda_oe ? i2c_sda_out : 1'bz;
   assign i2c_sda = i2c_slave_ack_drive_low ? 1'b0 : 1'bz;

   apb_top #(
      .CLK_FREQ(20),
      .BAUD_RATE(10)
   ) dut (
      .clk(clk),
      .rst_n(rst_n),
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
      .spi_sclk(spi_sclk),
      .spi_mosi(spi_mosi),
      .spi_miso(spi_miso),
      .spi_cs(spi_cs),
      .scl_out(i2c_scl),
      .sda_out(i2c_sda_out),
      .sda_oe(i2c_sda_oe),
      .sda_in(i2c_sda)
   );

   task fail;
      input [127:0] message;
      begin
         $display("FAIL: %0s", message);
         $finish;
      end
   endtask

   task apb_read;
      input [31:0] addr;
      output [31:0] data;
      begin
         @(negedge clk);
         PADDR   <= addr;
         PWRITE  <= 1'b0;
         PSEL    <= 1'b1;
         PENABLE <= 1'b0;
         @(posedge clk);
         #1;
         PENABLE <= 1'b1;
         while (!PREADY) begin
            @(posedge clk);
            #1;
         end
         data = PRDATA;
         @(posedge clk);
         #1;
         PSEL    <= 1'b0;
         PENABLE <= 1'b0;
         PADDR   <= 32'h00000000;
      end
   endtask

   initial begin
      $dumpfile("tb_apb_top_unit.vcd");
      $dumpvars(0, tb_apb_top_unit);

      repeat (4) @(posedge clk);
      rst_n <= 1'b1;
      repeat (2) @(posedge clk);

      if (dut.psel_uart !== 1'b0 || dut.psel_spi !== 1'b0 || dut.psel_i2c !== 1'b0) begin
         fail("APB top slaves should be idle after reset");
      end

      begin : uart_check
         reg [31:0] data;
         apb_read(UART_BASE + 32'h08, data);
         if (!dut.psel_uart || dut.psel_spi || dut.psel_i2c) fail("UART decode failed in apb_top");
         if (PREADY !== 1'b1) fail("UART read should be ready in apb_top");
         if (data[1:0] !== 2'b01) fail("UART status mux returned wrong value");
      end

      begin : spi_check
         reg [31:0] data;
         apb_read(SPI_BASE + 32'h08, data);
         if (dut.psel_uart || !dut.psel_spi || dut.psel_i2c) fail("SPI decode failed in apb_top");
         if (data[0] !== 1'b0) fail("SPI status mux returned wrong value");
      end

      begin : i2c_check
         reg [31:0] data;
         apb_read(I2C_BASE + 32'h08, data);
         if (dut.psel_uart || dut.psel_spi || !dut.psel_i2c) fail("I2C decode failed in apb_top");
         if (data[1:0] !== 2'b00) fail("I2C status mux returned wrong value");
      end

      if (PSLVERR !== 1'b0) fail("PSLVERR should be tied low at apb_top");

      $display("PASS: apb_top self-check completed");
      $finish;
   end
endmodule

`default_nettype wire