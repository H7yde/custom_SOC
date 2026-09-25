`timescale 1ns/1ps

// Simulation reference for the CNN described in the DOCX.
// It buffers one 32x32 RGB frame, then evaluates:
// Conv1 -> ReLU -> Pool -> Conv2 -> ReLU -> Pool
//       -> Conv3 -> ReLU -> Pool -> FC -> classification
//
// This version is intended to validate .mem files and numerical ordering.
// It is not the cycle-accurate streaming implementation for synthesis.
module cnn_docx_reference (
    input  logic        clk,
    input  logic        rst,
    input  logic [23:0] pixel_data,
    input  logic        pixel_valid,
    output logic        pixel_ready,
    output logic        result_valid,
    output logic        classification
);
    localparam integer PIXELS = 32 * 32;

    logic [23:0] image [0:PIXELS-1];
    logic signed [7:0] w1 [0:107];
    logic signed [7:0] w2 [0:143];
    logic signed [7:0] w3 [0:143];
    logic signed [7:0] wf [0:15];
    integer pixel_count;

    integer c1 [0:3][0:899];
    integer p1 [0:3][0:224];
    integer c2 [0:3][0:168];
    integer p2 [0:3][0:35];
    integer c3 [0:3][0:15];
    integer p3 [0:3][0:3];

    initial begin
        $readmemh("D:/LAB/custom_SOC/CNN_RTL/conv1_rgb_weight.mem", w1);
        $readmemh("D:/LAB/custom_SOC/CNN_RTL/conv2_weight.mem", w2);
        $readmemh("D:/LAB/custom_SOC/CNN_RTL/conv3_weight.mem", w3);
        $readmemh("D:/LAB/custom_SOC/CNN_RTL/fc_weight.mem", wf);
        pixel_count = 0;
        pixel_ready = 1'b1;
        result_valid = 1'b0;
        classification = 1'b0;
    end

    task automatic process_frame;
        integer oc, ic, x, y, kx, ky, idx, wi;
        integer sum, q, v, r, g, b, px;
        integer maxv, acc;
        begin
            // Conv1: 32x32x3 -> 30x30x4, then 2x2 pool -> 15x15x4.
            for (oc = 0; oc < 4; oc = oc + 1)
                for (y = 0; y < 30; y = y + 1)
                    for (x = 0; x < 30; x = x + 1) begin
                        sum = 0;
                        for (ic = 0; ic < 3; ic = ic + 1)
                            for (ky = 0; ky < 3; ky = ky + 1)
                                for (kx = 0; kx < 3; kx = kx + 1) begin
                                    px = image[(y + ky) * 32 + x + kx];
                                    if (ic == 0) r = (px[23:16] * 16) / 255;
                                    else if (ic == 1) g = (px[15:8] * 16) / 255;
                                    else b = (px[7:0] * 16) / 255;
                                    if (ic == 0) v = r;
                                    else if (ic == 1) v = g;
                                    else v = b;
                                    wi = oc * 27 + ic * 9 + ky * 3 + kx;
                                    sum = sum + v * $signed(w1[wi]);
                                end
                        q = sum >>> 4;
                        if (q < 0) q = 0;
                        if (q > 127) q = 127;
                        c1[oc][y * 30 + x] = q;
                    end

            for (oc = 0; oc < 4; oc = oc + 1)
                for (y = 0; y < 15; y = y + 1)
                    for (x = 0; x < 15; x = x + 1) begin
                        maxv = 0;
                        for (ky = 0; ky < 2; ky = ky + 1)
                            for (kx = 0; kx < 2; kx = kx + 1)
                                if (c1[oc][(2*y+ky)*30+2*x+kx] > maxv)
                                    maxv = c1[oc][(2*y+ky)*30+2*x+kx];
                        p1[oc][y * 15 + x] = maxv;
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
                                    sum = sum + p1[ic][(y+ky)*15+x+kx] * $signed(w2[wi]);
                                end
                        q = sum >>> 4;
                        if (q < 0) q = 0;
                        if (q > 127) q = 127;
                        c2[oc][y * 13 + x] = q;
                    end

            for (oc = 0; oc < 4; oc = oc + 1)
                for (y = 0; y < 6; y = y + 1)
                    for (x = 0; x < 6; x = x + 1) begin
                        maxv = 0;
                        for (ky = 0; ky < 2; ky = ky + 1)
                            for (kx = 0; kx < 2; kx = kx + 1)
                                if (c2[oc][(2*y+ky)*13+2*x+kx] > maxv)
                                    maxv = c2[oc][(2*y+ky)*13+2*x+kx];
                        p2[oc][y * 6 + x] = maxv;
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
                                    sum = sum + p2[ic][(y+ky)*6+x+kx] * $signed(w3[wi]);
                                end
                        q = sum >>> 4;
                        if (q < 0) q = 0;
                        if (q > 127) q = 127;
                        c3[oc][y * 4 + x] = q;
                    end

            for (oc = 0; oc < 4; oc = oc + 1)
                for (y = 0; y < 2; y = y + 1)
                    for (x = 0; x < 2; x = x + 1) begin
                        maxv = 0;
                        for (ky = 0; ky < 2; ky = ky + 1)
                            for (kx = 0; kx < 2; kx = kx + 1)
                                if (c3[oc][(2*y+ky)*4+2*x+kx] > maxv)
                                    maxv = c3[oc][(2*y+ky)*4+2*x+kx];
                        p3[oc][y * 2 + x] = maxv;
                    end

            // FC order is spatial position, then channel, as exported by Python.
            acc = 0;
            for (y = 0; y < 2; y = y + 1)
                for (x = 0; x < 2; x = x + 1)
                    for (oc = 0; oc < 4; oc = oc + 1) begin
                        wi = (y * 2 + x) * 4 + oc;
                        acc = acc + p3[oc][y * 2 + x] * $signed(wf[wi]);
                    end

            classification = (acc >= 0);
            $display("CNN frame complete: FC accumulator=%0d classification=%0d", acc, classification);
        end
    endtask

    always @(posedge clk) begin
        result_valid <= 1'b0;
        if (rst) begin
            pixel_count <= 0;
            result_valid <= 1'b0;
        end else if (pixel_valid && pixel_ready) begin
            image[pixel_count] = pixel_data;
            if (pixel_count == PIXELS - 1) begin
                process_frame;
                pixel_count <= 0;
                result_valid <= 1'b1;
            end else begin
                pixel_count <= pixel_count + 1;
            end
        end
    end
endmodule
