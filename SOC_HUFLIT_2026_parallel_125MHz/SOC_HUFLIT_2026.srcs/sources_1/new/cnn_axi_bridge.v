`timescale 1ns/1ps
// Two AXI4-Lite initiators: lane 0 PicoRV32, lane 1 ARM (after vendor CDC).
// One independently buffered AW, W, AR, B and R per initiator. Transactions
// serialize at the CNN with round-robin arbitration across both reads/writes.
// 0x40004F00: write 1 to claim, 0 to release; read owner (0/free,1/Pico,2/ARM)
// and busy at bit 8. Claims/releases while CNN busy are ignored, not faults.
// 0x40004F04: read bridge signature 0x434E4E42. Other reads go to CNN.
// Ownership lasts across transactions, including upload and result retrieval.
module cnn_axi_bridge #(
    parameter REQUIRE_LOCK = 1
)(
    input wire clk, input wire resetn, input wire cnn_busy,
    input wire [63:0] s_awaddr, input wire [1:0] s_awvalid,
    output wire [1:0] s_awready,
    input wire [63:0] s_wdata, input wire [7:0] s_wstrb,
    input wire [1:0] s_wvalid, output wire [1:0] s_wready,
    output wire [3:0] s_bresp, output reg [1:0] s_bvalid,
    input wire [1:0] s_bready,
    input wire [63:0] s_araddr, input wire [1:0] s_arvalid,
    output wire [1:0] s_arready,
    output wire [63:0] s_rdata, output wire [3:0] s_rresp,
    output reg [1:0] s_rvalid, input wire [1:0] s_rready,
    output reg [31:0] m_awaddr, output wire m_awvalid, input wire m_awready,
    output reg [31:0] m_wdata, output reg [3:0] m_wstrb,
    output wire m_wvalid, input wire m_wready,
    input wire [1:0] m_bresp, input wire m_bvalid, output wire m_bready,
    output reg [31:0] m_araddr, output wire m_arvalid, input wire m_arready,
    input wire [31:0] m_rdata, input wire [1:0] m_rresp,
    input wire m_rvalid, output wire m_rready
);
    localparam IDLE=0, WRITE_SEND=1, WRITE_RESPONSE=2,
               READ_SEND=3, READ_RESPONSE=4;
    reg [2:0] state;
    reg [1:0] owner, next_slot;
    reg active_lane, aw_sent, w_sent;
    reg [1:0] aw_pending, w_pending, ar_pending, writing, reading;
    reg [31:0] awaddr [0:1], wdata [0:1], araddr [0:1], rdata [0:1];
    reg [3:0] wstrb [0:1];
    reg [1:0] bresp [0:1], rresp [0:1];
    wire [3:0] requests = {ar_pending[1], aw_pending[1] && w_pending[1],
                          ar_pending[0], aw_pending[0] && w_pending[0]};
    reg grant_valid;
    reg [1:0] grant_slot;
    integer scan, candidate, lane;
    always @* begin
        grant_valid = 0;
        grant_slot = next_slot;
        candidate = 0;
        for (scan=0; scan<4; scan=scan+1) begin
            candidate = (next_slot + scan) & 3;
            if (!grant_valid && requests[candidate]) begin
                grant_valid = 1;
                grant_slot = candidate[1:0];
            end
        end
    end
    assign s_awready = ~aw_pending & ~writing & ~s_bvalid & {2{resetn}};
    assign s_wready = ~w_pending & ~writing & ~s_bvalid & {2{resetn}};
    assign s_arready = ~ar_pending & ~reading & ~s_rvalid & {2{resetn}};
    assign s_bresp = {bresp[1], bresp[0]};
    assign s_rresp = {rresp[1], rresp[0]};
    assign s_rdata = {rdata[1], rdata[0]};
    assign m_awvalid = resetn && state == WRITE_SEND && !aw_sent;
    assign m_wvalid = resetn && state == WRITE_SEND && !w_sent;
    assign m_bready = resetn && state == WRITE_RESPONSE;
    assign m_arvalid = resetn && state == READ_SEND;
    assign m_rready = resetn && state == READ_RESPONSE;
    wire selected_lane = grant_slot[1];
    wire [31:0] selected_addr = grant_slot[0] ? araddr[selected_lane] : awaddr[selected_lane];
    wire address_ok = selected_addr[31:12] == 20'h40004 && selected_addr[1:0] == 0;
    wire lock_addr = selected_addr[11:0] == 12'hF00;
    wire id_addr = selected_addr[11:0] == 12'hF04;
    wire permitted = owner == (selected_lane ? 2'd2 : 2'd1) ||
                     (!REQUIRE_LOCK && !selected_lane && owner == 0);
    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE;
            owner <= 0;
            next_slot <= 0;
            active_lane <= 0;
            aw_sent <= 0; w_sent <= 0;
            aw_pending <= 0; w_pending <= 0; ar_pending <= 0;
            writing <= 0; reading <= 0;
            s_bvalid <= 0; s_rvalid <= 0;
            m_awaddr <= 0; m_wdata <= 0; m_wstrb <= 0; m_araddr <= 0;
            for (lane=0; lane<2; lane=lane+1) begin
                awaddr[lane] <= 0; wdata[lane] <= 0; wstrb[lane] <= 0;
                araddr[lane] <= 0; rdata[lane] <= 0;
                bresp[lane] <= 0; rresp[lane] <= 0;
            end
        end else begin
            for (lane=0; lane<2; lane=lane+1) begin
                if (s_awvalid[lane] && s_awready[lane]) begin
                    awaddr[lane] <= s_awaddr[lane*32 +: 32];
                    aw_pending[lane] <= 1;
                end
                if (s_wvalid[lane] && s_wready[lane]) begin
                    wdata[lane] <= s_wdata[lane*32 +: 32];
                    wstrb[lane] <= s_wstrb[lane*4 +: 4];
                    w_pending[lane] <= 1;
                end
                if (s_arvalid[lane] && s_arready[lane]) begin
                    araddr[lane] <= s_araddr[lane*32 +: 32];
                    ar_pending[lane] <= 1;
                end
                if (s_bvalid[lane] && s_bready[lane]) begin
                    s_bvalid[lane] <= 0; writing[lane] <= 0;
                end
                if (s_rvalid[lane] && s_rready[lane]) begin
                    s_rvalid[lane] <= 0; reading[lane] <= 0;
                end
            end
            case (state)
                IDLE: if (grant_valid) begin
                    active_lane <= selected_lane;
                    next_slot <= grant_slot + 2'd1;
                    if (!grant_slot[0]) begin
                        aw_pending[selected_lane] <= 0;
                        w_pending[selected_lane] <= 0;
                        writing[selected_lane] <= 1;
                        if (!address_ok || id_addr || (!lock_addr && !permitted)) begin
                            bresp[selected_lane] <= 2'b10;
                            s_bvalid[selected_lane] <= 1;
                        end else if (lock_addr) begin
                            if (wstrb[selected_lane][0] && !cnn_busy) begin
                                if (wdata[selected_lane] == 1 && owner == 0)
                                    owner <= selected_lane ? 2'd2 : 2'd1;
                                if (wdata[selected_lane] == 0 && permitted)
                                    owner <= 0;
                            end
                            bresp[selected_lane] <= 0;
                            s_bvalid[selected_lane] <= 1;
                        end else begin
                            m_awaddr <= awaddr[selected_lane];
                            m_wdata <= wdata[selected_lane];
                            m_wstrb <= wstrb[selected_lane];
                            aw_sent <= 0; w_sent <= 0;
                            state <= WRITE_SEND;
                        end
                    end else begin
                        ar_pending[selected_lane] <= 0;
                        reading[selected_lane] <= 1;
                        if (!address_ok || lock_addr || id_addr) begin
                            rdata[selected_lane] <= !address_ok ? 0 :
                                lock_addr ? {23'd0, cnn_busy, 6'd0, owner} : 32'h434E4E42;
                            rresp[selected_lane] <= address_ok ? 2'b00 : 2'b10;
                            s_rvalid[selected_lane] <= 1;
                        end else begin
                            m_araddr <= araddr[selected_lane];
                            state <= READ_SEND;
                        end
                    end
                end
                WRITE_SEND: begin
                    if (m_awvalid && m_awready) aw_sent <= 1;
                    if (m_wvalid && m_wready) w_sent <= 1;
                    if ((aw_sent || m_awready) && (w_sent || m_wready))
                        state <= WRITE_RESPONSE;
                end
                WRITE_RESPONSE: if (m_bvalid) begin
                    bresp[active_lane] <= m_bresp;
                    s_bvalid[active_lane] <= 1;
                    state <= IDLE;
                end
                READ_SEND: if (m_arready) state <= READ_RESPONSE;
                READ_RESPONSE: if (m_rvalid) begin
                    rdata[active_lane] <= m_rdata;
                    rresp[active_lane] <= m_rresp;
                    s_rvalid[active_lane] <= 1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
