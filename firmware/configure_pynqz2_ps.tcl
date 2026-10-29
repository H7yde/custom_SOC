# Compatibility entry point. The current design uses H16 directly at 125 MHz.
source [file join [file dirname [file normalize [info script]]] select_timing_constraints_125MHz.tcl]
