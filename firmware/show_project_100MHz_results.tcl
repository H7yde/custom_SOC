# Open the existing 100 MHz implementation without launching another run.
set show100_repo [file dirname [file dirname [file normalize [info script]]]]
if {[llength [current_project -quiet]] != 1 ||
    ![string equal -nocase [file normalize [get_property DIRECTORY [current_project]]] \
        [file normalize [file join $show100_repo SOC_HUFLIT_2026_parallel_50MHz]]]} {
    error {Open the original SOC_HUFLIT_2026 project first.}
}
set show100_run [get_runs -quiet impl_100MHz]
if {[llength $show100_run] != 1 ||
    [get_property PROGRESS $show100_run] ne {100%} ||
    ![string match {route_design Complete*} [get_property STATUS $show100_run]]} {
    error {Wait for impl_100MHz to finish routing before opening its results.}
}
if {[get_property NEEDS_REFRESH $show100_run]} {
    error {impl_100MHz is out of date; inspect its sources and settings first.}
}
set show100_output [file join $show100_repo firmware build project_100MHz impl_100MHz]
file mkdir $show100_output
set show100_status [open [file join $show100_output show_results.log] a]
puts $show100_status "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] OPEN_LATEST_ROUTED_DESIGN"
close $show100_status
if {[llength [current_design -quiet]]} { close_design }
open_run impl_100MHz
report_route_status -file [file join $show100_output route_status.rpt]
report_clocks -file [file join $show100_output clocks.rpt]
check_timing -verbose -file [file join $show100_output check_timing.rpt]
report_drc -file [file join $show100_output drc.rpt]
report_timing_summary -name timing_100MHz_latest_[clock seconds] -delay_type min_max \
    -max_paths 10 -report_unconstrained -file [file join $show100_output timing_routed.rpt]
set show100_wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set show100_whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set show100_status [open [file join $show100_output show_results.log] a]
puts $show100_status "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] LATEST_RESULT WNS=$show100_wns WHS=$show100_whs DONE"
close $show100_status
puts "LATEST_PROJECT_IMPLEMENTATION_RESULT WNS=$show100_wns WHS=$show100_whs"
