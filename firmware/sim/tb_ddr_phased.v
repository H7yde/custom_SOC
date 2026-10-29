`timescale 1ns/1ps
module tb_ddr_phased;
    reg clk=0, rst_n=0, load=0;
    always #4 clk=~clk;
    reg [31:0] a=0,b=0,c=0,d=0;
    wire [15:0] data;
    wire forwarded,valid,done,ready;
    integer received=0, bursts=0;
    reg [31:0] expected [0:15];
    realtime last_change=0, last_main_rise=0;
    ddr_result_serializer #(.CLK_FREQ(125000000), .PHASED_CLOCK(1)) dut (
        .clk(clk),.rst_n(rst_n),.load(load),.data_rise_0(a),.data_fall_0(b),
        .data_rise_1(c),.data_fall_1(d),.ddr_data(data),.ddr_clk_out(forwarded),
        .ddr_valid(valid),.ddr_done(done),.ddr_ready(ready)
    );
    always @(data) last_change=$realtime;
    always @(posedge clk) last_main_rise=$realtime;
    always @(posedge forwarded or negedge forwarded) begin : receive_word
        reg [15:0] captured;
        reg [15:0] expected_half;
        if (rst_n && valid) begin
            if ($realtime-last_change < 2.5)
                $fatal(1,"DDR setup window too short: %0f ns",$realtime-last_change);
            captured=data;
            // Each pair of 32-bit rise/fall words is sent low halves first,
            // then high halves, over four cycles of the 16-bit DDR bus.
            if (received >= 32) $fatal(1,"Unexpected extra DDR halfword");
            if ((received % 4) < 2)
                expected_half = expected[(received / 4) * 2 + (received % 2)][15:0];
            else
                expected_half = expected[(received / 4) * 2 + (received % 2)][31:16];
            if (data !== expected_half)
                $fatal(1,"DDR halfword %0d got=%h expected=%h",received,data,expected_half);
            received=received+1;
            #1.1;
            if (rst_n && data !== captured) $fatal(1,"DDR hold window violated");
        end
    end
    always @(negedge forwarded) begin
        if (rst_n && (ready || valid) &&
            (($realtime-last_main_rise<2.58)||($realtime-last_main_rise>2.80)))
            // Include the UNISIM ODDR clock-to-Q propagation delay.
            $fatal(1,"Physical MMCM phase is not near 2.585714 ns: %0f",$realtime-last_main_rise);
    end
    task send_burst;
        input integer base;
        begin
            wait(ready===1'b1);
            @(negedge clk);
            a=expected[base];b=expected[base+1];c=expected[base+2];d=expected[base+3];load=1;
            @(negedge clk);load=0;
            wait(received==(base+4)*2);
            wait(done===1'b1);
            bursts=bursts+1;
        end
    endtask
    integer i;
    initial begin
        for(i=0;i<16;i=i+1) expected[i]=32'habcd0000^(32'h1234567*i);
        repeat(12) @(negedge clk);rst_n=1;
        send_burst(0);send_burst(4);
        @(negedge clk);rst_n=0;
        repeat(12) @(negedge clk);
        if(ready!==0 || valid!==0) $fatal(1,"DDR transmitter ready during reset");
        rst_n=1;
        send_burst(8);send_burst(12);
        $display("DDR PHASED CLOCK PASS bursts=%0d halfwords=%0d clock=125MHz phase=2.585714ns setup>=2.5ns hold>=1.1ns",bursts,received);
        $finish;
    end
    initial begin #1000000; $fatal(1,"DDR MMCM lock/transfer timeout"); end
endmodule
