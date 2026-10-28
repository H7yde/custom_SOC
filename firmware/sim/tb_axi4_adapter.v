`timescale 1ns/1ps

// Drive the native side and an independently stalled AXI response model.
// This unit test deliberately separates AW/W handshakes, unlike a BRAM that
// accepts every address immediately. No CPU or memory implementation is used.
module tb_axi4_adapter;
    reg clk = 0;
    reg resetn = 0;
    always #10 clk = ~clk;

    reg mem_valid = 0, mem_instr = 0;
    reg [31:0] mem_addr = 0, mem_wdata = 0;
    reg [3:0] mem_wstrb = 0;
    wire mem_ready, fault;
    wire [31:0] mem_rdata;

    wire [3:0] M_AXI_AWID, M_AXI_AWCACHE, M_AXI_AWQOS, M_AXI_AWREGION;
    wire [31:0] M_AXI_AWADDR;
    wire [7:0] M_AXI_AWLEN;
    wire [2:0] M_AXI_AWSIZE, M_AXI_AWPROT;
    wire [1:0] M_AXI_AWBURST;
    wire M_AXI_AWLOCK, M_AXI_AWUSER, M_AXI_AWVALID;
    reg M_AXI_AWREADY = 0;
    wire [31:0] M_AXI_WDATA;
    wire [3:0] M_AXI_WSTRB;
    wire M_AXI_WLAST, M_AXI_WUSER, M_AXI_WVALID;
    reg M_AXI_WREADY = 0;
    reg [3:0] M_AXI_BID = 0;
    reg [1:0] M_AXI_BRESP = 0;
    reg M_AXI_BUSER = 0, M_AXI_BVALID = 0;
    wire M_AXI_BREADY;

    wire [3:0] M_AXI_ARID, M_AXI_ARCACHE, M_AXI_ARQOS, M_AXI_ARREGION;
    wire [31:0] M_AXI_ARADDR;
    wire [7:0] M_AXI_ARLEN;
    wire [2:0] M_AXI_ARSIZE, M_AXI_ARPROT;
    wire [1:0] M_AXI_ARBURST;
    wire M_AXI_ARLOCK, M_AXI_ARUSER, M_AXI_ARVALID;
    reg M_AXI_ARREADY = 0;
    reg [3:0] M_AXI_RID = 0;
    reg [31:0] M_AXI_RDATA = 0;
    reg [1:0] M_AXI_RRESP = 0;
    reg M_AXI_RLAST = 0, M_AXI_RUSER = 0, M_AXI_RVALID = 0;
    wire M_AXI_RREADY;

    picorv32_axi4_bram_adapter dut (.*);

    integer checks = 0;
    integer aw_count = 0, w_count = 0, b_count = 0;
    integer ar_count = 0, r_count = 0, native_count = 0;
    integer cases = 0;
    reg hold_aw = 0, hold_w = 0, hold_ar = 0;
    reg [65:0] saved_aw, saved_ar;
    reg [37:0] saved_w;
    wire [65:0] aw_payload = {M_AXI_AWID, M_AXI_AWADDR, M_AXI_AWLEN,
        M_AXI_AWSIZE, M_AXI_AWBURST, M_AXI_AWLOCK, M_AXI_AWCACHE,
        M_AXI_AWPROT, M_AXI_AWQOS, M_AXI_AWREGION, M_AXI_AWUSER};
    wire [65:0] ar_payload = {M_AXI_ARID, M_AXI_ARADDR, M_AXI_ARLEN,
        M_AXI_ARSIZE, M_AXI_ARBURST, M_AXI_ARLOCK, M_AXI_ARCACHE,
        M_AXI_ARPROT, M_AXI_ARQOS, M_AXI_ARREGION, M_AXI_ARUSER};
    wire [37:0] w_payload = {M_AXI_WDATA, M_AXI_WSTRB, M_AXI_WLAST, M_AXI_WUSER};

    task check(input condition, input string reason);
        begin
            checks = checks + 1;
            if (condition !== 1'b1) $fatal(1, "Adapter check failed: %s", reason);
        end
    endtask

    always @(posedge clk) begin
        if (!resetn) begin
            hold_aw = 0; hold_w = 0; hold_ar = 0;
        end else begin
            if (hold_aw) check(M_AXI_AWVALID && aw_payload === saved_aw,
                               "AW VALID/payload changed while stalled");
            if (hold_w) check(M_AXI_WVALID && w_payload === saved_w,
                              "W VALID/payload changed while stalled");
            if (hold_ar) check(M_AXI_ARVALID && ar_payload === saved_ar,
                               "AR VALID/payload changed while stalled");
            hold_aw = M_AXI_AWVALID && !M_AXI_AWREADY;
            hold_w = M_AXI_WVALID && !M_AXI_WREADY;
            hold_ar = M_AXI_ARVALID && !M_AXI_ARREADY;
            saved_aw = aw_payload; saved_w = w_payload; saved_ar = ar_payload;

            if (M_AXI_AWVALID && M_AXI_AWREADY) aw_count = aw_count + 1;
            if (M_AXI_WVALID && M_AXI_WREADY) w_count = w_count + 1;
            if (M_AXI_BVALID && M_AXI_BREADY) b_count = b_count + 1;
            if (M_AXI_ARVALID && M_AXI_ARREADY) ar_count = ar_count + 1;
            if (M_AXI_RVALID && M_AXI_RREADY) r_count = r_count + 1;
            if (mem_ready) begin
                native_count = native_count + 1;
                check(native_count <= b_count + r_count,
                      "Native acknowledged before an AXI response");
            end
            if (M_AXI_AWVALID) begin
                check(M_AXI_AWID == 0 && M_AXI_AWLEN == 0 && M_AXI_AWSIZE == 2 &&
                      M_AXI_AWBURST == 1, "AW single-beat metadata");
                check({M_AXI_AWLOCK, M_AXI_AWCACHE, M_AXI_AWQOS,
                       M_AXI_AWREGION, M_AXI_AWUSER} == 0, "AW optional metadata");
            end
            if (M_AXI_ARVALID) begin
                check(M_AXI_ARID == 0 && M_AXI_ARLEN == 0 && M_AXI_ARSIZE == 2 &&
                      M_AXI_ARBURST == 1, "AR single-beat metadata");
                check({M_AXI_ARLOCK, M_AXI_ARCACHE, M_AXI_ARQOS,
                       M_AXI_ARREGION, M_AXI_ARUSER} == 0, "AR optional metadata");
            end
        end
    end

    task reset_dut;
        begin
            @(negedge clk);
            resetn = 0;
            mem_valid = 0;
            M_AXI_AWREADY = 0; M_AXI_WREADY = 0; M_AXI_ARREADY = 0;
            M_AXI_BVALID = 0; M_AXI_RVALID = 0;
            #1;
            check(!M_AXI_AWVALID && !M_AXI_WVALID && !M_AXI_ARVALID &&
                  !M_AXI_BREADY && !M_AXI_RREADY && !mem_ready && !fault,
                  "Reset must immediately clear pending requests and fault");
            repeat (2) @(negedge clk);
            resetn = 1;
            repeat (2) @(negedge clk);
        end
    endtask

    task request_native(input [31:0] address, input [31:0] data,
                        input [3:0] strobes, input instruction);
        begin
            @(negedge clk);
            mem_addr = address; mem_wdata = data; mem_wstrb = strobes;
            mem_instr = instruction; mem_valid = 1;
            @(negedge clk);
            check(!mem_ready, "Request cannot acknowledge on capture");
        end
    endtask

    task hold_native_after_ack;
        begin
            // The response is a pulse; keeping native VALID high must not
            // launch a second transaction for the same request.
            repeat (5) begin
                @(negedge clk);
                check(!mem_ready && !M_AXI_AWVALID && !M_AXI_WVALID &&
                      !M_AXI_ARVALID && !M_AXI_BREADY && !M_AXI_RREADY,
                      "Duplicate request while native VALID remains high");
            end
            mem_valid = 0;
            @(negedge clk);
        end
    endtask

    task write_case(input data_first, input [1:0] response,
                    input [3:0] response_id, input expected_fault);
        integer old_aw, old_w, old_b;
        begin
            old_aw = aw_count; old_w = w_count; old_b = b_count;
            request_native(32'h00000404, 32'h78563412, 4'b0101, 0);
            check(M_AXI_AWVALID && M_AXI_WVALID && !M_AXI_ARVALID,
                  "Write must present AW and W independently");
            check(M_AXI_AWADDR == 32'h404 && M_AXI_AWPROT == 0 &&
                  M_AXI_WDATA == 32'h78563412 && M_AXI_WSTRB == 4'b0101 &&
                  M_AXI_WLAST && !M_AXI_WUSER, "Write payload forwarding");
            repeat (3) begin
                @(negedge clk);
                check(!mem_ready && !M_AXI_BREADY, "Write acknowledged during initial stall");
            end
            if (data_first) M_AXI_WREADY = 1;
            else M_AXI_AWREADY = 1;
            @(negedge clk);
            M_AXI_WREADY = 0; M_AXI_AWREADY = 0;
            check(data_first ? (!M_AXI_WVALID && M_AXI_AWVALID) :
                               (!M_AXI_AWVALID && M_AXI_WVALID),
                  "Only the accepted write channel may drop VALID");
            repeat (3) begin
                @(negedge clk);
                check(!mem_ready && !M_AXI_BREADY, "Write acknowledged before both channels");
            end
            if (data_first) M_AXI_AWREADY = 1;
            else M_AXI_WREADY = 1;
            @(negedge clk);
            M_AXI_WREADY = 0; M_AXI_AWREADY = 0;
            check(!M_AXI_AWVALID && !M_AXI_WVALID && M_AXI_BREADY,
                  "Write must wait for B after both channels complete");
            repeat (3) begin
                @(negedge clk);
                check(!mem_ready, "Write acknowledged before BVALID");
            end
            M_AXI_BID = response_id; M_AXI_BRESP = response; M_AXI_BVALID = 1;
            @(negedge clk);
            check(mem_ready && mem_rdata == 0 && fault == expected_fault,
                  "Write response/native completion or fault mismatch");
            M_AXI_BVALID = 0;
            hold_native_after_ack;
            check(aw_count == old_aw + 1 && w_count == old_w + 1 && b_count == old_b + 1,
                  "Duplicate or missing AW/W/B handshake");
            cases = cases + 1;
        end
    endtask

    task read_case(input instruction, input [1:0] response,
                   input [3:0] response_id, input last, input expected_fault);
        integer old_ar, old_r;
        reg [31:0] expected_data;
        begin
            old_ar = ar_count; old_r = r_count;
            expected_data = response != 0 || response_id != 0 || !last ? 0 : 32'hcafe12ef;
            request_native(32'h00000608, 0, 0, instruction);
            check(M_AXI_ARVALID && !M_AXI_AWVALID && !M_AXI_WVALID &&
                  M_AXI_ARADDR == 32'h608 && M_AXI_ARPROT == (instruction ? 4 : 0),
                  "Read address/instruction protection forwarding");
            repeat (4) begin
                @(negedge clk);
                check(!mem_ready && !M_AXI_RREADY, "Read acknowledged before AR handshake");
            end
            M_AXI_ARREADY = 1;
            @(negedge clk);
            M_AXI_ARREADY = 0;
            check(!M_AXI_ARVALID && M_AXI_RREADY, "Read must wait for R after AR completes");
            repeat (3) begin
                @(negedge clk);
                check(!mem_ready, "Read acknowledged before RVALID");
            end
            M_AXI_RID = response_id; M_AXI_RRESP = response;
            M_AXI_RDATA = 32'hcafe12ef; M_AXI_RLAST = last; M_AXI_RVALID = 1;
            @(negedge clk);
            check(mem_ready && mem_rdata == expected_data && fault == expected_fault,
                  "Read response/native completion or fault mismatch");
            M_AXI_RVALID = 0;
            hold_native_after_ack;
            check(ar_count == old_ar + 1 && r_count == old_r + 1,
                  "Duplicate or missing AR/R handshake");
            cases = cases + 1;
        end
    endtask

    initial begin
        reset_dut;
        write_case(0, 0, 0, 0); // AW first, delayed W.
        write_case(1, 0, 0, 0); // W first, delayed AW.
        read_case(0, 0, 0, 1, 0);
        read_case(1, 0, 0, 1, 0); // Instruction protection bit.
        write_case(0, 2, 0, 1); // BRESP error.
        write_case(1, 0, 0, 1); // Fault remains set through a successful transfer.
        reset_dut;
        write_case(0, 0, 3, 1); // Unexpected BID.
        reset_dut;
        read_case(0, 2, 0, 1, 1); // RRESP error returns safe zero data.
        reset_dut;
        read_case(0, 0, 5, 1, 1); // Unexpected RID.
        reset_dut;
        read_case(0, 0, 0, 0, 1); // Single-beat response missing RLAST.
        reset_dut;

        // Reset aborts a partially accepted write without native completion.
        request_native(32'h700, 32'h12345678, 4'hf, 0);
        M_AXI_WREADY = 1;
        @(negedge clk);
        M_AXI_WREADY = 0;
        check(M_AXI_AWVALID && !M_AXI_WVALID && !mem_ready, "Pending AW reset setup");
        reset_dut;
        read_case(0, 0, 0, 1, 0);

        // Reset also aborts an AR that the slave has not accepted.
        request_native(32'h704, 0, 0, 1);
        repeat (2) @(negedge clk);
        check(M_AXI_ARVALID && !mem_ready, "Pending AR reset setup");
        reset_dut;
        write_case(1, 0, 0, 0);

        check(cases == 12 && native_count == 12 && b_count == 6 && r_count == 6,
              "Unexpected total native/AXI completion counts");
        $display("AXI4 ADAPTER PASS: cases=%0d checks=%0d native=%0d writes=%0d reads=%0d",
                 cases, checks, native_count, b_count, r_count);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "Adapter unit test timeout");
    end
endmodule
