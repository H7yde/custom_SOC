module apb_uart_slave #(
    parameter CLK_FREQ  = 50000000, // Tần số PCLK mặc định là 50MHz
    parameter BAUD_RATE = 115200
)(
    input  wire        PCLK, PRESETn,
    input  wire [31:0] UART_PADDR,
    input  wire        UART_PSEL, UART_PENABLE, UART_PWRITE,
    input  wire [31:0] UART_PWDATA,
    output reg  [31:0] UART_PRDATA,
    output wire        UART_PREADY,
    // Chân FPGA
    output wire        uart_tx,
    input  wire        uart_rx
);
    assign UART_PREADY = 1'b1; // Phản hồi lập tức

    // Định nghĩa các thanh ghi nội bộ
    reg [7:0] tx_data;
    reg       tx_start;
    wire      tx_busy;
    wire [7:0] rx_data;
    wire       rx_ready;
    reg        rx_clear;

    // Bộ giải mã địa chỉ APB (Write)
    wire apb_write = UART_PSEL && UART_PENABLE && UART_PWRITE;
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            tx_data  <= 8'h0;
            tx_start <= 1'b0;
        end else begin
            tx_start <= 1'b0;
            if (apb_write && (UART_PADDR[7:0] == 8'h00)) begin
                tx_data  <= UART_PWDATA[7:0];
                tx_start <= 1'b1;
            end
        end
    end

    // Bộ giải mã địa chỉ APB (Read)
    wire apb_read = UART_PSEL && !UART_PWRITE;
    always @(*) begin
        rx_clear = 1'b0;
        if (apb_read) begin
            case (UART_PADDR[7:0])
                8'h04: begin
                    UART_PRDATA   = {24'b0, rx_data};
                    rx_clear = UART_PENABLE; // Xóa cờ báo dữ liệu sau khi đọc xong
                end
                8'h08:   UART_PRDATA = {30'b0, rx_ready, !tx_busy};
                default: UART_PRDATA = 32'h0;
            endcase
        end else begin
            UART_PRDATA = 32'h0;
        end
    end

    // ─── LÕI UART TX (PHÁT TÍN HIỆU) ───
    localparam BIT_PERIOD = CLK_FREQ / BAUD_RATE;
    reg [15:0] clk_cnt;
    reg [3:0]  bit_idx;
    reg [9:0]  tx_shift_reg;
    reg        tx_active;

    assign uart_tx = tx_active ? tx_shift_reg[0] : 1'b1;
    assign tx_busy = tx_active || tx_start;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            clk_cnt <= 0; bit_idx <= 0; tx_active <= 0; tx_shift_reg <= 10'b1;
        end else if (tx_start && !tx_active) begin
            tx_active    <= 1'b1;
            tx_shift_reg <= {1'b1, tx_data, 1'b0}; // [Stop bit (1), Data (8-bit), Start bit (0)]
            clk_cnt      <= 0; bit_idx <= 0;
        end else if (tx_active) begin
            if (clk_cnt < BIT_PERIOD - 1) begin
                clk_cnt <= clk_cnt + 1;
            end else begin
                clk_cnt <= 0;
                if (bit_idx < 9) begin
                    bit_idx      <= bit_idx + 1;
                    tx_shift_reg <= tx_shift_reg >> 1;
                end else begin
                    tx_active <= 1'b0;
                end
            end
        end
    end

    // ─── LÕI UART RX (NHẬN TÍN HIỆU) ───
    // Tự động lấy mẫu ở giữa chu kỳ bit để tránh nhiễu tín hiệu
    reg [1:0] rx_sync;
    always @(posedge PCLK) rx_sync <= {rx_sync[0], uart_rx}; // Chống hiện tượng bất ổn định (Metastability)

    reg        rx_active;
    reg [15:0] rx_clk_cnt;
    reg [3:0]  rx_bit_idx;
    reg [7:0]  rx_shift_data;
    reg        rx_done;

    assign rx_data  = rx_shift_data;
    assign rx_ready = rx_done;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            rx_active <= 0; rx_clk_cnt <= 0; rx_bit_idx <= 0; rx_done <= 0;
        end else begin
            if (rx_clear) rx_done <= 1'b0;
            
            if (!rx_active && (rx_sync[1] == 1'b0)) begin // Phát hiện Start bit
                rx_active  <= 1'b1;
                rx_clk_cnt <= 0;
                rx_bit_idx <= 0;
            end else if (rx_active) begin
                if (rx_clk_cnt < BIT_PERIOD - 1) begin
                    rx_clk_cnt <= rx_clk_cnt + 1;
                end else begin
                    rx_clk_cnt <= 0;
                    if (rx_bit_idx == 0) begin // Bỏ qua Start bit
                        rx_bit_idx <= rx_bit_idx + 1;
                    end else if (rx_bit_idx <= 8) begin
                        rx_shift_data <= {rx_sync[1], rx_shift_data[7:1]};
                        rx_bit_idx    <= rx_bit_idx + 1;
                    end else begin
                        rx_active <= 1'b0;
                        rx_done   <= 1'b1; // Đã nhận đủ 1 khung byte dữ liệu
                    end
                end
            end
        end
    end
endmodule