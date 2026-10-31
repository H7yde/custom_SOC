`timescale 1ns/1ps
module tb_arm_cnn_bridge;
    reg clk=0, arm_clk=0, resetn=0;
    always #5 arm_clk=~arm_clk;
    always #4 clk=~clk;
    reg [1:0][31:0] awaddr=0, wdata=0, araddr=0;
    reg [1:0][3:0] wstrb=0;
    reg [1:0] awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
    wire [1:0] awready,wready,bvalid,arready,rvalid;
    wire [1:0][1:0] bresp,rresp;
    wire [1:0][31:0] rdata;
    wire [31:0] ca,cd,ra,rd;
    wire [3:0] cs;
    wire av,ay,wv,wy,bv,by,rv,ry,rrv,rry,busy;
    wire [1:0] br,rr;
    // Actual generated AMD asynchronous AXI converter: ARM 100 MHz, CNN 125 MHz.
    wire [1:0][31:0] cdc_awaddr;
    assign cdc_awaddr[0] = awaddr[0];
    wire [1:0] cdc_awvalid;
    assign cdc_awvalid[0] = awvalid[0];
    wire [1:0] cdc_awready;
    assign awready[0] = cdc_awready[0];
    wire [1:0][31:0] cdc_wdata;
    assign cdc_wdata[0] = wdata[0];
    wire [1:0][3:0] cdc_wstrb;
    assign cdc_wstrb[0] = wstrb[0];
    wire [1:0] cdc_wvalid;
    assign cdc_wvalid[0] = wvalid[0];
    wire [1:0] cdc_wready;
    assign wready[0] = cdc_wready[0];
    wire [1:0][1:0] cdc_bresp;
    assign bresp[0] = cdc_bresp[0];
    wire [1:0] cdc_bvalid;
    assign bvalid[0] = cdc_bvalid[0];
    wire [1:0] cdc_bready;
    assign cdc_bready[0] = bready[0];
    wire [1:0][31:0] cdc_araddr;
    assign cdc_araddr[0] = araddr[0];
    wire [1:0] cdc_arvalid;
    assign cdc_arvalid[0] = arvalid[0];
    wire [1:0] cdc_arready;
    assign arready[0] = cdc_arready[0];
    wire [1:0][31:0] cdc_rdata;
    assign rdata[0] = cdc_rdata[0];
    wire [1:0][1:0] cdc_rresp;
    assign rresp[0] = cdc_rresp[0];
    wire [1:0] cdc_rvalid;
    assign rvalid[0] = cdc_rvalid[0];
    wire [1:0] cdc_rready;
    assign cdc_rready[0] = rready[0];
    usb_hdmi_system_arm_cnn_cdc_0 actual_cdc(
        .s_axi_aclk(arm_clk),
        .s_axi_aresetn(resetn),
        .m_axi_aclk(clk),
        .m_axi_aresetn(resetn),
        .s_axi_awprot(3'b000),
        .s_axi_arprot(3'b000),
        .m_axi_awprot(),
        .m_axi_arprot(),
        .s_axi_awaddr(awaddr[1]),
        .m_axi_awaddr(cdc_awaddr[1]),
        .s_axi_awvalid(awvalid[1]),
        .m_axi_awvalid(cdc_awvalid[1]),
        .s_axi_awready(awready[1]),
        .m_axi_awready(cdc_awready[1]),
        .s_axi_wdata(wdata[1]),
        .m_axi_wdata(cdc_wdata[1]),
        .s_axi_wstrb(wstrb[1]),
        .m_axi_wstrb(cdc_wstrb[1]),
        .s_axi_wvalid(wvalid[1]),
        .m_axi_wvalid(cdc_wvalid[1]),
        .s_axi_wready(wready[1]),
        .m_axi_wready(cdc_wready[1]),
        .s_axi_bresp(bresp[1]),
        .m_axi_bresp(cdc_bresp[1]),
        .s_axi_bvalid(bvalid[1]),
        .m_axi_bvalid(cdc_bvalid[1]),
        .s_axi_bready(bready[1]),
        .m_axi_bready(cdc_bready[1]),
        .s_axi_araddr(araddr[1]),
        .m_axi_araddr(cdc_araddr[1]),
        .s_axi_arvalid(arvalid[1]),
        .m_axi_arvalid(cdc_arvalid[1]),
        .s_axi_arready(arready[1]),
        .m_axi_arready(cdc_arready[1]),
        .s_axi_rdata(rdata[1]),
        .m_axi_rdata(cdc_rdata[1]),
        .s_axi_rresp(rresp[1]),
        .m_axi_rresp(cdc_rresp[1]),
        .s_axi_rvalid(rvalid[1]),
        .m_axi_rvalid(cdc_rvalid[1]),
        .s_axi_rready(rready[1]),
        .m_axi_rready(cdc_rready[1])
    );
    cnn_axi_bridge dut(
        .clk(clk),.resetn(resetn),.cnn_busy(busy),
        .s_awaddr(cdc_awaddr),.s_awvalid(cdc_awvalid),.s_awready(cdc_awready),
        .s_wdata(cdc_wdata),.s_wstrb(cdc_wstrb),.s_wvalid(cdc_wvalid),.s_wready(cdc_wready),
        .s_bresp(cdc_bresp),.s_bvalid(cdc_bvalid),.s_bready(cdc_bready),
        .s_araddr(cdc_araddr),.s_arvalid(cdc_arvalid),.s_arready(cdc_arready),
        .s_rdata(cdc_rdata),.s_rresp(cdc_rresp),.s_rvalid(cdc_rvalid),.s_rready(cdc_rready),
        .m_awaddr(ca),.m_awvalid(av),.m_awready(ay),
        .m_wdata(cd),.m_wstrb(cs),.m_wvalid(wv),.m_wready(wy),
        .m_bresp(br),.m_bvalid(bv),.m_bready(by),
        .m_araddr(ra),.m_arvalid(rv),.m_arready(ry),
        .m_rdata(rd),.m_rresp(rr),.m_rvalid(rrv),.m_rready(rry)
    );
    CNN cnn(
        .clk(clk),.rst_n(resetn),.control_busy(busy),
        .S_AXI_AWADDR(ca),.S_AXI_AWVALID(av),.S_AXI_AWREADY(ay),
        .S_AXI_WDATA(cd),.S_AXI_WSTRB(cs),.S_AXI_WVALID(wv),.S_AXI_WREADY(wy),
        .S_AXI_BRESP(br),.S_AXI_BVALID(bv),.S_AXI_BREADY(by),
        .S_AXI_ARADDR(ra),.S_AXI_ARVALID(rv),.S_AXI_ARREADY(ry),
        .S_AXI_RDATA(rd),.S_AXI_RRESP(rr),.S_AXI_RVALID(rrv),.S_AXI_RREADY(rry),
        .M_AXI_ARADDR(),.M_AXI_ARVALID(),.M_AXI_ARREADY(1'b0),
        .M_AXI_RDATA(32'd0),.M_AXI_RVALID(1'b0),.M_AXI_RREADY()
    );
    task automatic tick(input integer p,input bit positive_edge);
        if(p==1) begin
            if(positive_edge) @(posedge arm_clk); else @(negedge arm_clk);
        end else begin
            if(positive_edge) @(posedge clk); else @(negedge clk);
        end
    endtask
    task automatic write_axi(input integer p,input [31:0] a,input [31:0] d,
                             input [3:0] st,input integer order,input [1:0] response);
        reg [1:0] held;
        begin
            // Exercise address-first, data-first and concurrent AW/W.
            fork
                begin
                    if(order==1) repeat(5) tick(p,0);
                    tick(p,0); awaddr[p]=a; awvalid[p]=1;
                    do tick(p,1); while(!awready[p]);
                    tick(p,0); awvalid[p]=0;
                end
                begin
                    if(order==0) repeat(5) tick(p,0);
                    tick(p,0); wdata[p]=d; wstrb[p]=st; wvalid[p]=1;
                    do tick(p,1); while(!wready[p]);
                    tick(p,0); wvalid[p]=0;
                end
            join
            wait(bvalid[p]); held=bresp[p];
            repeat(4) begin
                tick(p,0);
                if(!bvalid[p] || bresp[p]!==held) $fatal(1,"B backpressure p%0d",p);
            end
            if(held!==response) $fatal(1,"BRESP p%0d addr=%h got=%b expected=%b",p,a,held,response);
            bready[p]=1; tick(p,1); tick(p,0); bready[p]=0;
        end
    endtask
    task automatic read_axi(input integer p,input [31:0] a,output reg [31:0] d,
                            input [1:0] response);
        reg [31:0] held;
        reg [1:0] held_resp;
        begin
            tick(p,0); araddr[p]=a; arvalid[p]=1;
            do tick(p,1); while(!arready[p]);
            tick(p,0); arvalid[p]=0;
            wait(rvalid[p]); held=rdata[p]; held_resp=rresp[p];
            repeat(3) begin
                tick(p,0);
                if(!rvalid[p] || rdata[p]!==held || rresp[p]!==held_resp) $fatal(1,"R backpressure");
            end
            if(held_resp!==response) $fatal(1,"RRESP addr=%h",a);
            d=held; rready[p]=1; tick(p,1); tick(p,0); rready[p]=0;
        end
    endtask
    task automatic expect_reg(input integer p,input [31:0] a,input [31:0] wanted);
        reg [31:0] d;
        begin
            read_axi(p,a,d,0);
            if(d!==wanted) $fatal(1,"Read %h got %h expected %h",a,d,wanted);
        end
    endtask
    reg [31:0] images[0:1535];
    task automatic classify(input integer image_index,input integer expected);
        integer i,polls;
        reg [31:0] status;
        begin
            for(i=0;i<768;i=i+1)
                write_axi(1,32'h40004000+i*4,images[image_index*768+i],15,i%3,0);
            // Check both endpoints of the internal image RAM, including byte order.
            if(cnn.frame_mem[0]!==images[image_index*768] ||
               cnn.frame_mem[767]!==images[image_index*768+767]) $fatal(1,"Image write mismatch");
            write_axi(1,32'h40004fe4,768,15,2,0);
            write_axi(1,32'h40004ffc,1,15,2,0);
            // A running inference must retain ownership despite release/claim.
            write_axi(1,32'h40004f00,0,15,2,0);
            write_axi(0,32'h40004f00,1,15,2,0);
            expect_reg(0,32'h40004f00,32'h102);
            polls=0; status=0;
            while(status[1:0]!=2 && polls<100000) begin
                read_axi(1,32'h40004ff8,status,0); polls=polls+1;
            end
            if(status[1:0]!=2) $fatal(1,"CNN timeout");
            expect_reg(1,32'h40004ff4,expected);
            // Every raw RGB pixel must match, not only the binary result.
            for(i=0;i<1024;i=i+1) begin : pixels
                reg [23:0] pixel;
                integer b,j,idx,shift;
                pixel=0;
                for(j=0;j<3;j=j+1) begin
                    b=i*3+j; idx=image_index*768+b/4; shift=(3-b%4)*8;
                    pixel=(pixel<<8)|((images[idx]>>shift)&255);
                end
                if(cnn.u_cnn_reference.image[i]!==pixel) $fatal(1,"RGB mismatch pixel %0d",i);
            end
            $display("ARM_CNN_IMAGE_PASS image=%0d class=%0d",image_index,expected);
        end
    endtask
    reg [31:0] temp0,temp1;
    integer i;
    initial begin
        $readmemh("bridge_images.mem",images);
        repeat(8) @(negedge clk); resetn=1;
        expect_reg(0,32'h40004f04,32'h434e4e42);
        // Unlocked writes are denied; malformed addresses never reach CNN.
        write_axi(1,32'h40004fe4,123,15,0,2);
        read_axi(1,32'h40005000,temp0,2);
        write_axi(0,32'h40004fe5,123,15,1,2);
        // Simultaneous claim must produce exactly one winner.
        fork
            write_axi(0,32'h40004f00,1,15,2,0);
            write_axi(1,32'h40004f00,1,15,2,0);
        join
        read_axi(0,32'h40004f00,temp0,0);
        if(temp0!=1 && temp0!=2) $fatal(1,"Atomic lock claim failed");
        if(temp0==1) begin
            write_axi(1,32'h40004fe4,123,15,2,2);
            write_axi(1,32'h40004f00,0,15,2,0);
            expect_reg(0,32'h40004f00,1);
            write_axi(0,32'h40004f00,0,15,2,0);
        end else begin
            write_axi(0,32'h40004fe4,123,15,2,2);
            write_axi(0,32'h40004f00,0,15,2,0);
            expect_reg(1,32'h40004f00,2);
            write_axi(1,32'h40004f00,0,15,2,0);
        end
        expect_reg(1,32'h40004f00,0);
        write_axi(0,32'h40004f00,1,15,0,0);
        write_axi(0,32'h40004000,32'h11223344,15,0,0);
        write_axi(0,32'h40004000,32'haabbccdd,5,1,0);
        if(cnn.frame_mem[0]!==32'h11bb33dd) $fatal(1,"WSTRB");
        fork
            begin
                for(integer k=0;k<25;k=k+1) begin
                    write_axi(0,32'h40004fe4,768+k,15,k%3,0);
                    expect_reg(0,32'h40004fe4,768+k);
                end
            end
            begin
                for(integer k=0;k<50;k=k+1) expect_reg(1,32'h40004f04,32'h434e4e42);
            end
        join
        write_axi(0,32'h40004f00,0,15,1,0);
        write_axi(1,32'h40004f00,1,15,1,0);
        expect_reg(1,32'h40004f00,2);
        classify(0,1);
        classify(1,0);
        write_axi(1,32'h40004f00,0,15,2,0);
        expect_reg(0,32'h40004f00,0);
        // Reset discards an unmatched AW without leaving a stale write behind.
        @(negedge clk); awaddr[1]=32'h40004fe4; awvalid[1]=1;
        do tick(1,1); while(!awready[1]);
        @(negedge clk); awvalid[1]=0; resetn=0;
        repeat(5) @(negedge clk); resetn=1;
        expect_reg(0,32'h40004f00,0);
        write_axi(0,32'h40004f00,1,15,2,0);
        write_axi(0,32'h40004fe4,768,15,1,0);
        expect_reg(0,32'h40004fe4,768);
        $display("ARM_CNN_BRIDGE_TEST_PASS");
        $finish;
    end
    initial begin #200000000; $fatal(1,"Global timeout"); end
endmodule
