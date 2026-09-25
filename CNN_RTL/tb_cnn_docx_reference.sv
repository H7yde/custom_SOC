`timescale 1ns/1ps

// Put two 32x32 RGB frame files in the working directory:
//   human_frame.mem
//   nonhuman_frame.mem
// Each file must contain 1024 lines, one RGB pixel per line, RRGGBB.
module tb_cnn_docx_reference;
    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;
    reg [23:0] frame [0:1023];
    reg [23:0] pixel_data = 0;
    reg pixel_valid = 0;
    wire pixel_ready;
    wire result_valid;
    wire classification;
    integer i;
    integer errors = 0;

    cnn_docx_reference dut (
        .clk(clk), .rst(rst), .pixel_data(pixel_data),
        .pixel_valid(pixel_valid), .pixel_ready(pixel_ready),
        .result_valid(result_valid), .classification(classification)
    );

    task send_frame;
        input [8*256-1:0] filename;
        input expected_label;
        begin
            $readmemh(filename, frame);
            @(negedge clk);
            rst = 0;
            for (i = 0; i < 1024; i = i + 1) begin
                @(negedge clk);
                pixel_data = frame[i];
                pixel_valid = 1;
                @(posedge clk);
                while (!pixel_ready) @(posedge clk);
            end
            @(negedge clk);
            pixel_valid = 0;
            pixel_data = 0;
            // process_frame is a simulation reference and completes at the last pixel.
            @(posedge clk);
            #1;
            if (!result_valid) begin
                $display("FAIL: result_valid is not asserted for %0s", filename);
                errors = errors + 1;
            end
            if (classification !== expected_label) begin
                $display("FAIL: %0s -> got=%0d expected=%0d",
                         filename, classification, expected_label);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s -> classification=%0d (1=human, 0=non-human)",
                         filename, classification);
            end
        end
    endtask

    initial begin
        #20;
        send_frame("D:/LAB/custom_SOC/CNN_RTL/human_frame.mem", 1'b1);
        send_frame("D:/LAB/custom_SOC/CNN_RTL/nonhuman_frame.mem", 1'b0);
        if (errors == 0)
            $display("BINARY CLASSIFICATION PASS: human/non-human test passed.");
        else
            $display("BINARY CLASSIFICATION FAIL: %0d errors.", errors);
        $finish;
    end
endmodule
