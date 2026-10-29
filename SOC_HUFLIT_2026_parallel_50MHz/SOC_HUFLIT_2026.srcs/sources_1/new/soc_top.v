`timescale 1ns / 1ps

module soc_top #(
    // The PYNQ-Z2 H16 reference drives the SoC directly at 125 MHz.
    parameter CLK_FREQ  = 125_000_000,
    parameter BAUD_RATE = 115200,
    parameter ENABLE_MUL = 0,
    parameter ENABLE_DIV = 0,
    parameter ENABLE_IRQ = 1,
    parameter DDR_TX_PHASED_CLOCK = 1
)(
    input  wire        clk,
    input  wire        resetn,

    // --- Physical Pins ---
    output wire        uart_tx,
    input  wire        uart_rx,

    output wire        spi_sclk,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire        spi_cs,

    output wire        scl_out,
    inout  wire        sda,

    // --- IDDR / ODDR Stream Pins ---
    input  wire [15:0] ddr_data_in,
    input  wire        ddr_rx_valid,
    output wire [15:0] ddr_data,
    output wire        ddr_clk_out,
    output wire        ddr_valid,
    output wire        ddr_done

);

    wire sda_out_int, sda_oe_int, sda_in_int;
    IOBUF u_i2c_sda_iobuf (
        .I(sda_out_int), .T(~sda_oe_int), .O(sda_in_int), .IO(sda)
    );

    wire core_clk;
    BUFG u_core_clock_bufg (.I(clk), .O(core_clk));

    (* ASYNC_REG = "TRUE" *) reg [1:0] core_reset_release = 2'b00;

    // Assert reset asynchronously; release it after two core clock edges.
    always @(posedge core_clk or negedge resetn) begin
        if (!resetn) core_reset_release <= 2'b00;
        else core_reset_release <= {core_reset_release[0], 1'b1};
    end
    wire core_resetn = resetn && core_reset_release[1];

    wire        mem_valid, mem_instr;
    wire        mem_ready;
    wire [31:0] mem_rdata;
    wire [31:0] mem_addr, mem_wdata;
    wire [ 3:0] mem_wstrb;

    // --------------------------------------------------------
    // PicoRV32 CPU (Sá»­ dá»¥ng Native Memory Interface Ä‘á»ƒ náº¡p lá»‡nh siÃªu tá»‘c)
    // --------------------------------------------------------
    picorv32 #(
        .ENABLE_COUNTERS  (1),
        .ENABLE_REGS_16_31(1),
        .ENABLE_MUL       (ENABLE_MUL),
        .ENABLE_DIV       (ENABLE_DIV),
        .ENABLE_IRQ       (ENABLE_IRQ),
        .ENABLE_IRQ_TIMER (1),
        .PROGADDR_RESET   (32'h0000_0000),
        .STACKADDR        (32'h0000_0FF0)
    ) u_cpu (
        .clk      (core_clk),
        .resetn   (core_resetn),
        .trap     (),
        .mem_valid(mem_valid),
        .mem_instr(mem_instr),
        .mem_ready(mem_ready),
        .mem_addr (mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata),
        .mem_la_read (), .mem_la_write(), .mem_la_addr(), .mem_la_wdata(), .mem_la_wstrb(),
        .pcpi_valid(), .pcpi_insn(), .pcpi_rs1(), .pcpi_rs2(),
        .pcpi_wr(1'b0), .pcpi_rd(32'h0),
        .pcpi_wait(1'b0), .pcpi_ready(1'b0),
        .irq(32'h0), .eoi(),
        .trace_valid(), .trace_data()
    );

    // --------------------------------------------------------
    // Ráº½ nhÃ¡nh Bá»™ nhá»›: BRAM (Native) vs MMIO Ngoáº¡i vi (AXI)
    // --------------------------------------------------------
    wire is_bram = (mem_addr[31:28] == 4'h0); // 0x0000_0000 -> BRAM
    wire is_mmio = (mem_addr[31:28] == 4'h4); // 0x4000_0000 -> Ngoáº¡i vi

    wire        bram_ready;
    wire [31:0] bram_rdata;
    wire        mmio_ready;
    wire [31:0] mmio_rdata;

    // CPU nháº­n káº¿t quáº£ tá»« BRAM hoáº·c tá»« khá»‘i AXI MMIO
    assign mem_ready = is_bram ? bram_ready : (is_mmio ? mmio_ready : 1'b0);
    wire [31:0] mem_rdata_wire = is_bram ? bram_rdata : (is_mmio ? mmio_rdata : 32'h0);
    assign mem_rdata = mem_rdata_wire;

    // ========================================================
    // BRAM 4KB, accessed through a five-channel AXI4 controller.
    // ========================================================
    reg [31:0] bram [0:1023];
    // Vivado stages the registered initialization file into its run directory;
    // simulation runners can select the CPU image in their own run directory.
    initial $readmemh("firmware.hex", bram);

    // AXI4 BRAM channel: all five channels and metadata are visible here.
    wire [3:0]   bram_axi_awid;
    wire [31:0]  bram_axi_awaddr;
    wire [7:0]   bram_axi_awlen;
    wire [2:0]   bram_axi_awsize;
    wire [1:0]   bram_axi_awburst;
    wire         bram_axi_awlock;
    wire [3:0]   bram_axi_awcache;
    wire [2:0]   bram_axi_awprot;
    wire [3:0]   bram_axi_awqos;
    wire [3:0]   bram_axi_awregion;
    wire         bram_axi_awuser;
    wire         bram_axi_awvalid;
    wire         bram_axi_awready;
    wire [31:0]  bram_axi_wdata;
    wire [3:0]   bram_axi_wstrb;
    wire         bram_axi_wlast;
    wire         bram_axi_wuser;
    wire         bram_axi_wvalid;
    wire         bram_axi_wready;
    wire [3:0]   bram_axi_bid;
    wire [1:0]   bram_axi_bresp;
    wire         bram_axi_buser;
    wire         bram_axi_bvalid;
    wire         bram_axi_bready;
    wire [3:0]   bram_axi_arid;
    wire [31:0]  bram_axi_araddr;
    wire [7:0]   bram_axi_arlen;
    wire [2:0]   bram_axi_arsize;
    wire [1:0]   bram_axi_arburst;
    wire         bram_axi_arlock;
    wire [3:0]   bram_axi_arcache;
    wire [2:0]   bram_axi_arprot;
    wire [3:0]   bram_axi_arqos;
    wire [3:0]   bram_axi_arregion;
    wire         bram_axi_aruser;
    wire         bram_axi_arvalid;
    wire         bram_axi_arready;
    wire [3:0]   bram_axi_rid;
    wire [31:0]  bram_axi_rdata;
    wire [1:0]   bram_axi_rresp;
    wire         bram_axi_rlast;
    wire         bram_axi_ruser;
    wire         bram_axi_rvalid;
    wire         bram_axi_rready;
    wire bram_axi_fault;
    wire bram_mem_wr_en, bram_mem_rd_en;
    wire [9:0] bram_mem_wr_index, bram_mem_rd_index;
    wire [31:0] bram_mem_wr_data;
    wire [3:0] bram_mem_wr_strb;
    reg [31:0] bram_mem_rd_data;

    picorv32_axi4_bram_adapter u_bram_axi_adapter (
        .clk(core_clk), .resetn(core_resetn),
        .mem_valid(mem_valid && is_bram), .mem_instr(mem_instr),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_ready(bram_ready), .mem_rdata(bram_rdata), .fault(bram_axi_fault),
        .M_AXI_AWID(bram_axi_awid),
        .M_AXI_AWADDR(bram_axi_awaddr),
        .M_AXI_AWLEN(bram_axi_awlen),
        .M_AXI_AWSIZE(bram_axi_awsize),
        .M_AXI_AWBURST(bram_axi_awburst),
        .M_AXI_AWLOCK(bram_axi_awlock),
        .M_AXI_AWCACHE(bram_axi_awcache),
        .M_AXI_AWPROT(bram_axi_awprot),
        .M_AXI_AWQOS(bram_axi_awqos),
        .M_AXI_AWREGION(bram_axi_awregion),
        .M_AXI_AWUSER(bram_axi_awuser),
        .M_AXI_AWVALID(bram_axi_awvalid),
        .M_AXI_AWREADY(bram_axi_awready),
        .M_AXI_WDATA(bram_axi_wdata),
        .M_AXI_WSTRB(bram_axi_wstrb),
        .M_AXI_WLAST(bram_axi_wlast),
        .M_AXI_WUSER(bram_axi_wuser),
        .M_AXI_WVALID(bram_axi_wvalid),
        .M_AXI_WREADY(bram_axi_wready),
        .M_AXI_BID(bram_axi_bid),
        .M_AXI_BRESP(bram_axi_bresp),
        .M_AXI_BUSER(bram_axi_buser),
        .M_AXI_BVALID(bram_axi_bvalid),
        .M_AXI_BREADY(bram_axi_bready),
        .M_AXI_ARID(bram_axi_arid),
        .M_AXI_ARADDR(bram_axi_araddr),
        .M_AXI_ARLEN(bram_axi_arlen),
        .M_AXI_ARSIZE(bram_axi_arsize),
        .M_AXI_ARBURST(bram_axi_arburst),
        .M_AXI_ARLOCK(bram_axi_arlock),
        .M_AXI_ARCACHE(bram_axi_arcache),
        .M_AXI_ARPROT(bram_axi_arprot),
        .M_AXI_ARQOS(bram_axi_arqos),
        .M_AXI_ARREGION(bram_axi_arregion),
        .M_AXI_ARUSER(bram_axi_aruser),
        .M_AXI_ARVALID(bram_axi_arvalid),
        .M_AXI_ARREADY(bram_axi_arready),
        .M_AXI_RID(bram_axi_rid),
        .M_AXI_RDATA(bram_axi_rdata),
        .M_AXI_RRESP(bram_axi_rresp),
        .M_AXI_RLAST(bram_axi_rlast),
        .M_AXI_RUSER(bram_axi_ruser),
        .M_AXI_RVALID(bram_axi_rvalid),
        .M_AXI_RREADY(bram_axi_rready)
    );

    axi4_bram_slave u_bram_axi (
        .ACLK(core_clk), .ARESETn(core_resetn),
        .S_AXI_AWID(bram_axi_awid),
        .S_AXI_AWADDR(bram_axi_awaddr),
        .S_AXI_AWLEN(bram_axi_awlen),
        .S_AXI_AWSIZE(bram_axi_awsize),
        .S_AXI_AWBURST(bram_axi_awburst),
        .S_AXI_AWLOCK(bram_axi_awlock),
        .S_AXI_AWCACHE(bram_axi_awcache),
        .S_AXI_AWPROT(bram_axi_awprot),
        .S_AXI_AWQOS(bram_axi_awqos),
        .S_AXI_AWREGION(bram_axi_awregion),
        .S_AXI_AWUSER(bram_axi_awuser),
        .S_AXI_AWVALID(bram_axi_awvalid),
        .S_AXI_AWREADY(bram_axi_awready),
        .S_AXI_WDATA(bram_axi_wdata),
        .S_AXI_WSTRB(bram_axi_wstrb),
        .S_AXI_WLAST(bram_axi_wlast),
        .S_AXI_WUSER(bram_axi_wuser),
        .S_AXI_WVALID(bram_axi_wvalid),
        .S_AXI_WREADY(bram_axi_wready),
        .S_AXI_BID(bram_axi_bid),
        .S_AXI_BRESP(bram_axi_bresp),
        .S_AXI_BUSER(bram_axi_buser),
        .S_AXI_BVALID(bram_axi_bvalid),
        .S_AXI_BREADY(bram_axi_bready),
        .S_AXI_ARID(bram_axi_arid),
        .S_AXI_ARADDR(bram_axi_araddr),
        .S_AXI_ARLEN(bram_axi_arlen),
        .S_AXI_ARSIZE(bram_axi_arsize),
        .S_AXI_ARBURST(bram_axi_arburst),
        .S_AXI_ARLOCK(bram_axi_arlock),
        .S_AXI_ARCACHE(bram_axi_arcache),
        .S_AXI_ARPROT(bram_axi_arprot),
        .S_AXI_ARQOS(bram_axi_arqos),
        .S_AXI_ARREGION(bram_axi_arregion),
        .S_AXI_ARUSER(bram_axi_aruser),
        .S_AXI_ARVALID(bram_axi_arvalid),
        .S_AXI_ARREADY(bram_axi_arready),
        .S_AXI_RID(bram_axi_rid),
        .S_AXI_RDATA(bram_axi_rdata),
        .S_AXI_RRESP(bram_axi_rresp),
        .S_AXI_RLAST(bram_axi_rlast),
        .S_AXI_RUSER(bram_axi_ruser),
        .S_AXI_RVALID(bram_axi_rvalid),
        .S_AXI_RREADY(bram_axi_rready),
        .mem_wr_en(bram_mem_wr_en), .mem_wr_index(bram_mem_wr_index),
        .mem_wr_data(bram_mem_wr_data), .mem_wr_strb(bram_mem_wr_strb),
        .mem_rd_en(bram_mem_rd_en), .mem_rd_index(bram_mem_rd_index),
        .mem_rd_data(bram_mem_rd_data)
    );

    // Synchronous read-first BRAM backend. The AXI controller validates
    // addresses before asserting enables; the original bram hierarchy is kept.
    always @(posedge core_clk) begin
        if (core_resetn) begin
            if (bram_mem_rd_en)
                bram_mem_rd_data <= bram[bram_mem_rd_index];
            if (bram_mem_wr_en) begin
                if (bram_mem_wr_strb[0]) bram[bram_mem_wr_index][ 7: 0] <= bram_mem_wr_data[ 7: 0];
                if (bram_mem_wr_strb[1]) bram[bram_mem_wr_index][15: 8] <= bram_mem_wr_data[15: 8];
                if (bram_mem_wr_strb[2]) bram[bram_mem_wr_index][23:16] <= bram_mem_wr_data[23:16];
                if (bram_mem_wr_strb[3]) bram[bram_mem_wr_index][31:24] <= bram_mem_wr_data[31:24];
            end
        end
    end


    // ========================================================
    // Bá»˜ CHUYá»‚N Äá»”I (NATIVE to AXI4-LITE MASTER)
    // ========================================================
    wire        axi_m_awvalid, axi_m_awready;
    wire [31:0] axi_m_awaddr;
    wire [ 2:0] axi_m_awprot;
    wire        axi_m_wvalid, axi_m_wready;
    wire [31:0] axi_m_wdata;
    wire [ 3:0] axi_m_wstrb;
    wire        axi_m_bvalid, axi_m_bready;
    wire        axi_m_arvalid, axi_m_arready;
    wire [31:0] axi_m_araddr;
    wire [ 2:0] axi_m_arprot;
    wire        axi_m_rvalid, axi_m_rready;
    wire [31:0] axi_m_rdata;

    picorv32_axi_adapter u_axi_adapter (
        .clk            (core_clk),
        .resetn         (core_resetn),
        // AXI4-Lite Master Output
        .mem_axi_awvalid(axi_m_awvalid), .mem_axi_awready(axi_m_awready), .mem_axi_awaddr (axi_m_awaddr), .mem_axi_awprot(axi_m_awprot),
        .mem_axi_wvalid (axi_m_wvalid),  .mem_axi_wready (axi_m_wready),  .mem_axi_wdata  (axi_m_wdata),  .mem_axi_wstrb (axi_m_wstrb),
        .mem_axi_bvalid (axi_m_bvalid),  .mem_axi_bready (axi_m_bready),
        .mem_axi_arvalid(axi_m_arvalid), .mem_axi_arready(axi_m_arready), .mem_axi_araddr (axi_m_araddr), .mem_axi_arprot(axi_m_arprot),
        .mem_axi_rvalid (axi_m_rvalid),  .mem_axi_rready (axi_m_rready),  .mem_axi_rdata  (axi_m_rdata),
        // Native Input (Chá»‰ kÃ­ch hoáº¡t khi lÃ  MMIO)
        .mem_valid      (mem_valid && is_mmio),
        .mem_instr      (mem_instr),
        .mem_ready      (mmio_ready),
        .mem_addr       (mem_addr),
        .mem_wdata      (mem_wdata),
        .mem_wstrb      (mem_wstrb),
        .mem_rdata      (mmio_rdata)
    );

    // ========================================================
    // 1-to-2 AXI CROSSBAR (Bá»™ Ä‘á»‹nh tuyáº¿n AXI)
    // ========================================================
    wire aw_sel_parallel = (axi_m_awaddr[31:12] == 20'h40003);
    wire aw_sel_cnn      = (axi_m_awaddr[31:12] == 20'h40004);
    // 8-KB CNN memory window: 0x40006000 .. 0x40007FFF.
    wire aw_sel_cnn_mem  = (axi_m_awaddr[31:13] == 19'h20003);
    wire aw_sel_periph   = (axi_m_awaddr[31:12] >= 20'h40000 && axi_m_awaddr[31:12] <= 20'h40002);
    wire ar_sel_parallel = (axi_m_araddr[31:12] == 20'h40003);
    wire ar_sel_cnn      = (axi_m_araddr[31:12] == 20'h40004);
    wire ar_sel_cnn_mem  = (axi_m_araddr[31:13] == 19'h20003);
    wire ar_sel_periph   = (axi_m_araddr[31:12] >= 20'h40000 && axi_m_araddr[31:12] <= 20'h40002);

    // Chá»‘t má»¥c tiÃªu Ghi (Write Latch) - Sá»­a Ä‘iá»u kiá»‡n báº» khÃ³a Deadlock
    reg [3:0] w_target; // [3]: CNN memory, [2]: CNN, [1]: parallel, [0]: periph
    always @(posedge core_clk) begin
        if (!core_resetn) w_target <= 4'b0000;
        else if (axi_m_awvalid && !axi_m_bvalid)
            w_target <= {aw_sel_cnn_mem, aw_sel_cnn, aw_sel_parallel, aw_sel_periph};
        else if (axi_m_bvalid && axi_m_bready) w_target <= 4'b0000;
    end
    wire [3:0] act_w_target = (w_target != 4'b0000) ? w_target :
                              (axi_m_awvalid ? {aw_sel_cnn_mem, aw_sel_cnn, aw_sel_parallel, aw_sel_periph} : 4'b0000);

    // Chá»‘t má»¥c tiÃªu Äá»c (Read Latch) - Sá»­a Ä‘iá»u kiá»‡n báº» khÃ³a Deadlock
    reg [3:0] r_target;
    always @(posedge core_clk) begin
        if (!core_resetn) r_target <= 4'b0000;
        else if (axi_m_arvalid && !axi_m_rvalid)
            r_target <= {ar_sel_cnn_mem, ar_sel_cnn, ar_sel_parallel, ar_sel_periph};
        else if (axi_m_rvalid && axi_m_rready) r_target <= 4'b0000;
    end
    wire [3:0] act_r_target = (r_target != 4'b0000) ? r_target :
                              (axi_m_arvalid ? {ar_sel_cnn_mem, ar_sel_cnn, ar_sel_parallel, ar_sel_periph} : 4'b0000);

    // TÃ­n hiá»‡u AXI cho NhÃ³m Periph (UART, SPI, I2C)
    wire axi_periph_awready, axi_periph_wready, axi_periph_bvalid, axi_periph_arready, axi_periph_rvalid;
    wire [1:0] axi_periph_bresp, axi_periph_rresp;
    wire [31:0] axi_periph_rdata;

    // TÃ­n hiá»‡u AXI cho Khá»‘i Parallel DDR
    wire axi_parallel_awready, axi_parallel_wready, axi_parallel_bvalid, axi_parallel_arready, axi_parallel_rvalid;
    wire [1:0] axi_parallel_bresp, axi_parallel_rresp;
    wire [31:0] axi_parallel_rdata;

    wire axi_cnn_awready, axi_cnn_wready, axi_cnn_bvalid, axi_cnn_arready, axi_cnn_rvalid;
    wire [1:0] axi_cnn_bresp, axi_cnn_rresp;
    wire [31:0] axi_cnn_rdata;

    // CNN memory subsystem AXI-Lite slave responses.
    wire axi_cnn_mem_awready, axi_cnn_mem_wready, axi_cnn_mem_bvalid;
    wire axi_cnn_mem_arready, axi_cnn_mem_rvalid;
    wire [1:0] axi_cnn_mem_bresp, axi_cnn_mem_rresp;
    wire [31:0] axi_cnn_mem_rdata;

    // CNN read-only AXI master channel.
    wire [31:0] cnn_dma_araddr;
    wire        cnn_dma_arvalid;
    wire        cnn_dma_arready;
    wire [31:0] cnn_dma_rdata;
    wire        cnn_dma_rvalid;
    wire        cnn_dma_rready;

    // --- GhÃ©p kÃªnh tráº£ vá» CPU (Mux) ---
    assign axi_m_awready = (act_w_target[3] & axi_cnn_mem_awready) |
                           (act_w_target[2] & axi_cnn_awready) |
                           (act_w_target[1] & axi_parallel_awready) |
                           (act_w_target[0] & axi_periph_awready);
    assign axi_m_wready  = (act_w_target[3] & axi_cnn_mem_wready) |
                           (act_w_target[2] & axi_cnn_wready) |
                           (act_w_target[1] & axi_parallel_wready) |
                           (act_w_target[0] & axi_periph_wready);
    // All attached slaves register BVALID/RVALID. Their response can therefore
    // use the target captured when the address was presented. Keep the live
    // address bypass on request READY only; using it on response VALID creates
    // a long combinational path from the CPU address back into CPU mem_ready.
    assign axi_m_bvalid  = (w_target[3] & axi_cnn_mem_bvalid) |
                           (w_target[2] & axi_cnn_bvalid) |
                           (w_target[1] & axi_parallel_bvalid) |
                           (w_target[0] & axi_periph_bvalid);
    assign axi_m_bresp   = act_w_target[3] ? axi_cnn_mem_bresp :
                           act_w_target[2] ? axi_cnn_bresp :
                           act_w_target[1] ? axi_parallel_bresp :
                           axi_periph_bresp;

    assign axi_m_arready = (act_r_target[3] & axi_cnn_mem_arready) |
                           (act_r_target[2] & axi_cnn_arready) |
                           (act_r_target[1] & axi_parallel_arready) |
                           (act_r_target[0] & axi_periph_arready);
    assign axi_m_rvalid  = (r_target[3] & axi_cnn_mem_rvalid) |
                           (r_target[2] & axi_cnn_rvalid) |
                           (r_target[1] & axi_parallel_rvalid) |
                           (r_target[0] & axi_periph_rvalid);
    assign axi_m_rdata   = r_target[3] ? axi_cnn_mem_rdata :
                           r_target[2] ? axi_cnn_rdata :
                           r_target[1] ? axi_parallel_rdata :
                           axi_periph_rdata;
    assign axi_m_rresp   = r_target[3] ? axi_cnn_mem_rresp :
                           r_target[2] ? axi_cnn_rresp :
                           r_target[1] ? axi_parallel_rresp :
                           axi_periph_rresp;

    // ========================================================
    // TÃCH Há»¢P NGOáº I VI (AXI SLAVES)
    // ========================================================
    
    // 1. Cá»¥m thiáº¿t bá»‹ ngoáº¡i vi chuáº©n (UART, SPI, I2C)
    soc_axi_top #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_axi_periph (
        .clk             (core_clk),
        .rst_n           (core_resetn),
        
        .S_AXI_AWADDR    (axi_m_awaddr),
        .S_AXI_AWVALID   (axi_m_awvalid & act_w_target[0]),
        .S_AXI_AWREADY   (axi_periph_awready),
        .S_AXI_WDATA     (axi_m_wdata),
        .S_AXI_WSTRB     (axi_m_wstrb),
        .S_AXI_WVALID    (axi_m_wvalid & act_w_target[0]),
        .S_AXI_WREADY    (axi_periph_wready),
        .S_AXI_BRESP     (axi_periph_bresp),
        .S_AXI_BVALID    (axi_periph_bvalid),
        .S_AXI_BREADY    (axi_m_bready & act_w_target[0]),
        
        .S_AXI_ARADDR    (axi_m_araddr),
        .S_AXI_ARVALID   (axi_m_arvalid & act_r_target[0]),
        .S_AXI_ARREADY   (axi_periph_arready),
        .S_AXI_RDATA     (axi_periph_rdata),
        .S_AXI_RRESP     (axi_periph_rresp),
        .S_AXI_RVALID    (axi_periph_rvalid),
        .S_AXI_RREADY    (axi_m_rready & act_r_target[0]),
        
        .uart_tx         (uart_tx),
        .uart_rx         (uart_rx),
        .spi_sclk        (spi_sclk),
        .spi_mosi        (spi_mosi),
        .spi_miso        (spi_miso),
        .spi_cs          (spi_cs),
        .scl_out         (scl_out),
        .sda_out         (sda_out_int),
        .sda_oe          (sda_oe_int),
        .sda_in          (sda_in_int)
    );

    // 2. Bá»™ TÄƒng tá»‘c Song song DDR (IDDR & ODDR)
    parallel_axi #(.CLK_FREQ(CLK_FREQ), .DDR_TX_PHASED_CLOCK(DDR_TX_PHASED_CLOCK)) u_parallel_axi (
        .clk             (core_clk),
        .rst_n           (core_resetn),
        
        .S_AXI_AWADDR    (axi_m_awaddr),
        .S_AXI_AWVALID   (axi_m_awvalid & act_w_target[1]),
        .S_AXI_AWREADY   (axi_parallel_awready),
        .S_AXI_WDATA     (axi_m_wdata),
        .S_AXI_WSTRB     (axi_m_wstrb),
        .S_AXI_WVALID    (axi_m_wvalid & act_w_target[1]),
        .S_AXI_WREADY    (axi_parallel_wready),
        .S_AXI_BRESP     (axi_parallel_bresp),
        .S_AXI_BVALID    (axi_parallel_bvalid),
        .S_AXI_BREADY    (axi_m_bready & act_w_target[1]),
        
        .S_AXI_ARADDR    (axi_m_araddr),
        .S_AXI_ARVALID   (axi_m_arvalid & act_r_target[1]),
        .S_AXI_ARREADY   (axi_parallel_arready),
        .S_AXI_RDATA     (axi_parallel_rdata),
        .S_AXI_RRESP     (axi_parallel_rresp),
        .S_AXI_RVALID    (axi_parallel_rvalid),
        .S_AXI_RREADY    (axi_m_rready & act_r_target[1]),
        
        .ddr_data_in     (ddr_data_in),
        .ddr_rx_valid    (ddr_rx_valid),
        .result_out      (),
        .result_valid    (),
        .ddr_data        (ddr_data),
        .ddr_clk_out     (ddr_clk_out),
        .ddr_valid       (ddr_valid),
        .ddr_done        (ddr_done)
    );

    // 3. CNN AXI peripheral at base address 0x40004000.
    CNN u_cnn (
        .clk             (core_clk),
        .rst_n           (core_resetn),

        .S_AXI_AWADDR    (axi_m_awaddr),
        .S_AXI_AWVALID   (axi_m_awvalid & act_w_target[2]),
        .S_AXI_AWREADY   (axi_cnn_awready),
        .S_AXI_WDATA     (axi_m_wdata),
        .S_AXI_WSTRB     (axi_m_wstrb),
        .S_AXI_WVALID    (axi_m_wvalid & act_w_target[2]),
        .S_AXI_WREADY    (axi_cnn_wready),
        .S_AXI_BRESP     (axi_cnn_bresp),
        .S_AXI_BVALID    (axi_cnn_bvalid),
        .S_AXI_BREADY    (axi_m_bready & act_w_target[2]),

        .S_AXI_ARADDR    (axi_m_araddr),
        .S_AXI_ARVALID   (axi_m_arvalid & act_r_target[2]),
        .S_AXI_ARREADY   (axi_cnn_arready),
        .S_AXI_RDATA     (axi_cnn_rdata),
        .S_AXI_RRESP     (axi_cnn_rresp),
        .S_AXI_RVALID    (axi_cnn_rvalid),
        .S_AXI_RREADY    (axi_m_rready & act_r_target[2]),

        .M_AXI_ARADDR    (cnn_dma_araddr),
        .M_AXI_ARVALID   (cnn_dma_arvalid),
        .M_AXI_ARREADY   (cnn_dma_arready),
        .M_AXI_RDATA     (cnn_dma_rdata),
        .M_AXI_RVALID    (cnn_dma_rvalid),
        .M_AXI_RREADY    (cnn_dma_rready)
    );

    // 4. CNN memory subsystem.  This is an on-chip BRAM-style DDR
    // surrogate with two frame buffers.  It can later be replaced by a
    // vendor AXI DDR controller using the same AXI interfaces.
    cnn_memory_subsystem #(
        .BASE_ADDR    (32'h4000_6000),
        .BUFFER_WORDS(768),
        .TOTAL_WORDS (1536)
    ) u_cnn_memory (
        .clk             (core_clk),
        .rst_n           (core_resetn),

        .S_AXI_AWADDR    (axi_m_awaddr),
        .S_AXI_AWVALID   (axi_m_awvalid & act_w_target[3]),
        .S_AXI_AWREADY   (axi_cnn_mem_awready),
        .S_AXI_WDATA     (axi_m_wdata),
        .S_AXI_WSTRB     (axi_m_wstrb),
        .S_AXI_WVALID    (axi_m_wvalid & act_w_target[3]),
        .S_AXI_WREADY    (axi_cnn_mem_wready),
        .S_AXI_BRESP     (axi_cnn_mem_bresp),
        .S_AXI_BVALID    (axi_cnn_mem_bvalid),
        .S_AXI_BREADY    (axi_m_bready & act_w_target[3]),

        .S_AXI_ARADDR    (axi_m_araddr),
        .S_AXI_ARVALID   (axi_m_arvalid & act_r_target[3]),
        .S_AXI_ARREADY   (axi_cnn_mem_arready),
        .S_AXI_RDATA     (axi_cnn_mem_rdata),
        .S_AXI_RRESP     (axi_cnn_mem_rresp),
        .S_AXI_RVALID    (axi_cnn_mem_rvalid),
        .S_AXI_RREADY    (axi_m_rready & act_r_target[3]),

        .DMA_ARADDR     (cnn_dma_araddr),
        .DMA_ARVALID    (cnn_dma_arvalid),
        .DMA_ARREADY    (cnn_dma_arready),
        .DMA_RDATA      (cnn_dma_rdata),
        .DMA_RVALID     (cnn_dma_rvalid),
        .DMA_RREADY     (cnn_dma_rready)
    );

endmodule
