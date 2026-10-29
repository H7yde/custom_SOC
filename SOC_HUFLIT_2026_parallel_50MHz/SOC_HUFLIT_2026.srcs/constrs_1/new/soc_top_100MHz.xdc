# The PYNQ-Z2 H16 input is 125 MHz; the top-level MMCM generates the 100 MHz
# clock used by the SoC. Vivado derives the generated clock from the MMCM.

create_clock -period 8.000 -waveform {0.000 4.000} -name sys_clk_125m [get_ports clk]

# parallel.v: u_oddr_clk has D1=0, D2=1, so the forwarded clock is inverted.
# The source pin inherits the actual optional MMCM phase from the RTL.
# With DDR_TX_PHASED_CLOCK=1, the 115.071429-degree fixed fine phase is
# 3.196429 ns at 100 MHz; the inverted clock rises at 8.196429 ns.
# With the legacy bypass it rises at 5 ns and falls at 10 ns.
create_generated_clock -name ddr_clk_out \
    -source [get_pins {u_parallel_axi/u_ddr_result_serializer/u_oddr_clk/C}] \
    -divide_by 1 \
    -invert \
    [get_ports ddr_clk_out]

# Physical output-buffer setting used by the 100 MHz DDR transmitter.
# Preserve the board's IOSTANDARD/pin assignments in its separate board XDC.
set_property SLEW FAST [get_ports {ddr_data[*] ddr_clk_out ddr_valid ddr_done}]

# External-receiver assumptions retained from the original XDC, in ns.
# These device/PCB timing values are NOT scaled with the clock frequency.
# BOARD_SKEW_MAX is the late-data bound; BOARD_SKEW_MIN is the magnitude
# of the early-data bound: signed data-minus-clock skew is [-0.100, +0.500].
set DDR_TSU            2.000
set DDR_THD            1.000
set DDR_BOARD_SKEW_MAX 0.500
set DDR_BOARD_SKEW_MIN 0.100

set OUT_DELAY_MAX [expr {$DDR_TSU + $DDR_BOARD_SKEW_MAX}]
set OUT_DELAY_MIN [expr {-$DDR_THD - $DDR_BOARD_SKEW_MIN}]

set DDR_DATA_PORTS [get_ports {ddr_data[*]}]
set DDR_FLAG_PORTS [get_ports {ddr_valid ddr_done}]

# DDR data: check receiver setup and hold at BOTH forwarded-clock edges.
# Inversion alone does not center this clock in the DDR data eye; the actual
# edge-aligned transmitter can therefore still report output timing violations.
set_output_delay -clock ddr_clk_out -max $OUT_DELAY_MAX $DDR_DATA_PORTS
set_output_delay -clock ddr_clk_out -min $OUT_DELAY_MIN $DDR_DATA_PORTS
set_output_delay -clock ddr_clk_out -max $OUT_DELAY_MAX $DDR_DATA_PORTS -clock_fall -add_delay
set_output_delay -clock ddr_clk_out -min $OUT_DELAY_MIN $DDR_DATA_PORTS -clock_fall -add_delay

# Flags are single-rate. Preserve the original assumption that the external
# receiver samples ddr_valid/ddr_done on the RISING forwarded-clock edge.
# If the receiver samples flags on both edges, its requirements must be added.
set_output_delay -clock ddr_clk_out -max $OUT_DELAY_MAX $DDR_FLAG_PORTS
set_output_delay -clock ddr_clk_out -min $OUT_DELAY_MIN $DDR_FLAG_PORTS

# Remaining I/O timing is unspecified until the board/interface requirements
# are known: resetn, uart_rx/tx, SPI, I2C, cpu_trap, ddr_data_in, ddr_rx_valid.
# No false-path or multicycle exception is added to CPU, BRAM, AXI, or CNN.
