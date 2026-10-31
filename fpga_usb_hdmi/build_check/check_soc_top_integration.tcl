set soc_check_repo [file normalize [file join [file dirname [info script]] .. ..]]
set soc_check_projects [glob -nocomplain [file join $soc_check_repo SOC_HUFLIT_2026_parallel_* SOC_HUFLIT_2026.xpr]]
if {[llength $soc_check_projects] != 1} {error "Expected one active project"}
open_project [lindex $soc_check_projects 0]
source [file join $soc_check_repo fpga_usb_hdmi integrate_soc_top.tcl]
set_param general.maxThreads 2
set soc_check_run synth_soc_usb_hdmi
if {![llength [get_runs -quiet $soc_check_run]]} {
    create_run $soc_check_run -flow {Vivado Synthesis 2025} -strategy {Vivado Synthesis Defaults} -constrset constrs_1
}
set_property STEPS.SYNTH_DESIGN.ARGS.INCREMENTAL_MODE off [get_runs $soc_check_run]
if {[get_property NEEDS_REFRESH [get_runs $soc_check_run]] ||
    [string match {*Complete*} [get_property STATUS [get_runs $soc_check_run]]]} {
    reset_run $soc_check_run
}
create_ip_run [get_files */usb_hdmi_system.bd]
launch_runs $soc_check_run -jobs 1
wait_on_run $soc_check_run
if {![string match {*Complete*} [get_property STATUS [get_runs $soc_check_run]]]} {error "Combined synthesis failed"}
open_run $soc_check_run
if {[llength [get_cells -hierarchical -filter {REF_NAME == PS7}]] != 1} {error "Expected one PS7 primitive"}
if {[llength [get_cells -hierarchical -filter {REF_NAME == OBUFDS}]] < 4} {error "Missing HDMI differential outputs"}
if {![llength [get_cells -hierarchical -filter {NAME =~ *u_cnn*}]]} {error "Missing CNN logic"}
if {![llength [get_cells -hierarchical -filter {NAME =~ *u_arm_cnn_bridge*}]]} {error "Missing ARM/CNN bridge"}
foreach soc_check_port {DDR_dq[0] FIXED_IO_ps_clk hdmi_tx_clk_p hdmi_tx_clk_n hdmi_tx_d_p[0] hdmi_tx_d_n[0] hdmi_tx_hpdn clk uart_tx} {
    if {![llength [get_ports -quiet $soc_check_port]]} {error "Missing port $soc_check_port"}
}
set soc_check_dir [file join $soc_check_repo fpga_usb_hdmi build_check]
report_io -file [file join $soc_check_dir soc_top_integrated_io.rpt]
report_utilization -file [file join $soc_check_dir soc_top_integrated_utilization.rpt]
report_drc -checks {UCIO-1 NSTD-1} -file [file join $soc_check_dir soc_top_integrated_pin_drc.rpt]
if {[llength [get_drc_violations -quiet -filter {NAME =~ UCIO-1* || NAME =~ NSTD-1*}]]} {error "Unconstrained external pins"}
puts "SOC_TOP_USB_HDMI_SYNTHESIS_PASS"
close_design
close_project
exit
