// ============================================================
//  FemtoRV32 Quark memory bus to APB bridge
//
//  Quark bus:
//    mem_rstrb pulses for instruction/data reads.
//    mem_wmask is non-zero for stores.
//    mem_rbusy / mem_wbusy hold the CPU in WAIT until APB completes.
//
//  APB sequence:
//    IDLE -> SETUP(PSEL=1,PENABLE=0)
//         -> ENABLE(PSEL=1,PENABLE=1, wait PREADY)
//         -> IDLE
// ============================================================

`default_nettype none

module apb_bridge (
    input  wire        clk,
    input  wire        resetn,

    input  wire        bus_sel,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,
    input  wire [ 3:0] mem_wmask,
    input  wire        mem_rstrb,
    output reg  [31:0] mem_rdata,
    output wire        mem_rbusy,
    output wire        mem_wbusy,

    output reg  [31:0] PADDR,
    output reg         PWRITE,
    output reg         PSEL,
    output reg         PENABLE,
    output reg  [31:0] PWDATA,
    input  wire [31:0] PRDATA,
    input  wire        PREADY,
    input  wire        PSLVERR
);

    localparam S_IDLE   = 2'd0;
    localparam S_SETUP  = 2'd1;
    localparam S_ENABLE = 2'd2;

    reg [1:0] state;
    reg       txn_read;
    reg       txn_write;

    wire read_req  = bus_sel && mem_rstrb;
    wire write_req = bus_sel && |mem_wmask;
    wire request   = (read_req || write_req) && (state == S_IDLE);

    assign mem_rbusy = read_req ||
                       (((state == S_SETUP) || (state == S_ENABLE)) && txn_read);

    assign mem_wbusy = write_req ||
                       (((state == S_SETUP) || (state == S_ENABLE)) && txn_write);

    wire unused_pslverr = PSLVERR;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state     <= S_IDLE;
            txn_read  <= 1'b0;
            txn_write <= 1'b0;
            mem_rdata <= 32'h00000000;
            PADDR     <= 32'h00000000;
            PWRITE    <= 1'b0;
            PSEL      <= 1'b0;
            PENABLE   <= 1'b0;
            PWDATA    <= 32'h00000000;
        end else begin
            case (state)
                S_IDLE: begin
                    PSEL    <= 1'b0;
                    PENABLE <= 1'b0;

                    if (request) begin
                        PADDR     <= mem_addr;
                        PWRITE    <= write_req;
                        PWDATA    <= mem_wdata;
                        PSEL      <= 1'b1;
                        PENABLE   <= 1'b0;
                        txn_read  <= read_req;
                        txn_write <= write_req;
                        state     <= S_SETUP;
                    end
                end

                S_SETUP: begin
                    PSEL    <= 1'b1;
                    PENABLE <= 1'b1;
                    state   <= S_ENABLE;
                end

                S_ENABLE: begin
                    PSEL    <= 1'b1;
                    PENABLE <= 1'b1;

                    if (PREADY) begin
                        if (!PWRITE) begin
                            mem_rdata <= PRDATA;
                        end
                        PSEL      <= 1'b0;
                        PENABLE   <= 1'b0;
                        txn_read  <= 1'b0;
                        txn_write <= 1'b0;
                        state     <= S_IDLE;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
