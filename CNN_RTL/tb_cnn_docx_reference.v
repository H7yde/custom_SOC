`timescale 1ns/1ps

// Minimal binary-classification testbench.
// expected = 1: human, expected = 0: non-human.
module tb_cnn_docx_reference;
    reg clk;
    reg rst;
    reg [23:0] pixel_data;
    reg pixel_valid;
    wire pixel_ready;
    wire result_valid;
    wire classification;
    reg [23:0] frame [0:1023];
    integer errors;

    cnn_docx_reference dut (
        .clk(clk), .rst(rst), .pixel_data(pixel_data),
        .pixel_valid(pixel_valid), .pixel_ready(pixel_ready),
        .result_valid(result_valid), .classification(classification)
    );

    always #5 clk = ~clk;

    task run_case;
        input [2047:0] image_file;
        input expected;
        input [127:0] case_name;
        integer i;
        begin
            $display("[TB] START %0s, expected=%0d", case_name, expected);
            $readmemh(image_file, frame);

            // Send exactly 1024 RGB pixels using valid/ready handshake.
            for (i = 0; i < 1024; i = i + 1) begin
                @(negedge clk);
                pixel_data = frame[i];
                pixel_valid = 1'b1;
                @(posedge clk);
                // DUT lowers ready after accepting the last pixel.
                if (i < 1023)
                    while (!pixel_ready) @(posedge clk);
            end

            @(negedge clk);
            pixel_valid = 1'b0;
            pixel_data = 24'd0;
            @(posedge clk);
            #1;

            if (result_valid && classification === expected)
                $display("[TB] PASS %0s: got=%0d", case_name, classification);
            else begin
                $display("[TB] FAIL %0s: got=%0d expected=%0d valid=%0d",
                         case_name, classification, expected, result_valid);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        pixel_data = 24'd0;
        pixel_valid = 1'b0;
        errors = 0;

        #20;
        rst = 1'b0;
        run_case("D:/LAB/custom_SOC/CNN_RTL/human_frame.mem", 1'b1, "HUMAN");
        run_case("D:/LAB/custom_SOC/CNN_RTL/nonhuman_frame.mem", 1'b0, "NON-HUMAN");

        if (errors == 0)
            $display("[TB] FINAL PASS: both binary cases are correct");
        else
            $display("[TB] FINAL FAIL: %0d case(s) failed", errors);
        $finish;
    end
endmodule
