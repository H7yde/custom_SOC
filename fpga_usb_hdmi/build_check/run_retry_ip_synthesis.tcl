set retry_repo [file normalize [file join [file dirname [info script]] .. ..]]
set retry_projects [glob -nocomplain [file join $retry_repo SOC_HUFLIT_2026_parallel_* SOC_HUFLIT_2026.xpr]]
if {[llength $retry_projects] != 1} {error "Expected exactly one active project"}
open_project [lindex $retry_projects 0]
source [file join $retry_repo fpga_usb_hdmi retry_ip_synthesis.tcl]
close_project
exit
