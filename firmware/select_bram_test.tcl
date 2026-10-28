# Run in the OPEN Vivado project's Tcl Console, then relaunch simulation.
# Selects the BRAM-only firmware and its matching testbench.
set bram_fw_dir [file dirname [file normalize [info script]]]
set bram_repo [file dirname $bram_fw_dir]
set bram_image [file join $bram_fw_dir bram_test.hex]
set bram_design_image [file join $bram_repo SOC_HUFLIT_2026_parallel_50MHz \
    SOC_HUFLIT_2026.srcs sources_1 new firmware.hex]
set bram_tb [file join $bram_fw_dir sim tb_bram_firmware.v]
if {![file exists $bram_image]} {
    error "Build first: py firmware/build.py --app bram --no-deploy"
}
if {![file exists $bram_tb]} { error "BRAM testbench missing: $bram_tb" }
set bram_simset [current_fileset -simset]
if {[llength $bram_simset] == 0} { error "Open the SoC Vivado project first" }
# Keep the original Sources hierarchy (testbench -> dut -> child instances).
# SOURCE_MGMT_MODE=None disables automatic hierarchy refresh.
set_property -name source_mgmt_mode -value DisplayOnly -objects [current_project]
foreach bram_rtl_name {picorv32_axi4_bram_adapter.v axi4_bram_slave.v} {
    set bram_rtl [file join [file dirname $bram_design_image] $bram_rtl_name]
    if {[llength [get_files -quiet $bram_rtl]] == 0} {
        add_files -fileset sources_1 -norecurse $bram_rtl
    }
}
file copy -force $bram_image $bram_design_image
if {[llength [get_files -quiet $bram_design_image]] == 0} {
    add_files -fileset sources_1 -norecurse $bram_design_image
}
set_property -name FILE_TYPE -value {Memory Initialization Files} \
    -objects [get_files $bram_design_image]
set_property -name USED_IN_SYNTHESIS -value true -objects [get_files $bram_design_image]
set_property -name USED_IN_SIMULATION -value true -objects [get_files $bram_design_image]
if {[llength [get_files -quiet $bram_tb]] == 0} {
    add_files -fileset $bram_simset -norecurse $bram_tb
}
set_property -name FILE_TYPE -value SystemVerilog -objects [get_files $bram_tb]
set_property -name TOP -value tb_bram_firmware -objects $bram_simset
set_property -name xsim.simulate.xsim.more_options -value {} -objects $bram_simset
set_property -name xsim.simulate.runtime -value all -objects $bram_simset
# All design modules are explicitly registered; no SystemVerilog packages or
# include-order dependencies need a hierarchy scan here. Avoid launching the
# source scanner just to select the test (it can fail to spawn in a GUI session).
# If a GUI session cannot spawn its source scanner, restart that session or use
# run_bram.ps1 directly. Keep DisplayOnly so Sources retains its module tree.
puts "Selected BRAM-only firmware, AXI4 BRAM RTL and tb_bram_firmware."
puts "Close any old simulation, then Run Behavioral Simulation / Run All."
puts {Expected: BRAM FIRMWARE PASS; report at dut.bram[512..520].}
