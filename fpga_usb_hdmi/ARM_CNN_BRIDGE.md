# ARM to CNN bridge

Implemented in the active `soc_top` and `usb_hdmi_system` BD. No new board pins
are required. CNN still takes a full RGB 32x32 image (3072 bytes, 768 AXI words).

```text
PS7 M_AXI_GP0 -> control_bus/M03_AXI (100 MHz)
             -> arm_cnn_cdc (asynchronous AXI4-Lite 100 -> 125 MHz)
             -> ARM_CNN external BD interface, wired internally in soc_top
             -> cnn_axi_bridge lane 1 ----+
PicoRV32 decoded CNN AXI -> lane 0 -------+-> existing CNN slave (125 MHz)
```

The bridge buffers AW and W independently and holds read/write responses under
backpressure. It serializes CNN transactions with round-robin arbitration.
An ownership register protects the entire image upload/inference/result sequence,
not just individual AXI transactions. The bridge uses synchronized
`cnn_axi_aresetn`; CNN uses its derived `cnn_recovery_resetn`. Both sides of the CDC get reset when SW0/core reset or PS/video
reset asserts. The reset controllers release reset in their own clock domains.

With hardware `ENABLE_USB_HDMI=1`, PS clocks/reset must be initialized before
either CPU can use CNN. Do not reset PS or switch SW0 during a transaction;
after reset, software must reacquire ownership and upload a complete new frame.
Standalone simulation `ENABLE_USB_HDMI=0` bypasses the PS clock/reset dependency.

## Address map (ARM and PicoRV32)

| Address | Meaning |
| --- | --- |
| `0x40004000..0x40004BFC` | 768 image words; write only |
| `0x40004F00` | Ownership: read bits 1:0 = 0 free, 1 Pico, 2 ARM; bit 8 = CNN busy/pending start |
| `0x40004F04` | Read-only bridge ID `0x434E4E42` (`CNNB`) |
| `0x40004F08` | Recovery: read sticky bit 0 bus timeout, bit 1 CNN timeout, bit 8 reset active; write byte 0 = 1 to abort/reset/acknowledge |
| `0x40004FE4` | CONFIG: write 768 for ARM baseline mode (DMA disabled) |
| `0x40004FE8` | Last inference cycle count |
| `0x40004FF4` | Result bit 0: classification |
| `0x40004FF8` | Status: bit 0 busy, bit 1 done |
| `0x40004FFC` | Write 1 to START |

To claim, either CPU writes **1** to OWNER, then reads OWNER. The bridge derives
the requester identity from the AXI lane. Only a free, idle CNN can be claimed.
Competing claims are atomic; a rejected claim still returns AXI OKAY, so poll
OWNER to confirm ownership. The owner writes **0** to release. A non-owner or
a release during inference cannot free the lock. Image/config/START writes
without ownership return AXI SLVERR; software must claim first. Reads are
side-effect-free and available to both CPUs. Byte lane 0 must be enabled when
writing OWNER. Unaligned or out-of-aperture accesses return SLVERR.

The existing PicoRV32 DMA path into `cnn_memory_subsystem` at `0x40006000` stays
local to PicoRV32. The ARM aperture is only 4 KiB; ARM must use the baseline
image window. This change does not make CNN DMA read physical ARM DDR.

## Software

- `firmware/main.c` now claims around boot checks and every UART CNN command;
  it releases after result retrieval. The rebuilt firmware image is copied to
  the active Vivado source directory. Optional old diagnostic firmware is not
  a substitute for this ownership-aware firmware in the combined hardware.
- `firmware_arm/cnn_bridge.c` and `.h` provide `arm_cnn_classify_rgb`. Add both
  to an ARM bare-metal application. Call after PS initialization. Map the AXI
  aperture as device/non-cacheable memory and use one ARM software caller at
  a time; the lock distinguishes CPUs, not threads or the two ARM cores.
- Resize the full camera frame using bilinear interpolation to RGB 32x32;
  convert OpenCV BGR to RGB. Pass byte values 0..255. The driver packs each
  four bytes MSB first, matching `dma32_to_rgb24`.
- The driver returns a classification and cycles. It does not initialize USB,
  VTC, VDMA or HDMI. It is a driver source, not a complete ARM bootable ELF.

On watchdog timeout the bridge resets CNN and only the DMA response channel of
the local memory subsystem for eight core clocks. CPU memory transactions, PS7,
CDC and HDMI are not reset. Outstanding downstream AXI transactions terminate
with SLVERR; upstream response buffers survive reset. Sticky fault blocks further
CNN accesses with SLVERR until acknowledged; OWNER/ID/RECOVERY remain accessible.
Ownership is retained. Only the owner (or a client when free) may request recovery.
Software must wait for bit 8 to clear, then reload all image/configuration data.

