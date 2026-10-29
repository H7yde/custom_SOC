# Applied inside each launched Vivado process.
set_param general.maxThreads 4

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
