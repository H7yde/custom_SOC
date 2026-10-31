# PYNQ-Z2 HDMI OUT. Names match soc_usb_hdmi_top.v.
# Source: workspace board master pynq-z2.xdc, HDMI Tx section.
# Only pin constraints: video clock/timing must come from the real IP design.
set_property -dict {PACKAGE_PIN L16 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_clk_p}]
set_property -dict {PACKAGE_PIN L17 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_clk_n}]
set_property -dict {PACKAGE_PIN K17 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_d_p[0]}]
set_property -dict {PACKAGE_PIN K18 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_d_n[0]}]
set_property -dict {PACKAGE_PIN K19 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_d_p[1]}]
set_property -dict {PACKAGE_PIN J19 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_d_n[1]}]
set_property -dict {PACKAGE_PIN J18 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_d_p[2]}]
set_property -dict {PACKAGE_PIN H18 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_d_n[2]}]
set_property -dict {PACKAGE_PIN R19 IOSTANDARD LVCMOS33} [get_ports hdmi_tx_hpdn]
# hpdn is active-low at this board signal; adapt polarity to the video IP.
# PS DDR/MIO are configured in Zynq PS, not assigned as PL GPIO here.

