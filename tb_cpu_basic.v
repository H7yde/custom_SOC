`timescale 1ns / 1ps
`default_nettype none

module tb_cpu_basic;
   localparam integer RAM_BYTES = 1024;
   localparam integer RESULT_ADDR = 32'h00000100;
   localparam integer RESULT_WORD = RESULT_ADDR >> 2;

   reg clk = 1'b0;
   reg reset = 1'b0;

   wire [31:0] mem_addr;
   wire [31:0] mem_wdata;
   wire [31:0] mem_rdata;
   wire [3:0]  mem_wmask;
   wire        mem_rstrb;
   wire        mem_rbusy;
   wire        mem_wbusy;

   wire ram_sel = (mem_addr < RAM_BYTES);

   integer i;

   always #5 clk = ~clk;

   FemtoRV32 #(
      .RESET_ADDR(32'h00000000),
      .ADDR_WIDTH(10)
   ) cpu (
      .clk(clk),
      .mem_addr(mem_addr),
      .mem_wdata(mem_wdata),
      .mem_wmask(mem_wmask),
      .mem_rdata(mem_rdata),
      .mem_rstrb(mem_rstrb),
      .mem_rbusy(mem_rbusy),
      .mem_wbusy(mem_wbusy),
      .reset(reset)
   );

   femto_ram #(
      .RAM_BYTES(RAM_BYTES),
      .INIT_FILE("")
   ) ram (
      .clk(clk),
      .ram_sel(ram_sel),
      .mem_addr(mem_addr),
      .mem_wdata(mem_wdata),
      .mem_wmask(mem_wmask),
      .mem_rstrb(mem_rstrb),
      .mem_rdata(mem_rdata),
      .mem_rbusy(mem_rbusy),
      .mem_wbusy(mem_wbusy)
   );

   initial begin
      $dumpfile("tb_cpu_basic.vcd");
      $dumpvars(0, tb_cpu_basic);

      for (i = 0; i < RAM_BYTES / 4; i = i + 1) begin
         ram.ram[i] = 32'h00000013; // nop: addi x0, x0, 0
      end

      // Program:
      //   addi x1, x0, 5
      //   addi x2, x0, 7
      //   add  x3, x1, x2
      //   sw   x3, 0x100(x0)
      //   jal  x0, 0
      ram.ram[0] = 32'h00500093;
      ram.ram[1] = 32'h00700113;
      ram.ram[2] = 32'h002081b3;
      ram.ram[3] = 32'h10302023;
      ram.ram[4] = 32'h0000006f;

      // These registers are initialized by the core when BENCH is defined.
      // Setting them here keeps this testbench usable with ordinary compile flows.
      cpu.cycles = 0;
      cpu.aluShamt = 0;
      cpu.registerFile[0] = 0;

      repeat (5) @(posedge clk);
      reset = 1'b1;

      repeat (80) @(posedge clk);

      if (ram.ram[RESULT_WORD] !== 32'd12) begin
         $display("FAIL: RAM[0x%08h] = 0x%08h, expected 0x0000000c",
                  RESULT_ADDR, ram.ram[RESULT_WORD]);
         $finish;
      end

      $display("PASS: CPU wrote 0x%08h to RAM[0x%08h]",
               ram.ram[RESULT_WORD], RESULT_ADDR);
      $finish;
   end
endmodule

`default_nettype wire
