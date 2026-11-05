# Isolated synthesis check: does not mutate the user's open Vivado project.
set root [file normalize [file join [file dirname [info script]] ../..]]
source [file join $root firmware project_paths.tcl]
set rtl [file join [soc_paths::project] SOC_HUFLIT_2026.srcs sources_1 new]
set_param general.maxThreads 2
create_project -in_memory -part xc7z020clg400-1
foreach f [glob [file join $rtl *.v]] {read_verilog $f}
foreach f [glob [file join $rtl *.mem]] {add_files -norecurse $f}
synth_design -top soc_top -part xc7z020clg400-1 -generic ENABLE_USB_HDMI=0 -mode out_of_context
if {![llength [get_cells -hierarchical -filter {NAME =~ *u_arm_cnn_bridge*}]]} {error "Missing bridge"}
report_utilization -file [file join $root fpga_usb_hdmi build_check recovery_utilization.rpt]
puts "RECOVERY_SOC_SYNTHESIS_PASS"
close_project
exit
