# Timing closure, 2026-11-05

Original run: `impl_soc_usb_hdmi`, routed report at 11:22:38.
WNS -0.079 ns, TNS -0.396 ns, five failing setup endpoints; WHS +0.017 ns.
The worst path runs from `u_cpu/mem_addr_reg[21]` through the peripheral
response/decode logic to `u_cpu/decoded_rs1_reg[0]/R`. It is in the 125 MHz
core domain (8 ns period). Routing accounts for 5.883 ns of 7.393 ns data delay.

`phys_opt_design -directive AggressiveExplore` on the existing routed checkpoint
closed these paths without changing clock constraints or RTL:

| Measure | Before | After |
| --- | ---: | ---: |
| WNS | -0.079 ns | +0.001 ns |
| TNS | -0.396 ns | 0 ns |
| Failing setup endpoints | 5 | 0 |
| WHS | +0.017 ns | +0.017 ns |
| Failing hold endpoints | 0 | 0 |
| Worst pulse width slack | +2.000 ns | +2.000 ns |

All 15,328 routable nets remain fully routed, with zero routing errors.
The setup margin is small; a new synthesis/place/route can produce a different
result. Always check that build's reports before using its bitstream.

Outputs are saved separately under `fpga_usb_hdmi/build_check/timing_recovery/`:
`timing_summary.rpt`, `route_status.rpt`, `bus_skew.rpt`, `drc.rpt`,
`soc_top_postroute.dcp`, and (after successful bitstream generation)
`soc_top_timing_fixed.bit`. The original routed checkpoint is preserved.

In the open Vivado project, enable this step for future builds:

```tcl
source D:/LAB/custom_SOC-main/fpga_usb_hdmi/configure_timing_125MHz.tcl
```

The integration script now applies the same setting automatically. To reproduce
optimization of the current routed checkpoint and generate the separate bitstream:

```tcl
source D:/LAB/custom_SOC-main/fpga_usb_hdmi/fix_timing_125MHz.tcl
```

This opens the corrected design, but the original run's cached red timing result
remains historical. Load `soc_top_postroute.dcp` to inspect the corrected timing,
or rerun implementation with post-route physical optimization enabled to refresh
the run status. The reported missing external I/O delays need the actual external
interface timing specification; they were not hidden with false paths here.
