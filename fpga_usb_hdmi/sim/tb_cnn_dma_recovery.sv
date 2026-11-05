`timescale 1ns/1ps
module tb_cnn_dma_recovery;
    reg clk=0, resetn=0, dma_resetn=0;
    always #4 clk=~clk;
    reg av=0,wv=0,cv=0,dv=0,cr=0,dr=0;
    wire ay,wy,bv,cy,dy,rv,drv;
    wire [31:0] rd,dd;
    wire [1:0] br,rr;
    cnn_memory_subsystem dut(
        .clk(clk),.rst_n(resetn),.dma_resetn(dma_resetn),
        .S_AXI_AWADDR(32'h40006000),.S_AXI_AWVALID(av),.S_AXI_AWREADY(ay),
        .S_AXI_WDATA(32'h12345678),.S_AXI_WSTRB(4'hf),.S_AXI_WVALID(wv),.S_AXI_WREADY(wy),
        .S_AXI_BRESP(br),.S_AXI_BVALID(bv),.S_AXI_BREADY(1'b1),
        .S_AXI_ARADDR(32'h40006000),.S_AXI_ARVALID(cv),.S_AXI_ARREADY(cy),
        .S_AXI_RDATA(rd),.S_AXI_RRESP(rr),.S_AXI_RVALID(rv),.S_AXI_RREADY(cr),
        .DMA_ARADDR(32'h40006000),.DMA_ARVALID(dv),.DMA_ARREADY(dy),
        .DMA_RDATA(dd),.DMA_RVALID(drv),.DMA_RREADY(dr)
    );
    initial begin
        repeat(4) @(negedge clk); resetn=1; dma_resetn=1;
        @(negedge clk); av=1;wv=1;
        @(posedge clk); if(!ay || !wy) $fatal(1,"Write not accepted");
        @(negedge clk); av=0;wv=0;
        wait(bv); repeat(2) @(negedge clk);
        // Both read addresses arrive together; DMA wins, CPU remains pending.
        cv=1;dv=1;
        @(posedge clk); if(!dy || cy) $fatal(1,"Read arbitration deadlock");
        @(negedge clk); dv=0;
        if(!drv || dd!==32'h12345678) $fatal(1,"DMA data");
        // Reset only the DMA response while CPU is still requesting.
        dma_resetn=0;
        @(negedge clk);
        if(drv) $fatal(1,"Stale DMA response survived reset");
        @(posedge clk); if(!cy) $fatal(1,"CPU blocked after DMA reset");
        @(negedge clk); cv=0;
        if(!rv || rd!==32'h12345678) $fatal(1,"CPU state/RAM lost");
        repeat(3) @(negedge clk);
        if(!rv) $fatal(1,"CPU response lost during DMA reset");
        cr=1;
        @(negedge clk); cr=0;dma_resetn=1;dv=1;
        @(posedge clk); if(!dy) $fatal(1,"DMA did not restart");
        @(negedge clk); dv=0;
        if(!drv || dd!==32'h12345678) $fatal(1,"Fresh DMA read failed");
        dr=1;
        @(negedge clk); dr=0;
        if(drv) $fatal(1,"Duplicate DMA response");
        $display("CNN_DMA_RECOVERY_PASS"); $finish;
    end
    initial begin #100000; $fatal(1,"Timeout"); end
endmodule
