`timescale 1ns/1ps
module tb_arm_cnn_firmware_boot;
    reg clk=0,resetn=0,uart_rx=1;
    reg boot_ready=0, recovered=0, saw_recovery_write=0, saw_cnn_reset=0;
    always #4 clk=~clk;
    soc_top #(.ENABLE_USB_HDMI(0),.BAUD_RATE(1000000)) dut(
        .clk(clk),.resetn(resetn),.uart_rx(uart_rx),.uart_tx(),
        .spi_miso(1'b0),.spi_sclk(),.spi_mosi(),.spi_cs(),
        .sda(),.scl_out(),.ddr_data_in(16'd0),.ddr_rx_valid(1'b0),
        .ddr_data(),.ddr_clk_out(),.ddr_valid(),.ddr_done()
    );
    string output_text="";
    reg saw_claim=0, saw_release=0, saw_owner_read=0;
    always @(posedge clk) if(resetn) begin
        if(boot_ready && !dut.cnn_recovery_resetn) saw_cnn_reset=1;
        if(dut.mem_valid && dut.mem_ready && dut.mem_wstrb!=0 &&
           dut.mem_addr==32'h40004f08 && dut.mem_wdata==1) saw_recovery_write=1;
        if(dut.u_cpu.trap) $fatal(1,"CPU trapped");
        if(dut.mem_valid && dut.mem_ready && dut.mem_addr==32'h40004f00) begin
            if(dut.mem_wstrb!=0 && dut.mem_wdata==1) saw_claim=1;
            if(dut.mem_wstrb!=0 && dut.mem_wdata==0) saw_release=1;
            if(dut.mem_wstrb==0 && dut.mem_rdata==1) saw_owner_read=1;
        end
        if(dut.mem_valid && dut.mem_ready && dut.mem_wstrb!=0 && dut.mem_addr==32'h40000000) begin
            if(dut.mem_wdata[7:0]!=13)
                output_text={output_text,string'(dut.mem_wdata[7:0])};
            if(dut.mem_wdata[7:0]==10) begin
                $display("FIRMWARE: %s",output_text);
                if(output_text=="BOOT FAIL\n") $fatal(1,"Firmware boot test failed");
                if(output_text=="RECOVERED; RELOAD FRAME\n") recovered=1;
                if(output_text=="READY\n") begin
                    if(!saw_claim || !saw_release || !saw_owner_read) $fatal(1,"Lock not exercised by CPU");
                    if(dut.u_arm_cnn_bridge.owner!=0) $fatal(1,"Firmware leaked lock");
                    if(!boot_ready) boot_ready=1;
                    else begin
                        if(!recovered || !saw_recovery_write || !saw_cnn_reset)
                            $fatal(1,"Firmware recovery command did not reset CNN");
                        $display("ARM_CNN_FIRMWARE_RECOVERY_PASS");
                        $display("ARM_CNN_FIRMWARE_BOOT_PASS");
                        $finish;
                    end
                end
                output_text="";
            end
        end
    end
    initial begin repeat(10) @(negedge clk); resetn=1; end
    initial begin : send_recovery_command
        reg [7:0] command;
        command="r";
        wait(boot_ready);
        #20000;
        uart_rx=0; #1000;
        for(integer bit_index=0;bit_index<8;bit_index=bit_index+1) begin
            uart_rx=command[bit_index]; #1000;
        end
        uart_rx=1; #1000;
    end
    initial begin #3000000; $fatal(1,"Firmware boot timeout"); end
endmodule
