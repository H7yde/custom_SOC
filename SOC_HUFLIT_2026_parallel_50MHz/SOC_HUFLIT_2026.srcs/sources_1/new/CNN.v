`timescale 1ns/1ps

// AXI4-Lite CNN peripheral with two input paths:
//   1) baseline: CPU writes the frame into frame_mem through AXI4-Lite;
//   2) DMA: CNN reads a frame from an AXI memory subsystem through its
//      read-only AXI master channel.
//
// Register map relative to 0x40004000:
//   0x000..0xBFC : baseline frame_mem, 768 x 32-bit words
//   0xFE0        : DMA_BASE, default 0x40006000
//   0xFE4        : CONFIG
//                    [9:0]  source words (1..768, 0 means 768)
//                    [16]   DMA enable
//                    [17]   frame-level ping-pong enable
//                    [18]   buffer select (0/1)
//   0xFE8        : compute cycles for the last run
//   0xFEC        : AXI DMA read-address handshakes for the last run
//   0xFF0        : baseline AXI-Lite frame write count
//   0xFF4        : RESULT, bit 0 = classification
//   0xFF8        : STATUS, bit 0 = busy, bit 1 = done,
//                    bit 2 = active DMA, bit 3 = active buffer,
//                    bit 4 = ping-pong enabled
//   0xFFC        : CONTROL, write bit 0 = START
//
// The CNN core still consumes exactly one 32x32 RGB888 frame.  If CONFIG
// specifies fewer than 768 source words, the remaining words are zero-padded
// before the RGB stream reaches the core.
module CNN (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [31:0] S_AXI_AWADDR,
    input  wire        S_AXI_AWVALID,
    output wire        S_AXI_AWREADY,
    input  wire [31:0] S_AXI_WDATA,
    input  wire [3:0]  S_AXI_WSTRB,
    input  wire        S_AXI_WVALID,
    output wire        S_AXI_WREADY,
    output wire [1:0]  S_AXI_BRESP,
    output wire        S_AXI_BVALID,
    input  wire        S_AXI_BREADY,

    input  wire [31:0] S_AXI_ARADDR,
    input  wire        S_AXI_ARVALID,
    output wire        S_AXI_ARREADY,
    output wire [31:0] S_AXI_RDATA,
    output wire [1:0]  S_AXI_RRESP,
    output wire        S_AXI_RVALID,
    input  wire        S_AXI_RREADY,

    // Read-only AXI master channel used by the DMA mode.
    output wire [31:0] M_AXI_ARADDR,
    output wire        M_AXI_ARVALID,
    input  wire        M_AXI_ARREADY,
    input  wire [31:0] M_AXI_RDATA,
    input  wire        M_AXI_RVALID,
    output wire        M_AXI_RREADY
);
    reg [31:0] frame_mem [0:767];

    reg        aw_pending;
    reg        w_pending;
    reg [31:0] awaddr_reg;
    reg [31:0] wdata_reg;
    reg [3:0]  wstrb_reg;
    reg        bvalid_reg;
    reg        rvalid_reg;
    reg [31:0] rdata_reg;

    reg        start_pending;
    reg        busy_reg;
    reg        done_reg;
    reg        classification_reg;
    reg [9:0]  frame_word_index;
    reg        frame_send_valid;
    reg [31:0] frame_send_data_reg;

    reg [31:0] dma_base_addr_reg;
    reg [9:0]  frame_words_reg;
    reg        dma_enable_reg;
    reg        pingpong_enable_reg;
    reg        buffer_select_reg;
    reg        active_buffer_reg;
    reg [31:0] active_dma_base_reg;
    reg        dma_arvalid_reg;
    reg [31:0] dma_araddr_reg;
    reg        dma_read_wait_reg;
    reg        dma_padding_reg;

    reg [31:0] cycle_counter;
    reg [31:0] dma_read_counter;
    reg [31:0] baseline_write_counter;

    wire [11:0] write_offset = awaddr_reg[11:0];
    wire [11:0] read_offset  = S_AXI_ARADDR[11:0];
    wire        write_fire = aw_pending && w_pending && !bvalid_reg;

    wire [9:0] source_words_limit =
        (frame_words_reg == 10'd0 || frame_words_reg > 10'd768) ?
        10'd768 : frame_words_reg;

    wire [31:0] frame_send_data = dma_enable_reg ?
                                  frame_send_data_reg :
                                  frame_mem[frame_word_index];
    wire        dma_ready;
    wire [23:0] rgb_data;
    wire        rgb_valid;
    wire        rgb_ready;
    wire        cnn_result_valid;
    wire        cnn_classification;
    wire        rst = ~rst_n;

    assign S_AXI_AWREADY = !aw_pending && !bvalid_reg;
    assign S_AXI_WREADY  = !w_pending  && !bvalid_reg;
    assign S_AXI_BVALID  = bvalid_reg;
    assign S_AXI_BRESP   = 2'b00;
    assign S_AXI_ARREADY = !rvalid_reg;
    assign S_AXI_RVALID  = rvalid_reg;
    assign S_AXI_RDATA   = rdata_reg;
    assign S_AXI_RRESP   = 2'b00;

    assign M_AXI_ARADDR  = dma_araddr_reg;
    assign M_AXI_ARVALID = dma_arvalid_reg;
    assign M_AXI_RREADY  = dma_read_wait_reg && !frame_send_valid;

    dma32_to_rgb24 #(
        .MSB_FIRST(1'b1)
    ) u_dma_to_rgb (
        .clk       (clk),
        .rst       (rst),
        .dma_data  (frame_send_data),
        .dma_valid (frame_send_valid),
        .dma_ready (dma_ready),
        .rgb_data  (rgb_data),
        .rgb_valid (rgb_valid),
        .rgb_ready (rgb_ready)
    );

    cnn_docx_reference u_cnn_reference (
        .clk           (clk),
        .rst           (rst),
        .pixel_data    (rgb_data),
        .pixel_valid   (rgb_valid),
        .pixel_ready   (rgb_ready),
        .result_valid  (cnn_result_valid),
        .classification(cnn_classification)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            aw_pending          <= 1'b0;
            w_pending           <= 1'b0;
            awaddr_reg          <= 32'd0;
            wdata_reg           <= 32'd0;
            wstrb_reg           <= 4'd0;
            bvalid_reg          <= 1'b0;
            rvalid_reg          <= 1'b0;
            rdata_reg           <= 32'd0;
            start_pending       <= 1'b0;
            busy_reg            <= 1'b0;
            done_reg            <= 1'b0;
            classification_reg  <= 1'b0;
            frame_word_index    <= 10'd0;
            frame_send_valid    <= 1'b0;
            frame_send_data_reg <= 32'd0;
            dma_base_addr_reg   <= 32'h4000_6000;
            frame_words_reg     <= 10'd768;
            dma_enable_reg      <= 1'b0;
            pingpong_enable_reg <= 1'b0;
            buffer_select_reg   <= 1'b0;
            active_buffer_reg   <= 1'b0;
            active_dma_base_reg <= 32'h4000_6000;
            dma_arvalid_reg     <= 1'b0;
            dma_araddr_reg      <= 32'd0;
            dma_read_wait_reg   <= 1'b0;
            dma_padding_reg     <= 1'b0;
            cycle_counter       <= 32'd0;
            dma_read_counter    <= 32'd0;
            baseline_write_counter <= 32'd0;
        end else begin
            // Capture AXI write address and data independently.
            if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                awaddr_reg <= S_AXI_AWADDR;
                aw_pending <= 1'b1;
            end
            if (S_AXI_WVALID && S_AXI_WREADY) begin
                wdata_reg <= S_AXI_WDATA;
                wstrb_reg <= S_AXI_WSTRB;
                w_pending <= 1'b1;
            end

            if (write_fire) begin
                aw_pending <= 1'b0;
                w_pending  <= 1'b0;
                bvalid_reg <= 1'b1;

                // Baseline image buffer.
                if (write_offset < 12'hC00) begin
                    if (write_offset[11:2] < 10'd768) begin
                        if (wstrb_reg[0]) frame_mem[write_offset[11:2]][7:0]   <= wdata_reg[7:0];
                        if (wstrb_reg[1]) frame_mem[write_offset[11:2]][15:8]  <= wdata_reg[15:8];
                        if (wstrb_reg[2]) frame_mem[write_offset[11:2]][23:16] <= wdata_reg[23:16];
                        if (wstrb_reg[3]) frame_mem[write_offset[11:2]][31:24] <= wdata_reg[31:24];
                        baseline_write_counter <= baseline_write_counter + 32'd1;
                    end
                end

                // Runtime configuration registers.
                if (write_offset == 12'hFE0)
                    dma_base_addr_reg <= wdata_reg;
                if (write_offset == 12'hFE4) begin
                    frame_words_reg     <= wdata_reg[9:0];
                    dma_enable_reg      <= wdata_reg[16];
                    pingpong_enable_reg <= wdata_reg[17];
                    buffer_select_reg   <= wdata_reg[18];
                end

                // CONTROL: write bit 0 to start one frame.
                if (write_offset == 12'hFFC && wdata_reg[0] && !busy_reg) begin
                    start_pending <= 1'b1;
                    done_reg <= 1'b0;
                end
            end

            if (bvalid_reg && S_AXI_BREADY)
                bvalid_reg <= 1'b0;

            // One-cycle AXI read response.
            if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                rvalid_reg <= 1'b1;
                case (read_offset)
                    12'hFE0: rdata_reg <= dma_base_addr_reg;
                    12'hFE4: rdata_reg <= {13'd0, buffer_select_reg,
                                             pingpong_enable_reg,
                                             dma_enable_reg, 6'd0,
                                             frame_words_reg};
                    12'hFE8: rdata_reg <= cycle_counter;
                    12'hFEC: rdata_reg <= dma_read_counter;
                    12'hFF0: rdata_reg <= baseline_write_counter;
                    12'hFF4: rdata_reg <= {31'd0, classification_reg};
                    12'hFF8: rdata_reg <= {27'd0, pingpong_enable_reg,
                                             active_buffer_reg,
                                             dma_enable_reg, done_reg,
                                             busy_reg};
                    12'hFFC: rdata_reg <= 32'd0;
                    default: rdata_reg <= 32'd0;
                endcase
            end else if (rvalid_reg && S_AXI_RREADY) begin
                rvalid_reg <= 1'b0;
            end

            if (busy_reg)
                cycle_counter <= cycle_counter + 32'd1;

            // Start either the baseline frame stream or the AXI DMA stream.
            if (start_pending && !busy_reg) begin
                start_pending          <= 1'b0;
                busy_reg               <= 1'b1;
                done_reg               <= 1'b0;
                frame_word_index       <= 10'd0;
                frame_send_valid      <= 1'b0;
                dma_read_wait_reg      <= 1'b0;
                dma_padding_reg        <= 1'b0;
                cycle_counter          <= 32'd0;
                dma_read_counter       <= 32'd0;

                if (dma_enable_reg) begin
                    active_buffer_reg   <= buffer_select_reg;
                    active_dma_base_reg <= dma_base_addr_reg +
                                           (buffer_select_reg ? 32'h0000_0C00 : 32'h0000_0000);
                    dma_araddr_reg      <= dma_base_addr_reg +
                                           (buffer_select_reg ? 32'h0000_0C00 : 32'h0000_0000);
                    dma_arvalid_reg     <= 1'b1;
                end else begin
                    active_buffer_reg <= 1'b0;
                    frame_send_valid  <= 1'b1;
                end
            end

            // AXI master read address and response channels.
            if (dma_arvalid_reg && M_AXI_ARREADY) begin
                dma_arvalid_reg   <= 1'b0;
                dma_read_wait_reg <= 1'b1;
                dma_read_counter  <= dma_read_counter + 32'd1;
            end
            if (M_AXI_RVALID && M_AXI_RREADY) begin
                frame_send_data_reg <= M_AXI_RDATA;
                frame_send_valid    <= 1'b1;
                dma_read_wait_reg   <= 1'b0;
            end

            // The data packer consumes one 32-bit word at a time.  In DMA
            // mode, the next AXI read is launched only after the current
            // word is accepted, creating a deterministic streaming dataflow.
            if (frame_send_valid && dma_ready) begin
                if (frame_word_index == 10'd767) begin
                    frame_send_valid <= 1'b0;
                    dma_arvalid_reg  <= 1'b0;
                end else begin
                    frame_word_index <= frame_word_index + 10'd1;
                    if (!dma_enable_reg) begin
                        frame_send_valid <= 1'b1;
                    end else if (dma_padding_reg) begin
                        frame_send_data_reg <= 32'd0;
                        frame_send_valid    <= 1'b1;
                    end else if ((frame_word_index + 10'd1) < source_words_limit) begin
                        dma_araddr_reg   <= active_dma_base_reg +
                                            ((frame_word_index + 10'd1) << 2);
                        dma_arvalid_reg  <= 1'b1;
                        frame_send_valid <= 1'b0;
                    end else begin
                        dma_padding_reg   <= 1'b1;
                        frame_send_data_reg <= 32'd0;
                        frame_send_valid   <= 1'b1;
                    end
                end
            end

            if (cnn_result_valid) begin
                classification_reg <= cnn_classification;
                busy_reg            <= 1'b0;
                done_reg            <= 1'b1;
                dma_arvalid_reg     <= 1'b0;
                dma_read_wait_reg   <= 1'b0;
                if (pingpong_enable_reg)
                    buffer_select_reg <= ~active_buffer_reg;
            end
        end
    end
endmodule
