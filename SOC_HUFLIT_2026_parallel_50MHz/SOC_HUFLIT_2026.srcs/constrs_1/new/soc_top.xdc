################################################################################
# XCM-208 configuration bank. The board's configuration interface uses 3.3 V.
# Keep these values aligned with the actual board's VCCO_0 and CFGBVS wiring.
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# The XCM-208 on-board oscillator connected to clk is 100 MHz. The system,
# DDR serializer, and phase-shifted DDR clocks run at 100 MHz.
################################################################################
create_clock -name sys_clk -period 10.000 -waveform {0.000 5.000} [get_ports clk]

################################################################################
# Forwarded DDR output clock (100 MHz; same frequency as the SoC fabric clock).
# The XPR compiles sources_1/new/parallel.v. Its u_oddr_clk drives D1=0 and
# D2=1, so the forwarded clock is inverted relative to the MMCM's 100 MHz
# output. Keep -invert in sync with those ODDR values if the compiled RTL changes.
################################################################################
create_generated_clock -name ddr_clk_out \
    -source [get_pins u_parallel_axi/u_ddr_result_serializer/u_oddr_clk/C] \
    -divide_by 1 \
    -invert \
    [get_ports ddr_clk_out]

# Keep the valid status flop in the output I/O block. The done output is
# timed below with the other status flags; its internal acknowledgement path
# remains in the serializer clock domain.
set_property IOB TRUE [get_cells -hierarchical -filter {NAME =~ *u_ddr_result_serializer/ddr_valid_reg}]

################################################################################
# DDR output timing assumptions (nanoseconds)
# These are the values already used by this project; confirm them against the
# receiving device datasheet and the board clock/data routing before signoff.
################################################################################
set DDR_TSU            2.000
set DDR_THD            1.000
set DDR_BOARD_SKEW_MAX 0.500
set DDR_BOARD_SKEW_MIN 0.100

set OUT_DELAY_MAX [expr {$DDR_TSU + $DDR_BOARD_SKEW_MAX}]
set OUT_DELAY_MIN [expr {-$DDR_THD - $DDR_BOARD_SKEW_MIN}]

set DDR_DATA_PORTS [get_ports {ddr_data[*]}]
set DDR_FLAG_PORTS [get_ports {ddr_valid ddr_done}]

# Data is transmitted on both edges of the forwarded DDR clock.
set_output_delay -clock ddr_clk_out -max $OUT_DELAY_MAX $DDR_DATA_PORTS
set_output_delay -clock ddr_clk_out -min $OUT_DELAY_MIN $DDR_DATA_PORTS
set_output_delay -clock ddr_clk_out -clock_fall -add_delay -max $OUT_DELAY_MAX $DDR_DATA_PORTS
set_output_delay -clock ddr_clk_out -clock_fall -add_delay -min $OUT_DELAY_MIN $DDR_DATA_PORTS

# valid/done are status flags (SDR); only constrain them at the rising
# sampling edge. The data bus itself is DDR and remains constrained on both.
set_output_delay -clock ddr_clk_out -max $OUT_DELAY_MAX $DDR_FLAG_PORTS
set_output_delay -clock ddr_clk_out -min $OUT_DELAY_MIN $DDR_FLAG_PORTS

################################################################################
# Input timing is intentionally not assigned guessed values.
# Add set_input_delay constraints for ddr_data_in[*] (both edges) and
# ddr_rx_valid once the external launch clock, transmitter output timing, and
# board skew are known.
#
# HuMANDATA XCM-208A Rev A physical assignments. Package pins are from the
# official XCM208R1-PIN-JP-A table. The XPR targets xc7a200tfbg676-2L; verify
# the fitted FPGA speed grade before final bitstream generation. The supplied
# xc7z030fbg676 list is a different device family and is not used here.
#
# Board wiring plan: clk uses the onboard 100 MHz oscillator (N21); resetn uses
# active-low SW1 (K17). All remaining SoC signals use CNC user I/O: DDR TX on
# CNC[17:85] odd pins, DDR RX on CNC[18:82] even pins, and UART/SPI/I2C/cpu_trap
# on the remaining listed CNC pins. Wire the external interface to this plan.
# Bank A is fixed at 3.3 V. CNC is Bank Group C and requires external VIO(C).
# The supplied Vivado I/O screenshot shows 1.8 V, so the CNC constraints below
# assume VIO(C)=1.8 V. Change the I/O standard if the actual rail differs.
################################################################################
set_property PACKAGE_PIN N21 [get_ports clk]
set_property PACKAGE_PIN K17 [get_ports resetn]
set_property IOSTANDARD LVCMOS33 [get_ports {clk resetn}]

