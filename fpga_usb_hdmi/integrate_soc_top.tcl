# Apply the combined PicoRV32/CNN + Zynq USB/HDMI top in an open project.
if {![llength [current_project -quiet]]} {error "Open SOC_HUFLIT_2026.xpr first."}
if {[get_property PART [current_project]] ne {xc7z020clg400-1}} {error "Expected PYNQ-Z2 xc7z020clg400-1."}
set soc_integration_bd [get_files -quiet */usb_hdmi_system.bd]
if {[llength $soc_integration_bd] != 1} {error "Expected usb_hdmi_system.bd in this project."}
set soc_integration_top [get_files -quiet */new/soc_top.v]
if {[llength $soc_integration_top] != 1} {error "Expected exactly one soc_top.v."}
set soc_integration_xdc [get_files -quiet -of_objects [get_filesets constrs_1] */soc_top.xdc]
if {[llength $soc_integration_xdc] != 1} {error "Expected combined soc_top.xdc in constrs_1."}
open_bd_design $soc_integration_bd
set soc_integration_bridge [file join [file dirname [file normalize [info script]]] add_arm_cnn_bridge.tcl]
if {[file exists $soc_integration_bridge]} {source $soc_integration_bridge}
validate_bd_design
set soc_integration_generics {}
foreach soc_integration_generic [get_property GENERIC [get_filesets sources_1]] {
    if {![string match {ENABLE_USB_HDMI=*} $soc_integration_generic]} {
        lappend soc_integration_generics $soc_integration_generic
    }
}
lappend soc_integration_generics ENABLE_USB_HDMI=1
set_property GENERIC $soc_integration_generics [get_filesets sources_1]
set_property TOP soc_top [get_filesets sources_1]
set_property TARGET_CONSTRS_FILE $soc_integration_xdc [get_filesets constrs_1]
update_compile_order -fileset sources_1
if {![llength [get_runs -quiet synth_soc_usb_hdmi]]} {
    create_run synth_soc_usb_hdmi -flow {Vivado Synthesis 2025} -strategy {Vivado Synthesis Defaults} -constrset constrs_1
}
if {![llength [get_runs -quiet impl_soc_usb_hdmi]]} {
    create_run impl_soc_usb_hdmi -parent_run synth_soc_usb_hdmi -flow {Vivado Implementation 2025} -strategy {Vivado Implementation Defaults} -constrset constrs_1
}
current_run -synthesis [get_runs synth_soc_usb_hdmi]
current_run -implementation [get_runs impl_soc_usb_hdmi]
puts "SOC_TOP_USB_HDMI_INTEGRATION_APPLIED"
puts "Rebuild synthesis and implementation; ARM software must initialize PS, VTC and VDMA."
