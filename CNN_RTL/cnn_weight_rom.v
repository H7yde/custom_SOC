`timescale 1ns/1ps

// Generic synchronous ROM for INT8 Q4.4 CNN weights.
// The memory file is loaded at simulation/elaboration time with $readmemh.
module cnn_weight_rom #(
    parameter integer DEPTH = 16,
    parameter integer ADDR_WIDTH = 4,
    // Use forward slashes for Vivado/XSim on Windows.
    // Change this root if the project is moved to another directory.
    parameter FILE_NAME = "D:/LAB/custom_SOC/CNN_RTL/fc_weight.mem"
) (
    input  wire                         clk,
    input  wire                         en,
    input  wire [ADDR_WIDTH-1:0]        addr,
    output reg  signed [7:0]            data,
    output reg                          data_valid
);

    reg signed [7:0] mem [0:DEPTH-1];
    integer mem_file;

    initial begin
        mem_file = $fopen(FILE_NAME, "r");
        if (mem_file == 0) begin
            $fatal(1, "Cannot open weight memory file: %s", FILE_NAME);
        end
        $fclose(mem_file);
        $readmemh(FILE_NAME, mem);
    end

    always @(posedge clk) begin
        data_valid <= 1'b0;
        if (en) begin
            data <= mem[addr];
            data_valid <= 1'b1;
        end
    end
endmodule


// Memory wrapper with the exact files and sizes from the DOCX CNN design.
module cnn_all_weight_roms (
    input  wire        clk,
    input  wire        conv1_en,
    input  wire [6:0]  conv1_addr,
    output wire signed [7:0] conv1_data,
    output wire        conv1_valid,

    input  wire        conv2_en,
    input  wire [7:0]  conv2_addr,
    output wire signed [7:0] conv2_data,
    output wire        conv2_valid,

    input  wire        conv3_en,
    input  wire [7:0]  conv3_addr,
    output wire signed [7:0] conv3_data,
    output wire        conv3_valid,

    input  wire        fc_en,
    input  wire [3:0]  fc_addr,
    output wire signed [7:0] fc_data,
    output wire        fc_valid
);
    cnn_weight_rom #(
        .DEPTH(108), .ADDR_WIDTH(7),
        .FILE_NAME("D:/LAB/custom_SOC/CNN_RTL/conv1_rgb_weight.mem")
    ) u_conv1_rom (
        .clk(clk), .en(conv1_en), .addr(conv1_addr),
        .data(conv1_data), .data_valid(conv1_valid)
    );

    cnn_weight_rom #(
        .DEPTH(144), .ADDR_WIDTH(8),
        .FILE_NAME("D:/LAB/custom_SOC/CNN_RTL/conv2_weight.mem")
    ) u_conv2_rom (
        .clk(clk), .en(conv2_en), .addr(conv2_addr),
        .data(conv2_data), .data_valid(conv2_valid)
    );

    cnn_weight_rom #(
        .DEPTH(144), .ADDR_WIDTH(8),
        .FILE_NAME("D:/LAB/custom_SOC/CNN_RTL/conv3_weight.mem")
    ) u_conv3_rom (
        .clk(clk), .en(conv3_en), .addr(conv3_addr),
        .data(conv3_data), .data_valid(conv3_valid)
    );

    cnn_weight_rom #(
        .DEPTH(16), .ADDR_WIDTH(4),
        .FILE_NAME("D:/LAB/custom_SOC/CNN_RTL/fc_weight.mem")
    ) u_fc_rom (
        .clk(clk), .en(fc_en), .addr(fc_addr),
        .data(fc_data), .data_valid(fc_valid)
    );
endmodule
