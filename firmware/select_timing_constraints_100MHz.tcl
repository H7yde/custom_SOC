# Source in the OPEN SoC Vivado project's Tcl Console.
# Create a separate 100 MHz constraint set; keep existing sets/files intact.
# Select the matching frequency and optional physical DDR clock phase circuit.
# No run is reset or launched by this script.
set timing100_repo [file dirname [file dirname [file normalize [info script]]]]
set timing100_dir [file join $timing100_repo SOC_HUFLIT_2026_parallel_50MHz \
    SOC_HUFLIT_2026.srcs constrs_1 new]
set timing100_board_xdc [file normalize [file join $timing100_dir soc_top_board.xdc]]
set timing100_xdc [file normalize [file join $timing100_dir soc_top_100MHz.xdc]]
set timing100_profiles {}
foreach timing100_name {soc_top.xdc soc_top_50MHz_fixed.xdc soc_top_100MHz.xdc} {
    lappend timing100_profiles [string tolower [file normalize [file join $timing100_dir $timing100_name]]]
}
set timing100_set_name constrs_100MHz

if {[llength [current_project -quiet]] == 0} {
    error {Open the SoC Vivado project first.}
}
if {![file exists $timing100_xdc]} { error "Missing XDC: $timing100_xdc" }
if {![file exists $timing100_board_xdc]} { error "Missing board XDC: $timing100_board_xdc" }
set timing100_synth [get_runs -quiet synth_1]
set timing100_impl [get_runs -quiet impl_1]
if {[llength $timing100_synth] != 1 || [llength $timing100_impl] != 1} {
    error {Expected the SoC project with synth_1 and impl_1 runs.}
}

set timing100_previous [get_property CONSTRSET $timing100_synth]
set timing100_new_set [get_filesets -quiet $timing100_set_name]
if {[llength $timing100_new_set] == 0} {
    set timing100_old_set [get_filesets $timing100_previous]
    set timing100_new_set [create_fileset -constrset -clone_properties $timing100_old_set $timing100_set_name]
    # Preserve separate board/pin constraints; replace the known timing profile.
    foreach timing100_file [get_files -quiet -of_objects $timing100_old_set] {
        set timing100_path [file normalize $timing100_file]
        if {[lsearch -exact $timing100_profiles [string tolower $timing100_path]] < 0} {
            add_files -fileset $timing100_new_set -norecurse $timing100_path
        }
    }
}
set timing100_has_xdc 0
set timing100_has_board_xdc 0
foreach timing100_file [get_files -quiet -of_objects $timing100_new_set] {
    set timing100_path [file normalize $timing100_file]
    if {[string equal -nocase $timing100_path $timing100_xdc]} {
        set timing100_has_xdc 1
    } elseif {[string equal -nocase $timing100_path $timing100_board_xdc]} {
        set timing100_has_board_xdc 1
    } elseif {[lsearch -exact $timing100_profiles [string tolower $timing100_path]] >= 0} {
        error {The 100 MHz set contains another SoC timing XDC. Remove that file from this set first.}
    }
}
if {!$timing100_has_board_xdc} {
    add_files -fileset $timing100_new_set -norecurse $timing100_board_xdc
}
if {!$timing100_has_xdc} {
    add_files -fileset $timing100_new_set -norecurse $timing100_xdc
}
set_property -name TARGET_CONSTRS_FILE -value $timing100_xdc -objects $timing100_new_set
set_property -name CONSTRSET -value $timing100_set_name -objects $timing100_synth
set_property -name CONSTRSET -value $timing100_set_name -objects $timing100_impl
set timing100_generics {}
foreach timing100_generic [get_property GENERIC [get_filesets sources_1]] {
    if {![string match {CLK_FREQ=*} $timing100_generic] &&
        ![string match {DDR_TX_PHASED_CLOCK=*} $timing100_generic]} {
        lappend timing100_generics $timing100_generic
    }
}
lappend timing100_generics CLK_FREQ=100000000 DDR_TX_PHASED_CLOCK=1
set_property -name GENERIC -value $timing100_generics -objects [get_filesets sources_1]

puts "Selected $timing100_set_name for synth_1 and impl_1."
puts "XDC: $timing100_xdc"
puts "Previous synthesis constraint set: $timing100_previous (retained)."
puts {Re-run synthesis and implementation to evaluate the 10 ns / 100 MHz target.}
puts {Selected CLK_FREQ=100000000 and DDR_TX_PHASED_CLOCK=1; the external clock must be 100 MHz.}