# CNC connector: DDR transmit bus and its forwarded clock/flags.
set_property PACKAGE_PIN U26  [get_ports {ddr_data[0]}]
set_property PACKAGE_PIN U25  [get_ports {ddr_data[1]}]
set_property PACKAGE_PIN V26  [get_ports {ddr_data[2]}]
set_property PACKAGE_PIN W26  [get_ports {ddr_data[3]}]
set_property PACKAGE_PIN W25  [get_ports {ddr_data[4]}]
set_property PACKAGE_PIN Y26  [get_ports {ddr_data[5]}]
set_property PACKAGE_PIN Y25  [get_ports {ddr_data[6]}]
set_property PACKAGE_PIN AA25 [get_ports {ddr_data[7]}]
set_property PACKAGE_PIN AB26 [get_ports {ddr_data[8]}]
set_property PACKAGE_PIN AC26 [get_ports {ddr_data[9]}]
set_property PACKAGE_PIN AD26 [get_ports {ddr_data[10]}]
set_property PACKAGE_PIN AD25 [get_ports {ddr_data[11]}]
set_property PACKAGE_PIN AE26 [get_ports {ddr_data[12]}]
set_property PACKAGE_PIN AE25 [get_ports {ddr_data[13]}]
set_property PACKAGE_PIN AF25 [get_ports {ddr_data[14]}]
set_property PACKAGE_PIN AF24 [get_ports {ddr_data[15]}]
set_property PACKAGE_PIN AE23 [get_ports {ddr_data[16]}]
set_property PACKAGE_PIN AF23 [get_ports {ddr_data[17]}]
set_property PACKAGE_PIN AE22 [get_ports {ddr_data[18]}]
set_property PACKAGE_PIN AF22 [get_ports {ddr_data[19]}]
set_property PACKAGE_PIN AF20 [get_ports {ddr_data[20]}]
set_property PACKAGE_PIN AF19 [get_ports {ddr_data[21]}]
set_property PACKAGE_PIN AE18 [get_ports {ddr_data[22]}]
set_property PACKAGE_PIN AF18 [get_ports {ddr_data[23]}]
set_property PACKAGE_PIN AE17 [get_ports {ddr_data[24]}]
set_property PACKAGE_PIN AF17 [get_ports {ddr_data[25]}]
set_property PACKAGE_PIN V23  [get_ports {ddr_data[26]}]
set_property PACKAGE_PIN W23  [get_ports {ddr_data[27]}]
set_property PACKAGE_PIN Y22  [get_ports {ddr_data[28]}]
set_property PACKAGE_PIN Y23  [get_ports {ddr_data[29]}]
set_property PACKAGE_PIN AA24 [get_ports {ddr_data[30]}]
set_property PACKAGE_PIN AB25 [get_ports {ddr_data[31]}]
set_property PACKAGE_PIN W21 [get_ports ddr_clk_out] ;# IOC32 / CNC[81]
set_property PACKAGE_PIN Y21 [get_ports ddr_valid]   ;# IOC33 / CNC[83]
set_property PACKAGE_PIN W20 [get_ports ddr_done]    ;# IOC34 / CNC[85]

