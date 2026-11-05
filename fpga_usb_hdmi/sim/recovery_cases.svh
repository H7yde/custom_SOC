// Included inside tb_arm_cnn_bridge; exercises the real asynchronous CDC.
task automatic acknowledge_fault;
    reg [31:0] status;
    integer n;
    begin
        write_axi(1,32'h40004f08,1,1,2,0);
        n=0;
        do begin
            read_axi(1,32'h40004f08,status,0);
            n=n+1;
        end while(status!=0 && n<100);
        if(status!=0) $fatal(1,"Recovery did not complete");
        expect_reg(1,32'h40004f00,2);
        expect_reg(1,32'h40004fe4,768);
        expect_reg(1,32'h40004ff8,0);
    end
endtask

task automatic recovery_tests;
    reg [31:0] status;
    integer n;
    begin
        write_axi(1,32'h40004f00,1,1,2,0);
        // WSTRB=0 must have no effects, including START and counters.
        write_axi(1,32'h40004fe0,32'h11223344,15,0,0);
        write_axi(1,32'h40004fe0,32'haabbccdd,5,1,0);
        expect_reg(1,32'h40004fe0,32'h11bb33dd);
        write_axi(1,32'h40004fe0,0,0,2,0);
        expect_reg(1,32'h40004fe0,32'h11bb33dd);
        write_axi(1,32'h40004fe4,32'h00070300,4,2,0);
        write_axi(1,32'h40004fe4,32'h55,1,2,0);
        write_axi(1,32'h40004fe4,32'h100,2,2,0);
        expect_reg(1,32'h40004fe4,32'h00070155);
        write_axi(1,32'h40004fe4,0,0,2,0);
        expect_reg(1,32'h40004fe4,32'h00070155);
        write_axi(1,32'h40004ffc,1,0,2,0);
        write_axi(1,32'h40004ffc,1,2,2,0);
        if(busy) $fatal(1,"START ignored WSTRB");
        write_axi(1,32'h40004000,0,0,2,0);
        expect_reg(1,32'h40004ff0,0);
        // Another client cannot abort the owner's job.
        write_axi(0,32'h40004f08,1,1,2,2);
        // Stall each downstream channel; timeout completes with SLVERR.
        force ay=0;
        write_axi(1,32'h40004fe4,768,15,2,2);
        release ay;
        expect_reg(1,32'h40004f08,1);
        write_axi(1,32'h40004fe4,768,15,2,2);
        read_axi(1,32'h40004ff8,status,2);
        write_axi(1,32'h40004f08,1,0,2,0);
        expect_reg(1,32'h40004f08,1);
        acknowledge_fault();
        force wy=0;
        write_axi(1,32'h40004fe4,768,15,1,2);
        release wy;
        acknowledge_fault();
        force bv=0;
        write_axi(1,32'h40004fe4,768,15,0,2);
        release bv;
        acknowledge_fault();
        force ry=0;
        read_axi(1,32'h40004ff8,status,2);
        release ry;
        acknowledge_fault();
        force rrv=0;
        read_axi(1,32'h40004ff8,status,2);
        release rrv;
        acknowledge_fault();
        // DMA endpoint in this bench never answers: busy watchdog must abort.
        write_axi(1,32'h40004fe4,32'h10300,15,2,0);
        write_axi(1,32'h40004ffc,1,1,2,0);
        n=0;
        do begin
            read_axi(1,32'h40004f08,status,0); n=n+1;
        end while(status==0 && n<1000);
        if(!status[1]) $fatal(1,"Missing inference watchdog fault");
        repeat(12) @(negedge clk);
        if(busy) $fatal(1,"CNN remained busy after watchdog");
        acknowledge_fault();
        // Explicit abort is also permitted before the watchdog expires.
        write_axi(1,32'h40004fe4,32'h10300,15,2,0);
        write_axi(1,32'h40004ffc,1,1,2,0);
        acknowledge_fault();
        // Next job may acquire and write; no old response contaminates it.
        write_axi(1,32'h40004f00,0,1,2,0);
        write_axi(0,32'h40004f00,1,1,2,0);
        write_axi(0,32'h40004fe4,123,15,2,0);
        expect_reg(0,32'h40004fe4,123);
        $display("WSTRB_AND_WATCHDOG_PASS");
    end
endtask
