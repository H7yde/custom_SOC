module soc_top #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200,
    parameter ENABLE_MUL = 0,
    parameter ENABLE_DIV = 0,
    parameter ENABLE_IRQ = 1
)(
    input  wire        clk,
    input  wire        resetn,

    output wire        uart_tx,
    input  wire        uart_rx,

    output wire        spi_sclk,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire        spi_cs,

    output wire        scl_out,
    output wire        sda_out,
    output wire        sda_oe,
    input  wire        sda_in,

    // DDR result stream from the parallel accelerator
    output wire [31:0] ddr_data,
    output wire        ddr_clk_out,
    output wire        ddr_valid,
    output wire        ddr_done,

    output wire        cpu_trap
);

    wire        mem_valid, mem_instr, mem_ready;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [ 3:0] mem_wstrb;

    // --------------------------------------------------------
    // PicoRV32 CPU
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
        .clk      (clk),
        .resetn   (resetn),
        .trap     (cpu_trap),
        .mem_valid(mem_valid),
        .mem_instr(mem_instr),
        .mem_ready(mem_ready),
        .mem_addr (mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata),
        .mem_la_read (), .mem_la_write(), .mem_la_addr(),
        .pcpi_valid(), .pcpi_insn(), .pcpi_rs1(), .pcpi_rs2(),
        .pcpi_wr(1'b0), .pcpi_rd(32'h0),
        .pcpi_wait(1'b0), .pcpi_ready(1'b0),
        .irq(32'h0), .eoi(),
        .trace_valid(), .trace_data()
    );

    // --------------------------------------------------------
    // Master APB bus wires
    // --------------------------------------------------------
    wire [31:0] apb_paddr,  apb_pwdata, apb_prdata;
    wire        apb_pwrite, apb_psel,   apb_penable;
    wire        apb_pready;

    // BRAM interface
    wire        bram_en;
    wire [31:0] bram_addr, bram_rdata;

    picorv32_apb_bridge u_bridge (
        .clk        (clk),
        .resetn     (resetn),
        .mem_valid  (mem_valid),
        .mem_instr  (mem_instr),
        .mem_ready  (mem_ready),
        .mem_addr   (mem_addr),
        .mem_wdata  (mem_wdata),
        .mem_wstrb  (mem_wstrb),
        .mem_rdata  (mem_rdata),
        .PADDR      (apb_paddr),
        .PWRITE     (apb_pwrite),
        .PSEL       (apb_psel),
        .PENABLE    (apb_penable),
        .PWDATA     (apb_pwdata),
        .PRDATA     (apb_prdata),  
        .PREADY     (apb_pready), 
        .PSLVERR    (1'b0),
        .bram_en    (bram_en),
        .bram_addr  (bram_addr),
        .bram_rdata (bram_rdata)
    );

    // --------------------------------------------------------
    // BRAM 4KB
    // --------------------------------------------------------
    reg [31:0] bram [0:1023];
    initial $readmemh("firmware.hex", bram);

    reg [31:0] bram_rdata_reg;
    always @(posedge clk) begin
        if (bram_en)
            bram_rdata_reg <= bram[bram_addr[11:2]];

        if (mem_valid && !mem_instr && (mem_addr[31:12] == 20'h0)) begin
            if (mem_wstrb[0]) bram[mem_addr[11:2]][ 7: 0] <= mem_wdata[ 7: 0];
            if (mem_wstrb[1]) bram[mem_addr[11:2]][15: 8] <= mem_wdata[15: 8];
            if (mem_wstrb[2]) bram[mem_addr[11:2]][23:16] <= mem_wdata[23:16];
            if (mem_wstrb[3]) bram[mem_addr[11:2]][31:24] <= mem_wdata[31:24];
        end
    end
    assign bram_rdata = bram_rdata_reg;

    wire [31:0] prdata_periph, prdata_parallel;
    wire        pready_periph, pready_parallel;
    wire        pslverr_parallel;
    wire [31:0] parallel_result_out;
    wire        parallel_result_valid;

    wire psel_parallel = apb_psel && (apb_paddr[31:12] == 20'h40003);
    wire psel_periph   = apb_psel && !psel_parallel;

    assign apb_prdata = psel_parallel ? prdata_parallel : prdata_periph;
    assign apb_pready = psel_parallel ? pready_parallel : pready_periph;

    // --------------------------------------------------------
    // APB Decoder + UART/SPI/I2C
    // --------------------------------------------------------
    soc_apb_top #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_apb (
        .clk     (clk),
        .rst_n   (resetn),
        .PADDR   (apb_paddr),
        .PWRITE  (apb_pwrite),
        .PENABLE (apb_penable),
        .PWDATA  (apb_pwdata),
        .PRDATA  (prdata_periph),
        .PREADY  (pready_periph),
        .PSLVERR (),

        .uart_tx (uart_tx),
        .uart_rx (uart_rx),

        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .spi_cs  (spi_cs),

        .scl_out (scl_out),
        .sda_out (sda_out),
        .sda_oe  (sda_oe),
        .sda_in  (sda_in)
    );

     parallel u_parallel (
        .clk        (clk),
        .rst_n      (resetn),
      
        .PADDR      (apb_paddr),
        .PWRITE     (apb_pwrite),
        .PSEL       (psel_parallel),
        .PENABLE    (apb_penable),
        .PWDATA     (apb_pwdata),
        .PRDATA     (prdata_parallel),
        .PREADY     (pready_parallel),
        
        .PSLVERR    (pslverr_parallel),
        .result_out   (parallel_result_out),
        .result_valid (parallel_result_valid),
        .ddr_data     (ddr_data),
        .ddr_clk_out  (ddr_clk_out),
        .ddr_valid    (ddr_valid),
        .ddr_done     (ddr_done)
    );

endmodule
