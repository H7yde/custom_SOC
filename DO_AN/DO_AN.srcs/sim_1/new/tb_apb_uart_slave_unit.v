`timescale 1ns / 1ps
`default_nettype none

module tb_apb_uart_slave_unit;
   reg clk = 1'b0;
   reg presetn = 1'b0;

   reg  [31:0] UART_PADDR = 32'h00000000;
   reg         UART_PSEL = 1'b0;
   reg         UART_PENABLE = 1'b0;
   reg         UART_PWRITE = 1'b0;
   reg  [31:0] UART_PWDATA = 32'h00000000;
   wire [31:0] UART_PRDATA;
   wire        UART_PREADY;
   wire        uart_tx;
   reg         uart_rx = 1'b1;

   reg [9:0] sampled_frame;

   always #5 clk = ~clk;

   apb_uart_slave #(
      .CLK_FREQ(20),
      .BAUD_RATE(10)
   ) dut (
      .PCLK(clk),
      .PRESETn(presetn),
      .UART_PADDR(UART_PADDR),
      .UART_PSEL(UART_PSEL),
      .UART_PENABLE(UART_PENABLE),
      .UART_PWRITE(UART_PWRITE),
      .UART_PWDATA(UART_PWDATA),
      .UART_PRDATA(UART_PRDATA),
      .UART_PREADY(UART_PREADY),
      .uart_tx(uart_tx),
      .uart_rx(uart_rx)
   );

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
         UART_PADDR   <= {24'h0, addr};
         UART_PWDATA  <= {24'h0, data};
         UART_PWRITE  <= 1'b1;
         UART_PSEL    <= 1'b1;
         UART_PENABLE <= 1'b0;
         @(posedge clk);
         #1;
         UART_PENABLE <= 1'b1;
         while (!UART_PREADY) begin
            @(posedge clk);
            #1;
         end
         @(posedge clk);
         #1;
         UART_PSEL    <= 1'b0;
         UART_PENABLE <= 1'b0;
         UART_PWRITE  <= 1'b0;
         UART_PADDR   <= 32'h00000000;
         UART_PWDATA  <= 32'h00000000;
      end
   endtask

   task apb_read;
      input [7:0] addr;
      output [31:0] data;
      begin
         @(negedge clk);
         UART_PADDR   <= {24'h0, addr};
         UART_PWRITE  <= 1'b0;
         UART_PSEL    <= 1'b1;
         UART_PENABLE <= 1'b0;
         @(posedge clk);
         #1;
         UART_PENABLE <= 1'b1;
         while (!UART_PREADY) begin
            @(posedge clk);
            #1;
         end
         data = UART_PRDATA;
         @(posedge clk);
         #1;
         UART_PSEL    <= 1'b0;
         UART_PENABLE <= 1'b0;
         UART_PADDR   <= 32'h00000000;
      end
   endtask

   task drive_uart_rx_byte;
      input [7:0] value;
      integer bit_idx;
      begin
         uart_rx <= 1'b0;
         repeat (2) @(posedge clk);
         for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
            uart_rx <= value[bit_idx];
            repeat (2) @(posedge clk);
         end
         uart_rx <= 1'b1;
         repeat (2) @(posedge clk);
      end
   endtask

   task sample_tx_frame;
      input [7:0] expected_byte;
      integer bit_idx;
      begin
         sampled_frame = 10'b0;
         @(posedge clk);
         #1;
         sampled_frame[0] = uart_tx;
         for (bit_idx = 0; bit_idx < 9; bit_idx = bit_idx + 1) begin
            repeat (2) @(posedge clk);
            #1;
            sampled_frame[bit_idx + 1] = uart_tx;
         end
         if (sampled_frame[0] !== 1'b0) fail("UART TX start bit must be low");
         if (sampled_frame[9] !== 1'b1) fail("UART TX stop bit must be high");
         if (sampled_frame[1] !== expected_byte[0]) fail("UART TX bit 0 mismatch");
         if (sampled_frame[2] !== expected_byte[1]) fail("UART TX bit 1 mismatch");
         if (sampled_frame[3] !== expected_byte[2]) fail("UART TX bit 2 mismatch");
         if (sampled_frame[4] !== expected_byte[3]) fail("UART TX bit 3 mismatch");
         if (sampled_frame[5] !== expected_byte[4]) fail("UART TX bit 4 mismatch");
         if (sampled_frame[6] !== expected_byte[5]) fail("UART TX bit 5 mismatch");
         if (sampled_frame[7] !== expected_byte[6]) fail("UART TX bit 6 mismatch");
         if (sampled_frame[8] !== expected_byte[7]) fail("UART TX bit 7 mismatch");
      end
   endtask

   task wait_for_rx_ready;
      output [31:0] status;
      integer n;
      begin
         for (n = 0; n < 40; n = n + 1) begin
            apb_read(8'h08, status);
            if (status[1] === 1'b1) begin
               disable wait_for_rx_ready;
            end
            repeat (2) @(posedge clk);
         end
         fail("UART rx_ready did not assert in time");
      end
   endtask

   initial begin
      $dumpfile("tb_apb_uart_slave_unit.vcd");
      $dumpvars(0, tb_apb_uart_slave_unit);

      repeat (4) @(posedge clk);
      presetn <= 1'b1;
      repeat (2) @(posedge clk);

      if (uart_tx !== 1'b1) fail("UART TX must idle high after reset");

      $display("UART TX check: start");

      apb_write(8'h00, 8'hA5);
      sample_tx_frame(8'hA5);
      $display("UART TX check: PASS");

      $display("UART RX check: drive byte 0xFF on uart_rx");
      drive_uart_rx_byte(8'hFF);

      begin : status_check
         reg [31:0] status;
         wait_for_rx_ready(status);
         if (status[1:0] !== 2'b11) fail("UART status should show rx_ready=1 and tx_idle=1");
         $display("UART RX ready check: PASS");
      end

      begin : rx_read_check
         reg [31:0] rx_data;
         apb_read(8'h04, rx_data);
         if (rx_data[7:0] !== 8'hFF) fail("UART RX data mismatch");
         $display("UART RX data check: PASS (0x%02h)", rx_data[7:0]);
      end

      begin : status_clear_check
         reg [31:0] status_after;
         apb_read(8'h08, status_after);
         if (status_after[1:0] !== 2'b01) fail("UART rx_ready should clear after data read");
         $display("UART RX clear check: PASS");
      end

      $display("PASS: apb_uart_slave self-check completed");
      $finish;
   end
endmodule

`default_nettype wire