`timescale 1ns/1ps

// PicoRV32 native memory requests to a 32-bit AXI4 master.
// One outstanding native request, fixed ID 0, single-beat INCR transactions.
// Byte and halfword stores use the native write strobes on a 4-byte AXI beat.
// Complete a request only after its B/R response; hold VALID through stalls.
module picorv32_axi4_bram_adapter (
    input wire clk,
    input wire resetn,
    input wire mem_valid,
    input wire mem_instr,
    input wire [31:0] mem_addr,
    input wire [31:0] mem_wdata,
    input wire [3:0] mem_wstrb,
    output reg mem_ready,
    output reg [31:0] mem_rdata,
    output reg fault,
    output wire [3:0]   M_AXI_AWID,
    output wire [31:0]  M_AXI_AWADDR,
    output wire [7:0]   M_AXI_AWLEN,
    output wire [2:0]   M_AXI_AWSIZE,
    output wire [1:0]   M_AXI_AWBURST,
    output wire         M_AXI_AWLOCK,
    output wire [3:0]   M_AXI_AWCACHE,
    output wire [2:0]   M_AXI_AWPROT,
    output wire [3:0]   M_AXI_AWQOS,
    output wire [3:0]   M_AXI_AWREGION,
    output wire         M_AXI_AWUSER,
    output wire         M_AXI_AWVALID,
    input  wire         M_AXI_AWREADY,
    output wire [31:0]  M_AXI_WDATA,
    output wire [3:0]   M_AXI_WSTRB,
    output wire         M_AXI_WLAST,
    output wire         M_AXI_WUSER,
    output wire         M_AXI_WVALID,
    input  wire         M_AXI_WREADY,
    input  wire [3:0]   M_AXI_BID,
    input  wire [1:0]   M_AXI_BRESP,
    input  wire         M_AXI_BUSER,
    input  wire         M_AXI_BVALID,
    output wire         M_AXI_BREADY,
    output wire [3:0]   M_AXI_ARID,
    output wire [31:0]  M_AXI_ARADDR,
    output wire [7:0]   M_AXI_ARLEN,
    output wire [2:0]   M_AXI_ARSIZE,
    output wire [1:0]   M_AXI_ARBURST,
    output wire         M_AXI_ARLOCK,
    output wire [3:0]   M_AXI_ARCACHE,
    output wire [2:0]   M_AXI_ARPROT,
    output wire [3:0]   M_AXI_ARQOS,
    output wire [3:0]   M_AXI_ARREGION,
    output wire         M_AXI_ARUSER,
    output wire         M_AXI_ARVALID,
    input  wire         M_AXI_ARREADY,
    input  wire [3:0]   M_AXI_RID,
    input  wire [31:0]  M_AXI_RDATA,
    input  wire [1:0]   M_AXI_RRESP,
    input  wire         M_AXI_RLAST,
    input  wire         M_AXI_RUSER,
    input  wire         M_AXI_RVALID,
    output wire         M_AXI_RREADY
);
    localparam IDLE=0, WRITE=1, READ=2, WAIT_NATIVE=3;
    reg [1:0] state;
    reg [31:0] address_reg, data_reg;
    reg [3:0] strobe_reg;
    reg [2:0] protection_reg;
    reg aw_valid, w_valid, ar_valid;

    assign M_AXI_AWID = 4'd0;
    assign M_AXI_AWADDR = address_reg;
    assign M_AXI_AWLEN = 8'd0;
    assign M_AXI_AWSIZE = 3'd2;
    assign M_AXI_AWBURST = 2'b01;
    assign M_AXI_AWLOCK = 1'b0;
    assign M_AXI_AWCACHE = 4'd0;
    assign M_AXI_AWPROT = protection_reg;
    assign M_AXI_AWQOS = 4'd0;
    assign M_AXI_AWREGION = 4'd0;
    assign M_AXI_AWUSER = 1'b0;
    assign M_AXI_AWVALID = aw_valid;
    assign M_AXI_WDATA = data_reg;
    assign M_AXI_WSTRB = strobe_reg;
    assign M_AXI_WLAST = 1'b1;
    assign M_AXI_WUSER = 1'b0;
    assign M_AXI_WVALID = w_valid;
    assign M_AXI_BREADY = state == WRITE && !aw_valid && !w_valid;

    assign M_AXI_ARID = 4'd0;
    assign M_AXI_ARADDR = address_reg;
    assign M_AXI_ARLEN = 8'd0;
    assign M_AXI_ARSIZE = 3'd2;
    assign M_AXI_ARBURST = 2'b01;
    assign M_AXI_ARLOCK = 1'b0;
    assign M_AXI_ARCACHE = 4'd0;
    assign M_AXI_ARPROT = protection_reg;
    assign M_AXI_ARQOS = 4'd0;
    assign M_AXI_ARREGION = 4'd0;
    assign M_AXI_ARUSER = 1'b0;
    assign M_AXI_ARVALID = ar_valid;
    assign M_AXI_RREADY = state == READ && !ar_valid;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= IDLE;
            mem_ready <= 1'b0;
            mem_rdata <= 32'd0;
            fault <= 1'b0;
            address_reg <= 32'd0;
            data_reg <= 32'd0;
            strobe_reg <= 4'd0;
            protection_reg <= 3'd0;
            aw_valid <= 1'b0;
            w_valid <= 1'b0;
            ar_valid <= 1'b0;
        end else begin
            mem_ready <= 1'b0;
            case (state)
                IDLE: if (mem_valid) begin
                    // Native PicoRV32 accesses are word-addressed; low address
                    // bits do not encode the byte lane (mem_wstrb does).
                    address_reg <= {mem_addr[31:2], 2'b00};
                    data_reg <= mem_wdata;
                    strobe_reg <= mem_wstrb;
                    protection_reg <= {mem_instr, 2'b00};
                    if (|mem_wstrb) begin
                        aw_valid <= 1'b1;
                        w_valid <= 1'b1;
                        state <= WRITE;
                    end else begin
                        ar_valid <= 1'b1;
                        state <= READ;
                    end
                end
                WRITE: begin
                    if (M_AXI_AWVALID && M_AXI_AWREADY) aw_valid <= 1'b0;
                    if (M_AXI_WVALID && M_AXI_WREADY) w_valid <= 1'b0;
                    if (M_AXI_BVALID && M_AXI_BREADY) begin
                        if (M_AXI_BRESP != 2'b00 || M_AXI_BID != 4'd0)
                            fault <= 1'b1;
                        mem_ready <= 1'b1;
                        mem_rdata <= 32'd0;
                        state <= WAIT_NATIVE;
                    end
                end
                READ: begin
                    if (M_AXI_ARVALID && M_AXI_ARREADY) ar_valid <= 1'b0;
                    if (M_AXI_RVALID && M_AXI_RREADY) begin
                        if (M_AXI_RRESP != 2'b00 || M_AXI_RID != 4'd0 ||
                            !M_AXI_RLAST) begin
                            fault <= 1'b1;
                            mem_rdata <= 32'd0;
                        end else mem_rdata <= M_AXI_RDATA;
                        mem_ready <= 1'b1;
                        state <= WAIT_NATIVE;
                    end
                end
                // The CPU observes the registered mem_ready in this state.
                // Wait until it drops mem_valid before accepting another request.
                WAIT_NATIVE: if (!mem_valid) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule

