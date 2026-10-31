# USB camera hardware configuration for the PYNQ-Z2 Zynq PS.
# Source this file, then call: configure_pynq_z2_usb <PS BD cell>
# USB0 uses the onboard ULPI PHY: MIO 28..39; PHY reset: MIO 46.
# No USB D+/D- ports or PL XDC assignments are required.
# Apply AFTER the PYNQ-Z2 board preset. DDR/SD/UART/Linux remain board setup tasks.
# Reference: Xilinx/PYNQ boards/Pynq-Z2/petalinux_bsp/hardware_project/pynqz2.tcl

proc configure_pynq_z2_usb {ps_name} {
    set ps_cell [get_bd_cells -quiet $ps_name]
    if {[llength $ps_cell] != 1} {
        error "Expected one Zynq PS BD cell, got: $ps_name"
    }
    if {![string match "xilinx.com:ip:processing_system7:*" [get_property VLNV $ps_cell]]} {
        error "$ps_name is not a Zynq-7000 Processing System."
    }
    if {[get_property PART [current_project]] ne "xc7z020clg400-1"} {
        error "This USB configuration targets PYNQ-Z2 xc7z020clg400-1."
    }
    set usb_settings [list \
        CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
        CONFIG.PCW_GPIO_MIO_GPIO_ENABLE {1} \
        CONFIG.PCW_USB0_PERIPHERAL_ENABLE {1} \
        CONFIG.PCW_USB0_USB0_IO {MIO 28 .. 39} \
        CONFIG.PCW_USB0_RESET_ENABLE {1} \
        CONFIG.PCW_USB0_RESET_IO {MIO 46} \
        CONFIG.PCW_USB_RESET_POLARITY {Active Low} \
    ]
    foreach mio_index {28 29 30 31 32 33 34 35 36 37 38 39 46} {
        lappend usb_settings CONFIG.PCW_MIO_${mio_index}_IOTYPE {LVCMOS 1.8V}
    }
    # Set the bank voltage and pin types together, so PS validation sees
    # the complete PYNQ-Z2 configuration rather than a 3.3V default bank.
    set_property -dict $usb_settings $ps_cell
    foreach {usb_property usb_expected} $usb_settings {
        set usb_actual [get_property $usb_property $ps_cell]
        if {$usb_actual ne $usb_expected} {
            error "USB configuration not applied: $usb_property=$usb_actual (expected $usb_expected)"
        }
    }
    puts "PYNQ-Z2 USB0 enabled: ULPI MIO 28..39, PHY reset MIO 46."
    puts "USB reaches the top through FIXED_IO_mio. Linux USB host/UVC is required for the webcam."
}
