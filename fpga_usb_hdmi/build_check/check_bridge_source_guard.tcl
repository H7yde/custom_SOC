# Reproduce a stale run with no bridge in its initial source list.
set guard_repo [file normalize [file join [file dirname [info script]] .. ..]]
create_project -in_memory -part xc7z020clg400-1
set_param synth.vivado.isSynthRun true
set_param project.vivado.isBlockSynthRun false
if {[llength [get_files -quiet *cnn_axi_bridge.v]]} {error "Expected initially missing source"}
source [file join $guard_repo firmware vivado_run_threads.tcl]
if {[llength [get_files -quiet *cnn_axi_bridge.v]] != 1} {error "Source guard did not restore bridge"}
synth_design -top cnn_axi_bridge -part xc7z020clg400-1 -mode out_of_context
puts "ARM_CNN_SOURCE_GUARD_SYNTH_PASS"
close_project
exit
