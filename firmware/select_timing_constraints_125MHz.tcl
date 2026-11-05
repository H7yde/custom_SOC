source [file join [file dirname [file normalize [info script]]] project_paths.tcl]
# Select the PYNQ-Z2 H16 clock: all SoC logic runs directly at 125 MHz.
# The DDR forwarded-clock MMCM shifts phase without changing frequency.
if {[llength [current_project -quiet]] == 0} {
    error {Open the SOC_HUFLIT_2026 Vivado project first.}
}
set repo [file dirname [file dirname [file normalize [info script]]]]
set project_dir [file normalize [get_property DIRECTORY [current_project]]]
set expected [file normalize [file join [soc_paths::project]]]
if {![string equal -nocase $project_dir $expected]} {
    error "Wrong project is open: $project_dir"
}

# PS7 is required by the USB/HDMI block design; preserve its IP sources.

set xdc [file normalize [file join $project_dir [get_property NAME [current_project]].srcs constrs_1 new soc_top.xdc]]
if {![file exists $xdc]} { error "Missing board constraints: $xdc" }
set constrs [get_filesets constrs_1]
foreach f [get_files -quiet -of_objects $constrs] {
    if {[string equal -nocase [file extension $f] .xdc] &&
        ![string equal -nocase [file normalize $f] $xdc]} {
        remove_files -fileset constrs_1 $f
    }
}
if {![llength [get_files -quiet -of_objects $constrs $xdc]]} {
    add_files -fileset constrs_1 -norecurse $xdc
}
set_property TARGET_CONSTRS_FILE $xdc $constrs
foreach run [get_runs] { set_property CONSTRSET constrs_1 $run }

set generics {}
foreach generic [get_property GENERIC [get_filesets sources_1]] {
    if {![string match {CLK_FREQ=*} $generic] &&
        ![string match {DDR_TX_PHASED_CLOCK=*} $generic]} {
        lappend generics $generic
    }
}
lappend generics CLK_FREQ=125000000 DDR_TX_PHASED_CLOCK=1
set_property GENERIC $generics [get_filesets sources_1]
set_property top soc_top [get_filesets sources_1]
update_compile_order -fileset sources_1
puts {Clocking: board H16 input = 125 MHz; direct BUFG core clock = 125 MHz; PS7 preserved.}
