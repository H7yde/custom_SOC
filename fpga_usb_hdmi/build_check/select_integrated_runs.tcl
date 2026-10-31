set select_repo [file normalize [file join [file dirname [info script]] .. ..]]
set select_projects [glob -nocomplain [file join $select_repo SOC_HUFLIT_2026_parallel_* SOC_HUFLIT_2026.xpr]]
if {[llength $select_projects] != 1} {error "Expected one active project"}
open_project [lindex $select_projects 0]
source [file join $select_repo fpga_usb_hdmi integrate_soc_top.tcl]
puts "CURRENT_SYNTHESIS=[current_run -synthesis]"
puts "CURRENT_IMPLEMENTATION=[current_run -implementation]"
close_project
exit
