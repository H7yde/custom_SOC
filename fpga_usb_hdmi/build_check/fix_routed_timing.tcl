# Optimize a copy of the routed design; preserve the original run checkpoint.
set root [file normalize [file join [file dirname [info script]] ../..]]
source [file join $root firmware project_paths.tcl]
set output [file join $root fpga_usb_hdmi build_check timing_recovery]
file mkdir $output
set_param general.maxThreads 2
open_checkpoint [file join [soc_paths::project] SOC_HUFLIT_2026.runs impl_soc_usb_hdmi soc_top_routed.dcp]
phys_opt_design -directive AggressiveExplore
report_timing_summary -report_unconstrained -max_paths 10 -file [file join $output timing_summary.rpt]
report_route_status -file [file join $output route_status.rpt]
write_checkpoint -force [file join $output soc_top_postroute.dcp]
set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
puts "POST_ROUTE_RESULT setup=$setup hold=$hold"
if {$setup < 0 || $hold < 0} {error "Timing still fails; inspect timing_summary.rpt"}
puts "POST_ROUTE_TIMING_PASS"
close_design
exit
