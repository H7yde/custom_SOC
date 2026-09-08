`timescale 1ns / 1ps
`default_nettype none

module tb_apb_i2c_slave_unit;
   reg clk = 1'b0;
   reg presetn = 1'b0;

   reg  [31:0] I2C_PADDR = 32'h00000000;
   reg         I2C_PSEL = 1'b0;
   reg         I2C_PENABLE = 1'b0;
   reg         I2C_PWRITE = 1'b0;
   reg  [31:0] I2C_PWDATA = 32'h00000000;
   wire [31:0] I2C_PRDATA;
   wire        PREADY;
   wire        scl_out;
   wire        sda_out;
   wire        sda_oe;
   wire        sda_in;
   reg         slave_drive_low = 1'b0;

   always #5 clk = ~clk;

   pullup(sda_in);
   assign sda_in = sda_oe ? sda_out : 1'bz;
   assign sda_in = slave_drive_low ? 1'b0 : 1'bz;

   apb_i2c_slave dut (
      .PCLK(clk),
      .PRESETn(presetn),
      .I2C_PADDR(I2C_PADDR),
      .I2C_PSEL(I2C_PSEL),
      .I2C_PENABLE(I2C_PENABLE),
      .I2C_PWRITE(I2C_PWRITE),
      .I2C_PWDATA(I2C_PWDATA),
      .I2C_PRDATA(I2C_PRDATA),
      .PREADY(PREADY),
      .scl_out(scl_out),
      .sda_out(sda_out),
      .sda_oe(sda_oe),
      .sda_in(sda_in)
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
         I2C_PADDR   <= {24'h0, addr};
         I2C_PWDATA  <= {24'h0, data};
         I2C_PWRITE  <= 1'b1;
         I2C_PSEL    <= 1'b1;
         I2C_PENABLE <= 1'b0;
         @(posedge clk);
         #1;
         I2C_PENABLE <= 1'b1;
         while (!PREADY) begin
            @(posedge clk);
            #1;
         end
         @(posedge clk);
         #1;
         I2C_PSEL    <= 1'b0;
         I2C_PENABLE <= 1'b0;
         I2C_PWRITE  <= 1'b0;
         I2C_PADDR   <= 32'h00000000;
         I2C_PWDATA  <= 32'h00000000;
      end
   endtask

   task apb_read;
      input [7:0] addr;
      output [31:0] data;
      begin
         @(negedge clk);
         I2C_PADDR   <= {24'h0, addr};
         I2C_PWRITE  <= 1'b0;
         I2C_PSEL    <= 1'b1;
         I2C_PENABLE <= 1'b0;
         @(posedge clk);
         #1;
         I2C_PENABLE <= 1'b1;
         while (!PREADY) begin
            @(posedge clk);
            #1;
         end
         data = I2C_PRDATA;
         @(posedge clk);
         #1;
         I2C_PSEL    <= 1'b0;
         I2C_PENABLE <= 1'b0;
         I2C_PADDR   <= 32'h00000000;
      end
   endtask

   task wait_for_line_low;
      integer n;
      begin
         for (n = 0; n < 80; n = n + 1) begin
            @(posedge clk);
            #1;
            if (sda_in === 1'b0 && scl_out === 1'b1) begin
               disable wait_for_line_low;
            end
         end
         fail("I2C start condition did not drive SDA low while SCL high");
      end
   endtask

   task wait_for_scl_low;
      integer n;
      begin
         for (n = 0; n < 120; n = n + 1) begin
            @(posedge clk);
            #1;
            if (scl_out === 1'b0) begin
               disable wait_for_scl_low;
            end
         end
         fail("I2C start condition did not complete with SCL low");
      end
   endtask

   task wait_for_bus_high;
      integer n;
      begin
         for (n = 0; n < 160; n = n + 1) begin
            @(posedge clk);
            #1;
            if (scl_out === 1'b1 && sda_in === 1'b1) begin
               disable wait_for_bus_high;
            end
         end
         fail("I2C bus did not return high");
      end
   endtask

   task wait_for_ack_window;
      integer n;
      begin
         for (n = 0; n < 600; n = n + 1) begin
            @(posedge clk);
            #1;
            if (sda_oe === 1'b0) begin
               disable wait_for_ack_window;
            end
         end
         fail("I2C ACK phase was not reached");
      end
   endtask

   task check_idle_high;
      begin
         if (scl_out !== 1'b1 || sda_in !== 1'b1) fail("I2C bus should idle high");
      end
   endtask

   initial begin
      $dumpfile("tb_apb_i2c_slave_unit.vcd");
      $dumpvars(0, tb_apb_i2c_slave_unit);

      repeat (4) @(posedge clk);
      presetn <= 1'b1;
      repeat (2) @(posedge clk);

      check_idle_high();

      apb_write(8'h00, 8'hA0);
      apb_write(8'h04, 8'h01);
      wait_for_line_low();
      wait_for_scl_low();
      wait_for_bus_high();

      apb_write(8'h00, 8'hA0);
      apb_write(8'h04, 8'h04);
      wait_for_ack_window();
      slave_drive_low <= 1'b1;
      repeat (30) @(posedge clk);
      slave_drive_low <= 1'b0;
      repeat (80) @(posedge clk);

      begin : status_check
         reg [31:0] status;
         apb_read(8'h08, status);
         if (status[0] !== 1'b0) fail("I2C busy bit should clear after write");
         if (status[1] !== 1'b0) fail("I2C ACK bit should capture low ACK from slave");
      end

      apb_write(8'h04, 8'h02);
      wait_for_line_low();
      wait_for_bus_high();
      check_idle_high();

      $display("PASS: apb_i2c_slave self-check completed");
      $finish;
   end
endmodule

`default_nettype wire