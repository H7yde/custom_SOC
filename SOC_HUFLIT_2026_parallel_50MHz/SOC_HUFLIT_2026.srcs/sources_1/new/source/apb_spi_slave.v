`timescale 1ns/1ps

module apb_spi_slave (
    input  wire        PCLK, PRESETn,
    input  wire [31:0] SPI_PADDR,
    input  wire        SPI_PSEL, SPI_PENABLE, SPI_PWRITE,
    input  wire [31:0] SPI_PWDATA,
    output reg  [31:0] SPI_PRDATA,
    output wire        PREADY,
    // Chân vật lý SPI nối cảm biến
    output reg         spi_sclk,
    output reg         spi_cs,
    output wire        spi_mosi,
    input  wire        spi_miso
);
    assign PREADY = 1'b1;

    reg [7:0] tx_shifter;
    reg [7:0] tx_data_buf;
    reg [7:0] rx_data_buf;
    reg       spi_busy;
    reg       start_tx;
    
    assign spi_mosi = tx_shifter[7];

    // Giao tiếp ghi thanh ghi APB
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            spi_cs   <= 1'b1; // Mặc định không chọn chip
            start_tx <= 1'b0;
            tx_data_buf <= 8'h0;
        end else begin
            start_tx <= 1'b0;
            if (SPI_PSEL && SPI_PENABLE && SPI_PWRITE) begin
                case (SPI_PADDR[7:0])
                    8'h00: begin tx_data_buf <= SPI_PWDATA[7:0]; start_tx <= 1'b1; end
                    8'h04: spi_cs <= SPI_PWDATA[0];
                    default: ;
                endcase
            end
        end
    end

    // Giao tiếp đọc thanh ghi APB
    always @(*) begin
        if (SPI_PSEL && !SPI_PWRITE) begin
            case (SPI_PADDR[7:0])
                8'h00:   SPI_PRDATA = {24'b0, rx_data_buf};
                8'h04:  SPI_PRDATA = {31'b0, spi_cs};
                8'h08:   SPI_PRDATA = {31'b0, spi_busy};
                default: SPI_PRDATA = 32'h0;
            endcase
        end else SPI_PRDATA = 32'h0;
    end

    // ─── LÕI ĐIỀU KHIỂN SPI MASTER FSM ───
    reg [2:0] state;
    reg [3:0] bit_cnt;
    reg [7:0] clk_div; // Bộ chia tần số xung SCLK

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            state <= 0; spi_sclk <= 0; bit_cnt <= 0; clk_div <= 0; spi_busy <= 0; rx_data_buf <= 0; tx_shifter <= 0;
        end else begin
            case (state)
                0: begin // IDLE
                    spi_sclk <= 1'b0;
                    if (start_tx && !spi_cs) begin
                        spi_busy <= 1'b1;
                        bit_cnt  <= 0;
                        clk_div  <= 0;
                        tx_shifter <= tx_data_buf;
                        state    <= 1;
                    end else spi_busy <= 1'b0;
                end
                1: begin // Cạnh lên SCLK - Lấy mẫu dữ liệu MISO
                    spi_sclk <= 1'b1;
                    if (clk_div == 8'd5) begin // Điều chỉnh tốc độ truyền SPI
                        clk_div     <= 0;
                        rx_data_buf <= {rx_data_buf[6:0], spi_miso};
                        state       <= 2;
                    end else clk_div <= clk_div + 1;
                end
                2: begin // Cạnh xuống SCLK - Đẩy dữ liệu MOSI mới ra ngoài
                    spi_sclk <= 1'b0;
                    if (clk_div == 8'd5) begin
                        clk_div <= 0;
                        if (bit_cnt < 7) begin
                            bit_cnt    <= bit_cnt + 1;
                            tx_shifter <= tx_shifter << 1;
                            state      <= 1;
                        end else begin
                            state <= 0; // Đã truyền nhận xong 8-bit
                        end
                    end else clk_div <= clk_div + 1;
                end
                default: state <= 0;
            endcase
        end
    end
endmodule