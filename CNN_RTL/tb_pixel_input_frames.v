`timescale 1ns/1ps

// End-to-end testbench for cnn_input_frontend.
//
// The test sends two 32x32 RGB frames through the 32-bit DMA interface:
//   frame 0: HUMAN     (synthetic test pattern)
//   frame 1: NON_HUMAN (synthetic test pattern)
//
// This testbench checks:
//   * 32-bit words are accepted only with dma_valid && dma_ready;
//   * 3-byte RGB pixels are reconstructed across DMA-word boundaries;
//   * pixel order and pixel contents are preserved for both frames;
//   * FIFO backpressure does not lose, duplicate or reorder pixels;
//   * the exact end-of-frame count is 1024 pixels.
//
// Important: cnn_input_frontend has no classification output. Therefore the
// HUMAN/NON_HUMAN labels below are expected labels for the input vectors only.
// Connect a CNN/classifier DUT and compare its output against expected_label
// at each frame boundary to verify the final classification.

module tb_pixel_input_frames;

    localparam integer IMG_W      = 32;
    localparam integer IMG_H      = 32;
    localparam integer PIXELS     = IMG_W * IMG_H;
    localparam integer FRAMES     = 2;
    localparam integer BYTE_COUNT = PIXELS * 3;
    localparam integer WORD_COUNT = BYTE_COUNT / 4; // 3072 / 4 = 768

    reg clk;
    reg rst;
    reg [31:0] dma_data;
    reg        dma_valid;
    wire       dma_ready;
    wire [23:0] pixel_data;
    wire       pixel_valid;
    reg        pixel_ready;
    wire       fifo_full;
    wire       fifo_empty;

    integer frame_no;
    integer words_sent;
    integer pixels_received;
    integer total_received;
    integer errors;
    integer cycles;
    integer stall_count;

    // 1 = human, 0 = non-human. These are labels for the two test vectors.
    reg expected_label [0:FRAMES-1];

    cnn_input_frontend #(
        .FIFO_DEPTH(16),
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

    // Deterministic RGB test images. The patterns are deliberately different
    // so a frame swap or stale-pixel bug is detected by the scoreboard.
    function [7:0] image_byte;
        input integer f;
        input integer byte_index;
        integer p;
        integer c;
        integer x;
        integer y;
        begin
            p = byte_index / 3;
            c = byte_index % 3;
            x = p % IMG_W;
            y = p / IMG_W;
            if (f == 0) begin
                // HUMAN vector: structured gradient/checker pattern.
                case (c)
                    0: image_byte = (x * 5 + y * 3 + 8'h20) & 8'hff;
                    1: image_byte = (x * 2 + y * 7 + 8'h40) & 8'hff;
                    default: image_byte = ((x ^ y) * 9 + 8'h10) & 8'hff;
                endcase
            end else begin
                // NON_HUMAN vector: a different deterministic pattern.
                case (c)
                    0: image_byte = ((x * 13) ^ (y * 3) ^ 8'h91) & 8'hff;
                    1: image_byte = ((x * 7)  ^ (y * 11) ^ 8'h37) & 8'hff;
                    default: image_byte = ((x * 17) ^ (y * 5) ^ 8'hc3) & 8'hff;
                endcase
            end
        end
    endfunction

    function [23:0] expected_pixel;
        input integer f;
        input integer p;
        begin
            expected_pixel = {
                image_byte(f, p * 3),
                image_byte(f, p * 3 + 1),
                image_byte(f, p * 3 + 2)
            };
        end
    endfunction

    task send_dma_word;
        input integer f;
        input integer w;
        integer b;
        integer first_byte;
        reg [31:0] word_value;
        begin
            first_byte = w * 4;
            word_value = {
                image_byte(f, first_byte),
                image_byte(f, first_byte + 1),
                image_byte(f, first_byte + 2),
                image_byte(f, first_byte + 3)
            };

            @(negedge clk);
            while (!dma_ready)
                @(negedge clk);
            dma_data  = word_value;
            dma_valid = 1'b1;
            // Hold valid/data until the actual ready/valid transfer edge.
            @(posedge clk);
            while (!dma_ready)
                @(posedge clk);
            @(negedge clk);
            dma_valid = 1'b0;
            dma_data  = 32'd0;
        end
    endtask

    task send_frame;
        input integer f;
        integer w;
        begin
            for (w = 0; w < WORD_COUNT; w = w + 1)
                send_dma_word(f, w);
        end
    endtask

    // Backpressure pattern: initial long stall fills the FIFO, followed by
    // periodic stalls while the producer continues sending.
    always @(negedge clk) begin
        if (rst) begin
            pixel_ready <= 1'b0;
            stall_count <= 0;
        end else begin
            if (stall_count < 30)
                pixel_ready <= 1'b0;
            else if ((stall_count % 17) < 5)
                pixel_ready <= 1'b0;
            else
                pixel_ready <= 1'b1;
            stall_count <= stall_count + 1;
        end
    end

    // Pixel scoreboard. A mismatch identifies the frame and pixel position.
    always @(posedge clk) begin
        if (!rst && pixel_valid && pixel_ready) begin
            if (frame_no >= FRAMES) begin
                $display("FAIL: extra pixel after frame %0d: %h", FRAMES-1,
                         pixel_data);
                errors = errors + 1;
            end else if (pixel_data !== expected_pixel(frame_no, pixels_received)) begin
                $display("FAIL: frame=%0d pixel=%0d expected=%h got=%h",
                         frame_no, pixels_received,
                         expected_pixel(frame_no, pixels_received), pixel_data);
                errors = errors + 1;
            end

            pixels_received = pixels_received + 1;
            total_received  = total_received + 1;
            if (pixels_received == PIXELS) begin
                $display("INFO: frame %0d complete, expected label=%s",
                         frame_no, expected_label[frame_no] ? "HUMAN" : "NON-HUMAN");
                frame_no       = frame_no + 1;
                pixels_received = 0;
            end
        end
    end

    initial begin
        clk             = 1'b0;
        rst             = 1'b1;
        dma_data        = 32'd0;
        dma_valid       = 1'b0;
        pixel_ready     = 1'b0;
        frame_no        = 0;
        words_sent      = 0;
        pixels_received = 0;
        total_received  = 0;
        errors          = 0;
        cycles          = 0;
        stall_count     = 0;
        expected_label[0] = 1'b1;
        expected_label[1] = 1'b0;

        repeat (4) @(posedge clk);
        rst = 1'b0;

        fork
            begin
                send_frame(0);
                send_frame(1);
            end
        join

        // Wait for all 2048 pixels to leave the FIFO.
        while (total_received < FRAMES * PIXELS) begin
            @(posedge clk);
            cycles = cycles + 1;
            if (cycles > 200000) begin
                $display("FAIL: timeout, received=%0d/%0d pixels",
                         total_received, FRAMES * PIXELS);
                $finish;
            end
        end

        repeat (5) @(posedge clk);
        if ((errors == 0) && (frame_no == FRAMES))
            $display("PASS: %0d frames, %0d pixels, DMA/FIFO order preserved",
                     FRAMES, total_received);
        else
            $display("FAIL: errors=%0d frame_no=%0d received=%0d",
                     errors, frame_no, total_received);
        $finish;
    end

endmodule
