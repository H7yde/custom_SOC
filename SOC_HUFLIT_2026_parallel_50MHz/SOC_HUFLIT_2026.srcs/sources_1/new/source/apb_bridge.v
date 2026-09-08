// ============================================================
//  PicoRV32 Native Memory Interface → APB Master Bridge
//
//  PicoRV32 native:
//    mem_valid  : CPU muon truy cap
//    mem_instr  : 1=fetch lenh (bo qua, chi doc BRAM)
//    mem_ready  : tra loi cho CPU
//    mem_addr   : dia chi 32-bit
//    mem_wdata  : data ghi
//    mem_wstrb  : byte enable [3:0], =0000 la doc
//    mem_rdata  : data doc ve
//
//  APB master output:
//    PADDR / PWRITE / PSEL / PENABLE / PWDATA / PRDATA / PREADY
//
//  State machine: IDLE -> SETUP -> ENABLE -> (wait PREADY) -> IDLE
// ============================================================

module picorv32_apb_bridge (
    input  wire        clk,
    input  wire        resetn,

    // PicoRV32 native memory interface
    input  wire        mem_valid,
    input  wire        mem_instr,
    output reg         mem_ready,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,
    input  wire [ 3:0] mem_wstrb,
    output reg  [31:0] mem_rdata,

    // APB master interface (ket noi vao APB bus / decoder)
    output reg  [31:0] PADDR,
    output reg         PWRITE,
    output reg         PSEL,
    output reg         PENABLE,
    output reg  [31:0] PWDATA,
    input  wire [31:0] PRDATA,
    input  wire        PREADY,
    input  wire        PSLVERR,

    // BRAM instruction memory interface (cho fetch lenh)
    // CPU doc lenh tu BRAM rieng, khong qua APB
    output wire        bram_en,
    output wire [31:0] bram_addr,
    input  wire [31:0] bram_rdata
);

    // --------------------------------------------------------
    // Phan loai truy cap:
    //   - mem_instr=1  : fetch lenh -> BRAM
    //   - mem_wstrb=0  : doc data
    //   - mem_wstrb!=0 : ghi data
    //
    // APB only handles data read/write (not instruction fetch)
    // --------------------------------------------------------

    // Fetch lenh -> BRAM (combinational, 1-cycle latency)
    assign bram_en   = mem_valid && mem_instr;
    assign bram_addr = mem_addr;

    // --------------------------------------------------------
    // APB State Machine
    // --------------------------------------------------------
    localparam S_IDLE   = 2'd0;
    localparam S_SETUP  = 2'd1;   // PSEL=1, PENABLE=0
    localparam S_ENABLE = 2'd2;   // PSEL=1, PENABLE=1, wait PREADY

    reg [1:0] state;
    reg       is_instr_fetch;     // ghi nho day la fetch lenh

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state      <= S_IDLE;
            mem_ready  <= 1'b0;
            mem_rdata  <= 32'h0;
            PADDR      <= 32'h0;
            PWRITE     <= 1'b0;
            PSEL       <= 1'b0;
            PENABLE    <= 1'b0;
            PWDATA     <= 32'h0;
            is_instr_fetch <= 1'b0;
        end else begin
            mem_ready <= 1'b0;    // default: xoa sau 1 cycle

            case (state)

                S_IDLE: begin
                    PSEL    <= 1'b0;
                    PENABLE <= 1'b0;

                    if (mem_valid) begin
                        if (mem_instr) begin
                            // Fetch lenh: tra loi ngay tu BRAM (1 cycle)
                            mem_rdata      <= bram_rdata;
                            mem_ready      <= 1'b1;
                            is_instr_fetch <= 1'b1;
                            // Khong can chuyen state, o lai IDLE
                        end else begin
                            // Data access: qua APB
                            PADDR          <= mem_addr;
                            PWRITE         <= |mem_wstrb;
                            PWDATA         <= mem_wdata;
                            PSEL           <= 1'b1;
                            PENABLE        <= 1'b0;
                            is_instr_fetch <= 1'b0;
                            state          <= S_SETUP;
                        end
                    end
                end

                S_SETUP: begin
                    // APB setup phase: PSEL=1, PENABLE=0
                    PSEL    <= 1'b1;
                    PENABLE <= 1'b1;
                    state   <= S_ENABLE;
                end

                S_ENABLE: begin
                    // APB enable phase: cho PREADY
                    if (PREADY) begin
                        PSEL      <= 1'b0;
                        PENABLE   <= 1'b0;
                        mem_ready <= 1'b1;
                        if (!PWRITE)
                            mem_rdata <= PRDATA;
                        state <= S_IDLE;
                    end
                    // Neu PSLVERR: van tra mem_ready de CPU khong bi treo
                    // CPU co the kiem tra ket qua qua thanh ghi STATUS
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule