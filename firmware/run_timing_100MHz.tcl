# Isolated full synthesis/place/route. Does not open or save the user's project.
set timing_input [file normalize inputs]
set_param general.maxThreads 4
create_project -in_memory -part xc7a200tfbg676-2L
foreach timing_name {conv1_rgb_weight.mem conv2_weight.mem conv3_weight.mem fc_weight.mem firmware.hex} {
    read_mem [file join $timing_input $timing_name]
}
foreach timing_name {picorv32.v parallel.v soc_axi_top.v axi_uart_slave.v axi_spi_slave.v axi_i2c_slave.v CNN.v cnn_memory_subsystem.v cnn_docx_reference.v dma32_to_rgb24.v picorv32_axi4_bram_adapter.v axi4_bram_slave.v soc_top.v} {
    read_verilog [file join $timing_input $timing_name]
}
read_xdc [file join $timing_input soc_top_board.xdc]
read_xdc [file join $timing_input soc_top_100MHz.xdc]
synth_design -top soc_top -part xc7a200tfbg676-2L -flatten_hierarchy none \
    -generic {CLK_FREQ=100000000 DDR_TX_PHASED_CLOCK=1}
write_checkpoint -force synthesized.dcp
report_utilization -hierarchical -file utilization_synth.rpt
report_timing_summary -max_paths 10 -file timing_synth.rpt
opt_design
place_design -directive Explore
phys_opt_design -directive ExploreWithHoldFix
write_checkpoint -force placed.dcp
report_timing_summary -delay_type min_max -max_paths 10 -file timing_placed.rpt
route_design -directive Explore
write_checkpoint -force routed.dcp
report_route_status -file route_status.rpt
report_timing_summary -delay_type min_max -max_paths 20 -report_unconstrained -file timing_routed.rpt
report_timing -from [get_clocks sys_clk] -to [get_clocks sys_clk] -max_paths 10 -file timing_internal.rpt
report_timing -to [get_ports {ddr_data[*] ddr_valid ddr_done}] -delay_type min_max -max_paths 10 -file timing_ddr.rpt
report_utilization -hierarchical -file utilization_routed.rpt
report_clocks -file clocks.rpt
check_timing -verbose -file check_timing.rpt
report_drc -file drc.rpt
set timing_setup [get_timing_paths -delay_type max -max_paths 1]
set timing_hold [get_timing_paths -delay_type min -max_paths 1]
puts "FULL_IMPLEMENTATION_RESULT WNS=[get_property SLACK $timing_setup] WHS=[get_property SLACK $timing_hold]"
puts {Review timing_routed.rpt and check_timing.rpt; no bitstream was generated.}
close_design
exit
