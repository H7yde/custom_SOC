`timescale 1ns/1ps

// Full CPU -> AXI -> UART/CNN integration test. Compile as SystemVerilog.
// The firmware is loaded by soc_top's normal $readmemh("firmware.hex").
module tb_firmware;
    parameter integer BAUD_RATE = 1000000;
    localparam integer CLK_FREQ = 100000000;
    localparam integer BIT_CLOCKS = CLK_FREQ / BAUD_RATE;
    localparam integer BIT_NS = 10 * BIT_CLOCKS;

    reg clk = 0;
    reg resetn = 0;
    reg uart_rx = 1;
    wire uart_tx;
    wire cpu_trap;
    always #5 clk = ~clk;

    soc_top #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) dut (
        .clk(clk), .resetn(resetn),
        .uart_tx(uart_tx), .uart_rx(uart_rx),
        .spi_sclk(), .spi_mosi(), .spi_miso(1'b0), .spi_cs(),
        .scl_out(), .sda_out(), .sda_oe(), .sda_in(1'b1),
        .ddr_data_in(32'b0), .ddr_rx_valid(1'b0),
        .ddr_data(), .ddr_clk_out(), .ddr_valid(), .ddr_done(),
        .cpu_trap(cpu_trap)
    );

    reg [23:0] human_pixels [0:1023];
    reg [23:0] nonhuman_pixels [0:1023];
    integer ready_count = 0;
    integer send_count = 0;
    integer result_count = 0;
    integer smoke_count = 0;
    integer cnn_done_count = 0;
    integer dma_read_count = 0;
    integer expected_image = -1;
    integer pingpong_image_check = 0;
    integer result_class [0:15];
    reg [31:0] result_status [0:15];
    reg [31:0] result_cycles [0:15];
    reg [31:0] result_reads [0:15];
    string line = "";
    integer uart_log;

    // Observe the real serial pin, including start/stop bits; no UART bypass.
    initial begin : serial_monitor
        reg [7:0] value;
        integer bit_number;
        integer fields;
        integer classification;
        reg [31:0] status_value;
        reg [31:0] cycle_value;
        reg [31:0] read_value;
        uart_log = $fopen("uart.log", "w");
        forever begin
            @(negedge uart_tx);
            if (resetn) begin
                #(BIT_NS / 2);
                if (uart_tx !== 1'b0) $fatal(1, "UART start bit invalid");
                for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                    #(BIT_NS);
                    value[bit_number] = uart_tx;
                end
                #(BIT_NS);
                if (uart_tx !== 1'b1) $fatal(1, "UART stop bit invalid");
                $write("%c", value);
                $fwrite(uart_log, "%c", value);
                if (value == 8'h0a) begin
                    if (line == "READY") ready_count = ready_count + 1;
                    if (line == "SEND") send_count = send_count + 1;
                    if (line == "SMOKE PASS") smoke_count = smoke_count + 1;
                    if (line.len() >= 5 && line.substr(0, 4) == "ERROR")
                        $fatal(1, "Firmware error: %s", line);
                    if (line.len() >= 6 && line.substr(0, 5) == "RESULT") begin
                        fields = $sscanf(line, "RESULT %d STATUS %h CYCLES %h READS %h",
                                         classification, status_value, cycle_value, read_value);
                        if (fields != 4 || result_count >= 16)
                            $fatal(1, "Malformed firmware result: %s", line);
                        result_class[result_count] = classification;
                        result_status[result_count] = status_value;
                        result_cycles[result_count] = cycle_value;
                        result_reads[result_count] = read_value;
                        result_count = result_count + 1;
                    end
                    line = "";
                end else if (value != 8'h0d) begin
                    line = {line, value};
                end
            end
        end
    end

    always @(posedge clk) begin
        if (resetn) begin
            if (cpu_trap === 1'b1)
                $fatal(1, "PicoRV32 trapped at address %08x", dut.mem_addr);
            if (dut.cnn_dma_arvalid && dut.cnn_dma_arready)
                dma_read_count = dma_read_count + 1;
            if (dut.u_cnn.cnn_result_valid) begin
                cnn_done_count = cnn_done_count + 1;
                if (expected_image >= 0) check_pixels(expected_image);
                if (pingpong_image_check) expected_image = 0;
            end
        end
    end

    task send_byte(input [7:0] value);
        integer bit_number;
        begin
            @(negedge clk);
            uart_rx = 0;
            #(BIT_NS);
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                uart_rx = value[bit_number];
                #(BIT_NS);
            end
            uart_rx = 1;
            #(BIT_NS);
            // The hardware has one RX holding register, so leave CPU service time.
            repeat (100) @(negedge clk);
        end
    endtask

    task upload_frame(input [7:0] command, input integer is_human);
        integer old_send_count;
        integer pixel_number;
        reg [23:0] pixel_value;
        begin
            old_send_count = send_count;
            send_byte(command);
            wait(send_count == old_send_count + 1);
            repeat (BIT_CLOCKS) @(posedge clk);
            for (pixel_number = 0; pixel_number < 1024; pixel_number = pixel_number + 1) begin
                pixel_value = is_human ? human_pixels[pixel_number] : nonhuman_pixels[pixel_number];
                send_byte(pixel_value[23:16]);
                send_byte(pixel_value[15:8]);
                send_byte(pixel_value[7:0]);
            end
        end
    endtask

    task check_result(input integer index, input integer expected_class,
                      input integer expected_dma, input integer expected_buffer,
                      input integer expected_pingpong);
        reg [31:0] expected_status;
        begin
            wait(result_count > index);
            expected_status = 2 | (expected_dma << 2) | (expected_buffer << 3) |
                              (expected_pingpong << 4);
            if (result_class[index] !== expected_class)
                $fatal(1, "Result %0d: class %0d expected %0d", index, result_class[index], expected_class);
            if ((result_status[index] & 32'h1f) !== expected_status)
                $fatal(1, "Result %0d: status %08x expected %08x", index, result_status[index], expected_status);
            if (result_cycles[index] == 0 || result_cycles[index] === 32'hxxxxxxxx)
                $fatal(1, "Result %0d: cycle counter invalid", index);
            if (result_reads[index] !== (expected_dma ? 768 : 0))
                $fatal(1, "Result %0d: DMA read counter invalid (%0d)", index, result_reads[index]);
        end
    endtask

    task check_pixels(input integer is_human);
        integer pixel_number;
        reg [23:0] expected_pixel;
        begin
            for (pixel_number = 0; pixel_number < 1024; pixel_number = pixel_number + 1) begin
                expected_pixel = is_human ? human_pixels[pixel_number] : nonhuman_pixels[pixel_number];
                if (dut.u_cnn.u_cnn_reference.image[pixel_number] !== expected_pixel)
                    $fatal(1, "Pixel %0d mismatch after firmware upload", pixel_number);
            end
        end
    endtask

    initial begin : test_sequence
        integer first_result;
        repeat (20) @(negedge clk);
        resetn = 1;
        wait(ready_count == 1);
        send_byte("z");
        wait(smoke_count == 1);
        if (cnn_done_count != 3 || dma_read_count != 1536)
            $fatal(1, "Smoke did not execute baseline + DMA0 + DMA1 (%0d runs, %0d reads)",
                   cnn_done_count, dma_read_count);

        if ($test$plusargs("FULL_IMAGES")) begin
            $readmemh("D:/SoC/custom_SOC-main/custom_SOC-main/CNN_RTL/human_frames.mem", human_pixels);
            $readmemh("D:/SoC/custom_SOC-main/custom_SOC-main/CNN_RTL/nonhuman_frame.mem", nonhuman_pixels);
            first_result = result_count;
            expected_image = 1;
            upload_frame("B", 1);
            check_result(first_result, 1, 0, 0, 0);
            upload_frame("0", 1);
            check_result(first_result + 1, 1, 1, 0, 0);
            expected_image = 0;
            upload_frame("1", 0);
            check_result(first_result + 2, 0, 1, 1, 0);
            expected_image = 1;
            pingpong_image_check = 1;
            send_byte("P");
            check_result(first_result + 3, 1, 1, 0, 1);
            check_result(first_result + 4, 0, 1, 1, 1);
            if (cnn_done_count != 8 || dma_read_count != 4608)
                $fatal(1, "Full run counts wrong (%0d runs, %0d reads)", cnn_done_count, dma_read_count);
        end
        $display("\nFIRMWARE INTEGRATION PASS");
        $fclose(uart_log);
        $finish;
    end

    initial begin
        #2000000000;
        $fatal(1, "Firmware timeout. CPU address=%08x, last UART line=%s", dut.mem_addr, line);
    end
endmodule
