`timescale 1ns/1ps

// Exercise the real CNN and Xilinx BUFGCE through its AXI interface.
module tb_cnn_clock_gating;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [31:0] awaddr = 0, wdata = 0, araddr = 0;
    reg [3:0] wstrb = 4'hf;
    reg awvalid = 0, wvalid = 0, arvalid = 0;
    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata, dma_addr, dma_data;
    wire dma_valid, dma_ready, dma_rvalid, dma_rready;

    CNN dut (
        .clk(clk), .rst_n(rst_n),
        .S_AXI_AWADDR(awaddr), .S_AXI_AWVALID(awvalid), .S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata), .S_AXI_WSTRB(wstrb),
        .S_AXI_WVALID(wvalid), .S_AXI_WREADY(wready),
        .S_AXI_BRESP(bresp), .S_AXI_BVALID(bvalid), .S_AXI_BREADY(1'b1),
        .S_AXI_ARADDR(araddr), .S_AXI_ARVALID(arvalid), .S_AXI_ARREADY(arready),
        .S_AXI_RDATA(rdata), .S_AXI_RRESP(rresp),
        .S_AXI_RVALID(rvalid), .S_AXI_RREADY(1'b1),
        .M_AXI_ARADDR(dma_addr), .M_AXI_ARVALID(dma_valid), .M_AXI_ARREADY(dma_ready),
        .M_AXI_RDATA(dma_data), .M_AXI_RVALID(dma_rvalid), .M_AXI_RREADY(dma_rready)
    );

    cnn_memory_subsystem memory (
        .clk(clk), .rst_n(rst_n),
        .S_AXI_AWADDR(32'd0), .S_AXI_AWVALID(1'b0), .S_AXI_AWREADY(),
        .S_AXI_WDATA(32'd0), .S_AXI_WSTRB(4'd0), .S_AXI_WVALID(1'b0), .S_AXI_WREADY(),
        .S_AXI_BRESP(), .S_AXI_BVALID(), .S_AXI_BREADY(1'b1),
        .S_AXI_ARADDR(32'd0), .S_AXI_ARVALID(1'b0), .S_AXI_ARREADY(),
        .S_AXI_RDATA(), .S_AXI_RRESP(), .S_AXI_RVALID(), .S_AXI_RREADY(1'b1),
        .DMA_ARADDR(dma_addr), .DMA_ARVALID(dma_valid), .DMA_ARREADY(dma_ready),
        .DMA_RDATA(dma_data), .DMA_RVALID(dma_rvalid), .DMA_RREADY(dma_rready)
    );

    reg [23:0] human [0:1023], nonhuman [0:1023];
    integer core_edges = 0, results = 0, frames = 0;
    realtime rising_at = 0;
    always @(posedge dut.cnn_clk) begin
        core_edges = core_edges + 1;
        rising_at = $realtime;
        if (clk !== 1'b1) $fatal(1, "CNN clock edge outside source clock");
    end
    always @(negedge dut.cnn_clk)
        if (rising_at > 0 && ($realtime - rising_at) < 4.999)
            $fatal(1, "Truncated CNN clock pulse");
    always @(posedge clk)
        if (rst_n && dut.cnn_result_valid) results = results + 1;

    reg word_stalled = 0;
    reg [31:0] stalled_word;
    always @(posedge dut.cnn_clk) begin
        if (!rst_n) word_stalled <= 0;
        else begin
            if (word_stalled && (dut.frame_send_valid !== 1 ||
                                dut.frame_send_data !== stalled_word))
                $fatal(1, "Frame word changed while the RGB packer stalled");
            word_stalled <= dut.frame_send_valid && !dut.dma_ready;
            stalled_word <= dut.frame_send_data;
        end
    end

    task axi_write_mask(input [31:0] address, input [31:0] data, input [3:0] mask);
        begin
            @(negedge clk); awaddr = address; awvalid = 1;
            @(posedge clk); while (!awready) @(posedge clk);
            @(negedge clk); awvalid = 0; wdata = data; wstrb = mask; wvalid = 1;
            @(posedge clk); while (!wready) @(posedge clk);
            @(negedge clk); wvalid = 0;
            @(posedge clk); while (!bvalid) @(posedge clk);
            if (bresp !== 0) $fatal(1, "AXI write error");
            @(negedge clk);
        end
    endtask

    task axi_write(input [31:0] address, input [31:0] data);
        begin axi_write_mask(address, data, 4'hf); end
    endtask

    task axi_read(input [31:0] address, output [31:0] data);
        begin
            @(negedge clk); araddr = address; arvalid = 1;
            @(posedge clk); while (!arready) @(posedge clk);
            @(negedge clk); arvalid = 0;
            while (!rvalid) @(negedge clk);
            if (rresp !== 0) $fatal(1, "AXI read error");
            data = rdata;
            @(negedge clk);
        end
    endtask

    task check_sleep;
        integer before_edges;
        reg [31:0] status;
        begin
            repeat (8) @(negedge clk);
            before_edges = core_edges;
            // AXI must still respond while the compute clock is stopped.
            axi_read(32'hff8, status);
            repeat (20) @(negedge clk);
            if (core_edges != before_edges || dut.cnn_clk !== 0 ||
                dut.cnn_clk_en !== 0 || status[0] !== 0)
                $fatal(1, "CNN did not sleep, or AXI failed while asleep");
            if (dut.cnn_result_valid !== 0)
                $fatal(1, "Stale result pulse while asleep");
        end
    endtask

    task reset_cnn;
        integer before_edges;
        begin
            @(negedge clk); rst_n = 0;
            before_edges = core_edges;
            // Includes the global simulation startup interval on the first reset.
            repeat (20) @(negedge clk);
            if (core_edges <= before_edges || dut.u_cnn_reference.pixel_ready !== 1 ||
                dut.u_cnn_reference.result_valid !== 0)
                $fatal(1, "Synchronous reset did not reach the sleeping CNN");
            rst_n = 1;
            check_sleep;
        end
    endtask

    function [31:0] frame_word(input integer index, input integer is_human);
        integer b, offset;
        reg [23:0] pixel;
        begin
            frame_word = 0;
            for (b = 0; b < 4; b = b + 1) begin
                offset = 4 * index + b;
                pixel = is_human ? human[offset / 3] : nonhuman[offset / 3];
                case (offset % 3)
                    0: frame_word = {frame_word[23:0], pixel[23:16]};
                    1: frame_word = {frame_word[23:0], pixel[15:8]};
                    2: frame_word = {frame_word[23:0], pixel[7:0]};
                endcase
            end
        end
    endfunction

    task run_frame(input integer is_human, input integer use_dma, input integer reload);
        integer i, elapsed, before_results;
        reg [31:0] status, result_value, read_count;
        reg [23:0] expected_pixel;
        begin
            before_results = results;
            if (reload) begin
                for (i = 0; i < 768; i = i + 1)
                    if (use_dma) memory.mem[i] = frame_word(i, is_human);
                    else if (is_human) axi_write(4 * i, frame_word(i, is_human));
                    else begin
                        // Each partial write must preserve the other lanes;
                        // zero strobes must not alter the assembled word.
                        axi_write(4 * i, 32'hffffffff);
                        axi_write_mask(4 * i, frame_word(i, is_human), 4'h3);
                        axi_write_mask(4 * i, frame_word(i, is_human), 4'hc);
                        axi_write_mask(4 * i, ~frame_word(i, is_human), 4'h0);
                    end
            end
            check_sleep;
            axi_write(32'hfe4, use_dma ? 32'h00010300 : 32'h00000300);
            axi_write(32'hffc, 1);
            status = 0;
            elapsed = 0;
            while (!status[1] && elapsed < 2000000) begin
                repeat (100) @(negedge clk);
                elapsed = elapsed + 100;
                axi_read(32'hff8, status);
            end
            if (!status[1] || status[0]) $fatal(1, "Frame did not complete");
            axi_read(32'hff4, result_value);
            axi_read(32'hfec, read_count);
            if (result_value[0] !== (is_human != 0) ||
                read_count !== (use_dma ? 32'd768 : 32'd0))
                $fatal(1, "Incorrect classification or DMA transfer count");
            for (i = 0; i < 1024; i = i + 1) begin
                expected_pixel = is_human ? human[i] : nonhuman[i];
                if (dut.u_cnn_reference.image[i] !== expected_pixel)
                    $fatal(1, "Pixel mismatch at %0d", i);
            end
            check_sleep;
            if (results != before_results + 1) $fatal(1, "Missing or repeated DONE pulse");
            frames = frames + 1;
            $display("Frame %0d PASS: human=%0d DMA=%0d; clock stopped after DONE",
                     frames, is_human, use_dma);
        end
    endtask

    initial begin
        $readmemh("human_frames.mem", human, 0, 1023);
        $readmemh("nonhuman_frame.mem", nonhuman, 0, 1023);
        reset_cnn;
        run_frame(1, 0, 1);
        run_frame(0, 1, 1); // Wake again without a reset between frames.
        run_frame(0, 0, 1); // Return to baseline, using partial/zero-strobe writes.
        reset_cnn;      // Reset while the gated clock is stopped.
        run_frame(0, 0, 0); // The frame BRAM must retain its contents across reset.
        axi_write(32'hffc, 1);
        repeat (50) @(negedge clk);
        if (dut.busy_reg !== 1) $fatal(1, "CNN did not wake");
        reset_cnn;      // Abort an active frame, then run a complete frame.
        run_frame(1, 1, 1);
        $display("CNN CLOCK GATING PASS: 5 frames, baseline/DMA, partial writes, RAM retention, stalls, idle/busy reset");
        $finish;
    end

    initial begin
        #80000000;
        $fatal(1, "Clock gating test timeout");
    end
endmodule
