`timescale 1ns/1ps

// Boot the real PicoRV32 from the SoC's normal firmware.hex BRAM image.
// Observe the CPU memory interface; this test never supplies CPU read data.
module tb_bram_firmware;
    parameter integer CLK_FREQ = 100000000;
    parameter integer DDR_TX_PHASED_CLOCK = 1;
    localparam real HALF_CLOCK_NS = 500000000.0 / CLK_FREQ;
    reg clk = 0;
    reg resetn = 0;
    wire uart_tx;
    wire cpu_trap;
    always #(HALF_CLOCK_NS) clk = ~clk;

    soc_top #(.CLK_FREQ(CLK_FREQ), .DDR_TX_PHASED_CLOCK(DDR_TX_PHASED_CLOCK)) dut (
        .clk(clk), .resetn(resetn),
        .uart_tx(uart_tx), .uart_rx(1'b1),
        .spi_sclk(), .spi_mosi(), .spi_miso(1'b0), .spi_cs(),
        .scl_out(), .sda_out(), .sda_oe(), .sda_in(1'b1),
        .ddr_data_in(32'b0), .ddr_rx_valid(1'b0),
        .ddr_data(), .ddr_clk_out(), .ddr_valid(), .ddr_done(),
        .cpu_trap(cpu_trap)
    );

    // Stable waveform aliases for the software report at byte address 0x800.
    wire [31:0] report_magic     = dut.bram[512];
    wire [31:0] report_status    = dut.bram[513];
    wire [31:0] report_errors    = dut.bram[514];
    wire [31:0] report_fail_addr = dut.bram[515];
    wire [31:0] report_expected  = dut.bram[516];
    wire [31:0] report_observed  = dut.bram[517];
    wire [31:0] report_phase     = dut.bram[518];
    wire [31:0] report_checks    = dut.bram[519];
    wire [31:0] report_heartbeat = dut.bram[520];
    wire        cpu_mem_valid   = dut.mem_valid;
    wire        cpu_mem_ready   = dut.mem_ready;
    wire        cpu_mem_instr   = dut.mem_instr;
    wire [31:0] cpu_mem_addr    = dut.mem_addr;
    wire [31:0] cpu_mem_wdata   = dut.mem_wdata;
    wire [31:0] cpu_mem_rdata   = dut.mem_rdata;
    wire [3:0]  cpu_mem_wstrb   = dut.mem_wstrb;

    // Full AXI4 bus aliases, including the attributes hidden by AXI4-Lite.
    wire [3:0]  bram_axi_awid = dut.bram_axi_awid;
    wire [31:0] bram_axi_awaddr = dut.bram_axi_awaddr;
    wire [7:0]  bram_axi_awlen = dut.bram_axi_awlen;
    wire [2:0]  bram_axi_awsize = dut.bram_axi_awsize;
    wire [1:0]  bram_axi_awburst = dut.bram_axi_awburst;
    wire bram_axi_awlock = dut.bram_axi_awlock;
    wire [3:0] bram_axi_awcache = dut.bram_axi_awcache;
    wire [2:0] bram_axi_awprot = dut.bram_axi_awprot;
    wire [3:0] bram_axi_awqos = dut.bram_axi_awqos;
    wire [3:0] bram_axi_awregion = dut.bram_axi_awregion;
    wire bram_axi_awuser = dut.bram_axi_awuser;
    wire bram_axi_awvalid = dut.bram_axi_awvalid;
    wire bram_axi_awready = dut.bram_axi_awready;
    wire [31:0] bram_axi_wdata = dut.bram_axi_wdata;
    wire [3:0] bram_axi_wstrb = dut.bram_axi_wstrb;
    wire bram_axi_wlast = dut.bram_axi_wlast;
    wire bram_axi_wuser = dut.bram_axi_wuser;
    wire bram_axi_wvalid = dut.bram_axi_wvalid;
    wire bram_axi_wready = dut.bram_axi_wready;
    wire [3:0] bram_axi_bid = dut.bram_axi_bid;
    wire [1:0] bram_axi_bresp = dut.bram_axi_bresp;
    wire bram_axi_buser = dut.bram_axi_buser;
    wire bram_axi_bvalid = dut.bram_axi_bvalid;
    wire bram_axi_bready = dut.bram_axi_bready;
    wire [3:0] bram_axi_arid = dut.bram_axi_arid;
    wire [31:0] bram_axi_araddr = dut.bram_axi_araddr;
    wire [7:0] bram_axi_arlen = dut.bram_axi_arlen;
    wire [2:0] bram_axi_arsize = dut.bram_axi_arsize;
    wire [1:0] bram_axi_arburst = dut.bram_axi_arburst;
    wire bram_axi_arlock = dut.bram_axi_arlock;
    wire [3:0] bram_axi_arcache = dut.bram_axi_arcache;
    wire [2:0] bram_axi_arprot = dut.bram_axi_arprot;
    wire [3:0] bram_axi_arqos = dut.bram_axi_arqos;
    wire [3:0] bram_axi_arregion = dut.bram_axi_arregion;
    wire bram_axi_aruser = dut.bram_axi_aruser;
    wire bram_axi_arvalid = dut.bram_axi_arvalid;
    wire bram_axi_arready = dut.bram_axi_arready;
    wire [3:0] bram_axi_rid = dut.bram_axi_rid;
    wire [31:0] bram_axi_rdata = dut.bram_axi_rdata;
    wire [1:0] bram_axi_rresp = dut.bram_axi_rresp;
    wire bram_axi_rlast = dut.bram_axi_rlast;
    wire bram_axi_ruser = dut.bram_axi_ruser;
    wire bram_axi_rvalid = dut.bram_axi_rvalid;
    wire bram_axi_rready = dut.bram_axi_rready;
    wire bram_axi_fault = dut.bram_axi_fault;

    wire [65:0] aw_payload = {bram_axi_awid, bram_axi_awaddr, bram_axi_awlen,
        bram_axi_awsize, bram_axi_awburst, bram_axi_awlock, bram_axi_awcache,
        bram_axi_awprot, bram_axi_awqos, bram_axi_awregion, bram_axi_awuser};
    wire [37:0] w_payload = {bram_axi_wdata, bram_axi_wstrb, bram_axi_wlast, bram_axi_wuser};
    wire [6:0] b_payload = {bram_axi_bid, bram_axi_bresp, bram_axi_buser};
    wire [65:0] ar_payload = {bram_axi_arid, bram_axi_araddr, bram_axi_arlen,
        bram_axi_arsize, bram_axi_arburst, bram_axi_arlock, bram_axi_arcache,
        bram_axi_arprot, bram_axi_arqos, bram_axi_arregion, bram_axi_aruser};
    wire [39:0] r_payload = {bram_axi_rid, bram_axi_rdata, bram_axi_rresp,
                           bram_axi_rlast, bram_axi_ruser};
    reg aw_stalled = 0, w_stalled = 0, b_stalled = 0, ar_stalled = 0, r_stalled = 0;
    reg [65:0] previous_aw, previous_ar;
    reg [37:0] previous_w;
    reg [6:0] previous_b;
    reg [39:0] previous_r;
    integer axi_aw_count = 0, axi_w_count = 0, axi_b_count = 0;
    integer axi_ar_count = 0, axi_r_count = 0;
    integer native_write_count = 0;

    reg [31:0] initial_image [0:1023];
    integer word_stores = 0;
    integer byte_stores = 0;
    integer halfword_stores = 0;
    integer instruction_reads = 0;
    integer data_reads = 0;

    always @(posedge clk) begin
        if (resetn) begin
            if (cpu_trap === 1'b1)
                $fatal(1, "CPU trapped at %08x", cpu_mem_addr);
            if (bram_axi_fault !== 1'b0)
                $fatal(1, "Native-to-AXI4 adapter reported a fault");
            if (uart_tx !== 1'b1)
                $fatal(1, "BRAM-only firmware transmitted UART data");
            if (cpu_mem_valid) begin
                if (cpu_mem_addr[31:28] == 4'h4)
                    $fatal(1, "BRAM-only firmware accessed peripheral %08x", cpu_mem_addr);
                if (cpu_mem_addr >= 32'h1000)
                    $fatal(1, "CPU accessed outside its 4 KiB BRAM: %08x", cpu_mem_addr);
            end
            if (cpu_mem_valid && cpu_mem_ready) begin
                if (cpu_mem_instr) instruction_reads = instruction_reads + 1;
                else if (cpu_mem_wstrb == 0) data_reads = data_reads + 1;
                else begin
                    native_write_count = native_write_count + 1;
                    if (cpu_mem_addr >= 32'h400 && cpu_mem_addr < 32'h800) begin
                        case (cpu_mem_wstrb)
                            4'b1111: word_stores = word_stores + 1;
                            4'b0001, 4'b0010, 4'b0100, 4'b1000:
                                byte_stores = byte_stores + 1;
                            4'b0011, 4'b1100: halfword_stores = halfword_stores + 1;
                            default: $fatal(1, "Unexpected BRAM write mask %b", cpu_mem_wstrb);
                        endcase
                    end
                end
            end
        end
    end

    always @(posedge clk) begin : check_axi_protocol
        if (!resetn) begin
            aw_stalled = 0; w_stalled = 0; b_stalled = 0;
            ar_stalled = 0; r_stalled = 0;
        end else begin
            if (aw_stalled && (!bram_axi_awvalid || aw_payload !== previous_aw))
                $fatal(1, "AXI4 AW changed while stalled");
            if (w_stalled && (!bram_axi_wvalid || w_payload !== previous_w))
                $fatal(1, "AXI4 W changed while stalled");
            if (b_stalled && (!bram_axi_bvalid || b_payload !== previous_b))
                $fatal(1, "AXI4 B changed while stalled");
            if (ar_stalled && (!bram_axi_arvalid || ar_payload !== previous_ar))
                $fatal(1, "AXI4 AR changed while stalled");
            if (r_stalled && (!bram_axi_rvalid || r_payload !== previous_r))
                $fatal(1, "AXI4 R changed while stalled");
            aw_stalled = bram_axi_awvalid && !bram_axi_awready;
            w_stalled = bram_axi_wvalid && !bram_axi_wready;
            b_stalled = bram_axi_bvalid && !bram_axi_bready;
            ar_stalled = bram_axi_arvalid && !bram_axi_arready;
            r_stalled = bram_axi_rvalid && !bram_axi_rready;
            previous_aw = aw_payload; previous_w = w_payload; previous_b = b_payload;
            previous_ar = ar_payload; previous_r = r_payload;

            if (bram_axi_awvalid && bram_axi_awready) begin
                axi_aw_count = axi_aw_count + 1;
                if (bram_axi_awid !== 0 || bram_axi_awlen !== 0 || bram_axi_awsize !== 2 ||
                    bram_axi_awburst !== 1 || bram_axi_awlock !== 0 || bram_axi_awcache !== 0 ||
                    bram_axi_awqos !== 0 || bram_axi_awregion !== 0 || bram_axi_awuser !== 0 ||
                    bram_axi_awprot !== {cpu_mem_instr, 2'b00})
                    $fatal(1, "CPU AXI4 AW attributes incorrect");
                if (!cpu_mem_valid || cpu_mem_wstrb == 0 ||
                    bram_axi_awaddr !== {cpu_mem_addr[31:2], 2'b00})
                    $fatal(1, "AXI4 AW does not match the native CPU request");
            end
            if (bram_axi_wvalid && bram_axi_wready) begin
                axi_w_count = axi_w_count + 1;
                if (bram_axi_wlast !== 1 || bram_axi_wuser !== 0 ||
                    bram_axi_wstrb !== cpu_mem_wstrb || bram_axi_wdata !== cpu_mem_wdata)
                    $fatal(1, "CPU AXI4 W data/mask/last incorrect");
            end
            if (bram_axi_bvalid && bram_axi_bready) begin
                axi_b_count = axi_b_count + 1;
                if (bram_axi_bid !== 0 || bram_axi_bresp !== 0 || bram_axi_buser !== 0)
                    $fatal(1, "CPU AXI4 B response incorrect");
            end
            if (bram_axi_arvalid && bram_axi_arready) begin
                axi_ar_count = axi_ar_count + 1;
                if (bram_axi_arid !== 0 || bram_axi_arlen !== 0 || bram_axi_arsize !== 2 ||
                    bram_axi_arburst !== 1 || bram_axi_arlock !== 0 || bram_axi_arcache !== 0 ||
                    bram_axi_arqos !== 0 || bram_axi_arregion !== 0 || bram_axi_aruser !== 0 ||
                    bram_axi_arprot !== {cpu_mem_instr, 2'b00})
                    $fatal(1, "CPU AXI4 AR attributes incorrect");
                if (!cpu_mem_valid || cpu_mem_wstrb != 0 ||
                    bram_axi_araddr !== {cpu_mem_addr[31:2], 2'b00})
                    $fatal(1, "AXI4 AR does not match the native CPU request");
            end
            if (bram_axi_rvalid && bram_axi_rready) begin
                axi_r_count = axi_r_count + 1;
                if (bram_axi_rid !== 0 || bram_axi_rresp !== 0 ||
                    bram_axi_rlast !== 1 || bram_axi_ruser !== 0)
                    $fatal(1, "CPU AXI4 R response incorrect");
            end
            if (axi_b_count > axi_aw_count || axi_b_count > axi_w_count ||
                axi_r_count > axi_ar_count || axi_aw_count - axi_b_count > 1 ||
                axi_w_count - axi_b_count > 1 || axi_ar_count - axi_r_count > 1)
                $fatal(1, "AXI4 single-outstanding transaction accounting failed");
        end
    end

    initial begin : boot_and_check
        integer word_index;
        reg [31:0] heartbeat_before;
        $readmemh("firmware.hex", initial_image);
        repeat (20) @(negedge clk);
        resetn = 1;
        wait(report_magic === 32'h4252414d);
        wait(report_status === 32'd1 || report_status === 32'd2);
        if (report_status !== 1 || report_errors !== 0)
            $fatal(1, "BRAM firmware FAIL phase=%0d errors=%0d addr=%08x expected=%08x observed=%08x",
                   report_phase, report_errors, report_fail_addr, report_expected, report_observed);
        if (report_phase !== 7 || report_checks !== 1792)
            $fatal(1, "Incomplete BRAM test: phase=%0d checks=%0d", report_phase, report_checks);
        for (word_index = 0; word_index < 256; word_index = word_index + 1) begin
            if (dut.bram[word_index] !== initial_image[word_index])
                $fatal(1, "Firmware overwrote program at %08x", word_index * 4);
            if (dut.bram[256 + word_index] !== 32'habcd1234)
                $fatal(1, "Final halfword pattern wrong at %08x", 32'h400 + word_index * 4);
        end
        if (byte_stores < 1024 || halfword_stores < 512 || word_stores < 1280 ||
            instruction_reads == 0 || data_reads < 1792)
            $fatal(1, "Missing real CPU/BRAM operations: words=%0d bytes=%0d halfwords=%0d reads=%0d",
                   word_stores, byte_stores, halfword_stores, data_reads);
        heartbeat_before = report_heartbeat;
        wait(report_heartbeat !== heartbeat_before && report_heartbeat !== 32'hxxxxxxxx);
        repeat (20) @(posedge clk);
        // Stop between requests so the five AXI channels and native completions
        // can be compared without counting a transaction still in flight.
        @(negedge clk);
        while (cpu_mem_valid || axi_aw_count != axi_b_count || axi_w_count != axi_b_count ||
               axi_ar_count != axi_r_count) @(negedge clk);
        if (axi_aw_count == 0 || axi_ar_count == 0 ||
            axi_b_count != native_write_count || axi_r_count != instruction_reads + data_reads)
            $fatal(1, "Native requests and AXI4 responses do not match");
        if (report_status !== 1 || report_errors !== 0)
            $fatal(1, "BRAM report changed after successful completion");
        $display("BRAM FIRMWARE PASS: phase=%0d checks=%0d errors=%0d heartbeat=%0d",
                 report_phase, report_checks, report_errors, report_heartbeat);
        $display("CPU stores in test area: word=%0d byte=%0d halfword=%0d; data reads=%0d",
                 word_stores, byte_stores, halfword_stores, data_reads);
        $display("AXI4 handshakes: AW=%0d W=%0d B=%0d AR=%0d R=%0d; fault=%b",
                 axi_aw_count, axi_w_count, axi_b_count, axi_ar_count, axi_r_count, bram_axi_fault);
        $display("No peripheral accesses; cpu_trap=0; program unchanged.");
        $finish;
    end

    initial begin
        #100000000;
        $fatal(1, "BRAM firmware timeout: addr=%08x phase=%0d checks=%0d status=%0d",
               cpu_mem_addr, report_phase, report_checks, report_status);
    end
endmodule
