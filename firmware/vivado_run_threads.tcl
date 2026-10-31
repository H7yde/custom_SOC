# Applied inside each launched Vivado process.
set_param general.maxThreads 2

# This hook is also present in older GUI sessions. Add the bridge from disk
# before the run script reads HDL, even if that GUI lost the new source entry.
if {[llength [current_project -quiet]] &&
    [get_param synth.vivado.isSynthRun] &&
    ![get_param project.vivado.isBlockSynthRun]} {
    set bridge_hook_repo [file dirname [file dirname [file normalize [info script]]]]
    set bridge_hook_files [glob -nocomplain [file join $bridge_hook_repo SOC_HUFLIT_2026_parallel_* SOC_HUFLIT_2026.srcs sources_1 new cnn_axi_bridge.v]]
    if {[llength $bridge_hook_files] == 1} {
        set bridge_hook_rtl [file normalize [lindex $bridge_hook_files 0]]
        if {![llength [get_files -quiet $bridge_hook_rtl]]} {
            add_files -norecurse $bridge_hook_rtl
        }
        set_property USED_IN_SYNTHESIS true [get_files $bridge_hook_rtl]
        puts "ARM_CNN_SOURCE_GUARD_PASS: $bridge_hook_rtl"
    }
}

# H16 drives the SoC directly at 125 MHz. A stale GUI session can otherwise
# regenerate a run with CLK_FREQ=100000000 and an illegal 125 MHz x10 MMCM.
if {[llength [current_project -quiet]] &&
    [get_property DESIGN_MODE [current_fileset]] eq {RTL}} {
    foreach soc_clock_generic [get_property GENERIC [current_fileset]] {
        if {[regexp {^CLK_FREQ=(.+)$} $soc_clock_generic -> soc_clock_frequency] &&
            [string map {_ {}} $soc_clock_frequency] ne {125000000}} {
            error "Clock mismatch: H16 is 125 MHz but CLK_FREQ=$soc_clock_frequency. Source firmware/select_timing_constraints_125MHz.tcl in the OPEN Vivado project, then rebuild."
        }
    }
    unset -nocomplain soc_clock_generic soc_clock_frequency
}
