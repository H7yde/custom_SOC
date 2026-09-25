`timescale 1ns/1ps

// Basic testbench: verify that Verilog can load all trained .mem files.
// Run the simulator from D:\LAB\custom_SOC\CNN_RTL so the relative paths resolve.
module tb_mem_load;
    reg signed [7:0] conv1_mem [0:107];
    reg signed [7:0] conv2_mem [0:143];
    reg signed [7:0] conv3_mem [0:143];
    reg signed [7:0] fc_mem    [0:15];

    integer i;
    integer errors;

    initial begin
        errors = 0;

        $readmemh("conv1_rgb_weight.mem", conv1_mem);
        $readmemh("conv2_weight.mem",     conv2_mem);
        $readmemh("conv3_weight.mem",     conv3_mem);
        $readmemh("fc_weight.mem",        fc_mem);

        // Detect an uninitialized/X word in each memory.
        for (i = 0; i < 108; i = i + 1)
            if (^conv1_mem[i] === 1'bx) errors = errors + 1;
        for (i = 0; i < 144; i = i + 1)
            if (^conv2_mem[i] === 1'bx) errors = errors + 1;
        for (i = 0; i < 144; i = i + 1)
            if (^conv3_mem[i] === 1'bx) errors = errors + 1;
        for (i = 0; i < 16; i = i + 1)
            if (^fc_mem[i] === 1'bx) errors = errors + 1;

        $display("conv1[0]=%h (%0d), conv1[107]=%h (%0d)",
                 conv1_mem[0], $signed(conv1_mem[0]),
                 conv1_mem[107], $signed(conv1_mem[107]));
        $display("conv2[0]=%h, conv3[0]=%h", conv2_mem[0], conv3_mem[0]);
        $display("fc[0]=%h (%0d), fc[15]=%h (%0d)",
                 fc_mem[0], $signed(fc_mem[0]),
                 fc_mem[15], $signed(fc_mem[15]));

        if (errors == 0)
            $display("PASS: all .mem words were loaded.");
        else
            $display("FAIL: %0d uninitialized words found.", errors);

        $finish;
    end
endmodule
