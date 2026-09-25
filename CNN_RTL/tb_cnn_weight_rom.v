`timescale 1ns/1ps

module tb_cnn_weight_rom;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg conv1_en = 0;
    reg [6:0] conv1_addr = 0;
    wire signed [7:0] conv1_data;
    wire conv1_valid;

    reg conv2_en = 0;
    reg [7:0] conv2_addr = 0;
    wire signed [7:0] conv2_data;
    wire conv2_valid;

    reg conv3_en = 0;
    reg [7:0] conv3_addr = 0;
    wire signed [7:0] conv3_data;
    wire conv3_valid;

    reg fc_en = 0;
    reg [3:0] fc_addr = 0;
    wire signed [7:0] fc_data;
    wire fc_valid;

    integer i;
    integer errors;
    integer sum_conv1;
    integer sum_conv2;
    integer sum_conv3;
    integer sum_fc;

    cnn_all_weight_roms dut (
        .clk(clk),
        .conv1_en(conv1_en), .conv1_addr(conv1_addr),
        .conv1_data(conv1_data), .conv1_valid(conv1_valid),
        .conv2_en(conv2_en), .conv2_addr(conv2_addr),
        .conv2_data(conv2_data), .conv2_valid(conv2_valid),
        .conv3_en(conv3_en), .conv3_addr(conv3_addr),
        .conv3_data(conv3_data), .conv3_valid(conv3_valid),
        .fc_en(fc_en), .fc_addr(fc_addr),
        .fc_data(fc_data), .fc_valid(fc_valid)
    );

    task read_fc;
        input [3:0] address;
        begin
            @(negedge clk);
            fc_addr = address;
            fc_en = 1'b1;
            @(posedge clk);
            #1;
            if (!fc_valid) begin
                $display("FAIL: FC valid is low at address %0d", address);
                errors = errors + 1;
            end
            $display("FC[%0d] = %h (%0d)", address, fc_data, $signed(fc_data));
            @(negedge clk);
            fc_en = 1'b0;
        end
    endtask

    initial begin
        errors = 0;
        sum_conv1 = 0;
        sum_conv2 = 0;
        sum_conv3 = 0;
        sum_fc = 0;
        #1;

        // Read representative addresses from each memory.
        @(negedge clk);
        conv1_addr = 0; conv1_en = 1'b1;
        conv2_addr = 0; conv2_en = 1'b1;
        conv3_addr = 0; conv3_en = 1'b1;
        @(posedge clk);
        #1;
        $display("CONV1[0] = %h (%0d)", conv1_data, $signed(conv1_data));
        $display("CONV2[0] = %h (%0d)", conv2_data, $signed(conv2_data));
        $display("CONV3[0] = %h (%0d)", conv3_data, $signed(conv3_data));

        if (!conv1_valid || !conv2_valid || !conv3_valid) begin
            $display("FAIL: convolution ROM valid signal is low");
            errors = errors + 1;
        end

        // Current-file fingerprints. These detect wrong files or wrong paths.
        // Regenerate these expected values if the Python model is retrained.
        for (i = 0; i < 108; i = i + 1)
            sum_conv1 = sum_conv1 + $signed(dut.u_conv1_rom.mem[i]);
        for (i = 0; i < 144; i = i + 1)
            sum_conv2 = sum_conv2 + $signed(dut.u_conv2_rom.mem[i]);
        for (i = 0; i < 144; i = i + 1)
            sum_conv3 = sum_conv3 + $signed(dut.u_conv3_rom.mem[i]);
        for (i = 0; i < 16; i = i + 1)
            sum_fc = sum_fc + $signed(dut.u_fc_rom.mem[i]);

        $display("Checksums: conv1=%0d conv2=%0d conv3=%0d fc=%0d",
                 sum_conv1, sum_conv2, sum_conv3, sum_fc);
        if (sum_conv1 != 146 || sum_conv2 != 43 ||
            sum_conv3 != 37 || sum_fc != -26) begin
            $display("FAIL: weight checksum does not match current Python export");
            errors = errors + 1;
        end

        @(negedge clk);
        conv1_en = 1'b0;
        conv2_en = 1'b0;
        conv3_en = 1'b0;

        for (i = 0; i < 16; i = i + 1)
            read_fc(i[3:0]);

        if (errors == 0)
            $display("PASS: all CNN .mem files were loaded and read.");
        else
            $display("FAIL: %0d test errors.", errors);

        $finish;
    end
endmodule
