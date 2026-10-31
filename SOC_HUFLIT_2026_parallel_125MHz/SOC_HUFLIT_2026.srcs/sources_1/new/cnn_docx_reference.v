`timescale 1ns/1ps

// One shared MAC, with registered address/read/normalize/multiply/accumulate
// stages. Narrow loop counters avoid division-based address generation.
module cnn_docx_reference(
    input wire clk, input wire rst, input wire [23:0] pixel_data,
    input wire pixel_valid, output reg pixel_ready,
    output reg result_valid, output reg classification
);
    localparam CAP=0,C1=1,P1=2,C2=3,P2=4,C3=5,P3=6,FC=7,DONE=8;
    reg [3:0] st;
    reg [2:0] phase;
    reg [10:0] pix;
    reg [11:0] n;
    reg [5:0] k;
    reg [2:0] pk;
    reg [4:0] fi;
    reg [4:0] x, y;
    reg [1:0] oc, ic, kx, ky;
    reg [11:0] row_base, channel_base, kernel_row;
    reg [7:0] weight_base, weight_addr;
    reg [11:0] read_addr;
    reg [23:0] raw_pixel;
    reg signed [7:0] sample, layer_sample, weight_value, pool_sample, pmax;
    reg signed [15:0] product;
    reg signed [31:0] acc, total;
    reg [7:0] quantized;

    // Raw RGB image remains visible for the existing firmware waveform checks.
    reg [23:0] image [0:1023];
    reg signed [7:0] w1 [0:107], w2 [0:143], w3 [0:143], wf [0:15];
    reg signed [7:0] c1 [0:3599], p1 [0:899];
    reg signed [7:0] c2 [0:675], p2 [0:143];
    reg signed [7:0] c3 [0:63], p3 [0:15];

    initial begin
        $readmemh("conv1_rgb_weight.mem",w1);
        $readmemh("conv2_weight.mem",w2);
        $readmemh("conv3_weight.mem",w3);
        $readmemh("fc_weight.mem",wf);
    end

    function [7:0] normalize;
        input [7:0] v;
        begin
            // Exact floor(v*16/255), including the endpoint 255 -> 16.
            normalize = (v == 8'hff) ? 8'd16 : {4'b0,v[7:4]};
        end
    endfunction
    function [7:0] qrelu;
        input signed [31:0] v;
        begin
            if (v[31]) qrelu=0;
            else if (|v[30:11]) qrelu=127;
            else qrelu={1'b0,v[10:4]};
        end
    endfunction

    wire [4:0] conv_last = st==C1 ? 5'd29 : st==C2 ? 5'd12 : 5'd3;
    wire [11:0] conv_width = st==C1 ? 12'd32 : st==C2 ? 12'd15 : 12'd6;
    wire [11:0] conv_plane = st==C2 ? 12'd225 : st==C3 ? 12'd36 : 12'd0;
    wire [4:0] pool_last = st==P1 ? 5'd14 : st==P2 ? 5'd5 : 5'd1;
    wire [11:0] pool_width = st==P1 ? 12'd30 : st==P2 ? 12'd13 : 12'd4;
    wire [11:0] pool_plane = st==P1 ? 12'd900 : st==P2 ? 12'd169 : 12'd16;
    wire [11:0] pool_offset = pk[1] ? (pool_width + {11'b0,pk[0]}) : {11'b0,pk[0]};

    always @(posedge clk) begin
        if (rst) begin
            st<=CAP; phase<=0; pix<=0; n<=0; k<=0; pk<=0; fi<=0;
            x<=0; y<=0; oc<=0; ic<=0; kx<=0; ky<=0;
            row_base<=0; channel_base<=0; kernel_row<=0;
            weight_base<=0; weight_addr<=0; read_addr<=0; raw_pixel<=0;
            sample<=0; layer_sample<=0; weight_value<=0; product<=0;
            acc<=0; total<=0; quantized<=0; pool_sample<=0; pmax<=0;
            pixel_ready<=1; result_valid<=0; classification<=0;
        end else begin
            result_valid<=0;
            case (st)
                CAP: begin
                    pixel_ready<=1;
                    if (pixel_valid && pixel_ready) begin
                        image[pix]<=pixel_data;
                        if (pix==1023) begin
                            pix<=0; pixel_ready<=0; st<=C1; phase<=0;
                            n<=0; k<=0; acc<=0; x<=0; y<=0; oc<=0;
                            ic<=0; kx<=0; ky<=0; row_base<=0;
                            channel_base<=0; kernel_row<=0; weight_base<=0;
                        end else pix<=pix+1'b1;
                    end
                end
                C1,C2,C3: begin
                    case (phase)
                        0: begin
                            read_addr<=channel_base+row_base+{7'b0,x}+kernel_row+{10'b0,kx};
                            weight_addr<=weight_base+{2'b0,k};
                            phase<=1;
                        end
                        1: begin
                            if (st==C1) begin
                                raw_pixel<=image[read_addr[9:0]];
                                weight_value<=w1[weight_addr];
                            end else if (st==C2) begin
                                layer_sample<=p1[read_addr[9:0]];
                                weight_value<=w2[weight_addr];
                            end else begin
                                layer_sample<=p2[read_addr[7:0]];
                                weight_value<=w3[weight_addr];
                            end
                            phase<=2;
                        end
                        2: begin
                            if (st==C1) begin
                                case (ic)
                                    0: sample<=normalize(raw_pixel[23:16]);
                                    1: sample<=normalize(raw_pixel[15:8]);
                                    default: sample<=normalize(raw_pixel[7:0]);
                                endcase
                            end else sample<=layer_sample;
                            phase<=3;
                        end
                        3: begin product<=$signed(sample)*$signed(weight_value); phase<=4; end
                        4: begin total<=acc+{{16{product[15]}},product}; phase<=5; end
                        5: begin
                            if (k==((st==C1)?6'd26:6'd35)) begin
                                quantized<=qrelu(total); phase<=6;
                            end else begin
                                acc<=total; k<=k+1'b1; phase<=0;
                                if (kx==2) begin
                                    kx<=0;
                                    if (ky==2) begin
                                        ky<=0; kernel_row<=0; ic<=ic+1'b1;
                                        channel_base<=channel_base+conv_plane;
                                    end else begin
                                        ky<=ky+1'b1; kernel_row<=kernel_row+conv_width;
                                    end
                                end else kx<=kx+1'b1;
                            end
                        end
                        6: begin
                            if (st==C1) c1[n]<=quantized;
                            else if (st==C2) c2[n[9:0]]<=quantized;
                            else c3[n[5:0]]<=quantized;
                            acc<=0; k<=0; ic<=0; kx<=0; ky<=0;
                            channel_base<=0; kernel_row<=0; phase<=0;
                            if ((st==C1 && n==3599) || (st==C2 && n==675) || (st==C3 && n==63)) begin
                                st<=st+1'b1; n<=0; pk<=0; x<=0; y<=0;
                                oc<=0; row_base<=0; weight_base<=0; pmax<=0;
                            end else begin
                                n<=n+1'b1;
                                if (x==conv_last) begin
                                    x<=0;
                                    if (y==conv_last) begin
                                        y<=0; oc<=oc+1'b1; row_base<=0;
                                        weight_base<=weight_base+((st==C1)?8'd27:8'd36);
                                    end else begin y<=y+1'b1; row_base<=row_base+conv_width; end
                                end else x<=x+1'b1;
                            end
                        end
                        default: phase<=0;
                    endcase
                end
                P1,P2,P3: begin
                    case (phase)
                        0: begin
                            read_addr<=channel_base+row_base+{6'b0,x,1'b0}+pool_offset;
                            phase<=1;
                        end
                        1: begin
                            if (st==P1) pool_sample<=c1[read_addr];
                            else if (st==P2) pool_sample<=c2[read_addr[9:0]];
                            else pool_sample<=c3[read_addr[5:0]];
                            phase<=2;
                        end
                        2: begin
                            if (pk==0 || $signed(pool_sample)>$signed(pmax)) pmax<=pool_sample;
                            phase<=3;
                        end
                        3: begin
                            phase<=0;
                            if (pk==3) begin
                                if (st==P1) p1[n[9:0]]<=pmax;
                                else if (st==P2) p2[n[7:0]]<=pmax;
                                else p3[n[3:0]]<=pmax;
                                pk<=0;
                                if ((st==P1 && n==899) || (st==P2 && n==143) || (st==P3 && n==15)) begin
                                    st<=st+1'b1; n<=0; k<=0; fi<=0; acc<=0;
                                    x<=0; y<=0; oc<=0; ic<=0; kx<=0; ky<=0;
                                    row_base<=0; channel_base<=0; kernel_row<=0; weight_base<=0;
                                end else begin
                                    n<=n+1'b1;
                                    if (x==pool_last) begin
                                        x<=0;
                                        if (y==pool_last) begin
                                            y<=0; oc<=oc+1'b1; row_base<=0;
                                            channel_base<=channel_base+pool_plane;
                                        end else begin
                                            y<=y+1'b1; row_base<=row_base+(pool_width<<1);
                                        end
                                    end else x<=x+1'b1;
                                end
                            end else pk<=pk+1'b1;
                        end
                        default: phase<=0;
                    endcase
                end
                FC: begin
                    case (phase)
                        0: begin
                            // Pixel-major weights, channel-major pooled data.
                            read_addr<={8'b0,fi[1:0],fi[3:2]}; phase<=1;
                        end
                        1: begin layer_sample<=p3[read_addr[3:0]]; weight_value<=wf[fi[3:0]]; phase<=2; end
                        2: begin sample<=layer_sample; phase<=3; end
                        3: begin product<=$signed(sample)*$signed(weight_value); phase<=4; end
                        4: begin total<=acc+{{16{product[15]}},product}; phase<=5; end
                        5: begin
                            phase<=0;
                            if (fi==15) begin
                                classification<=!total[31]; result_valid<=1; st<=DONE;
                            end else begin acc<=total; fi<=fi+1'b1; end
                        end
                        default: phase<=0;
                    endcase
                end
                DONE: begin pixel_ready<=1; pix<=0; st<=CAP; end
                default: begin st<=CAP; phase<=0; end
            endcase
        end
    end
endmodule
