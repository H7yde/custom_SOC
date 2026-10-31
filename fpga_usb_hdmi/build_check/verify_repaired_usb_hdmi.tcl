set verification_repo [file normalize [file join [file dirname [info script]] .. ..]]
set verification_projects [glob -nocomplain [file join $verification_repo SOC_HUFLIT_2026_parallel_* SOC_HUFLIT_2026.xpr]]
if {[llength $verification_projects] != 1} {error "Expected one active project"}
open_project [lindex $verification_projects 0]
set verification_bd [get_files */usb_hdmi_system.bd]
open_bd_design $verification_bd
foreach clock_port {hdmi_tx_clk_p hdmi_tx_clk_n} {
    set_property CONFIG.FREQ_HZ 25200000 [get_bd_ports $clock_port]
}
validate_bd_design
save_bd_design
set verification_ps [get_bd_cells processing_system7_0]
foreach {property expected} {
    PCW_UIPARAM_DDR_BUS_WIDTH {16 Bit}
    PCW_CRYSTAL_PERIPHERAL_FREQMHZ 50
    PCW_USE_M_AXI_GP0 1
    PCW_USE_S_AXI_HP0 1
    PCW_USE_S_AXI_GP0 0
    PCW_USB0_USB0_IO {MIO 28 .. 39}
    PCW_USB0_RESET_IO {MIO 46}
    PCW_SD0_PERIPHERAL_ENABLE 1
    PCW_UART0_PERIPHERAL_ENABLE 1
} {
    set actual [get_property CONFIG.$property $verification_ps]
    if {[string is double -strict $expected] && [string is double -strict $actual]} {
        if {abs($actual - $expected) > 0.000001} {error "Unexpected PS config $property=$actual"}
    } elseif {$actual ne $expected} {
        error "Unexpected PS config $property=$actual"
    }
}
foreach reset {reset_axi reset_pixel} {
    if {[get_property CONFIG.C_EXT_RESET_HIGH [get_bd_cells $reset]] != 0} {error "Reset polarity: $reset"}
}
set verification_wrapper [make_wrapper -files $verification_bd -top]
puts "GENERATED_WRAPPER=$verification_wrapper"
puts "USB_HDMI_REOPEN_VALIDATE_PASS"
write_bd_tcl -force [file join $verification_repo fpga_usb_hdmi build_check usb_hdmi_system_repaired_export.tcl]
close_project
