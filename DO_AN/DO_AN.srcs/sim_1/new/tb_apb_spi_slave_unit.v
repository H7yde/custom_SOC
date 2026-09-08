`timescale 1ns / 1ps
`default_nettype none

module tb_apb_spi_slave_unit;
   reg clk = 1'b0;
   reg presetn = 1'b0;

   reg  [31:0] SPI_PADDR = 32'h00000000;
   reg         SPI_PSEL = 1'b0;
   reg         SPI_PENABLE = 1'b0;
   reg         SPI_PWRITE = 1'b0;
   reg  [31:0] SPI_PWDATA = 32'h00000000;
   wire [31:0] SPI_PRDATA;
   wire        PREADY;
   wire        spi_sclk;
   wire        spi_cs;
   wire        spi_mosi;
   reg         spi_miso = 1'b1;

   integer sclk_toggle_count = 0;

   always #5 clk = ~clk;

   apb_spi_slave dut (
      .PCLK(clk),
      .PRESETn(presetn),
      .SPI_PADDR(SPI_PADDR),
      .SPI_PSEL(SPI_PSEL),
      .SPI_PENABLE(SPI_PENABLE),
      .SPI_PWRITE(SPI_PWRITE),
      .SPI_PWDATA(SPI_PWDATA),
      .SPI_PRDATA(SPI_PRDATA),
      .PREADY(PREADY),
      .spi_sclk(spi_sclk),
      .spi_cs(spi_cs),
      .spi_mosi(spi_mosi),
      .spi_miso(spi_miso)
   );

   always @(spi_sclk) begin
      if (presetn) begin
         sclk_toggle_count = sclk_toggle_count + 1;
      end
   end

   task fail;
      input [127:0] message;
      begin
         $display("FAIL: %0s", message);
         $finish;
      end
   endtask

   task apb_write;
      input [7:0] addr;
      input [7:0] data;
      begin
         @(negedge clk);
         SPI_PADDR   <= {24'h0, addr};
         SPI_PWDATA  <= {24'h0, data};
         SPI_PWRITE  <= 1'b1;
         SPI_PSEL    <= 1'b1;
         SPI_PENABLE <= 1'b0;
         @(posedge clk);
         #1;
         SPI_PENABLE <= 1'b1;
         while (!PREADY) begin
            @(posedge clk);
            #1;
         end
         @(posedge clk);
         #1;
         SPI_PSEL    <= 1'b0;
         SPI_PENABLE <= 1'b0;
         SPI_PWRITE  <= 1'b0;
         SPI_PADDR   <= 32'h00000000;
         SPI_PWDATA  <= 32'h00000000;
      end
   endtask

   task apb_read;
      input [7:0] addr;
      output [31:0] data;
      begin
         @(negedge clk);
         SPI_PADDR   <= {24'h0, addr};
         SPI_PWRITE  <= 1'b0;
         SPI_PSEL    <= 1'b1;
         SPI_PENABLE <= 1'b0;
         @(posedge clk);
         #1;
         SPI_PENABLE <= 1'b1;
         while (!PREADY) begin
            @(posedge clk);
            #1;
         end
         data = SPI_PRDATA;
         @(posedge clk);
         #1;
         SPI_PSEL    <= 1'b0;
         SPI_PENABLE <= 1'b0;
         SPI_PADDR   <= 32'h00000000;
      end
   endtask

   initial begin
      $dumpfile("tb_apb_spi_slave_unit.vcd");
      $dumpvars(0, tb_apb_spi_slave_unit);

      repeat (4) @(posedge clk);
      presetn <= 1'b1;
      repeat (2) @(posedge clk);

      if (spi_cs !== 1'b1 || spi_sclk !== 1'b0) fail("SPI must idle with CS high and SCLK low");

      apb_write(8'h04, 8'h00);
      if (spi_cs !== 1'b0) fail("SPI CS should go low after CS write");

      sclk_toggle_count = 0;
      spi_miso = 1'b1;
      apb_write(8'h00, 8'hA5);

      repeat (4) @(posedge clk);
      begin : busy_check
         reg [31:0] status;
         apb_read(8'h08, status);
         if (status[0] !== 1'b1) fail("SPI busy bit should be high during transfer");
      end

      repeat (150) @(posedge clk);
      if (sclk_toggle_count < 10) fail("SPI SCLK did not toggle enough during transfer");

      begin : rx_check
         reg [31:0] rx_data;
         apb_read(8'h00, rx_data);
         if (rx_data[7:0] !== 8'hFF) fail("SPI RX data should capture constant MISO=1 as 0xFF");
      end

      begin : done_check
         reg [31:0] status_done;
         apb_read(8'h08, status_done);
         if (status_done[0] !== 1'b0) fail("SPI busy bit should clear after transfer");
      end

      apb_write(8'h04, 8'h01);
      if (spi_cs !== 1'b1) fail("SPI CS should return high after CS write");

      $display("PASS: apb_spi_slave self-check completed");
      $finish;
   end
endmodule

`default_nettype wire