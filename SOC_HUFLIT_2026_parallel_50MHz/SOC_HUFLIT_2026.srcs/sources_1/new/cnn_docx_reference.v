`timescale 1ns/1ps

// Synthesizable sequential CNN core. One MAC is used per clock.
// Interface and memory format are kept compatible with CNN.v and the
// existing conv*_weight.mem/fc_weight.mem files.
module cnn_docx_reference(
    input wire clk, input wire rst, input wire [23:0] pixel_data,
    input wire pixel_valid, output reg pixel_ready,
    output reg result_valid, output reg classification
);
    localparam CAP=0,C1=1,P1=2,C2=3,P2=4,C3=5,P3=6,FC=7,DONE=8;
    localparam integer MACS_PER_CYCLE = 4;
    reg [3:0] st;
    reg [10:0] pix;
    reg [11:0] n;
    reg [5:0] k;
    reg [2:0] pk;
    reg [4:0] fi;
    reg signed [31:0] acc;
    reg signed [7:0] pmax;

    reg [23:0] image [0:1023];
    reg signed [7:0] w1 [0:107], w2 [0:143], w3 [0:143], wf [0:15];
    reg signed [7:0] c1 [0:3599], p1 [0:899];
    reg signed [7:0] c2 [0:675],  p2 [0:143];
    reg signed [7:0] c3 [0:63],   p3 [0:15];

    integer rem, oc, ic, x, y, kx, ky, si, wi;
    integer prem, poc, px, py;
    reg signed [7:0] sample, pool_sample, weight_value;
    reg signed [31:0] mac_sum;
    wire signed [31:0] total_next = acc + mac_sum;

    initial begin
        $readmemh("D:/LAB/custom_SOC/CNN_RTL/conv1_rgb_weight.mem",w1);
        $readmemh("D:/LAB/custom_SOC/CNN_RTL/conv2_weight.mem",w2);
        $readmemh("D:/LAB/custom_SOC/CNN_RTL/conv3_weight.mem",w3);
        $readmemh("D:/LAB/custom_SOC/CNN_RTL/fc_weight.mem",wf);
    end

    function [7:0] qrelu;
        input signed [31:0] v;
        reg signed [31:0] q;
        begin
            q=v>>>4;
            if(q<0) qrelu=0; else if(q>127) qrelu=127; else qrelu=q[7:0];
        end
    endfunction

    // Return one convolution MAC term. Four terms are accumulated per clock
    // below; the address calculation remains identical to the reference path.
    function signed [31:0] conv_product;
        input [3:0] state_value;
        input [11:0] n_value;
        input [5:0]  k_value;
        integer f_rem, f_oc, f_ic, f_x, f_y, f_kx, f_ky, f_si, f_wi;
        reg signed [7:0] f_sample, f_weight;
        begin
            f_rem=0; f_oc=0; f_ic=0; f_x=0; f_y=0;
            f_kx=0; f_ky=0; f_si=0; f_wi=0;
            f_sample=0; f_weight=0;
            if (state_value==C1) begin
                f_oc=n_value/900; f_rem=n_value%900; f_y=f_rem/30; f_x=f_rem%30;
                f_ic=k_value/9; f_rem=k_value%9; f_ky=f_rem/3; f_kx=f_rem%3;
                f_si=(f_y+f_ky)*32+f_x+f_kx;
                if(f_ic==0) f_sample=(image[f_si][23:16]*16)/255;
                else if(f_ic==1) f_sample=(image[f_si][15:8]*16)/255;
                else f_sample=(image[f_si][7:0]*16)/255;
                f_wi=f_oc*27+k_value; f_weight=w1[f_wi];
            end else if (state_value==C2) begin
                f_oc=n_value/169; f_rem=n_value%169; f_y=f_rem/13; f_x=f_rem%13;
                f_ic=k_value/9; f_rem=k_value%9; f_ky=f_rem/3; f_kx=f_rem%3;
                f_si=f_ic*225+(f_y+f_ky)*15+f_x+f_kx; f_sample=p1[f_si];
                f_wi=f_oc*36+k_value; f_weight=w2[f_wi];
            end else begin
                f_oc=n_value/16; f_rem=n_value%16; f_y=f_rem/4; f_x=f_rem%4;
                f_ic=k_value/9; f_rem=k_value%9; f_ky=f_rem/3; f_kx=f_rem%3;
                f_si=f_ic*36+(f_y+f_ky)*6+f_x+f_kx; f_sample=p2[f_si];
                f_wi=f_oc*36+k_value; f_weight=w3[f_wi];
            end
            conv_product=$signed(f_sample)*$signed(f_weight);
        end
    endfunction

    integer mac_lane;
    always @* begin
        mac_sum=0;
        if (st==C1 || st==C2 || st==C3) begin
            for (mac_lane=0; mac_lane<MACS_PER_CYCLE; mac_lane=mac_lane+1)
                if ((k + mac_lane) < ((st==C1) ? 27 : 36))
                    mac_sum = mac_sum + conv_product(st, n, k + mac_lane);
        end else if (st==FC) begin
            for (mac_lane=0; mac_lane<MACS_PER_CYCLE; mac_lane=mac_lane+1)
                if ((fi + mac_lane) < 16)
                    mac_sum = mac_sum +
                              $signed(p3[((fi+mac_lane)%4)*4+((fi+mac_lane)/4)]) *
                              $signed(wf[fi+mac_lane]);
        end
    end

    // Pooling sample address. Pooling also uses one comparison per clock.
    always @* begin
        prem=0; poc=0; px=0; py=0; pool_sample=0;
        if(st==P1) begin
            poc=n/225; prem=n%225; py=prem/15; px=prem%15;
            pool_sample=c1[poc*900+(2*py+pk/2)*30+2*px+(pk%2)];
        end else if(st==P2) begin
            poc=n/36; prem=n%36; py=prem/6; px=prem%6;
            pool_sample=c2[poc*169+(2*py+pk/2)*13+2*px+(pk%2)];
        end else if(st==P3) begin
            poc=n/4; prem=n%4; py=prem/2; px=prem%2;
            pool_sample=c3[poc*16+(2*py+pk/2)*4+2*px+(pk%2)];
        end
    end

    always @(posedge clk) begin
        if(rst) begin
            st<=CAP; pix<=0; n<=0; k<=0; pk<=0; fi<=0; acc<=0;
            pmax<=0; pixel_ready<=1; result_valid<=0; classification<=0;
        end else begin
            result_valid<=0;
            case(st)
                CAP: begin
                    pixel_ready<=1;
                    if(pixel_valid && pixel_ready) begin
                        image[pix]<=pixel_data;
                        if(pix==1023) begin pix<=0; n<=0; k<=0; acc<=0;
                            pixel_ready<=0; st<=C1;
                        end else pix<=pix+1;
                    end
                end
                C1,C2,C3: begin
                    if((k + MACS_PER_CYCLE) >= ((st==C1)?27:36)) begin
                        if(st==C1) c1[n]<=qrelu(total_next);
                        else if(st==C2) c2[n]<=qrelu(total_next);
                        else c3[n]<=qrelu(total_next);
                        acc<=0; k<=0;
                        if(st==C1) begin
                            if(n==3599) begin n<=0; pk<=0; st<=P1; end
                            else n<=n+1;
                        end else if(st==C2) begin
                            if(n==675) begin n<=0; pk<=0; st<=P2; end
                            else n<=n+1;
                        end else begin
                            if(n==63) begin n<=0; pk<=0; st<=P3; end
                            else n<=n+1;
                        end
                    end else begin acc<=total_next; k<=k+MACS_PER_CYCLE; end
                end
                P1,P2,P3: begin
                    if(pk==0) pmax<=pool_sample;
                    else if(pool_sample>pmax) pmax<=pool_sample;
                    if(pk==3) begin
                        if(st==P1) p1[n]<=pool_sample>pmax?pool_sample:pmax;
                        else if(st==P2) p2[n]<=pool_sample>pmax?pool_sample:pmax;
                        else p3[n]<=pool_sample>pmax?pool_sample:pmax;
                        pk<=0;
                        if(st==P1) begin
                            if(n==899) begin n<=0; st<=C2; end else n<=n+1;
                        end else if(st==P2) begin
                            if(n==143) begin n<=0; st<=C3; end else n<=n+1;
                        end else begin
                            if(n==15) begin fi<=0; acc<=0; st<=FC; end
                            else n<=n+1;
                        end
                    end else pk<=pk+1;
                end
                FC: begin
                    if((fi + MACS_PER_CYCLE) >= 16) begin classification<=total_next>=0; result_valid<=1;
                        pixel_ready<=0; st<=DONE;
                    end else begin acc<=total_next; fi<=fi+MACS_PER_CYCLE; end
                end
                DONE: begin
                    // Return to capture mode after the result pulse so the
                    // AXI peripheral can start another frame without reset.
                    pixel_ready<=1; pix<=0; st<=CAP;
                end
                default: st<=CAP;
            endcase
        end
    end
endmodule
