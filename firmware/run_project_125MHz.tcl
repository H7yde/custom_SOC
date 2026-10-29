# Source from the Tcl Console of the open SoC project.
# Create fresh runs in that project and leave the routed timing report open.
namespace eval soc_run125 {
    variable repo [file dirname [file dirname [file normalize [info script]]]]
    variable output
    variable status_file
    proc event {message} {
        variable status_file
        set stream [open $status_file a]
        puts $stream "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] $message"
        close $stream
        puts $message
    }
    proc main {} {
        variable repo
        variable output
        variable status_file
        set expected [file normalize [file join $repo SOC_HUFLIT_2026_parallel_50MHz]]
        if {[llength [current_project -quiet]] != 1 ||
            ![string equal -nocase [file normalize [get_property DIRECTORY [current_project]]] $expected]} {
            error {Open the original SOC_HUFLIT_2026 project before sourcing this script.}
        }
        if {[get_property TOP [get_filesets sources_1]] ne {soc_top}} {
            error {The synthesis top must be soc_top.}
        }
        set suffix {}
        set index 1
        while {[llength [get_runs -quiet synth_h16_core125$suffix]] ||
               [llength [get_runs -quiet impl_h16_core125$suffix]] ||
               [file exists [file join $expected SOC_HUFLIT_2026.runs synth_h16_core125$suffix]] ||
               [file exists [file join $expected SOC_HUFLIT_2026.runs impl_h16_core125$suffix]]} {
            incr index
            set suffix _$index
        }
        set synth_name synth_h16_core125$suffix
        set impl_name impl_h16_core125$suffix
        set output [file join $repo firmware build project_h16_core125 $impl_name]
        file mkdir $output
        set status_file [file join $output status.log]
        event "START project=[current_project] synth=$synth_name impl=$impl_name"

        set backup [file join $repo firmware backups before_project_run_[clock format [clock seconds] -format %Y%m%d_%H%M%S]]
        file mkdir $backup
        file copy [file join $expected SOC_HUFLIT_2026.xpr] [file join $backup SOC_HUFLIT_2026.xpr]
        event "PROJECT_BACKUP=$backup"
        if {[llength [current_design -quiet]]} { close_design }
        source [file join $repo firmware select_timing_constraints_125MHz.tcl]
        set threads [file join $repo firmware vivado_run_threads.tcl]
        set_param general.maxThreads 4
        update_compile_order -fileset sources_1

        set synth_flow [get_property FLOW [get_runs synth_1]]
        set impl_flow [get_property FLOW [get_runs impl_1]]
        set project_part [get_property PART [current_project]]
        if {![llength [get_runs -quiet $synth_name]]} {
            create_run $synth_name -part $project_part -flow $synth_flow \
                -strategy {Vivado Synthesis Defaults} -srcset sources_1 -constrset constrs_1
        }
        set synth [get_runs $synth_name]
        set_property AUTO_INCREMENTAL_CHECKPOINT 0 $synth
        set_property INCREMENTAL_CHECKPOINT {} $synth
        set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none $synth
        set_property STEPS.SYNTH_DESIGN.TCL.PRE $threads $synth
        if {![llength [get_runs -quiet $impl_name]]} {
            create_run $impl_name -part $project_part -flow $impl_flow \
                -strategy {Vivado Implementation Defaults} -parent_run $synth_name -constrset constrs_1
        }
        set impl [get_runs $impl_name]
        set_property AUTO_INCREMENTAL_CHECKPOINT 0 $impl
        set_property INCREMENTAL_CHECKPOINT {} $impl
        set_property STEPS.INIT_DESIGN.TCL.PRE $threads $impl
        set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE Default $impl
        set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore $impl
        set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED 1 $impl
        set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE ExploreWithHoldFix $impl
        set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Explore $impl
        set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED 1 $impl
        set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $impl
        foreach step {POWER_OPT_DESIGN POST_PLACE_POWER_OPT_DESIGN} {
            set_property STEPS.$step.IS_ENABLED 0 $impl
        }
        current_run -synthesis $synth
        current_run -implementation $impl
        set stream [open [file join $output settings.txt] w]
        puts $stream "PROJECT=[current_project]"
        puts $stream "GENERIC=[get_property GENERIC [get_filesets sources_1]]"
        puts $stream "CONSTRSET=[get_property CONSTRSET $impl]"
        puts $stream "SYNTH_DIRECTORY=[get_property DIRECTORY $synth]"
        puts $stream "IMPL_DIRECTORY=[get_property DIRECTORY $impl]"
        puts $stream {PLACE=Explore PHYS_OPT=ExploreWithHoldFix ROUTE=Explore POST_ROUTE_PHYS_OPT=AggressiveExplore THREADS=4}
        close $stream
        event "SYNTHESIS_START directory=[get_property DIRECTORY $synth]"
        launch_runs $synth_name -jobs 1
        wait_on_run $synth_name
        event "SYNTHESIS_STATUS=[get_property STATUS $synth] PROGRESS=[get_property PROGRESS $synth]"
        if {[get_property PROGRESS $synth] ne {100%} ||
            [string match -nocase {*error*} [get_property STATUS $synth]]} {
            error "Synthesis failed; inspect [get_property DIRECTORY $synth]/runme.log"
        }
        event "IMPLEMENTATION_START directory=[get_property DIRECTORY $impl]"
        launch_runs $impl_name -to_step {phys_opt_design (Post-Route)} -jobs 1
        wait_on_run $impl_name
        event "IMPLEMENTATION_STATUS=[get_property STATUS $impl] PROGRESS=[get_property PROGRESS $impl]"
        if {[get_property PROGRESS $impl] ne {100%} ||
            [string match -nocase {*error*} [get_property STATUS $impl]]} {
            error "Implementation failed; inspect [get_property DIRECTORY $impl]/runme.log"
        }
        event OPEN_ROUTED_DESIGN
        open_run $impl_name
        report_route_status -file [file join $output route_status.rpt]
        report_clocks -file [file join $output clocks.rpt]
        report_utilization -hierarchical -file [file join $output utilization_routed.rpt]
        report_clock_utilization -file [file join $output clock_utilization.rpt]
        report_power -file [file join $output power_routed.rpt]
        check_timing -verbose -file [file join $output check_timing.rpt]
        report_drc -file [file join $output drc.rpt]
        report_timing_summary -name timing_project_h16_core125$suffix -delay_type min_max \
            -max_paths 10 -report_unconstrained -file [file join $output timing_routed.rpt]
        set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
        set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
        event "PROJECT_IMPLEMENTATION_RESULT WNS=$wns WHS=$whs"
        set mmcms [get_cells -hierarchical -filter {REF_NAME == MMCME2_ADV}]
        set bufgs [get_cells -hierarchical -filter {REF_NAME == BUFG}]
        event "CLOCK_RESOURCES MMCM=[llength $mmcms] BUFG=[llength $bufgs]"
        if {[llength $mmcms] != 1 || [llength [get_cells -quiet u_core_clock_mmcm]]} {
            error {Expected only the DDR phase-shift MMCM in the 125 MHz design.}
        }
        foreach mmcm $mmcms {
            set mult [get_property CLKFBOUT_MULT_F $mmcm]
            set input_period [get_property CLKIN1_PERIOD $mmcm]
            set divclk [get_property DIVCLK_DIVIDE $mmcm]
            set fvco [expr {1000.0 * $mult / ($input_period * $divclk)}]
            event "MMCM_VCO cell=$mmcm input_period=$input_period multiplier=$mult divider=$divclk FVCO_MHz=$fvco"
            if {$fvco < 600.0 || $fvco > 1200.0} {
                error "Invalid MMCM VCO frequency: $fvco MHz ($mmcm)"
            }
        }
        foreach clock_name [get_clocks] {
            if {abs([get_property PERIOD $clock_name] - 8.0) > 0.001} {
                error "Unexpected clock period: $clock_name [get_property PERIOD $clock_name]"
            }
        }
        if {$wns < 0 || $whs < 0} {
            error "125 MHz timing is not closed: WNS=$wns WHS=$whs; inspect $output/timing_routed.rpt"
        }
        event "DONE reports=$output"
    }
}
if {[catch {soc_run125::main} soc_run125_error soc_run125_options]} {
    if {[info exists soc_run125::status_file]} { soc_run125::event "ERROR=$soc_run125_error" }
    if {[info exists soc_run125::output]} {
        set soc_run125_trace [open [file join $soc_run125::output error_info.txt] w]
        puts $soc_run125_trace [dict get $soc_run125_options -errorinfo]
        close $soc_run125_trace
    }
    return -options $soc_run125_options $soc_run125_error
}
