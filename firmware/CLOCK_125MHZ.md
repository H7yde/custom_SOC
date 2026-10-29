# Direct H16 125 MHz clock

The current PYNQ-Z2 design uses H16 directly through `u_core_clock_bufg`.
There is no core frequency-conversion MMCM or PS7 clock dependency.
`soc_top.CLK_FREQ` and the project synthesis generic are both 125000000.
CPU, BRAM, AXI, CNN, DDR receive logic, and DDR transmit data all use this
8 ns core clock. UART derives its configured baud rate from the same frequency;
SPI and I2C keep their existing serial-clock dividers.

AXI response VALID, read data, and read response use the registered transaction
target. All attached slaves register their response VALID outputs, so this
preserves their handshake timing while removing the live address bypass from
the response path into the CPU. Request READY retains the live address bypass.

The one remaining MMCM is
`u_parallel_axi/u_ddr_result_serializer/gen_phased_clock.u_tx_mmcm`.
Its input and output are both 125 MHz (multiply 8, divide 8, 1 GHz VCO).
It shifts the forwarded clock by 116.357143 degrees, approximately 2.585714 ns.
The output-clock ODDR inverts that waveform because D1=0 and D2=1.
RTL explicitly instantiates one MMCM and three BUFGs. The final implementation
uses four BUFGs because post-route optimization replicated `u_core_clock_bufg`
as `u_core_clock_bufg_replica` to improve clock skew. Both core branches remain
125 MHz; the replica does not create another clock frequency.

## Build

Open `SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.xpr` in Vivado 2025.2
and source `firmware/run_project_125MHz.tcl` using its absolute path.
This selects the physical pin constraints in `soc_top.xdc`, sets
`CLK_FREQ=125000000 DDR_TX_PHASED_CLOCK=1`, and creates fresh
`synth_h16_core125` / `impl_h16_core125` runs (with a suffix if needed).
It routes the design and writes reports under
`firmware/build/project_h16_core125/<implementation-run>/`.
The older project-selection entry points redirect to this current configuration.
The standalone `run_timing_100MHz.*` files remain historical 100 MHz experiments;
use `run_project_125MHz.tcl` for this design.

If an older open GUI session retains `CLK_FREQ=100000000`, it can overwrite
the project settings and regenerate the DDR MMCM with multiply/divide 10.
With the actual 8 ns input this gives an illegal 1250 MHz VCO (DRC AVAL-46).
Run this in that GUI's Tcl Console to restore its settings and reopen the
validated implementation:

```tcl
source D:/LAB/custom_SOC-main/firmware/fix_mmcm_125MHz.tcl
```

The repair restores the run references without rerunning synthesis or routing.
It checks the existing MMCM attributes (8 ns input, multiply 8, output divide 8)
and runs DRC AVAL-46. The report is `build/mmcm_fix/aval46.rpt` (0 checks found).
The pre-synthesis hook now rejects a stale 100 MHz generic before synthesis.
The build script also checks the MMCM VCO range and avoids reusing unregistered
run directories left on disk by an older project session.

## Validation

Behavioral tests passed on 2026-10-29 using Vivado/XSim 2025.2 and the installed
Xilinx UNISIM primitives:

- `sim/run_bram.ps1`: real PicoRV32 firmware, 1792 BRAM checks, AXI4 transaction
  accounting, and phased DDR clock enabled at 125 MHz.
- `sim/run.ps1`: real CPU firmware boot, serial UART traffic, and CNN baseline
  plus two DMA buffer runs at 125 MHz.
- `sim/run_ddr_phased.ps1`: four 16-bit DDR bursts, 32 halfwords, reset recovery,
  and the forwarded-clock phase at 125 MHz.

Logs for the final RTL: `build/sim_bram_direct125_final/simulate.log`,
`build/sim_firmware_direct125_final/simulate.log`, and
`build/sim_ddr_direct125/simulate.log`. The integration test completed the
baseline and both DMA buffer runs with the expected result/status/read counts.

Pass `-VivadoBin <Vivado-installation>/bin` to each PowerShell runner.
The runner checks explicit PASS markers, so a simulator's exit code alone does
not count as a passing test.

Final implemented run: `impl_h16_core125_2`, on `xc7z020clg400-1`.
Implementation includes `Explore` placement/routing, `ExploreWithHoldFix`
physical optimization, and `AggressiveExplore` post-route physical optimization.
The checked final checkpoint is `soc_top_postroute_physopt.dcp` in that run's
directory. Use the post-route optimized checkpoint when reviewing timing.

| Final metric | Result |
| --- | ---: |
| Core and DDR clocks | 125 MHz, 8.000 ns |
| Setup WNS / TNS | +0.007 ns / 0.000 ns |
| Hold WHS / THS | +0.013 ns / 0.000 ns |
| Failing setup / hold endpoints | 0 / 0 |
| Internal unconstrained endpoints | 0 |
| Routing errors | 0 |
| MMCM / BUFG | 1 / 4 |
| LUT / FF | 4986 / 2609 |

Reports: `build/project_h16_core125/impl_h16_core125_2/`.
`clocks.rpt` confirms every reported clock has an 8 ns period.
`timing_routed.rpt` contains timing after post-route physical optimization.
DRC has no errors. It retains BRAM asynchronous-control warnings and a
`PLBUFGOPT-1` warning about the replicated clock-buffer connection; see `drc.rpt`.
The setup margin is small, so later RTL or implementation changes require
another timing check.

## External interfaces

The active XDC retains the existing physical pin assignments and the true
8 ns input clock. It derives `ddr_clk_out` from the actual clock ODDR.
External input/output delays are unspecified in this project. A passing
internal timing result or behavioral simulation does not establish timing
closure with an external receiver, transmitter, or a particular cable/PCB.
No external delays or timing exceptions were invented for this change.
No bitstream is programmed onto the board by the build script.

The source/project backup before this change is under
`firmware/backups/before_direct125_20261029_202708/`.
