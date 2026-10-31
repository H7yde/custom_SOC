set repair_repository [file normalize [file join [file dirname [info script]] .. ..]]
set repair_projects [glob -nocomplain [file join $repair_repository SOC_HUFLIT_2026_parallel_* SOC_HUFLIT_2026.xpr]]
if {[llength $repair_projects] != 1} {error "Expected one active SoC project"}
open_project [lindex $repair_projects 0]
source -notrace [file join $repair_repository fpga_usb_hdmi repair_usb_hdmi.tcl]
close_project
