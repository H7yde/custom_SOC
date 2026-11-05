set root [file normalize [file join [file dirname [info script]] ../..]]
set output [file join $root fpga_usb_hdmi build_check timing_recovery]
open_checkpoint [file join $output soc_top_postroute.dcp]
report_bus_skew -file [file join $output bus_skew.rpt]
report_drc -file [file join $output drc.rpt]
write_bitstream -force [file join $output soc_top_timing_fixed.bit]
puts "TIMING_FIXED_BITSTREAM_PASS"
close_design
source [file join $root firmware project_paths.tcl]
open_project [file join [soc_paths::project] SOC_HUFLIT_2026.xpr]
source [file join $root fpga_usb_hdmi configure_timing_125MHz.tcl]
close_project
exit
