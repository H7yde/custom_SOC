`timescale 1ns / 1ps

// Independent AXI4 master fixture: the PicoRV32 adapter only generates single
// beats, so these tests exercise the BRAM slave's actual burst capabilities.
module tb_axi4_bram;
    reg ACLK = 0;
    always #10 ACLK = ~ACLK;
    reg ARESETn = 0;
    reg [3:0] S_AXI_AWID = 0;
    reg [31:0] S_AXI_AWADDR = 0;
    reg [7:0] S_AXI_AWLEN = 0;
    reg [2:0] S_AXI_AWSIZE = 2;
    reg [1:0] S_AXI_AWBURST = 1;
    reg S_AXI_AWLOCK = 0;
    reg [3:0] S_AXI_AWCACHE = 0;
    reg [2:0] S_AXI_AWPROT = 0;
    reg [3:0] S_AXI_AWQOS = 0;
    reg [3:0] S_AXI_AWREGION = 0;
    reg S_AXI_AWUSER = 0;
    reg S_AXI_AWVALID = 0;
    wire S_AXI_AWREADY;
    reg [31:0] S_AXI_WDATA = 0;
    reg [3:0] S_AXI_WSTRB = 0;
    reg S_AXI_WLAST = 0;
    reg S_AXI_WUSER = 0;
    reg S_AXI_WVALID = 0;
    wire S_AXI_WREADY;
    wire [3:0] S_AXI_BID;
    wire [1:0] S_AXI_BRESP;
    wire S_AXI_BUSER;
    wire S_AXI_BVALID;
    reg S_AXI_BREADY = 0;
    reg [3:0] S_AXI_ARID = 0;
    reg [31:0] S_AXI_ARADDR = 0;
    reg [7:0] S_AXI_ARLEN = 0;
    reg [2:0] S_AXI_ARSIZE = 2;
    reg [1:0] S_AXI_ARBURST = 1;
    reg S_AXI_ARLOCK = 0;
    reg [3:0] S_AXI_ARCACHE = 0;
    reg [2:0] S_AXI_ARPROT = 0;
    reg [3:0] S_AXI_ARQOS = 0;
    reg [3:0] S_AXI_ARREGION = 0;
    reg S_AXI_ARUSER = 0;
    reg S_AXI_ARVALID = 0;
    wire S_AXI_ARREADY;
    wire [3:0] S_AXI_RID;
    wire [31:0] S_AXI_RDATA;
    wire [1:0] S_AXI_RRESP;
    wire S_AXI_RLAST;
    wire S_AXI_RUSER;
    wire S_AXI_RVALID;
    reg S_AXI_RREADY = 0;
    wire mem_wr_en;
    wire [9:0] mem_wr_index;
    wire [31:0] mem_wr_data;
    wire [3:0] mem_wr_strb;
    wire mem_rd_en;
    wire [9:0] mem_rd_index;
    reg [31:0] mem_rd_data = 0;

    axi4_bram_slave dut (.*);

    reg [31:0] ram [0:1023];
    reg [31:0] expected [0:1023];
    integer checks = 0;
    integer backend_writes = 0;
    integer backend_reads = 0;
    integer clock_count = 0;
    integer lane;
    always @(posedge ACLK) begin
        clock_count = clock_count + 1;
        if (clock_count > 100000)
            $fatal(1, "AXI4 BRAM timeout: master/slave did not finish");
        // Same one-cycle synchronous read latency as the SoC's physical BRAM.
        if (mem_rd_en) begin
            mem_rd_data <= ram[mem_rd_index];
            backend_reads = backend_reads + 1;
        end
        if (mem_wr_en) begin
            for (lane = 0; lane < 4; lane = lane + 1)
                if (mem_wr_strb[lane])
                    ram[mem_wr_index][lane*8 +: 8] <= mem_wr_data[lane*8 +: 8];
            backend_writes = backend_writes + 1;
        end
        if (!ARESETn && (mem_rd_en || mem_wr_en))
            $fatal(1, "Backend request asserted during reset");
    end

    // These checks remain active during every task, including simultaneous
    // reads/writes. VALID and its complete payload must survive backpressure.
    reg stalled_b = 0;
    reg [6:0] saved_b;
    reg stalled_r = 0;
    reg [39:0] saved_r;
    always @(posedge ACLK) begin
        if (!ARESETn) begin
            stalled_b <= 0;
            stalled_r <= 0;
        end else begin
            if (stalled_b && (!S_AXI_BVALID ||
                {S_AXI_BID, S_AXI_BRESP, S_AXI_BUSER} !== saved_b))
                $fatal(1, "B response changed while BREADY=0");
            if (stalled_r && (!S_AXI_RVALID ||
                {S_AXI_RID, S_AXI_RDATA, S_AXI_RRESP, S_AXI_RLAST, S_AXI_RUSER} !== saved_r))
                $fatal(1, "R response changed while RREADY=0");
            stalled_b <= S_AXI_BVALID && !S_AXI_BREADY;
            saved_b <= {S_AXI_BID, S_AXI_BRESP, S_AXI_BUSER};
            stalled_r <= S_AXI_RVALID && !S_AXI_RREADY;
            saved_r <= {S_AXI_RID, S_AXI_RDATA, S_AXI_RRESP, S_AXI_RLAST, S_AXI_RUSER};
        end
    end

    task check(input condition, input string message);
        begin
            checks = checks + 1;
            if (condition !== 1'b1) $fatal(1, "%s", message);
        end
    endtask

    function [31:0] beat_address;
        input [31:0] start;
        input integer beat, len, size, burst;
        integer span;
        begin
            span = (len + 1) * (1 << size);
            case (burst)
                0: beat_address = start;
                2: beat_address = (start / span) * span +
                                  ((start % span + beat * (1 << size)) % span);
                default: beat_address = start + beat * (1 << size);
            endcase
        end
    endfunction

    function [31:0] pattern;
        input [31:0] seed;
        input integer beat;
        begin pattern = seed ^ (beat * 32'h01030507); end
    endfunction

    function [3:0] byte_mask;
        input [31:0] address;
        input integer size;
        begin byte_mask = ((1 << (1 << size)) - 1) << address[1:0]; end
    endfunction

    task model_write(input [31:0] address, input [31:0] data, input [3:0] strobe);
        integer b;
        begin
            for (b = 0; b < 4; b = b + 1)
                if (strobe[b]) expected[address >> 2][b*8 +: 8] = data[b*8 +: 8];
        end
    endtask

    task send_aw(input [31:0] address, input integer len, size, burst,
                 input [3:0] id, input locked);
        integer wait_cycles;
        begin
            @(negedge ACLK);
            S_AXI_AWADDR = address; S_AXI_AWLEN = len; S_AXI_AWSIZE = size;
            S_AXI_AWBURST = burst; S_AXI_AWID = id; S_AXI_AWLOCK = locked;
            S_AXI_AWCACHE = 4'h3; S_AXI_AWPROT = 3'h2;
            S_AXI_AWQOS = 4'h9; S_AXI_AWREGION = 4'h6; S_AXI_AWUSER = 1;
            S_AXI_AWVALID = 1;
            wait_cycles = 0;
            @(posedge ACLK);
            while (S_AXI_AWREADY !== 1'b1) begin
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > 100) $fatal(1, "AW handshake timeout");
                @(posedge ACLK);
            end
            @(negedge ACLK); S_AXI_AWVALID = 0;
        end
    endtask

    task send_w(input [31:0] data, input [3:0] strobe, input last);
        integer wait_cycles;
        begin
            @(negedge ACLK);
            S_AXI_WDATA = data; S_AXI_WSTRB = strobe;
            S_AXI_WLAST = last; S_AXI_WUSER = 1; S_AXI_WVALID = 1;
            wait_cycles = 0;
            @(posedge ACLK);
            while (S_AXI_WREADY !== 1'b1) begin
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > 100) $fatal(1, "W handshake timeout");
                @(posedge ACLK);
            end
            @(negedge ACLK); S_AXI_WVALID = 0;
        end
    endtask

    // wanted=4 means any error: AXI does not prescribe the response to a
    // master's illegal transaction (such as crossing a 4 KiB boundary).
    task check_response(input [1:0] actual, input integer wanted, input string channel);
        begin
            if (wanted == 4) check(actual === 2'b10 || actual === 2'b11,
                                   {channel, " must return an error"});
            else check(actual === wanted[1:0],
                       $sformatf("%s response %b, expected %b", channel, actual, wanted[1:0]));
        end
    endtask

    task receive_b(input [3:0] id, input integer wanted, hold_cycles);
        integer wait_cycles;
        begin
            wait_cycles = 0;
            @(posedge ACLK);
            while (S_AXI_BVALID !== 1'b1) begin
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > 100) $fatal(1, "B response timeout");
                @(posedge ACLK);
            end
            repeat (hold_cycles) @(posedge ACLK);
            @(negedge ACLK); S_AXI_BREADY = 1;
            @(posedge ACLK);
            check(S_AXI_BVALID, "BVALID disappeared before handshake");
            check(S_AXI_BID === id, "BID did not echo AWID");
            check_response(S_AXI_BRESP, wanted, "B");
            @(negedge ACLK); S_AXI_BREADY = 0;
        end
    endtask

    task send_ar(input [31:0] address, input integer len, size, burst,
                 input [3:0] id, input locked);
        integer wait_cycles;
        begin
            @(negedge ACLK);
            S_AXI_ARADDR = address; S_AXI_ARLEN = len; S_AXI_ARSIZE = size;
            S_AXI_ARBURST = burst; S_AXI_ARID = id; S_AXI_ARLOCK = locked;
            S_AXI_ARCACHE = 4'h3; S_AXI_ARPROT = 3'h2;
            S_AXI_ARQOS = 4'h5; S_AXI_ARREGION = 4'h7; S_AXI_ARUSER = 1;
            S_AXI_ARVALID = 1;
            wait_cycles = 0;
            @(posedge ACLK);
            while (S_AXI_ARREADY !== 1'b1) begin
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > 100) $fatal(1, "AR handshake timeout");
                @(posedge ACLK);
            end
            @(negedge ACLK); S_AXI_ARVALID = 0;
        end
    endtask

    task read_burst(input [31:0] address, input integer len, size, burst,
                    input [3:0] id, input integer wanted, input verify_data,
                    input integer stalls);
        integer beat, wait_cycles, b;
        reg [31:0] current_address;
        reg [3:0] mask;
        begin
            send_ar(address, len, size, burst, id, 0);
            for (beat = 0; beat <= len; beat = beat + 1) begin
                wait_cycles = 0;
                @(posedge ACLK);
                while (S_AXI_RVALID !== 1'b1) begin
                    wait_cycles = wait_cycles + 1;
                    if (wait_cycles > 100) $fatal(1, "R beat %0d timeout", beat);
                    @(posedge ACLK);
                end
                if ((beat % 3) == 0) repeat (stalls) @(posedge ACLK);
                @(negedge ACLK); S_AXI_RREADY = 1;
                @(posedge ACLK);
                check(S_AXI_RVALID, "RVALID disappeared before handshake");
                check(S_AXI_RID === id, "RID did not echo ARID");
                check(S_AXI_RLAST === (beat == len), "RLAST in wrong position");
                check_response(S_AXI_RRESP, wanted, "R");
                if (verify_data) begin
                    current_address = beat_address(address, beat, len, size, burst);
                    mask = byte_mask(current_address, size);
                    for (b = 0; b < 4; b = b + 1)
                        if (mask[b]) check(S_AXI_RDATA[b*8 +: 8] === expected[current_address >> 2][b*8 +: 8],
                            $sformatf("Data mismatch at 0x%08h, beat %0d byte %0d: got %08h expected %08h",
                                      current_address, beat, b, S_AXI_RDATA, expected[current_address >> 2]));
                end else if (wanted != 0) check(S_AXI_RDATA === 0, "Error RDATA must be zero");
                @(negedge ACLK); S_AXI_RREADY = 0;
            end
        end
    endtask

    task write_burst(input [31:0] address, input integer len, size, burst,
                     input [3:0] id, input [31:0] seed);
        integer beat;
        reg [31:0] current_address;
        begin
            send_aw(address, len, size, burst, id, 0);
            for (beat = 0; beat <= len; beat = beat + 1) begin
                current_address = beat_address(address, beat, len, size, burst);
                send_w(pattern(seed, beat), byte_mask(current_address, size), beat == len);
                model_write(current_address, pattern(seed, beat), byte_mask(current_address, size));
            end
            receive_b(id, 0, 4);
        end
    endtask

    task invalid_write(input [31:0] address, input integer len, size, burst,
                       input locked, input integer wanted);
        integer beat, before_writes;
        begin
            before_writes = backend_writes;
            send_aw(address, len, size, burst, 4'hE, locked);
            for (beat = 0; beat <= len; beat = beat + 1)
                send_w(32'hBAD0BAD0, 4'hF, beat == len);
            receive_b(4'hE, wanted, 2);
            check(backend_writes == before_writes, "Invalid AW transaction modified BRAM");
        end
    endtask

    task reset_bus;
        begin
            @(negedge ACLK);
            ARESETn = 0;
            S_AXI_AWVALID = 0; S_AXI_WVALID = 0; S_AXI_ARVALID = 0;
            S_AXI_BREADY = 0; S_AXI_RREADY = 0;
            // Assert halfway between active clock edges and observe immediately.
            // This also runs when a response is stalled with VALID already high.
            #1;
            check(!S_AXI_BVALID && !S_AXI_RVALID, "Asynchronous reset did not clear B/RVALID");
            check(!mem_wr_en && !mem_rd_en, "Reset did not immediately gate backend requests");
            repeat (3) @(posedge ACLK);
            @(negedge ACLK);
            check(!S_AXI_BVALID && !S_AXI_RVALID, "Reset did not clear pending responses");
            ARESETn = 1;
            repeat (2) @(posedge ACLK);
        end
    endtask

    integer i, previous_reads, previous_writes;
    initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            ram[i] = 32'hC0010000 ^ i;
            expected[i] = 32'hC0010000 ^ i;
        end
        reset_bus;

        $display("AXI4 TEST: independent AW/W, narrow transfers and byte strobes");
        // WVALID precedes AWVALID by six cycles. The master holds its payload
        // until WREADY even if the slave chooses to wait for the address.
        fork
            begin repeat (6) @(posedge ACLK); send_aw(32'h20, 0, 2, 1, 4'hA, 0); end
            begin send_w(32'h12345678, 4'hF, 1); end
        join
        model_write(32'h20, 32'h12345678, 4'hF);
        receive_b(4'hA, 0, 5);
        send_aw(32'h24, 0, 2, 1, 4'hB, 0);
        repeat (7) @(posedge ACLK);
        check(!S_AXI_BVALID, "BVALID before any write data");
        send_w(32'h87654321, 4'hF, 1);
        model_write(32'h24, 32'h87654321, 4'hF);
        receive_b(4'hB, 0, 3);
        for (i = 0; i < 4; i = i + 1) begin
            write_burst(32'h30 + i, 0, 0, 1, i, 32'h44332211 + i * 32'h01010101);
            read_burst(32'h30 + i, 0, 0, 1, 15-i, 0, 1, 3);
        end
        for (i = 0; i < 2; i = i + 1) begin
            write_burst(32'h34 + i*2, 0, 1, 1, 4'hC, 32'hA5C37E19);
            read_burst(32'h34 + i*2, 0, 1, 1, 4'hD, 0, 1, 2);
        end
        // Sparse and zero strobes are legal when within the transfer's lanes.
        send_aw(32'h38, 0, 2, 1, 1, 0);
        send_w(32'hDEADBEEF, 4'b0101, 1);
        model_write(32'h38, 32'hDEADBEEF, 4'b0101);
        receive_b(1, 0, 0);
        send_aw(32'h38, 0, 2, 1, 2, 0);
        send_w(0, 0, 1); receive_b(2, 0, 0);
        read_burst(32'h20, 7, 2, 1, 4'hF, 0, 1, 3);

        $display("AXI4 TEST: INCR 4/256 beats, narrow bursts, WRAP and FIXED");
        write_burst(32'h100, 3, 2, 1, 3, 32'hACE00000);
        read_burst(32'h100, 3, 2, 1, 4, 0, 1, 4);
        write_burst(32'h400, 255, 2, 1, 5, 32'h55880000);
        read_burst(32'h400, 255, 2, 1, 6, 0, 1, 2);
        write_burst(32'h150, 7, 0, 1, 7, 32'h89112233);
        read_burst(32'h150, 7, 0, 1, 8, 0, 1, 3);
        write_burst(32'h160, 7, 1, 1, 9, 32'hAABBCCDD);
        read_burst(32'h160, 7, 1, 1, 10, 0, 1, 2);
        // Address sequence: 18C,180,184,188 (wrap boundary is 16 bytes).
        write_burst(32'h18C, 3, 2, 2, 11, 32'h0F0E0D0C);
        read_burst(32'h18C, 3, 2, 2, 12, 0, 1, 4);
        write_burst(32'h1C0, 3, 2, 0, 13, 32'h51525354);
        read_burst(32'h1C0, 3, 2, 0, 14, 0, 1, 3);

        $display("AXI4 TEST: simultaneous independent read/write channels");
        fork
            write_burst(32'h200, 15, 2, 1, 2, 32'hABDCE000);
            read_burst(32'h400, 15, 2, 1, 9, 0, 1, 5);
        join
        read_burst(32'h200, 15, 2, 1, 7, 0, 1, 1);

        $display("AXI4 TEST: invalid transactions return errors without aliasing");
        invalid_write(32'h200, 2, 3, 1, 0, 2); // unsupported SIZE
        invalid_write(32'h200, 2, 2, 3, 0, 2); // reserved BURST
        invalid_write(32'h202, 0, 2, 1, 0, 2); // unaligned word
        invalid_write(32'h200, 0, 2, 1, 1, 2); // unsupported exclusive
        invalid_write(32'h1000, 0, 2, 1, 0, 3); // outside mapped BRAM
        invalid_write(32'hFFC, 1, 2, 1, 0, 4); // 4 KiB crossing
        invalid_write(32'h200, 2, 2, 2, 0, 2); // illegal WRAP length
        invalid_write(32'h200, 16, 2, 0, 0, 2); // FIXED max 16 beats
        previous_writes = backend_writes;
        send_aw(32'h221, 0, 0, 1, 5, 0);
        send_w(32'hDEADBEEF, 4'b0001, 1); // byte lane 0 outside byte at address+1
        receive_b(5, 2, 2);
        check(backend_writes == previous_writes, "Illegal WSTRB changed BRAM");
        previous_reads = backend_reads;
        read_burst(32'h1000, 3, 2, 1, 1, 3, 0, 2);
        read_burst(32'hFFC, 1, 2, 1, 2, 4, 0, 2);
        read_burst(32'h201, 0, 2, 1, 3, 2, 0, 2);
        read_burst(32'h200, 2, 3, 1, 4, 2, 0, 2);
        read_burst(32'h200, 2, 2, 3, 5, 2, 0, 2);
        check(backend_reads == previous_reads, "Invalid AR transaction accessed BRAM");
        // Whole read of original addresses proves failed writes did not alias.
        read_burst(32'h200, 15, 2, 1, 11, 0, 1, 2);
        read_burst(32'h0, 0, 2, 1, 12, 0, 1, 2);
        read_burst(32'hFFC, 0, 2, 1, 13, 0, 1, 2);

        $display("AXI4 TEST: malformed WLAST is drained and diagnosed");
        send_aw(32'h280, 3, 2, 1, 6, 0);
        for (i = 0; i < 4; i = i + 1) send_w(32'hABCD0000 + i, 4'hF, i == 0 || i == 3);
        receive_b(6, 2, 3);
        send_aw(32'h290, 0, 2, 1, 7, 0);
        send_w(32'h11223344, 4'hF, 0);
        receive_b(7, 2, 2);

        $display("AXI4 TEST: reset aborts pending R/B and incomplete writes");
        send_ar(32'h400, 3, 2, 1, 8, 0);
        repeat (8) @(posedge ACLK);
        check(S_AXI_RVALID, "Read response not presented for reset test");
        reset_bus;
        read_burst(32'h400, 3, 2, 1, 9, 0, 1, 2);
        send_aw(32'h300, 0, 2, 1, 10, 0);
        send_w(32'h88776655, 4'hF, 1);
        model_write(32'h300, 32'h88776655, 4'hF);
        repeat (4) @(posedge ACLK);
        check(S_AXI_BVALID, "Write response not presented for reset test");
        reset_bus;
        send_aw(32'h304, 3, 2, 1, 11, 0);
        send_w(32'hBBCCDDEE, 4'hF, 0);
        model_write(32'h304, 32'hBBCCDDEE, 4'hF);
        reset_bus;
        write_burst(32'h30C, 0, 2, 1, 12, 32'h0055AAFF);
        read_burst(32'h300, 3, 2, 1, 13, 0, 1, 2);

        $display("AXI4 BRAM PROTOCOL PASS: %0d checks, backend writes=%0d reads=%0d",
                 checks, backend_writes, backend_reads);
        $finish;
    end
endmodule
