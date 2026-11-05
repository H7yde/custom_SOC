# Shared project resolver. Fail on ambiguity rather than selecting an old copy.
namespace eval soc_paths {
    variable root [file dirname [file dirname [file normalize [info script]]]]
    proc project {} {
        variable root
        set matches [glob -nocomplain -types f [file join $root SOC_HUFLIT_2026_parallel_* SOC_HUFLIT_2026.xpr]]
        if {[llength $matches] != 1} {
            error "Expected exactly one SoC .xpr under $root; found [llength $matches]"
        }
        return [file dirname [file normalize [lindex $matches 0]]]
    }
}
