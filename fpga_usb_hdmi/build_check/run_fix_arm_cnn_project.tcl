set bridge_fix_root [file normalize [file join [file dirname [info script]] .. ..]]
set bridge_fix_projects [glob -nocomplain [file join $bridge_fix_root SOC_HUFLIT_2026_parallel_* SOC_HUFLIT_2026.xpr]]
if {[llength $bridge_fix_projects] != 1} {error "Expected one active project"}
open_project [lindex $bridge_fix_projects 0]
source [file join $bridge_fix_root fpga_usb_hdmi fix_arm_cnn_project.tcl]
close_project
exit
