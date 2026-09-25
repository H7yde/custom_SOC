`timescale 1ns/1ps

// Pure Verilog simulation reference for the DOCX CNN.
// RGB 32x32 -> Conv1/Pool -> Conv2/Pool -> Conv3/Pool -> FC.
// This is a frame-level reference model for simulation, not a streaming RTL core.
module cnn_docx_reference (
    input  wire        clk,
    input  wire        rst,
    input  wire [23:0] pixel_data,
    input  wire        pixel_valid,
    output reg         pixel_ready,
    output reg         result_valid,
    output reg         classification
);
    reg [23:0] image [0:1023];
    reg signed [7:0] w1 [0:107];
    reg signed [7:0] w2 [0:143];
    reg signed [7:0] w3 [0:143];
    reg signed [7:0] wf [0:15];

    integer pixel_count;
    reg processing;
    integer c1 [0:3599];
    integer p1 [0:899];
    integer c2 [0:675];
    integer p2 [0:143];
    integer c3 [0:63];
    integer p3 [0:15];

    task check_weight_memory;
        integer f1, f2, f3, ff;
        integer i;
        begin
            f1 = $fopen("D:/LAB/custom_SOC/CNN_RTL/conv1_rgb_weight.mem", "r");
            f2 = $fopen("D:/LAB/custom_SOC/CNN_RTL/conv2_weight.mem", "r");
            f3 = $fopen("D:/LAB/custom_SOC/CNN_RTL/conv3_weight.mem", "r");
            ff = $fopen("D:/LAB/custom_SOC/CNN_RTL/fc_weight.mem", "r");
            if (f1 == 0 || f2 == 0 || f3 == 0 || ff == 0)
                $fatal(1, "Cannot open one or more CNN .mem files");
            $fclose(f1);
            $fclose(f2);
            $fclose(f3);
            $fclose(ff);

            for (i = 0; i < 108; i = i + 1)
                if (^w1[i] === 1'bx) $fatal(1, "Missing word in conv1 weight memory at %0d", i);
            for (i = 0; i < 144; i = i + 1)
                if (^w2[i] === 1'bx) $fatal(1, "Missing word in conv2 weight memory at %0d", i);
            for (i = 0; i < 144; i = i + 1)
                if (^w3[i] === 1'bx) $fatal(1, "Missing word in conv3 weight memory at %0d", i);
            for (i = 0; i < 16; i = i + 1)
                if (^wf[i] === 1'bx) $fatal(1, "Missing word in FC weight memory at %0d", i);

            $display("CNN memories loaded: 108 + 144 + 144 + 16 INT8 words");
        end
    endtask

    initial begin
        $readmemh("D:/LAB/custom_SOC/CNN_RTL/conv1_rgb_weight.mem", w1);
        $readmemh("D:/LAB/custom_SOC/CNN_RTL/conv2_weight.mem", w2);
        $readmemh("D:/LAB/custom_SOC/CNN_RTL/conv3_weight.mem", w3);
        $readmemh("D:/LAB/custom_SOC/CNN_RTL/fc_weight.mem", wf);
        #1 check_weight_memory;
        pixel_count = 0;
        processing = 1'b0;
        pixel_ready = 1'b1;
        result_valid = 1'b0;
        classification = 1'b0;
    end

    task process_frame;
        integer oc, ic, x, y, kx, ky, idx, wi;
        integer sum, q, v, r, g, b, px, maxv, acc;
        begin
            // Conv1: 32x32x3 -> 30x30x4, then pool -> 15x15x4.
            for (oc = 0; oc < 4; oc = oc + 1)
                for (y = 0; y < 30; y = y + 1)
                    for (x = 0; x < 30; x = x + 1) begin
                        sum = 0;
                        for (ic = 0; ic < 3; ic = ic + 1)
                            for (ky = 0; ky < 3; ky = ky + 1)
                                for (kx = 0; kx < 3; kx = kx + 1) begin
                                    px = image[(y + ky) * 32 + x + kx];
                                    if (ic == 0) v = (px[23:16] * 16) / 255;
                                    else if (ic == 1) v = (px[15:8] * 16) / 255;
                                    else v = (px[7:0] * 16) / 255;
                                    wi = oc * 27 + ic * 9 + ky * 3 + kx;
                                    sum = sum + v * $signed(w1[wi]);
                                end
                        q = sum >>> 4;
                        if (q < 0) q = 0;
                        if (q > 127) q = 127;
                        c1[oc * 900 + y * 30 + x] = q;
                    end

            for (oc = 0; oc < 4; oc = oc + 1)
                for (y = 0; y < 15; y = y + 1)
                    for (x = 0; x < 15; x = x + 1) begin
                        maxv = 0;
                        for (ky = 0; ky < 2; ky = ky + 1)
                            for (kx = 0; kx < 2; kx = kx + 1)
                                if (c1[oc * 900 + (2*y+ky)*30 + 2*x+kx] > maxv)
                                    maxv = c1[oc * 900 + (2*y+ky)*30 + 2*x+kx];
                        p1[oc * 225 + y * 15 + x] = maxv;
                    end

            // Conv2: 15x15x4 -> 13x13x4, then pool -> 6x6x4.
            for (oc = 0; oc < 4; oc = oc + 1)
                for (y = 0; y < 13; y = y + 1)
                    for (x = 0; x < 13; x = x + 1) begin
                        sum = 0;
                        for (ic = 0; ic < 4; ic = ic + 1)
                            for (ky = 0; ky < 3; ky = ky + 1)
                                for (kx = 0; kx < 3; kx = kx + 1) begin
                                    wi = oc * 36 + ic * 9 + ky * 3 + kx;
                                    sum = sum + p1[ic * 225 + (y+ky)*15+x+kx] * $signed(w2[wi]);
                                end
                        q = sum >>> 4;
                        if (q < 0) q = 0;
                        if (q > 127) q = 127;
                        c2[oc * 169 + y * 13 + x] = q;
                    end

            for (oc = 0; oc < 4; oc = oc + 1)
                for (y = 0; y < 6; y = y + 1)
                    for (x = 0; x < 6; x = x + 1) begin
                        maxv = 0;
                        for (ky = 0; ky < 2; ky = ky + 1)
                            for (kx = 0; kx < 2; kx = kx + 1)
                                if (c2[oc * 169 + (2*y+ky)*13 + 2*x+kx] > maxv)
                                    maxv = c2[oc * 169 + (2*y+ky)*13 + 2*x+kx];
                        p2[oc * 36 + y * 6 + x] = maxv;
                    end

            // Conv3: 6x6x4 -> 4x4x4, then pool -> 2x2x4.
            for (oc = 0; oc < 4; oc = oc + 1)
                for (y = 0; y < 4; y = y + 1)
                    for (x = 0; x < 4; x = x + 1) begin
                        sum = 0;
                        for (ic = 0; ic < 4; ic = ic + 1)
                            for (ky = 0; ky < 3; ky = ky + 1)
                                for (kx = 0; kx < 3; kx = kx + 1) begin
                                    wi = oc * 36 + ic * 9 + ky * 3 + kx;
                                    sum = sum + p2[ic * 36 + (y+ky)*6+x+kx] * $signed(w3[wi]);
                                end
                        q = sum >>> 4;
                        if (q < 0) q = 0;
                        if (q > 127) q = 127;
                        c3[oc * 16 + y * 4 + x] = q;
                    end

            for (oc = 0; oc < 4; oc = oc + 1)
                for (y = 0; y < 2; y = y + 1)
                    for (x = 0; x < 2; x = x + 1) begin
                        maxv = 0;
                        for (ky = 0; ky < 2; ky = ky + 1)
                            for (kx = 0; kx < 2; kx = kx + 1)
                                if (c3[oc * 16 + (2*y+ky)*4 + 2*x+kx] > maxv)
                                    maxv = c3[oc * 16 + (2*y+ky)*4 + 2*x+kx];
                        p3[oc * 4 + y * 2 + x] = maxv;
                    end

            // FC order: pixel0[ch0..ch3], pixel1[ch0..ch3], ...
            acc = 0;
            for (y = 0; y < 2; y = y + 1)
                for (x = 0; x < 2; x = x + 1)
                    for (oc = 0; oc < 4; oc = oc + 1) begin
                        wi = (y * 2 + x) * 4 + oc;
                        acc = acc + p3[oc * 4 + y * 2 + x] * $signed(wf[wi]);
                    end

            classification = (acc >= 0);
            $display("CNN frame complete: accumulator=%0d classification=%0d", acc, classification);
        end
    endtask

    always @(posedge clk) begin
        result_valid <= 1'b0;
        if (rst) begin
            pixel_count <= 0;
            processing <= 1'b0;
            pixel_ready <= 1'b1;
            result_valid <= 1'b0;
        end else if (processing) begin
            // The frame is complete; process it before accepting another frame.
            process_frame;
            processing <= 1'b0;
            pixel_ready <= 1'b1;
            result_valid <= 1'b1;
        end else if (pixel_valid && pixel_ready) begin
            // A transfer occurs only when both valid and ready are high.
            image[pixel_count] = pixel_data;
            if (pixel_count == 1023) begin
                // Stop the producer for one processing phase; no pixel is lost.
                processing <= 1'b1;
                pixel_ready <= 1'b0;
                pixel_count <= 0;
            end else begin
                pixel_count <= pixel_count + 1;
            end
        end
    end
endmodule
