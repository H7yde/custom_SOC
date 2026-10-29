## Timing constraint for cnn_input_frontend
## Target clock: 50 MHz
## Clock period: 20 ns

create_clock -name clk_50MHz \
    -period 20.000 \
    -waveform {0.000 10.000} \
    [get_ports clk]

## The following pin constraints are board/device dependent and are
## intentionally not specified here. Add them for the selected FPGA board,
## for example:
## set_property PACKAGE_PIN <clock_pin> [get_ports clk]
## set_property IOSTANDARD LVCMOS33 [get_ports clk]

