# Source in the OPEN Vivado project's Tcl Console. This updates the live
# session too, preventing its stale 100 MHz settings from overwriting the XPR.
set fix125_repo [file dirname [file dirname [file normalize [info script]]]]
set fix125_project [file join $fix125_repo SOC_HUFLIT_2026_parallel_50MHz]
set fix125_runs [file join $fix125_project SOC_HUFLIT_2026.runs]
set fix125_checkpoint [file join $fix125_runs impl_h16_core125_2 soc_top_postroute_physopt.dcp]

if {![file exists $fix125_checkpoint]} {
    error {The validated 125 MHz checkpoint is missing. Use firmware/run_project_125MHz.tcl to rebuild.}
}
if {[llength [current_design -quiet]]} { close_design }
source [file join $fix125_repo firmware select_timing_constraints_125MHz.tcl]

# The GUI may have saved an older project without the validated run records.
# Reattach those existing directories without resetting or rebuilding them.
if {![llength [get_runs -quiet synth_h16_core125_2]]} {
    create_run synth_h16_core125_2 -part [get_property PART [current_project]] \
        -flow [get_property FLOW [get_runs synth_1]] \
        -strategy {Vivado Synthesis Defaults} -srcset sources_1 -constrset constrs_1
}
set fix125_synth [get_runs synth_h16_core125_2]
set_property AUTO_INCREMENTAL_CHECKPOINT 0 $fix125_synth
set_property INCREMENTAL_CHECKPOINT {} $fix125_synth
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none $fix125_synth
set_property STEPS.SYNTH_DESIGN.TCL.PRE [file join $fix125_repo firmware vivado_run_threads.tcl] $fix125_synth

if {![llength [get_runs -quiet impl_h16_core125_2]]} {
    create_run impl_h16_core125_2 -part [get_property PART [current_project]] \
        -flow [get_property FLOW [get_runs impl_1]] \
        -strategy {Vivado Implementation Defaults} -parent_run synth_h16_core125_2 \
        -constrset constrs_1
}
set fix125_impl [get_runs impl_h16_core125_2]
set_property AUTO_INCREMENTAL_CHECKPOINT 0 $fix125_impl
set_property INCREMENTAL_CHECKPOINT {} $fix125_impl
set_property STEPS.INIT_DESIGN.TCL.PRE [file join $fix125_repo firmware vivado_run_threads.tcl] $fix125_impl
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore $fix125_impl
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED 1 $fix125_impl
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE ExploreWithHoldFix $fix125_impl
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Explore $fix125_impl
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED 1 $fix125_impl
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $fix125_impl
foreach fix125_step {POWER_OPT_DESIGN POST_PLACE_POWER_OPT_DESIGN} {
    set_property STEPS.$fix125_step.IS_ENABLED 0 $fix125_impl
}
current_run -synthesis $fix125_synth
current_run -implementation $fix125_impl

# Recreated run objects do not automatically load their existing gen_run.xml.
# Restore these native XPR references, then reload so Open Implemented Design
# uses the completed post-route result instead of a stale 100 MHz run.
set fix125_xpr [file join $fix125_project SOC_HUFLIT_2026.xpr]
close_project
set fix125_stream [open $fix125_xpr r]
fconfigure $fix125_stream -encoding utf-8
set fix125_xml [read $fix125_stream]
close $fix125_stream
foreach fix125_name {synth_h16_core125_2 impl_h16_core125_2} {
    set fix125_start [string first "<Run Id=\"$fix125_name\"" $fix125_xml]
    set fix125_end [string first {</Run>} $fix125_xml $fix125_start]
    if {$fix125_start < 0 || $fix125_end < 0} { error "Missing run record: $fix125_name" }
    incr fix125_end 5
    set fix125_block [string range $fix125_xml $fix125_start $fix125_end]
    set fix125_tag_end [string first {>} $fix125_block]
    set fix125_tag [string range $fix125_block 0 [expr {$fix125_tag_end - 1}]]
    regsub { Dir="[^"]*"} $fix125_tag {} fix125_tag
    append fix125_tag [format { Dir="$PRUNDIR/%s">} $fix125_name]
    set fix125_block "$fix125_tag[string range $fix125_block [expr {$fix125_tag_end + 1}] end]"
    if {[string first {<GeneratedRun } $fix125_block] < 0} {
        set fix125_insert [string first {      <ReportStrategy } $fix125_block]
        if {$fix125_insert < 0} { error "Missing report strategy: $fix125_name" }
        set fix125_record {      <GeneratedRun Dir="$PRUNDIR" File="gen_run.xml"/>}
        set fix125_block "[string range $fix125_block 0 [expr {$fix125_insert - 1}]]$fix125_record\n[string range $fix125_block $fix125_insert end]"
    }
    set fix125_xml [string replace $fix125_xml $fix125_start $fix125_end $fix125_block]
}
set fix125_stream [open $fix125_xpr w]
fconfigure $fix125_stream -encoding utf-8 -translation lf
puts -nonewline $fix125_stream $fix125_xml
close $fix125_stream
open_project $fix125_xpr
puts "RESTORED_RUN synth=[get_property STATUS [get_runs synth_h16_core125_2]] impl=[get_property STATUS [get_runs impl_h16_core125_2]]"
open_run impl_h16_core125_2
set fix125_mmcm [get_cells -hierarchical -filter {REF_NAME == MMCME2_ADV}]
if {[llength $fix125_mmcm] != 1} { error {Expected exactly one DDR phase-shift MMCM.} }
set fix125_period [get_property CLKIN1_PERIOD $fix125_mmcm]
set fix125_mult [get_property CLKFBOUT_MULT_F $fix125_mmcm]
set fix125_divclk [get_property DIVCLK_DIVIDE $fix125_mmcm]
set fix125_outdiv [get_property CLKOUT0_DIVIDE_F $fix125_mmcm]
set fix125_vco [expr {1000.0 * $fix125_mult / ($fix125_period * $fix125_divclk)}]
if {$fix125_period != 8.0 || $fix125_mult != 8.0 || $fix125_divclk != 1 || $fix125_outdiv != 8.0} {
    error "Unexpected MMCM configuration: period=$fix125_period mult=$fix125_mult divclk=$fix125_divclk outdiv=$fix125_outdiv"
}
set fix125_output [file join $fix125_repo firmware build mmcm_fix]
file mkdir $fix125_output
report_drc -checks [get_drc_checks AVAL-46] -file [file join $fix125_output aval46.rpt]
report_clocks -file [file join $fix125_output clocks.rpt]
puts "MMCM_125MHz_FIXED input_period=$fix125_period multiplier=$fix125_mult output_divider=$fix125_outdiv FVCO_MHz=$fix125_vco"
puts {The source generic is now CLK_FREQ=125000000 and the validated 125 MHz checkpoint is open.}
