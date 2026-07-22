`timescale 1ns / 1ps
`default_nettype none

module tb_apb_peripherals_wave;
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
   reg  spi_miso = 1'b0;
   wire spi_cs;

   wire i2c_scl;
   wire i2c_sda_out;
   wire i2c_sda_oe;
   wire i2c_sda;
   wire i2c_sda_in;
   reg  i2c_slave_ack_drive_low = 1'b0;

   always #5 clk = ~clk;

   pullup(i2c_sda);
   assign i2c_sda = i2c_sda_oe ? i2c_sda_out : 1'bz;
   assign i2c_sda = i2c_slave_ack_drive_low ? 1'b0 : 1'bz;
   assign i2c_sda_in = i2c_sda;

   apb_top #(
      .CLK_FREQ(1_000_000),
      .BAUD_RATE(100_000)
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
      .sda_in(i2c_sda_in)
   );

   task apb_write;
      input [31:0] addr;
      input [31:0] data;
      begin
         @(posedge clk);
         PADDR <= addr;
         PSEL <= 1'b1;
         PWDATA <= data;
         PWRITE <= 1'b1;
         PENABLE <= 1'b0;

         @(posedge clk);
         PENABLE <= 1'b1;

         while (!PREADY) begin
            @(posedge clk);
         end

         @(posedge clk);
         PENABLE <= 1'b0;
         PSEL <= 1'b0;
         PWRITE <= 1'b0;
         PADDR <= 32'h00000000;
         PWDATA <= 32'h00000000;
      end
   endtask

   task apb_read;
      input [31:0] addr;
      begin
         @(posedge clk);
         PADDR <= addr;
         PSEL <= 1'b1;
         PWDATA <= 32'h00000000;
         PWRITE <= 1'b0;
         PENABLE <= 1'b0;

         @(posedge clk);
         PENABLE <= 1'b1;

         while (!PREADY) begin
            @(posedge clk);
         end

         @(posedge clk);
         PENABLE <= 1'b0;
         PSEL <= 1'b0;
         PADDR <= 32'h00000000;
      end
   endtask

   initial begin
      $dumpfile("tb_apb_peripherals_wave.vcd");
      $dumpvars(0, tb_apb_peripherals_wave);

      repeat (8) @(posedge clk);
      rst_n <= 1'b1;
      repeat (4) @(posedge clk);

      // UART: write one byte to TX data register.
      apb_write(UART_BASE + 32'h00, 32'h00000055);
      repeat (140) @(posedge clk);

      // SPI: assert chip select low, then start an 8-bit transfer.
      spi_miso <= 1'b1;
      apb_write(SPI_BASE + 32'h04, 32'h00000000);
      apb_write(SPI_BASE + 32'h00, 32'h000000a5);
      repeat (140) @(posedge clk);
      apb_write(SPI_BASE + 32'h04, 32'h00000001);
      repeat (20) @(posedge clk);

      // I2C: START, write one byte, then STOP. Pull SDA low during ACK window.
      apb_write(I2C_BASE + 32'h00, 32'h000000a0);
      apb_write(I2C_BASE + 32'h04, 32'h00000001);
      repeat (130) @(posedge clk);

      apb_write(I2C_BASE + 32'h04, 32'h00000004);
      repeat (380) @(posedge clk);
      i2c_slave_ack_drive_low <= 1'b1;
      repeat (80) @(posedge clk);
      i2c_slave_ack_drive_low <= 1'b0;
      repeat (80) @(posedge clk);

      apb_write(I2C_BASE + 32'h04, 32'h00000002);
      repeat (160) @(posedge clk);

      $finish;
   end
endmodule

`default_nettype wire
