set bridge_repo [file normalize [file join [file dirname [info script]] .. ..]]
set bridge_projects [glob -nocomplain [file join $bridge_repo SOC_HUFLIT_2026_parallel_* SOC_HUFLIT_2026.xpr]]
if {[llength $bridge_projects] != 1} {error "Expected one SoC project"}
open_project [lindex $bridge_projects 0]
source [file join $bridge_repo fpga_usb_hdmi add_arm_cnn_bridge.tcl]
close_project
exit
