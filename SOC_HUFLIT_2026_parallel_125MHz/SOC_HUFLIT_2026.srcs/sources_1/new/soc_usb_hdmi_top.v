`timescale 1ns/1ps
// Wrapper for the real Vivado Block Design usb_hdmi_system.
// PYNQ-Z2 DDR controller uses x16 mode. Vivado's PS7 hard-interface wrapper
// still exposes 32 DQ / 4 DM,DQS signals; keep these widths as generated.
// Camera/display software runs on ARM/Linux.
// The ARM/PicoRV32 CNN bridge is not part of this wrapper yet.
// USB host uses PS MIO through FIXED_IO, not PL USB D+/D- pins.
// USB setup: source pynq_z2_usb_ps.tcl in Vivado and call
// configure_pynq_z2_usb processing_system7_0 in usb_hdmi_system.bd.
// USB0 ULPI occupies FIXED_IO_mio[39:28], PHY reset uses MIO 46.
// Run fpga_usb_hdmi/add_integration_sources.tcl to apply this automatically.
// See fpga_usb_hdmi/README.md for the Block Design connection contract.
module soc_usb_hdmi_top (
    inout wire [14:0] DDR_addr,
    inout wire [2:0]  DDR_ba,
    inout wire        DDR_cas_n,
    inout wire        DDR_ck_n,
    inout wire        DDR_ck_p,
    inout wire        DDR_cke,
    inout wire        DDR_cs_n,
    inout wire [3:0]  DDR_dm,
    inout wire [31:0] DDR_dq,
    inout wire [3:0]  DDR_dqs_n,
    inout wire [3:0]  DDR_dqs_p,
    inout wire        DDR_odt,
    inout wire        DDR_ras_n,
    inout wire        DDR_reset_n,
    inout wire        DDR_we_n,
    inout wire        FIXED_IO_ddr_vrn,
    inout wire        FIXED_IO_ddr_vrp,
    inout wire [53:0] FIXED_IO_mio,
    inout wire        FIXED_IO_ps_clk,
    inout wire        FIXED_IO_ps_porb,
    inout wire        FIXED_IO_ps_srstb,
    output wire        hdmi_tx_clk_p,
    output wire        hdmi_tx_clk_n,
    output wire [2:0]  hdmi_tx_d_p,
    output wire [2:0]  hdmi_tx_d_n,
    input wire        hdmi_tx_hpdn
);
    usb_hdmi_system u_system (
        .DDR_addr(DDR_addr),
        .DDR_ba(DDR_ba),
        .DDR_cas_n(DDR_cas_n),
        .DDR_ck_n(DDR_ck_n),
        .DDR_ck_p(DDR_ck_p),
        .DDR_cke(DDR_cke),
        .DDR_cs_n(DDR_cs_n),
        .DDR_dm(DDR_dm),
        .DDR_dq(DDR_dq),
        .DDR_dqs_n(DDR_dqs_n),
        .DDR_dqs_p(DDR_dqs_p),
        .DDR_odt(DDR_odt),
        .DDR_ras_n(DDR_ras_n),
        .DDR_reset_n(DDR_reset_n),
        .DDR_we_n(DDR_we_n),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio(FIXED_IO_mio),
        .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        .hdmi_tx_clk_p(hdmi_tx_clk_p),
        .hdmi_tx_clk_n(hdmi_tx_clk_n),
        .hdmi_tx_d_p(hdmi_tx_d_p),
        .hdmi_tx_d_n(hdmi_tx_d_n),
        .hdmi_tx_hpdn(hdmi_tx_hpdn)
    );
endmodule

