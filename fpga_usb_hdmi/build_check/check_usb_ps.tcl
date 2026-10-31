# Exercise the real Vivado PS IP without modifying the user's project.
set check_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $check_dir .. ..]]
create_project -in_memory -part xc7z020clg400-1
create_bd_design usb_ps_check
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7
source [file join $repo_dir SOC_HUFLIT_2026_parallel_50MHz SOC_HUFLIT_2026.srcs sources_1 new pynq_z2_usb_ps.tcl]
configure_pynq_z2_usb ps7
configure_pynq_z2_usb ps7
foreach {property expected} {
    PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V}
    PCW_USB0_PERIPHERAL_ENABLE 1
    PCW_USB0_USB0_IO {MIO 28 .. 39}
    PCW_USB0_RESET_ENABLE 1
    PCW_USB0_RESET_IO {MIO 46}
    PCW_USB_RESET_POLARITY {Active Low}
} {
    set actual [get_property CONFIG.$property [get_bd_cells ps7]]
    if {$actual ne $expected} {error "$property: expected $expected, got $actual"}
}
puts "USB_PS_CONFIG_CHECK_PASS"
close_project
