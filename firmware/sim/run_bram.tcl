# Resolve HDL objects in the current top scope: xelab gives parameterized
# tops an escaped name, so hard-coded absolute string paths do not match.
log_wave [get_objects clk]
log_wave [get_objects resetn]
log_wave [get_objects cpu_trap]
log_wave [get_objects uart_tx]
log_wave [get_objects report_*]
log_wave [get_objects cpu_mem_*]
log_wave [get_objects bram_axi_*]
run all
quit
