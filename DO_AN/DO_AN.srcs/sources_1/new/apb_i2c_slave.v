module apb_i2c_slave (
    input  wire        PCLK, PRESETn,
    input  wire [31:0] I2C_PADDR,
    input  wire        I2C_PSEL, I2C_PENABLE, I2C_PWRITE,
    input  wire [31:0] I2C_PWDATA,
    output reg  [31:0] I2C_PRDATA,
    output wire        PREADY,
    // Các chân I2C vật lý kết nối linh hoạt tri-state bên ngoài top wrapper
    output reg         scl_out,
    output reg         sda_out,
    output reg         sda_oe, // 1: FPGA kéo dây SDA, 0: Thả nổi cho cảm biến kéo
    input  wire        sda_in
);
    reg [7:0] i2c_data;
    reg [3:0] i2c_cmd;
    reg        cmd_trigger;
    wire       i2c_busy;
    wire       rx_ack;
    wire cmd_write = I2C_PSEL && I2C_PENABLE && I2C_PWRITE &&
                     (I2C_PADDR[7:0] == 8'h04);
    assign PREADY = !(cmd_write && i2c_busy);

    wire apb_write = I2C_PSEL && I2C_PENABLE && I2C_PWRITE && PREADY;

    // Giao tiếp APB Write
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            i2c_data    <= 8'h0; 
            i2c_cmd     <= 4'h0; 
            cmd_trigger <= 1'b0;
        end else begin
            cmd_trigger <= 1'b0;
            if (apb_write) begin
                if (I2C_PADDR[7:0] == 8'h00) i2c_data <= I2C_PWDATA[7:0];
                if (I2C_PADDR[7:0] == 8'h04) begin 
                    i2c_cmd     <= I2C_PWDATA[3:0]; 
                    cmd_trigger <= 1'b1; 
                end
            end
        end
    end

    // Giao tiếp APB Read
    always @(*) begin
        if (I2C_PSEL && !I2C_PWRITE) begin
            case (I2C_PADDR[7:0])
                8'h00:   I2C_PRDATA = {24'b0, i2c_data};
                8'h08:   I2C_PRDATA = {30'b0, rx_ack, i2c_busy};
                default: I2C_PRDATA = 32'h0;
            endcase
        end else begin
            I2C_PRDATA = 32'h0;
        end
    end

    // ─── LÕI ĐIỀU KHIỂN I2C STATE MACHINE ───
    reg [3:0] state;
    reg [7:0] clk_cnt;
    reg [2:0] bit_idx;
    reg        busy_reg;
    reg        ack_reg;

    assign i2c_busy = busy_reg;
    assign rx_ack   = ack_reg;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            state    <= 0; 
            scl_out  <= 1; 
            sda_out  <= 1; 
            sda_oe   <= 1; 
            busy_reg <= 0; 
            ack_reg  <= 0; 
            clk_cnt  <= 0; 
            bit_idx  <= 0;
        end else begin
            case (state)
                0: begin // IDLE
                    scl_out  <= 1'b1;
                    sda_out  <= 1'b1;
                    sda_oe   <= 1'b1;
                    if (cmd_trigger) begin
                        busy_reg <= 1'b1;
                        clk_cnt  <= 0;
                        if (i2c_cmd[0])      state <= 1; // Lệnh START
                        else if (i2c_cmd[1]) state <= 3; // Lệnh STOP
                        else if (i2c_cmd[2]) begin bit_idx <= 7; state <= 5; end // Ghi Byte
                    end else begin
                        busy_reg <= 1'b0;
                    end
                end

                // MẠCH ĐIỀU KHIỂN START CONDITION
                1: begin sda_out <= 1'b0; clk_cnt <= clk_cnt + 1; if(clk_cnt == 50) begin clk_cnt <= 0; state <= 2; end end
                2: begin scl_out <= 1'b0; clk_cnt <= clk_cnt + 1; if(clk_cnt == 50) begin clk_cnt <= 0; state <= 0; end end

                // MẠCH ĐIỀU KHIỂN STOP CONDITION
                3: begin sda_out <= 1'b0; scl_out <= 1'b1; clk_cnt <= clk_cnt + 1; if(clk_cnt == 50) begin clk_cnt <= 0; state <= 4; end end
                4: begin sda_out <= 1'b1; clk_cnt <= clk_cnt + 1; if(clk_cnt == 50) begin clk_cnt <= 0; state <= 0; end end

                // MẠCH TRUYỀN DỮ LIỆU (8-BIT) & KIỂM TRA ACK
                5: begin // Đẩy bit dữ liệu ra dây SDA
                    sda_out <= i2c_data[bit_idx];
                    clk_cnt <= clk_cnt + 1;
                    if (clk_cnt == 25) scl_out <= 1'b1;
                    if (clk_cnt == 50) begin
                        scl_out <= 1'b0;
                        clk_cnt <= 0;
                        if (bit_idx > 0) bit_idx <= bit_idx - 1;
                        else state <= 6; // Chuyển sang chu kỳ kiểm tra bit phản hồi ACK
                    end
                end
                
                6: begin // Nhận cờ ACK từ thiết bị ngoại vi ngoài chip
                    sda_oe  <= 1'b0; // Thả chân SDA cho Slave kéo xuống
                    clk_cnt <= clk_cnt + 1;
                    if (clk_cnt == 25) begin scl_out <= 1'b1; ack_reg <= sda_in; end // Lấy mẫu bit ACK
                    if (clk_cnt == 50) begin
                        scl_out <= 1'b0;
                        clk_cnt <= 0;
                        state   <= 0;
                    end
                end
                default: state <= 0;
            endcase
        end
    end
endmodule
