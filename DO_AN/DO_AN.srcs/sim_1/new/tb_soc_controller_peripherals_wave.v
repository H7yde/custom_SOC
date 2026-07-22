`timescale 1ns / 1ps
`default_nettype none

module tb_soc_controller_peripherals_wave;
   localparam integer RAM_BYTES = 8 * 1024;

   reg clk = 1'b0;
   reg reset = 1'b0;

   reg  [31:0] gpio_in = 32'h00000000;
   wire [31:0] gpio_out;
   wire [31:0] gpio_oe;

   reg  uart_rx = 1'b1;
   wire uart_tx;

   wire spi_sck;
   wire spi_mosi;
   reg  spi_miso = 1'b1;
   wire spi_cs_n;

   wire i2c_scl;
   wire i2c_sda;
   reg  i2c_slave_ack_drive_low = 1'b0;

   integer pc;
   integer i;

   always #5 clk = ~clk;

   pullup(i2c_sda);
   assign i2c_sda = i2c_slave_ack_drive_low ? 1'b0 : 1'bz;

   soc_controller #(
      .RAM_BYTES(RAM_BYTES),
      .INIT_FILE(""),
      .RESET_ADDR(32'h00000000),
      .ADDR_WIDTH(32),
      .CLK_FREQ(1_000_000),
      .BAUD_RATE(100_000)
   ) dut (
      .clk(clk),
      .reset(reset),
      .gpio_in(gpio_in),
      .gpio_out(gpio_out),
      .gpio_oe(gpio_oe),
      .uart_rx(uart_rx),
      .uart_tx(uart_tx),
      .spi_sck(spi_sck),
      .spi_mosi(spi_mosi),
      .spi_miso(spi_miso),
      .spi_cs_n(spi_cs_n),
      .i2c_scl(i2c_scl),
      .i2c_sda(i2c_sda)
   );

   function [31:0] rv_lui;
      input [4:0] rd;
      input [19:0] imm20;
      begin
         rv_lui = {imm20, rd, 7'b0110111};
      end
   endfunction

   function [31:0] rv_addi;
      input [4:0] rd;
      input [4:0] rs1;
      input [11:0] imm;
      begin
         rv_addi = {imm, rs1, 3'b000, rd, 7'b0010011};
      end
   endfunction

   function [31:0] rv_sw;
      input [4:0] rs2;
      input [4:0] rs1;
      input [11:0] imm;
      begin
         rv_sw = {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011};
      end
   endfunction

   task emit;
      input [31:0] instr;
      begin
         dut.ram.ram[pc] = instr;
         pc = pc + 1;
      end
   endtask

   task emit_nops;
      input integer count;
      integer n;
      begin
         for (n = 0; n < count; n = n + 1) begin
            emit(32'h00000013);
         end
      end
   endtask

   task emit_mmio_write;
      input [19:0] addr_hi;
      input [11:0] offset;
      input [11:0] data;
      begin
         emit(rv_lui(5'd1, addr_hi));
         emit(rv_addi(5'd2, 5'd0, data));
         emit(rv_sw(5'd2, 5'd1, offset));
      end
   endtask

   initial begin
      $dumpfile("tb_soc_controller_peripherals_wave.vcd");
      $dumpvars(0, tb_soc_controller_peripherals_wave);

      for (i = 0; i < RAM_BYTES / 4; i = i + 1) begin
         dut.ram.ram[i] = 32'h00000013;
      end

      pc = 0;

      // UART path: CPU -> controller -> apb_bridge -> apb_top -> UART TX.
      emit_mmio_write(20'h40000, 12'h000, 12'h055);
      emit_nops(80);

      // SPI path: CS low, transmit 0xa5, wait for SCLK/MOSI activity, CS high.
      emit_mmio_write(20'h40001, 12'h004, 12'h000);
      emit_mmio_write(20'h40001, 12'h000, 12'h0a5);
      emit_nops(120);
      emit_mmio_write(20'h40001, 12'h004, 12'h001);
      emit_nops(40);

      // I2C path: load data 0xa0, START, WRITE byte, ACK from TB, STOP.
      emit_mmio_write(20'h40002, 12'h000, 12'h0a0);
      emit_mmio_write(20'h40002, 12'h004, 12'h001);
      emit_nops(160);
      emit_mmio_write(20'h40002, 12'h004, 12'h004);
      emit_nops(520);
      emit_mmio_write(20'h40002, 12'h004, 12'h002);
      emit_nops(160);

      emit(32'h0000006f);

      dut.cpu.cycles = 0;
      dut.cpu.aluShamt = 0;
      dut.cpu.registerFile[0] = 0;

      repeat (8) @(posedge clk);
      reset <= 1'b1;

      repeat (1700) @(posedge clk);
      i2c_slave_ack_drive_low <= 1'b1;
      repeat (90) @(posedge clk);
      i2c_slave_ack_drive_low <= 1'b0;

      repeat (2200) @(posedge clk);
      $finish;
   end
endmodule

`default_nettype wire
