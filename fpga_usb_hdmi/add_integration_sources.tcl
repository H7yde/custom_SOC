# Run only inside a NEW integration project, after creating the real BD.
# This script does not change the original SoC project or generate dummy IP.
set integration_dir [file dirname [file normalize [info script]]]
set integration_shells [glob -nocomplain [file join $integration_dir .. SOC_HUFLIT_2026_parallel_* SOC_HUFLIT_2026.srcs sources_1 new soc_usb_hdmi_top.v]]
if {[llength $integration_shells] != 1} {
    error "Expected one SoC source tree containing soc_usb_hdmi_top.v."
}
set integration_rtl_dir [file dirname [file normalize [lindex $integration_shells 0]]]
if {[llength [get_projects -quiet]] == 0} {
    error "Open the PYNQ-Z2 integration project first."
}
if {[get_property PART [current_project]] ne "xc7z020clg400-1"} {
    error "Expected PYNQ-Z2 part xc7z020clg400-1."
}
set integration_bd [get_files -quiet */usb_hdmi_system.bd]
if {[llength $integration_bd] != 1} {
    error "Create usb_hdmi_system.bd according to README.md first. No stub will be generated."
}
open_bd_design $integration_bd
set integration_ps [get_bd_cells -quiet -hierarchical -filter {VLNV =~ "xilinx.com:ip:processing_system7:*"}]
if {[llength $integration_ps] != 1} {
    error "usb_hdmi_system must contain exactly one Zynq PS cell."
}
source [file join $integration_rtl_dir pynq_z2_usb_ps.tcl]
configure_pynq_z2_usb $integration_ps
validate_bd_design
save_bd_design
generate_target all $integration_bd
add_files -norecurse [file join $integration_rtl_dir soc_usb_hdmi_top.v]
add_files -fileset constrs_1 -norecurse [file join $integration_dir pynq_z2_hdmi_out.xdc]
set_property top soc_usb_hdmi_top [current_fileset]
update_compile_order -fileset sources_1
puts "Sources added. Review BD ports, clocks, address map and timing before building."

