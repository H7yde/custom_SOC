# Run in the Tcl Console of the OPEN project after `py firmware/build.py`.
set fw_repo [file dirname [file dirname [file normalize [info script]]]]
set fw_image [file join $fw_repo SOC_HUFLIT_2026_parallel_50MHz \
    SOC_HUFLIT_2026.srcs sources_1 new firmware.hex]
if {![file exists $fw_image]} { error "Build firmware first: py firmware/build.py" }
foreach fw_rtl_name {picorv32_axi4_bram_adapter.v axi4_bram_slave.v} {
    set fw_rtl [file join [file dirname $fw_image] $fw_rtl_name]
    if {[llength [get_files -quiet $fw_rtl]] == 0} {
        add_files -fileset sources_1 -norecurse $fw_rtl
    }
}
if {[llength [get_files -quiet $fw_image]] == 0} {
    add_files -fileset sources_1 -norecurse $fw_image
}
set_property file_type {Memory Initialization Files} [get_files $fw_image]
set_property used_in_synthesis true [get_files $fw_image]
set_property used_in_simulation true [get_files $fw_image]
update_compile_order -fileset sources_1
puts "BRAM image registered: $fw_image"
puts "Use firmware/sim/run.ps1 to simulate the CPU; tb_CNN does not instantiate it."
