# Timing-only copy of soc_top.xdc for the current soc_top RTL.
# Select this file INSTEAD OF soc_top.xdc; keep board/pin XDC files separately.
# This corrects the clock model. It does not change or relax the 50 MHz target.

create_clock -period 20.000 -waveform {0.000 10.000} -name sys_clk [get_ports clk]

# parallel.v: u_oddr_clk has D1=0, D2=1, so the forwarded clock is inverted.
# sys_clk rises at 0 ns; ddr_clk_out rises at 10 ns and falls at 20 ns.
# Preserve the real phase relationship between these related clocks.
create_generated_clock -name ddr_clk_out \
    -source [get_pins {u_parallel_axi/u_ddr_result_serializer/u_oddr_clk/C}] \
    -divide_by 1 \
    -invert \
    [get_ports ddr_clk_out]

# External-receiver assumptions COPIED from the original XDC, in ns.
# Replace these with the receiver datasheet and PCB timing before board signoff.
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

# Remaining I/O timing is intentionally unspecified until the board/interface
# requirements are known: resetn, uart_rx/tx, SPI, I2C, cpu_trap, ddr_data_in,
# and ddr_rx_valid. check_timing must continue to show those missing delays.
# Do not replace missing information with zero delays or broad false paths.
# No false-path or multicycle exception is added to CPU, BRAM, AXI, or CNN.
