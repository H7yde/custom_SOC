# PS-generated 100 MHz clock and routed timing

Historical configuration. The current design uses H16 directly at 125 MHz;
see [CLOCK_125MHZ.md](CLOCK_125MHZ.md).

The SoC now takes its core clock from the Zynq PS `FCLK_CLK0`, configured to
100 MHz. The PL input clock on PYNQ-Z2 H16 (125 MHz) is no longer a top-level
port or a timing source. The serializer's phase-shift MMCM remains because it
creates the forwarded DDR output clock; it does not change the core frequency.

Vivado automatically derives the `clk_fpga_0` clock from the PS7 output. The
selected routed implementation is `impl_ps_fclk100_2` in
`SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.runs/`.

Routed timing from `firmware/build/project_ps_fclk100/impl_ps_fclk100_2/`:

| Metric | Result |
| --- | ---: |
| Core clock | 100.000 MHz, 10.000 ns |
| Setup WNS | +0.315 ns |
| Setup TNS | 0.000 ns, 0 failing endpoints |
| Hold WHS | +0.037 ns |
| Hold THS | 0.000 ns, 0 failing endpoints |
| Internal unconstrained endpoints | 0 |
| DRC errors | 0 |

`check_timing.rpt` still reports 21 input ports and 25 output ports without
external delay constraints. Those delays depend on the devices connected to
the custom DDR and peripheral interfaces. The positive slack above applies to
the paths covered by the current constraints; it does not validate those
external device timing assumptions.

`configure_pynqz2_ps.tcl` creates/configures the PS7 IP clock output. A
PS-generated clock must be enabled by PS initialization at runtime. On a PYNQ
image, load the PL design after the board's normal PS boot/initialization. For
standalone JTAG use, initialize the PS with the PYNQ-Z2 board configuration
before relying on FCLK0.
