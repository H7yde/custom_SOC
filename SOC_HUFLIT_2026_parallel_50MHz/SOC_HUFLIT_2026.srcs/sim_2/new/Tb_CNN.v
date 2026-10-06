`timescale 1ns/1ps

// Verilog-only testbench for the AXI4-Lite CNN block.
// It sends a 32x32 RGB frame through the CNN AXI register interface,
// starts inference, waits for DONE, then reads CLASSIFICATION.
module tb_CNN;
    reg clk;
    reg rst_n;

    reg  [31:0] awaddr;
    reg         awvalid;
    wire        awready;
    reg  [31:0] wdata;
    reg  [3:0]  wstrb;
    reg         wvalid;
    wire [1:0]  bresp;
    wire        bvalid;
    reg         bready;

    reg  [31:0] araddr;
    reg         arvalid;
    wire        arready;
    wire [31:0] rdata;
    wire [1:0]  rresp;
    wire        rvalid;
    reg         rready;

    reg [23:0] human_pixels [0:1023];
    reg [23:0] nonhuman_pixels [0:1023];
    reg [31:0] tx_word;
    reg [31:0] rx_data;
    reg [31:0] status_data;
    reg [31:0] cycle_data;
    reg [31:0] dma_reads_data;
    wire dut_wready;
    wire [31:0] cnn_dma_araddr;
    wire        cnn_dma_arvalid;
    wire        cnn_dma_arready;
    wire [31:0] cnn_dma_rdata;
    wire        cnn_dma_rvalid;
    wire        cnn_dma_rready;

    reg  [31:0] mem_awaddr;
    reg         mem_awvalid;
    wire        mem_awready;
    reg  [31:0] mem_wdata;
    reg  [3:0]  mem_wstrb;
    reg         mem_wvalid;
    wire        mem_wready;
    wire [1:0]  mem_bresp;
    wire        mem_bvalid;
    reg         mem_bready;
    reg  [31:0] mem_araddr;
    reg         mem_arvalid;
    wire        mem_arready;
    wire [31:0] mem_rdata;
    wire [1:0]  mem_rresp;
    wire        mem_rvalid;
    reg         mem_rready;
    integer i, j, byte_index, pixel_index, byte_in_pixel;
    integer pass_count, fail_count, timeout_count;
    integer sim_cycle, start_cycle, end_cycle;
    reg [7:0] one_byte;

    CNN dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .S_AXI_AWADDR  (awaddr),
        .S_AXI_AWVALID (awvalid),
        .S_AXI_AWREADY (awready),
        .S_AXI_WDATA   (wdata),
        .S_AXI_WSTRB   (wstrb),
        .S_AXI_WVALID  (wvalid),
        .S_AXI_WREADY  (dut_wready),
        .S_AXI_BRESP   (bresp),
        .S_AXI_BVALID  (bvalid),
        .S_AXI_BREADY  (bready),
        .S_AXI_ARADDR  (araddr),
        .S_AXI_ARVALID (arvalid),
        .S_AXI_ARREADY (arready),
        .S_AXI_RDATA   (rdata),
        .S_AXI_RRESP   (rresp),
        .S_AXI_RVALID  (rvalid),
        .S_AXI_RREADY  (rready),
        .M_AXI_ARADDR  (cnn_dma_araddr),
        .M_AXI_ARVALID (cnn_dma_arvalid),
        .M_AXI_ARREADY (cnn_dma_arready),
        .M_AXI_RDATA   (cnn_dma_rdata),
        .M_AXI_RVALID  (cnn_dma_rvalid),
        .M_AXI_RREADY  (cnn_dma_rready)
    );

    cnn_memory_subsystem #(
        .BASE_ADDR(32'h4000_6000),
        .BUFFER_WORDS(768),
        .TOTAL_WORDS(1536)
    ) mem_dut (
        .clk(clk), .rst_n(rst_n),
        .S_AXI_AWADDR(mem_awaddr), .S_AXI_AWVALID(mem_awvalid), .S_AXI_AWREADY(mem_awready),
        .S_AXI_WDATA(mem_wdata), .S_AXI_WSTRB(mem_wstrb), .S_AXI_WVALID(mem_wvalid), .S_AXI_WREADY(mem_wready),
        .S_AXI_BRESP(mem_bresp), .S_AXI_BVALID(mem_bvalid), .S_AXI_BREADY(mem_bready),
        .S_AXI_ARADDR(mem_araddr), .S_AXI_ARVALID(mem_arvalid), .S_AXI_ARREADY(mem_arready),
        .S_AXI_RDATA(mem_rdata), .S_AXI_RRESP(mem_rresp), .S_AXI_RVALID(mem_rvalid), .S_AXI_RREADY(mem_rready),
        .DMA_ARADDR(cnn_dma_araddr), .DMA_ARVALID(cnn_dma_arvalid), .DMA_ARREADY(cnn_dma_arready),
        .DMA_RDATA(cnn_dma_rdata), .DMA_RVALID(cnn_dma_rvalid), .DMA_RREADY(cnn_dma_rready)
    );
    always #10 clk = ~clk;       // 50 MHz
    always @(posedge clk) sim_cycle = sim_cycle + 1;

    // Write one AXI4-Lite transaction. CNN accepts address and data
    // independently, so this task waits for both handshakes.
    task axi_write;
        input [31:0] address;
        input [31:0] data;
        begin
            @(posedge clk);
            awaddr  <= address;
            awvalid <= 1'b1;
            while (!awready) @(posedge clk);
            @(posedge clk);
            awvalid <= 1'b0;

            wdata   <= data;
            wstrb   <= 4'b1111;
            wvalid  <= 1'b1;
            while (!dut_wready) @(posedge clk);
            @(posedge clk);
            wvalid  <= 1'b0;

            while (!bvalid) @(posedge clk);
            @(posedge clk);
        end
    endtask

    task axi_read;
        input  [31:0] address;
        output [31:0] data;
        begin
            @(posedge clk);
            araddr  <= address;
            arvalid <= 1'b1;
            while (!arready) @(posedge clk);
            @(posedge clk);
            arvalid <= 1'b0;
            while (!rvalid) @(posedge clk);
            data = rdata;
            @(posedge clk);
        end
    endtask

    task mem_axi_write;
        input [31:0] address;
        input [31:0] data;
        begin
            @(posedge clk);
            mem_awaddr  <= address;
            mem_awvalid <= 1'b1;
            while (!mem_awready) @(posedge clk);
            @(posedge clk);
            mem_awvalid <= 1'b0;

            mem_wdata   <= data;
            mem_wstrb   <= 4'b1111;
            mem_wvalid  <= 1'b1;
            while (!mem_wready) @(posedge clk);
            @(posedge clk);
            mem_wvalid  <= 1'b0;

            while (!mem_bvalid) @(posedge clk);
            @(posedge clk);
        end
    endtask

    // Pack four consecutive RGB bytes into one 32-bit AXI word.
    // The packing matches dma32_to_rgb24 with MSB_FIRST=1.
    task make_word;
        input  integer word_number;
        input  integer which_frame;
        output [31:0] word_value;
        begin
            word_value = 32'd0;
            for (j = 0; j < 4; j = j + 1) begin
                byte_index = word_number * 4 + j;
                pixel_index = byte_index / 3;
                byte_in_pixel = byte_index % 3;
                if (which_frame == 1)
                    case (byte_in_pixel)
                        0: one_byte = human_pixels[pixel_index][23:16];
                        1: one_byte = human_pixels[pixel_index][15:8];
                        default: one_byte = human_pixels[pixel_index][7:0];
                    endcase
                else
                    case (byte_in_pixel)
                        0: one_byte = nonhuman_pixels[pixel_index][23:16];
                        1: one_byte = nonhuman_pixels[pixel_index][15:8];
                        default: one_byte = nonhuman_pixels[pixel_index][7:0];
                    endcase
                word_value = {word_value[23:0], one_byte};
            end
        end
    endtask

    task run_case;
        input integer case_number;
        input integer expected_value;
        begin
            start_cycle = sim_cycle;
            $display("============================================================");
            if (case_number == 1)
                $display("[TB][CASE 1] HUMAN");
            else
                $display("[TB][CASE 2] NON-HUMAN");

            $display("[TB][INFO] writing 768 RGB words through AXI");
            for (i = 0; i < 768; i = i + 1) begin
                make_word(i, case_number, tx_word);
                axi_write(i * 4, tx_word);
            end
            $display("[TB][INPUT] transferred words: 768/768");

            axi_write(32'h00000FFC, 32'h00000001);
            timeout_count = 0;
            status_data = 0;
            while (!status_data[1] && timeout_count < 300000) begin
                axi_read(32'h00000FF8, status_data);
                timeout_count = timeout_count + 1;
            end

            if (timeout_count >= 300000) begin
                $display("[TB][FAIL] timeout waiting for CNN DONE");
                fail_count = fail_count + 1;
            end else begin
                axi_read(32'h00000FF4, rx_data);
                $display("[TB][RESULT] status=%h classification=%0d expected=%0d",
                         status_data, rx_data[0], expected_value);
                if (rx_data[0] == expected_value) begin
                    $display("[TB][PASS]");
                    pass_count = pass_count + 1;
                end else begin
                    $display("[TB][FAIL]");
                    fail_count = fail_count + 1;
                end
                end_cycle = sim_cycle;
                $display("[TB][BASELINE] end_to_end_cycles=%0d", end_cycle - start_cycle);
            end
        end
    endtask

    task run_dma_case;
        input integer case_number;
        input integer expected_value;
        input integer buffer_number;
        begin
            start_cycle = sim_cycle;
            $display("============================================================");
            $display("[TB][DMA] writing frame to ping-pong buffer %0d", buffer_number);
            for (i = 0; i < 768; i = i + 1) begin
                make_word(i, case_number, tx_word);
                mem_axi_write(32'h4000_6000 +
                              (buffer_number * 32'h0000_0C00) + i * 4,
                              tx_word);
            end

            // FE0 = memory base, FE4 = 768 words + DMA + ping-pong + buffer.
            axi_write(32'h0000_0FE0, 32'h4000_6000);
            axi_write(32'h0000_0FE4, 32'h0003_0300 |
                                      (buffer_number ? 32'h0004_0000 : 32'h0));
            axi_write(32'h0000_0FFC, 32'h0000_0001);

            timeout_count = 0;
            status_data = 0;
            while (!status_data[1] && timeout_count < 300000) begin
                axi_read(32'h0000_0FF8, status_data);
                timeout_count = timeout_count + 1;
            end

            if (timeout_count >= 300000) begin
                $display("[TB][DMA][FAIL] timeout waiting for CNN DONE");
                fail_count = fail_count + 1;
            end else begin
                axi_read(32'h0000_0FF4, rx_data);
                axi_read(32'h0000_0FE8, cycle_data);
                axi_read(32'h0000_0FEC, dma_reads_data);
                end_cycle = sim_cycle;
                $display("[TB][DMA][RESULT] status=%h classification=%0d expected=%0d",
                         status_data, rx_data[0], expected_value);
                $display("[TB][DMA] end_to_end_cycles=%0d compute_cycles=%0d dma_reads=%0d",
                         end_cycle - start_cycle, cycle_data, dma_reads_data);
                if (rx_data[0] == expected_value) begin
                    $display("[TB][DMA][PASS]");
                    pass_count = pass_count + 1;
                end else begin
                    $display("[TB][DMA][FAIL]");
                    fail_count = fail_count + 1;
                end
            end
        end
    endtask

    // Runtime register programming and readback.  This test does not reset
    // the DUT, so it also checks that configuration can change while idle.
    task test_runtime_config;
        reg [31:0] base_readback;
        reg [31:0] cfg_readback;
        begin
            $display("============================================================");
            $display("[TB][RUNTIME 1] configuration write/readback");

            axi_write(32'h0000_0FE0, 32'h4000_6000);
            axi_write(32'h0000_0FE4, 32'h0003_0300);
            axi_read (32'h0000_0FE0, base_readback);
            axi_read (32'h0000_0FE4, cfg_readback);

            if (base_readback == 32'h4000_6000 &&
                cfg_readback  == 32'h0003_0300) begin
                $display("[TB][RUNTIME 1][PASS] base=%h config=%h",
                         base_readback, cfg_readback);
                pass_count = pass_count + 1;
            end else begin
                $display("[TB][RUNTIME 1][FAIL] base=%h config=%h",
                         base_readback, cfg_readback);
                fail_count = fail_count + 1;
            end

            // A zero frame-word field is defined as a full 768-word frame.
            axi_write(32'h0000_0FE4, 32'h0003_0000);
            axi_read (32'h0000_0FE4, cfg_readback);
            if (cfg_readback == 32'h0003_0000) begin
                $display("[TB][RUNTIME 1][PASS] zero-length field maps to full frame");
                pass_count = pass_count + 1;
            end else begin
                $display("[TB][RUNTIME 1][FAIL] zero-length field readback=%h",
                         cfg_readback);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Switch from DMA to the legacy AXI-Lite frame path and back without a
    // reset.  The two classifications verify that the selected data path is
    // changed at runtime rather than only during initialization.
    task test_runtime_mode_switch;
        begin
            $display("============================================================");
            $display("[TB][RUNTIME 2] baseline <-> DMA mode switch");

            // Disable DMA and run a new frame through CNN.frame_mem.
            axi_write(32'h0000_0FE4, 32'h0000_0000);
            for (i = 0; i < 768; i = i + 1) begin
                make_word(i, 2, tx_word);
                axi_write(i * 4, tx_word);
            end
            axi_write(32'h0000_0FFC, 32'h0000_0001);
            timeout_count = 0;
            status_data = 0;
            while (!status_data[1] && timeout_count < 300000) begin
                axi_read(32'h0000_0FF8, status_data);
                timeout_count = timeout_count + 1;
            end
            axi_read(32'h0000_0FF4, rx_data);
            if (timeout_count < 300000 && rx_data[0] == 1'b0 &&
                status_data[2] == 1'b0) begin
                $display("[TB][RUNTIME 2][PASS] baseline classification=%0d status=%h",
                         rx_data[0], status_data);
                pass_count = pass_count + 1;
            end else begin
                $display("[TB][RUNTIME 2][FAIL] baseline classification=%0d status=%h",
                         rx_data[0], status_data);
                fail_count = fail_count + 1;
            end

            // Re-enable DMA and consume buffer 0 without resetting the DUT.
            axi_write(32'h0000_0FE4, 32'h0003_0300);
            axi_write(32'h0000_0FFC, 32'h0000_0001);
            timeout_count = 0;
            status_data = 0;
            while (!status_data[1] && timeout_count < 300000) begin
                axi_read(32'h0000_0FF8, status_data);
                timeout_count = timeout_count + 1;
            end
            axi_read(32'h0000_0FF4, rx_data);
            if (timeout_count < 300000 && rx_data[0] == 1'b1 &&
                status_data[2] == 1'b1) begin
                $display("[TB][RUNTIME 2][PASS] DMA classification=%0d status=%h",
                         rx_data[0], status_data);
                pass_count = pass_count + 1;
            end else begin
                $display("[TB][RUNTIME 2][FAIL] DMA classification=%0d status=%h",
                         rx_data[0], status_data);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Buffer 0 contains the human frame and buffer 1 contains the non-human
    // frame.  The second START intentionally does not rewrite CONFIG: the
    // RTL must toggle buffer_select after the first completed inference.
    task test_runtime_pingpong_toggle;
        begin
            $display("============================================================");
            $display("[TB][RUNTIME 3] automatic ping-pong buffer toggle");

            axi_write(32'h0000_0FE0, 32'h4000_6000);
            axi_write(32'h0000_0FE4, 32'h0003_0300);

            axi_write(32'h0000_0FFC, 32'h0000_0001);
            timeout_count = 0;
            status_data = 0;
            while (!status_data[1] && timeout_count < 300000) begin
                axi_read(32'h0000_0FF8, status_data);
                timeout_count = timeout_count + 1;
            end
            axi_read(32'h0000_0FF4, rx_data);
            if (timeout_count < 300000 && rx_data[0] == 1'b1 &&
                status_data[3] == 1'b0 && status_data[4] == 1'b1) begin
                $display("[TB][RUNTIME 3][PASS] frame 0 buffer=%0d class=%0d",
                         status_data[3], rx_data[0]);
                pass_count = pass_count + 1;
            end else begin
                $display("[TB][RUNTIME 3][FAIL] frame 0 status=%h class=%0d",
                         status_data, rx_data[0]);
                fail_count = fail_count + 1;
            end

            // No CONFIG write here.  The previous completion must select buf1.
            axi_write(32'h0000_0FFC, 32'h0000_0001);
            timeout_count = 0;
            status_data = 0;
            while (!status_data[1] && timeout_count < 300000) begin
                axi_read(32'h0000_0FF8, status_data);
                timeout_count = timeout_count + 1;
            end
            axi_read(32'h0000_0FF4, rx_data);
            if (timeout_count < 300000 && rx_data[0] == 1'b0 &&
                status_data[3] == 1'b1 && status_data[4] == 1'b1) begin
                $display("[TB][RUNTIME 3][PASS] frame 1 buffer=%0d class=%0d",
                         status_data[3], rx_data[0]);
                pass_count = pass_count + 1;
            end else begin
                $display("[TB][RUNTIME 3][FAIL] frame 1 status=%h class=%0d",
                         status_data, rx_data[0]);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        awaddr = 0; awvalid = 0; wdata = 0; wstrb = 0; wvalid = 0;
        bready = 1'b1;
        araddr = 0; arvalid = 0; rready = 1'b1;
        mem_awaddr = 0; mem_awvalid = 0; mem_wdata = 0; mem_wstrb = 0;
        mem_wvalid = 0; mem_bready = 1'b1;
        mem_araddr = 0; mem_arvalid = 0; mem_rready = 1'b1;
        pass_count = 0;
        fail_count = 0;
        sim_cycle = 0;

        $readmemh("D:/LAB/custom_SOC/CNN_RTL/human_frame.mem", human_pixels);
        $readmemh("D:/LAB/custom_SOC/CNN_RTL/nonhuman_frame.mem", nonhuman_pixels);

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        run_case(1, 1);          // 1 = human
        run_case(2, 0);          // 0 = non-human
        //run_dma_case(1, 1, 0);   // DMA + buffer 0
        //run_dma_case(2, 0, 1);   // DMA + buffer 1
        //test_runtime_config;
        //test_runtime_mode_switch;
        //test_runtime_pingpong_toggle;

        $display("============================================================");
        $display("[TB][SUMMARY] passed=%0d failed=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("[TB][SUMMARY] CNN AXI TEST PASS");
        else
            $display("[TB][SUMMARY] CNN AXI TEST FAIL");
        $finish;
    end
endmodule
