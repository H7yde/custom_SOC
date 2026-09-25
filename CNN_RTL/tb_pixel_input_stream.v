`timescale 1ns/1ps

module tb_pixel_input_stream;

    reg clk;
    reg rst;

    reg [31:0] dma_data;
    reg        dma_valid;
    wire       dma_ready;

    wire [23:0] pixel_data;
    wire        pixel_valid;
    reg         pixel_ready;
    wire        fifo_full;
    wire        fifo_empty;

    reg [23:0] expected [0:7];
    integer received;
    integer errors;
    integer cycles;

    cnn_input_frontend #(
        .FIFO_DEPTH(4),
        .MSB_FIRST (1'b1)
    ) dut (
        .clk        (clk),
        .rst        (rst),
        .dma_data   (dma_data),
        .dma_valid  (dma_valid),
        .dma_ready  (dma_ready),
        .pixel_data (pixel_data),
        .pixel_valid(pixel_valid),
        .pixel_ready(pixel_ready),
        .fifo_full  (fifo_full),
        .fifo_empty (fifo_empty)
    );

    always #5 clk = ~clk;

    task send_dma_word;
        input [31:0] word_value;
        begin
            @(negedge clk);
            while (!dma_ready)
                @(negedge clk);
            dma_data  = word_value;
            dma_valid = 1'b1;
            @(negedge clk);
            dma_valid = 1'b0;
            dma_data  = 32'd0;
        end
    endtask

    // The first four cycles intentionally exercise FIFO backpressure.  The
    // FIFO depth is only four, so the DMA producer must eventually pause
    // while pixel_ready is low; no pixel may be dropped or reordered.
    initial begin
        clk         = 1'b0;
        rst         = 1'b1;
        dma_data    = 32'd0;
        dma_valid   = 1'b0;
        pixel_ready = 1'b0;
        received    = 0;
        errors      = 0;
        cycles      = 0;

        expected[0] = 24'h010203;
        expected[1] = 24'h040506;
        expected[2] = 24'h070809;
        expected[3] = 24'h0A0B0C;
        expected[4] = 24'h0D0E0F;
        expected[5] = 24'h101112;
        expected[6] = 24'h131415;
        expected[7] = 24'h161718;

        repeat (3) @(posedge clk);
        rst = 1'b0;

        fork
            begin
                // 24 sequential bytes packed into six 32-bit DMA words.
                // RGB triplets cross word boundaries in this sequence.
                send_dma_word(32'h01020304);
                send_dma_word(32'h05060708);
                send_dma_word(32'h090A0B0C);
                send_dma_word(32'h0D0E0F10);
                send_dma_word(32'h11121314);
                send_dma_word(32'h15161718);
            end

            begin
                repeat (40) @(posedge clk);
                pixel_ready = 1'b1;
            end
        join

        while (received < 8) begin
            @(posedge clk);
            cycles = cycles + 1;
            if (cycles > 500) begin
                $display("FAIL: timeout, received=%0d", received);
                $finish;
            end
        end

        repeat (3) @(posedge clk);
        if (errors == 0)
            $display("PASS: all %0d RGB pixels preserved through DMA unpacker and FIFO", received);
        else
            $display("FAIL: %0d scoreboard errors", errors);
        $finish;
    end

    always @(posedge clk) begin
        if (!rst && pixel_valid && pixel_ready) begin
            if (received >= 8) begin
                $display("FAIL: unexpected extra pixel %h", pixel_data);
                errors = errors + 1;
            end else if (pixel_data !== expected[received]) begin
                $display("FAIL: pixel %0d expected %h got %h",
                         received, expected[received], pixel_data);
                errors = errors + 1;
            end
            received = received + 1;
        end
    end

endmodule