# CNC connector: DDR receive bus and valid input.
set_property PACKAGE_PIN V19  [get_ports {ddr_data_in[0]}]
set_property PACKAGE_PIN W19  [get_ports {ddr_data_in[1]}]
set_property PACKAGE_PIN AA23 [get_ports {ddr_data_in[2]}]
set_property PACKAGE_PIN AA22 [get_ports {ddr_data_in[3]}]
set_property PACKAGE_PIN AC24 [get_ports {ddr_data_in[4]}]
set_property PACKAGE_PIN AB24 [get_ports {ddr_data_in[5]}]
set_property PACKAGE_PIN T18  [get_ports {ddr_data_in[6]}]
set_property PACKAGE_PIN T17  [get_ports {ddr_data_in[7]}]
set_property PACKAGE_PIN U20  [get_ports {ddr_data_in[8]}]
set_property PACKAGE_PIN T20  [get_ports {ddr_data_in[9]}]
set_property PACKAGE_PIN AD21 [get_ports {ddr_data_in[10]}]
set_property PACKAGE_PIN AE21 [get_ports {ddr_data_in[11]}]
set_property PACKAGE_PIN AD20 [get_ports {ddr_data_in[12]}]
set_property PACKAGE_PIN AE20 [get_ports {ddr_data_in[13]}]
set_property PACKAGE_PIN AC19 [get_ports {ddr_data_in[14]}]
set_property PACKAGE_PIN AD19 [get_ports {ddr_data_in[15]}]
set_property PACKAGE_PIN AC18 [get_ports {ddr_data_in[16]}]
set_property PACKAGE_PIN AD18 [get_ports {ddr_data_in[17]}]
set_property PACKAGE_PIN AD17 [get_ports {ddr_data_in[18]}]
set_property PACKAGE_PIN AC17 [get_ports {ddr_data_in[19]}]
set_property PACKAGE_PIN AB16 [get_ports {ddr_data_in[20]}]
set_property PACKAGE_PIN AC16 [get_ports {ddr_data_in[21]}]
set_property PACKAGE_PIN T19  [get_ports {ddr_data_in[22]}]
set_property PACKAGE_PIN U19  [get_ports {ddr_data_in[23]}]
set_property PACKAGE_PIN AC23 [get_ports {ddr_data_in[24]}]
set_property PACKAGE_PIN AC22 [get_ports {ddr_data_in[25]}]
set_property PACKAGE_PIN V17  [get_ports {ddr_data_in[26]}]
set_property PACKAGE_PIN V16  [get_ports {ddr_data_in[27]}]
set_property PACKAGE_PIN Y15  [get_ports {ddr_data_in[28]}]
set_property PACKAGE_PIN AA15 [get_ports {ddr_data_in[29]}]
set_property PACKAGE_PIN W15  [get_ports {ddr_data_in[30]}]
set_property PACKAGE_PIN W14  [get_ports {ddr_data_in[31]}]
set_property PACKAGE_PIN V14 [get_ports ddr_rx_valid] ;# IOC74 / CNC[82]

# CNC connector: UART, SPI, I2C and CPU trap.
set_property PACKAGE_PIN Y20  [get_ports uart_rx]  ;# IOC35 / CNC[87]
set_property PACKAGE_PIN AA19 [get_ports uart_tx]  ;# IOC36 / CNC[89]
set_property PACKAGE_PIN AB19 [get_ports spi_sclk] ;# IOC37 / CNC[91]
set_property PACKAGE_PIN Y18  [get_ports spi_mosi] ;# IOC38 / CNC[93]
set_property PACKAGE_PIN AA18 [get_ports spi_miso] ;# IOC39 / CNC[95]
set_property PACKAGE_PIN Y17  [get_ports spi_cs]   ;# IOC40 / CNC[97]
set_property PACKAGE_PIN Y16  [get_ports scl_out]  ;# IOC41 / CNC[99]
set_property PACKAGE_PIN U14  [get_ports sda_out]  ;# IOC75 / CNC[84]
set_property PACKAGE_PIN T15  [get_ports sda_oe]   ;# IOC76 / CNC[86]
set_property PACKAGE_PIN T14  [get_ports sda_in]   ;# IOC77 / CNC[88]
set_property PACKAGE_PIN U16  [get_ports cpu_trap] ;# IOC78 / CNC[90]

# I/O standards follow the board's bank voltages: Bank A is fixed at 3.3 V;
# CNC's Bank Group C must be externally powered at 1.8 V for LVCMOS18.
set CNC_SOC_PORTS [get_ports {
    ddr_data[*] ddr_clk_out ddr_valid ddr_done
    ddr_data_in[*] ddr_rx_valid
    uart_tx uart_rx spi_sclk spi_mosi spi_miso spi_cs
    scl_out sda_out sda_oe sda_in cpu_trap
}]
set CNC_IO_STANDARD LVCMOS18
set_property IOSTANDARD $CNC_IO_STANDARD $CNC_SOC_PORTS
# Keep the forwarded DDR clock and data edges sharp and well matched.
set_property SLEW FAST [get_ports {ddr_data[*] ddr_clk_out ddr_valid ddr_done}]
################################################################################

