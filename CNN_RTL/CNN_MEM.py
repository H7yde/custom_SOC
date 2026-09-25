`timescale 1ns / 1ps

module conv_weight_bram #(
    parameter DATA_WIDTH   = 8,           // Dữ liệu INT8 (Q4.4)
    parameter KERNEL_SIZE  = 3,           // Cửa sổ tích chập 3x3
    parameter IN_CHANNELS  = 1,           // Số channel đầu vào
    parameter OUT_CHANNELS = 4,           // Số filter (Kernel count)
    parameter FILE_NAME    = "conv1_weight.hex"
)(
    input  wire                            clk,
    input  wire                            rst_n,
    
    // Control interface
    input  wire [$clog2(OUT_CHANNELS)-1:0] filter_idx,    // Chọn kernel (0 đến OUT_CHANNELS-1)
    input  wire                            req_valid,     // Yêu cầu nạp trọng số mới
    output reg                             weights_valid, // Báo hiệu trọng số đã sẵn sàng
    
    // Song song 9 đầu ra cho cửa sổ 3x3
    output reg  signed [DATA_WIDTH-1:0]    w00, w01, w02,
    output reg  signed [DATA_WIDTH-1:0]    w10, w11, w12,
    output reg  signed [DATA_WIDTH-1:0]    w20, w21, w22
);

    localparam KERNEL_WORDS  = KERNEL_SIZE * KERNEL_SIZE; // 9 words / filter
    localparam TOTAL_WEIGHTS = OUT_CHANNELS * IN_CHANNELS * KERNEL_WORDS;

    // Khai báo BRAM Array
    (* ram_style = "block" *) reg signed [DATA_WIDTH-1:0] bram [0:TOTAL_WEIGHTS-1];

    // Readmemh nạp file .hex khi tổng hợp / mô phỏng
    initial begin
        $readmemh(FILE_NAME, bram);
    end

    // Tính địa chỉ gốc của Filter tương ứng
    wire [31:0] base_addr = filter_idx * KERNEL_WORDS;

    // Đọc đồng bộ từ BRAM (đảm bảo Vivado suy luận ra Block RAM chuẩn)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w00 <= 8'sd0; w01 <= 8'sd0; w02 <= 8'sd0;
            w10 <= 8'sd0; w11 <= 8'sd0; w12 <= 8'sd0;
            w20 <= 8'sd0; w21 <= 8'sd0; w22 <= 8'sd0;
            weights_valid <= 1'b0;
        end else if (req_valid) begin
            w00 <= bram[base_addr + 0];
            w01 <= bram[base_addr + 1];
            w02 <= bram[base_addr + 2];
            w10 <= bram[base_addr + 3];
            w11 <= bram[base_addr + 4];
            w12 <= bram[base_addr + 5];
            w20 <= bram[base_addr + 6];
            w21 <= bram[base_addr + 7];
            w22 <= bram[base_addr + 8];
            weights_valid <= 1'b1;
        end else begin
            weights_valid <= 1'b0;
        end
    end

endmodule