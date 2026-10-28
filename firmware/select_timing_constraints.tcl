# Source in the OPEN SoC Vivado project's Tcl Console.
# Create/select the 100 MHz constraint set; keep other sets/files intact.
# No synthesis/implementation run is reset or launched by this script.
set timing_repo [file dirname [file dirname [file normalize [info script]]]]
set timing_dir [file join $timing_repo SOC_HUFLIT_2026_parallel_50MHz \
    SOC_HUFLIT_2026.srcs constrs_1 new]
set timing_original [file normalize [file join $timing_dir soc_top.xdc]]
set timing_board [file normalize [file join $timing_dir soc_top_board.xdc]]
set timing_fixed [file normalize [file join $timing_dir soc_top_100MHz.xdc]]
set timing_set_name constrs_100MHz

if {[llength [current_project -quiet]] == 0} {
    error {Open the SoC Vivado project first.}
}
if {![file exists $timing_fixed]} { error "Missing XDC: $timing_fixed" }
if {![file exists $timing_board]} { error "Missing board XDC: $timing_board" }
set timing_synth [get_runs -quiet synth_1]
set timing_impl [get_runs -quiet impl_1]
if {[llength $timing_synth] != 1 || [llength $timing_impl] != 1} {
    error {Expected the SoC project with synth_1 and impl_1 runs.}
}

set timing_previous [get_property CONSTRSET $timing_synth]
set timing_new_set [get_filesets -quiet $timing_set_name]
if {[llength $timing_new_set] == 0} {
    # Keep any separate board/pin constraints from the existing set as references.
    # The old timing XDC is replaced only in the NEW set, not changed on disk.
    set timing_old_set [get_filesets $timing_previous]
    set timing_new_set [create_fileset -constrset -clone_properties $timing_old_set $timing_set_name]
    foreach timing_file [get_files -quiet -of_objects $timing_old_set] {
        set timing_path [file normalize $timing_file]
        if {![string equal -nocase $timing_path $timing_original] &&
            ![string equal -nocase $timing_path $timing_fixed]} {
            add_files -fileset $timing_new_set -norecurse $timing_path
        }
    }
}
set timing_has_fixed 0
set timing_has_board 0
foreach timing_file [get_files -quiet -of_objects $timing_new_set] {
    set timing_path [file normalize $timing_file]
    if {[string equal -nocase $timing_path $timing_original]} {
        error {The new set already contains soc_top.xdc. Remove it from that set before selecting the replacement.}
    }
    if {[string equal -nocase $timing_path $timing_fixed]} { set timing_has_fixed 1 }
    if {[string equal -nocase $timing_path $timing_board]} { set timing_has_board 1 }
}
if {!$timing_has_board} {
    add_files -fileset $timing_new_set -norecurse $timing_board
}
if {!$timing_has_fixed} {
    add_files -fileset $timing_new_set -norecurse $timing_fixed
}
set_property -name TARGET_CONSTRS_FILE -value $timing_fixed -objects $timing_new_set
set_property -name CONSTRSET -value $timing_set_name -objects $timing_synth
set_property -name CONSTRSET -value $timing_set_name -objects $timing_impl
set timing_generics {}
foreach timing_generic [get_property GENERIC [get_filesets sources_1]] {
    if {![string match {CLK_FREQ=*} $timing_generic] &&
        ![string match {DDR_TX_PHASED_CLOCK=*} $timing_generic]} {
        lappend timing_generics $timing_generic
    }
}
lappend timing_generics CLK_FREQ=100000000 DDR_TX_PHASED_CLOCK=1
set_property -name GENERIC -value $timing_generics -objects [get_filesets sources_1]

puts "Selected $timing_set_name for synth_1 and impl_1."
puts "XDC: $timing_fixed"
puts "Previous synthesis constraint set: $timing_previous (retained)."
puts {Re-run synthesis and implementation to obtain new timing results.}
puts {CNN timing violations and unspecified board I/O requirements still need separate work.}
