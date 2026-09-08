`timescale 1ns / 1ps
`default_nettype none

module tb_femto_ram_unit;
   localparam integer RAM_BYTES = 64;

   reg clk = 1'b0;
   reg ram_sel = 1'b0;
   reg [31:0] mem_addr = 32'h00000000;
   reg [31:0] mem_wdata = 32'h00000000;
   reg [3:0]  mem_wmask = 4'b0000;
   reg        mem_rstrb = 1'b0;
   wire [31:0] mem_rdata;
   wire        mem_rbusy;
   wire        mem_wbusy;

   integer i;

   always #5 clk = ~clk;

   femto_ram #(
      .RAM_BYTES(RAM_BYTES),
      .INIT_FILE("")
   ) dut (
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

   task fail;
      input [127:0] message;
      begin
         $display("FAIL: %0s", message);
         $finish;
      end
   endtask

   task write_word;
      input [31:0] addr;
      input [31:0] data;
      input [3:0] mask;
      begin
         @(negedge clk);
         ram_sel   <= 1'b1;
         mem_addr  <= addr;
         mem_wdata <= data;
         mem_wmask <= mask;
         mem_rstrb <= 1'b0;
         @(posedge clk);
         #1;
         mem_wmask <= 4'b0000;
      end
   endtask

   task read_word;
      input [31:0] addr;
      input [31:0] expected;
      begin
         @(negedge clk);
         ram_sel   <= 1'b1;
         mem_addr  <= addr;
         mem_wmask <= 4'b0000;
         mem_rstrb <= 1'b1;
         @(posedge clk);
         #1;
         if (mem_rdata !== expected) begin
            $display("FAIL: read 0x%08h from 0x%08h, expected 0x%08h",
                     mem_rdata, addr, expected);
            $finish;
         end
         mem_rstrb <= 1'b0;
      end
   endtask

   initial begin
      $dumpfile("tb_femto_ram_unit.vcd");
      $dumpvars(0, tb_femto_ram_unit);

      for (i = 0; i < RAM_BYTES / 4; i = i + 1) begin
         dut.ram[i] = 32'h00000000;
      end

      repeat (2) @(posedge clk);

      write_word(32'h00000000, 32'h11223344, 4'b1111);
      read_word(32'h00000000, 32'h11223344);

      write_word(32'h00000000, 32'h0000aa00, 4'b0010);
      read_word(32'h00000000, 32'h1122aa44);

      write_word(32'h00000004, 32'hcc000000, 4'b1000);
      read_word(32'h00000004, 32'hcc000000);

      @(negedge clk);
      ram_sel   <= 1'b0;
      mem_addr  <= 32'h00000008;
      mem_wdata <= 32'hdeadbeef;
      mem_wmask <= 4'b1111;
      @(posedge clk);
      #1;
      if (dut.ram[2] !== 32'h00000000) begin
         fail("write changed memory while ram_sel was low");
      end

      if (mem_rbusy !== 1'b0 || mem_wbusy !== 1'b0) begin
         fail("busy outputs should stay low for femto_ram");
      end

      $display("PASS: femto_ram self-check completed");
      $finish;
   end
endmodule

`default_nettype wire