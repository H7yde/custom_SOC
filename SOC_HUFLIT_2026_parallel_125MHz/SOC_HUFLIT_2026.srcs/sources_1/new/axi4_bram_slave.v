`timescale 1ns/1ps

// AXI4 interface to an external 32-bit synchronous BRAM, based at address zero.
// One read burst and one write burst can be outstanding independently.
// Supported: aligned 1/2/4-byte transfers, FIXED (1..16 beats), INCR
// (1..256 beats), and WRAP (2/4/8/16 beats). No burst may cross a 4 KiB boundary.
// Exclusive accesses (AxLOCK=1) are rejected with SLVERR. CACHE/PROT/QOS/REGION
// and USER are accepted as metadata without changing memory behavior; response
// USER fields are zero. IDs are returned unchanged.
//
// Backend contract: the owner of the memory performs byte-enabled writes on
// each rising edge with mem_wr_en=1, and registers mem_rd_data on each rising
// edge with mem_rd_en=1. This module samples that registered read data on the
// following rising edge. The memory itself is neither initialized nor reset
// here. ADDR_BITS is the word-index width (1..30); default capacity is 4 KiB.
//
// Invalid AW metadata suppresses the entire write burst. Invalid WSTRB/WLAST
// suppresses that beat and all subsequent writes in the burst. Earlier valid
// beats are not rolled back. The slave consumes AWLEN+1 beats before returning
// BRESP, even after an early WLAST protocol error. Invalid reads return the
// requested number of zero-data beats with an error response and proper RLAST.
module axi4_bram_slave #(
    parameter integer ID_WIDTH = 4,
    parameter integer USER_WIDTH = 1,
    parameter integer ADDR_BITS = 10
)(
    input  wire                      ACLK,
    input  wire                      ARESETn,

    input  wire [ID_WIDTH-1:0]       S_AXI_AWID,
    input  wire [31:0]               S_AXI_AWADDR,
    input  wire [7:0]                S_AXI_AWLEN,
    input  wire [2:0]                S_AXI_AWSIZE,
    input  wire [1:0]                S_AXI_AWBURST,
    input  wire                     S_AXI_AWLOCK,
    input  wire [3:0]                S_AXI_AWCACHE,
    input  wire [2:0]                S_AXI_AWPROT,
    input  wire [3:0]                S_AXI_AWQOS,
    input  wire [3:0]                S_AXI_AWREGION,
    input  wire [USER_WIDTH-1:0]     S_AXI_AWUSER,
    input  wire                     S_AXI_AWVALID,
    output wire                     S_AXI_AWREADY,

    input  wire [31:0]               S_AXI_WDATA,
    input  wire [3:0]                S_AXI_WSTRB,
    input  wire                     S_AXI_WLAST,
    input  wire [USER_WIDTH-1:0]     S_AXI_WUSER,
    input  wire                     S_AXI_WVALID,
    output wire                     S_AXI_WREADY,

    output reg  [ID_WIDTH-1:0]       S_AXI_BID,
    output reg  [1:0]                S_AXI_BRESP,
    output wire [USER_WIDTH-1:0]     S_AXI_BUSER,
    output reg                      S_AXI_BVALID,
    input  wire                     S_AXI_BREADY,

    input  wire [ID_WIDTH-1:0]       S_AXI_ARID,
    input  wire [31:0]               S_AXI_ARADDR,
    input  wire [7:0]                S_AXI_ARLEN,
    input  wire [2:0]                S_AXI_ARSIZE,
    input  wire [1:0]                S_AXI_ARBURST,
    input  wire                     S_AXI_ARLOCK,
    input  wire [3:0]                S_AXI_ARCACHE,
    input  wire [2:0]                S_AXI_ARPROT,
    input  wire [3:0]                S_AXI_ARQOS,
    input  wire [3:0]                S_AXI_ARREGION,
    input  wire [USER_WIDTH-1:0]     S_AXI_ARUSER,
    input  wire                     S_AXI_ARVALID,
    output wire                     S_AXI_ARREADY,

    output reg  [ID_WIDTH-1:0]       S_AXI_RID,
    output reg  [31:0]               S_AXI_RDATA,
    output reg  [1:0]                S_AXI_RRESP,
    output reg                      S_AXI_RLAST,
    output wire [USER_WIDTH-1:0]     S_AXI_RUSER,
    output reg                      S_AXI_RVALID,
    input  wire                     S_AXI_RREADY,

    output wire                     mem_wr_en,
    output wire [ADDR_BITS-1:0]      mem_wr_index,
    output wire [31:0]               mem_wr_data,
    output wire [3:0]                mem_wr_strb,
    output wire                     mem_rd_en,
    output wire [ADDR_BITS-1:0]      mem_rd_index,
    input  wire [31:0]               mem_rd_data
);
    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;
    localparam [1:0] RESP_DECERR = 2'b11;
    localparam [32:0] MEMORY_BYTES = 33'd1 << (ADDR_BITS + 2);

    // Check the entire address footprint before issuing any backend request.
    // The extra bit prevents 32-bit address overflow from wrapping into BRAM.
    function [1:0] request_response;
        input [31:0] address;
        input [7:0] length;
        input [2:0] size;
        input [1:0] burst;
        input locked;
        reg [32:0] beat_bytes, burst_bytes, first_byte, last_byte;
        reg invalid;
        begin
            beat_bytes = 33'd1 << size;
            burst_bytes = ({25'd0, length} + 33'd1) << size;
            first_byte = {1'b0, address};
            last_byte = first_byte + beat_bytes - 33'd1;
            invalid = locked || (size > 3'd2) || (burst == 2'b11) ||
                      ((first_byte & (beat_bytes - 33'd1)) != 33'd0);

            if (burst == 2'b00 && length > 8'd15)
                invalid = 1'b1;
            if (burst == 2'b01)
                last_byte = first_byte + burst_bytes - 33'd1;
            if (burst == 2'b10) begin
                if (!(length == 8'd1 || length == 8'd3 ||
                      length == 8'd7 || length == 8'd15))
                    invalid = 1'b1;
                first_byte = first_byte & ~(burst_bytes - 33'd1);
                last_byte = first_byte + burst_bytes - 33'd1;
            end
            if (first_byte[32:12] != last_byte[32:12])
                invalid = 1'b1;

            if (invalid)
                request_response = RESP_SLVERR;
            else if (first_byte >= MEMORY_BYTES || last_byte >= MEMORY_BYTES)
                request_response = RESP_DECERR;
            else
                request_response = RESP_OKAY;
        end
    endfunction

    function [31:0] burst_wrap_mask;
        input [7:0] length;
        input [2:0] size;
        begin
            burst_wrap_mask = (({24'd0, length} + 32'd1) << size) - 32'd1;
        end
    endfunction

    function [31:0] next_address;
        input [31:0] address;
        input [2:0] size;
        input [1:0] burst;
        input [31:0] wrap_base;
        input [31:0] wrap_mask;
        reg [31:0] incremented;
        begin
            incremented = address + (32'd1 << size);
            case (burst)
                2'b00: next_address = address;
                2'b10: next_address = wrap_base | (incremented & wrap_mask);
                default: next_address = incremented;
            endcase
        end
    endfunction

    function [3:0] byte_lane_mask;
        input [31:0] address;
        input [2:0] size;
        begin
            case (size)
                3'd0: byte_lane_mask = 4'b0001 << address[1:0];
                3'd1: byte_lane_mask = 4'b0011 << address[1:0];
                3'd2: byte_lane_mask = 4'b1111;
                default: byte_lane_mask = 4'b0000;
            endcase
        end
    endfunction

    reg wr_active;
    reg [ID_WIDTH-1:0] wr_id;
    reg [31:0] wr_address, wr_wrap_base, wr_wrap_mask;
    reg [7:0] wr_length, wr_beat;
    reg [2:0] wr_size;
    reg [1:0] wr_burst, wr_response;

    reg rd_active, rd_pending;
    reg [ID_WIDTH-1:0] rd_id;
    reg [31:0] rd_address, rd_wrap_base, rd_wrap_mask;
    reg [7:0] rd_length, rd_beat;
    reg [2:0] rd_size;
    reg [1:0] rd_burst, rd_response;

    wire write_fire = S_AXI_WVALID && S_AXI_WREADY;
    wire write_last = (wr_beat == wr_length);
    wire [3:0] allowed_strobes = byte_lane_mask(wr_address, wr_size);
    wire bad_write_beat = (S_AXI_WLAST != write_last) ||
                          (|(S_AXI_WSTRB & ~allowed_strobes));
    wire [1:0] write_response = (wr_response != RESP_OKAY) ? wr_response :
                                (bad_write_beat ? RESP_SLVERR : RESP_OKAY);

    assign S_AXI_AWREADY = ARESETn && !wr_active && !S_AXI_BVALID;
    // Waiting for AW before asserting WREADY is legal; AW never waits on W.
    assign S_AXI_WREADY = ARESETn && wr_active && !S_AXI_BVALID;
    assign S_AXI_ARREADY = ARESETn && !rd_active && !rd_pending && !S_AXI_RVALID;
    assign S_AXI_BUSER = {USER_WIDTH{1'b0}};
    assign S_AXI_RUSER = {USER_WIDTH{1'b0}};

    assign mem_wr_en = ARESETn && write_fire && (write_response == RESP_OKAY);
    assign mem_wr_index = wr_address[ADDR_BITS+1:2];
    assign mem_wr_data = S_AXI_WDATA;
    assign mem_wr_strb = S_AXI_WSTRB;
    assign mem_rd_en = ARESETn && rd_active && !rd_pending &&
                       !S_AXI_RVALID && (rd_response == RESP_OKAY);
    assign mem_rd_index = rd_address[ADDR_BITS+1:2];

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            wr_active <= 1'b0;
            wr_id <= {ID_WIDTH{1'b0}};
            wr_address <= 32'd0;
            wr_wrap_base <= 32'd0;
            wr_wrap_mask <= 32'd0;
            wr_length <= 8'd0;
            wr_beat <= 8'd0;
            wr_size <= 3'd0;
            wr_burst <= 2'd0;
            wr_response <= RESP_OKAY;
            S_AXI_BID <= {ID_WIDTH{1'b0}};
            S_AXI_BRESP <= RESP_OKAY;
            S_AXI_BVALID <= 1'b0;
        end else begin
            if (S_AXI_BVALID && S_AXI_BREADY)
                S_AXI_BVALID <= 1'b0;

            if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                wr_active <= 1'b1;
                wr_id <= S_AXI_AWID;
                wr_address <= S_AXI_AWADDR;
                wr_wrap_mask <= burst_wrap_mask(S_AXI_AWLEN, S_AXI_AWSIZE);
                wr_wrap_base <= S_AXI_AWADDR &
                                ~burst_wrap_mask(S_AXI_AWLEN, S_AXI_AWSIZE);
                wr_length <= S_AXI_AWLEN;
                wr_beat <= 8'd0;
                wr_size <= S_AXI_AWSIZE;
                wr_burst <= S_AXI_AWBURST;
                wr_response <= request_response(S_AXI_AWADDR, S_AXI_AWLEN,
                                                S_AXI_AWSIZE, S_AXI_AWBURST,
                                                S_AXI_AWLOCK);
            end

            if (write_fire) begin
                wr_response <= write_response;
                if (write_last) begin
                    wr_active <= 1'b0;
                    S_AXI_BID <= wr_id;
                    S_AXI_BRESP <= write_response;
                    S_AXI_BVALID <= 1'b1;
                end else begin
                    wr_beat <= wr_beat + 8'd1;
                    wr_address <= next_address(wr_address, wr_size, wr_burst,
                                               wr_wrap_base, wr_wrap_mask);
                end
            end
        end
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            rd_active <= 1'b0;
            rd_pending <= 1'b0;
            rd_id <= {ID_WIDTH{1'b0}};
            rd_address <= 32'd0;
            rd_wrap_base <= 32'd0;
            rd_wrap_mask <= 32'd0;
            rd_length <= 8'd0;
            rd_beat <= 8'd0;
            rd_size <= 3'd0;
            rd_burst <= 2'd0;
            rd_response <= RESP_OKAY;
            S_AXI_RID <= {ID_WIDTH{1'b0}};
            S_AXI_RDATA <= 32'd0;
            S_AXI_RRESP <= RESP_OKAY;
            S_AXI_RLAST <= 1'b0;
            S_AXI_RVALID <= 1'b0;
        end else begin
            if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                rd_active <= 1'b1;
                rd_id <= S_AXI_ARID;
                rd_address <= S_AXI_ARADDR;
                rd_wrap_mask <= burst_wrap_mask(S_AXI_ARLEN, S_AXI_ARSIZE);
                rd_wrap_base <= S_AXI_ARADDR &
                                ~burst_wrap_mask(S_AXI_ARLEN, S_AXI_ARSIZE);
                rd_length <= S_AXI_ARLEN;
                rd_beat <= 8'd0;
                rd_size <= S_AXI_ARSIZE;
                rd_burst <= S_AXI_ARBURST;
                rd_response <= request_response(S_AXI_ARADDR, S_AXI_ARLEN,
                                                S_AXI_ARSIZE, S_AXI_ARBURST,
                                                S_AXI_ARLOCK);
            end

            if (rd_active && !rd_pending && !S_AXI_RVALID) begin
                if (rd_response == RESP_OKAY) begin
                    // mem_rd_en is high at this edge. The BRAM updates its
                    // registered output after the edge; capture it next cycle.
                    rd_pending <= 1'b1;
                end else begin
                    S_AXI_RID <= rd_id;
                    S_AXI_RDATA <= 32'd0;
                    S_AXI_RRESP <= rd_response;
                    S_AXI_RLAST <= (rd_beat == rd_length);
                    S_AXI_RVALID <= 1'b1;
                end
            end

            if (rd_pending) begin
                rd_pending <= 1'b0;
                S_AXI_RID <= rd_id;
                // Narrow reads preserve the natural byte lanes; other bytes
                // in the returned aligned BRAM word are harmless extra data.
                S_AXI_RDATA <= mem_rd_data;
                S_AXI_RRESP <= rd_response;
                S_AXI_RLAST <= (rd_beat == rd_length);
                S_AXI_RVALID <= 1'b1;
            end

            if (S_AXI_RVALID && S_AXI_RREADY) begin
                S_AXI_RVALID <= 1'b0;
                if (S_AXI_RLAST) begin
                    rd_active <= 1'b0;
                end else begin
                    rd_beat <= rd_beat + 8'd1;
                    rd_address <= next_address(rd_address, rd_size, rd_burst,
                                               rd_wrap_base, rd_wrap_mask);
                end
            end
        end
    end
endmodule