Default thresholds at 125 MHz: `BUS_TIMEOUT_CYCLES=4096` (32.768 us per forwarded
transaction), `CNN_TIMEOUT_CYCLES=12500000` (100 ms continuously busy). These are
parameters in `cnn_axi_bridge.v`. They do not time upstream BREADY/RREADY stalls.
Clocks must continue running. This does not recover a dead PS, stopped clock,
upstream interconnect/CDC failure, or an initiator that never sends its missing
AW/W half. A future external DDR endpoint needs its own safe reset/drain scheme.

ARM: -4 software timeout or -5 watchdog fault -> call `arm_cnn_recover(limit)`.
It acknowledges/reset, waits, then releases the lock; it refuses to abort a Pico
owner. Poll limits count MMIO iterations, not milliseconds. An AXI SLVERR can raise
a Cortex-A9 Data Abort; install a platform exception handler for bus-fault tests.
The C driver does not catch CPU exceptions. Pico UART: send lowercase `r` to abort
its own job/recover, wait for `RECOVERED; RELOAD FRAME`, then upload a new frame.

## Apply/build

The BD and project are already updated. Close/reopen any stale Vivado GUI before
saving or building so it does not overwrite the changed BD/project.

```tcl
source D:/LAB/custom_SOC-main/fpga_usb_hdmi/integrate_soc_top.tcl
```

`integrate_soc_top.tcl` invokes `add_arm_cnn_bridge.tcl`, selects `soc_top` and
the combined synthesis/implementation runs. Build with one job. Generate a new
bitstream and export a new XSA for the ARM application. Earlier `.bit` files do
not contain this bridge. The old standalone `soc_usb_hdmi_top` template does not
include this CNN connection; use `soc_top` for the combined system.

Backups are under `fpga_usb_hdmi/backups/before_arm_cnn_bridge_20261031_193430`.

If an older Vivado GUI saves a source list without `cnn_axi_bridge.v`, run
the following in that same GUI (with no builds active):

```tcl
source D:/LAB/custom_SOC-main/fpga_usb_hdmi/fix_arm_cnn_project.tcl
```

This restores the source entry, bridge configuration and current runs, then
retries IPs one at a time, including runs whose cached-result logs contain
startup directory errors. Wait for `ARM_CNN_PROJECT_FIX_PASS` before launching
`synth_soc_usb_hdmi` with one job. The synthesis pre-hook also restores the
bridge source in a stale generated run; it is verified separately by
`build_check/check_bridge_source_guard.tcl`.

## Verification

```powershell
python fpga_usb_hdmi/sim/run_bridge_test.py
python fpga_usb_hdmi/sim/run_bridge_test.py --firmware-boot
python fpga_usb_hdmi/sim/run_bridge_test.py --recovery
python fpga_usb_hdmi/sim/run_bridge_test.py --memory-recovery
```

The first test uses the actual generated AMD clock converter at 100/125 MHz,
two AXI initiators and the real CNN/weights. It checks AW/W skew, response
backpressure, lock contention, denial of non-owner writes, WSTRB, reset with
an unmatched AW, two image results and every raw RGB pixel captured by CNN.
The second boots the rebuilt PicoRV32 firmware and checks real MMIO claim,
ownership readback, release and BOOT PASS/READY.

Full synthesis validation is in `build_check/check_soc_top_integration.tcl`.
Placement/routing, physical timing closure and board execution require a new
implementation and are not implied by simulation or synthesis success.

Verified 2026-10-31 (Vivado 2025.2):

- `ARM_CNN_BRIDGE_TEST_PASS` in `build_check/arm_cnn_sim/simulate.log`,
  including the real asynchronous clock converter; image classes 1 and 0,
  all 2048 captured RGB pixels checked.
- `ARM_CNN_FIRMWARE_BOOT_PASS` in `build_check/arm_cnn_firmware_boot/simulate.log`.
- Driver compiled to an ARM ELF relocatable object with Clang targeting
  `armv7-none-eabi`, `cortex-a9`, `-Wall -Wextra -Werror`.
- `SOC_TOP_USB_HDMI_SYNTHESIS_PASS` in `build_check/check_arm_cnn_synthesis_final.log`;
  PS7, CNN, bridge and HDMI buffers present. UCIO-1/NSTD-1: zero violations.
- Post-synthesis resources: 9435 LUTs, 10070 registers, 11 BRAM tiles.
- PicoRV32 firmware occupies through `0xA88`, with 872 bytes remaining before
  the reserved stack region. Source/staged firmware SHA256:
  `47ebd3d4e40f2a5b63fe967e5c9ae8dc790bb83bfa6b88f43e241260f6fc5955`.

The bridge setup initially tried to set the interface's read-only FREQ_HZ
parameter. That directive has been removed; the saved BD/generated interface
correctly inherits 125000000 Hz from `cnn_axi_clk`.
