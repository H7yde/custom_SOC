`timescale 1ns / 1ps
`default_nettype none

module tb_apb_bridge_unit;
   reg clk = 1'b0;
   reg resetn = 1'b0;

   reg        bus_sel = 1'b0;
   reg [31:0] mem_addr = 32'h00000000;
   reg [31:0] mem_wdata = 32'h00000000;
   reg [3:0]  mem_wmask = 4'b0000;
   reg        mem_rstrb = 1'b0;
   wire [31:0] mem_rdata;
   wire        mem_rbusy;
   wire        mem_wbusy;

   wire [31:0] PADDR;
   wire        PWRITE;
   wire        PSEL;
   wire        PENABLE;
   wire [31:0] PWDATA;
   reg  [31:0] PRDATA = 32'h00000000;
   reg         PREADY = 1'b0;
   reg         PSLVERR = 1'b0;

   always #5 clk = ~clk;

   apb_bridge dut (
      .clk(clk),
      .resetn(resetn),
      .bus_sel(bus_sel),
      .mem_addr(mem_addr),
      .mem_wdata(mem_wdata),
      .mem_wmask(mem_wmask),
      .mem_rstrb(mem_rstrb),
      .mem_rdata(mem_rdata),
      .mem_rbusy(mem_rbusy),
      .mem_wbusy(mem_wbusy),
      .PADDR(PADDR),
      .PWRITE(PWRITE),
      .PSEL(PSEL),
      .PENABLE(PENABLE),
      .PWDATA(PWDATA),
      .PRDATA(PRDATA),
      .PREADY(PREADY),
      .PSLVERR(PSLVERR)
   );

   task fail;
      input [127:0] message;
      begin
         $display("FAIL: %0s", message);
         $finish;
      end
   endtask

   task tick;
      begin
         @(posedge clk);
         #1;
      end
   endtask

   task start_read;
      input [31:0] addr;
      begin
         @(negedge clk);
         bus_sel   <= 1'b1;
         mem_addr  <= addr;
         mem_wmask <= 4'b0000;
         mem_rstrb <= 1'b1;
         mem_wdata <= 32'h00000000;
      end
   endtask

   task start_write;
      input [31:0] addr;
      input [31:0] data;
      begin
         @(negedge clk);
         bus_sel   <= 1'b1;
         mem_addr  <= addr;
         mem_wdata <= data;
         mem_wmask <= 4'b1111;
         mem_rstrb <= 1'b0;
      end
   endtask

   initial begin
      $dumpfile("tb_apb_bridge_unit.vcd");
      $dumpvars(0, tb_apb_bridge_unit);

      repeat (2) tick();
      resetn <= 1'b1;
      tick();

      PRDATA <= 32'hcafebabe;
      PREADY <= 1'b0;
      start_read(32'h1234_5678);
      tick();
      if (!PSEL || PENABLE || PWRITE) fail("read did not enter SETUP correctly");
      if (PADDR !== 32'h1234_5678 || PWDATA !== 32'h00000000) fail("read address/data not latched");
      if (!mem_rbusy || mem_wbusy) fail("busy flags wrong in SETUP for read");

      mem_rstrb <= 1'b0;
      tick();
      if (!PSEL || !PENABLE || PWRITE) fail("read did not enter ENABLE correctly");
      if (!mem_rbusy) fail("read busy must stay high during ENABLE");

      tick();
      if (!PSEL || !PENABLE) fail("read must stall while PREADY is low");

      @(negedge clk);
      PREADY <= 1'b1;
      @(posedge clk);
      #1;
      if (mem_rdata !== 32'hcafebabe) fail("read data not captured on completion");
      if (PSEL || PENABLE) fail("APB bus not released after read completion");
      if (mem_rbusy || mem_wbusy) fail("busy flags not cleared after read completion");

      PREADY <= 1'b0;
      start_write(32'h0000_00a4, 32'hdead_beef);
      tick();
      if (!PSEL || PENABLE || !PWRITE) fail("write did not enter SETUP correctly");
      if (PADDR !== 32'h0000_00a4 || PWDATA !== 32'hdead_beef) fail("write payload not latched");
      if (!mem_wbusy || mem_rbusy) fail("busy flags wrong in SETUP for write");

      mem_wmask <= 4'b0000;
      tick();
      if (!PSEL || !PENABLE || !PWRITE) fail("write did not enter ENABLE correctly");
      if (!mem_wbusy) fail("write busy must stay high during ENABLE");

      tick();
      if (!PSEL || !PENABLE) fail("write must stall while PREADY is low");

      @(negedge clk);
      PREADY <= 1'b1;
      @(posedge clk);
      #1;
      if (PSEL || PENABLE) fail("APB bus not released after write completion");
      if (mem_rbusy || mem_wbusy) fail("busy flags not cleared after write completion");

      if (PSLVERR !== 1'b0) fail("PSLVERR should be tied low");

      $display("PASS: apb_bridge self-check completed");
      $finish;
   end
endmodule

`default_nettype wire