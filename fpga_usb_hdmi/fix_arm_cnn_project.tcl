# Source in the SAME Vivado GUI that reported the missing module.
# Restores the source entry and retries IPs sequentially; does not program FPGA.
if {![llength [current_project -quiet]]} {error "Open SOC_HUFLIT_2026.xpr first"}
set bridge_fix_dir [file dirname [file normalize [info script]]]
set bridge_fix_repo [file dirname $bridge_fix_dir]
set bridge_fix_project [file normalize [get_property DIRECTORY [current_project]]]
if {![string equal -nocase [file dirname $bridge_fix_project] $bridge_fix_repo]} {
    error "Open the project under $bridge_fix_repo"
}
set bridge_fix_rtl [file join $bridge_fix_project [get_property NAME [current_project]].srcs sources_1 new cnn_axi_bridge.v]
if {![file isfile $bridge_fix_rtl]} {error "Bridge source missing on disk: $bridge_fix_rtl"}
if {![llength [get_files -quiet $bridge_fix_rtl]]} {add_files -fileset sources_1 -norecurse $bridge_fix_rtl}
set_property FILE_TYPE Verilog [get_files $bridge_fix_rtl]
set_property USED_IN_SYNTHESIS true [get_files $bridge_fix_rtl]
set_property USED_IN_SIMULATION true [get_files $bridge_fix_rtl]
source [file join $bridge_fix_dir integrate_soc_top.tcl]
create_ip_run [get_files */usb_hdmi_system.bd]
set bridge_fix_hook [file join $bridge_fix_repo firmware vivado_run_threads.tcl]
foreach bridge_fix_run {synth_h16_core125_2 synth_soc_usb_hdmi} {
    if {[llength [get_runs -quiet $bridge_fix_run]]} {
        set_property STEPS.SYNTH_DESIGN.TCL.PRE $bridge_fix_hook [get_runs $bridge_fix_run]
    }
}
update_compile_order -fileset sources_1
source [file join $bridge_fix_dir retry_ip_synthesis.tcl]
puts "ARM_CNN_PROJECT_FIX_PASS"
puts "Source registered: [get_files $bridge_fix_rtl]"
puts "Current synthesis: [current_run -synthesis]"
puts "Current implementation: [current_run -implementation]"
puts "Build with: launch_runs synth_soc_usb_hdmi -jobs 1"
