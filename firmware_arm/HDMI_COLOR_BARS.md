# HDMI color bars (standalone ARM, PYNQ-Z2)

The active application is `arm_test/src/main.c`. A reusable copy is provided as
`firmware_arm/hdmi_color_bars.c`; use it **instead of** another `main.c` when
creating a different application. The earlier Hello World main is backed up at
`firmware_arm/backups/arm_test_main_before_hdmi.c`.

This app initializes the existing display chain after PS7/DDR/FCLK initialization
and PL programming by the Vitis hardware launch. It does not change the FPGA RTL
or start USB/CNN. Use the XSA/bitstream matching the current `usb_hdmi_system` BD.

| Setting | Value |
| --- | --- |
| VDMA control | `XPAR_XAXIVDMA_0_BASEADDR`, currently `0x43000000` |
| VTC control | `XPAR_XVTC_0_BASEADDR`, currently `0x43C00000` |
| Active picture | 640 x 480, progressive |
| Horizontal front/sync/back porch | 16 / 96 / 48 pixels |
| Vertical front/sync/back porch | 10 / 2 / 33 lines |
| Total | 800 x 525 |
| Pixel / serial clock from PL | 25.2 / 126 MHz |
| Refresh rate | 60 Hz |
| VDMA HSIZE / stride / VSIZE | 1920 bytes / 1920 bytes / 480 lines |
| Framebuffer | 921600 bytes, static DDR allocation aligned to 64 bytes |

VTC sync polarity is positive internally because the existing PL inverts HSync
and VSync before RGB2DVI. All VTC timing and polarity sources select the software
generator; detector sync is disabled. Both generator enable and VTC global
software enable are set. Do not remove the explicit `XVtc_Enable()` call.

The framebuffer contains eight 80-pixel bars: white, yellow, cyan, green,
magenta, red, blue, black. DDR byte order is **G, B, R**, matching AXI video
`[23:16]=R, [15:8]=B, [7:0]=G` and the installed Digilent RGB2DVI input mapping.
This is a display buffer layout, not the CNN's RGB byte input layout.
Reference: [AMD AXI4-Stream video packing](https://www.amd.com/content/dam/amd/en/documents/products/adaptive-socs-and-fpgas/technologies/axi4-stream-video-ip-and-system-design-guide.pdf).

All three VDMA read frame slots reference the same immutable image, so this test
uses only one frame allocation. Before starting VDMA, the app fills the entire
frame and flushes its cache range with a completion barrier. For future animation,
use separate buffers and flush each completed frame before handing it to DMA.

## Run in Vitis

1. Stop the old ARM debug/run session.
2. Select `arm_test` and **Build**. Drivers `xaxivdma` and `xvtc` must be included
   in the platform BSP (already present in the current platform).
3. Start the existing Hardware/JTAG launch on `ps7_cortexa9_0`, with matching PL
   bitstream and PS7 initialization. Download the newly built `arm_test.elf`.
4. If stopped at `main()`, press Resume/Continue. Open board UART at 115200 8N1.
5. Connect the monitor to **HDMI OUT** and select that monitor input.

Expected startup messages (framebuffer address may change):

```text
HDMI COLOR BARS 640x480 @60Hz
Framebuffer=........ bytes=921600 stride=1920
DDR color bars written; cache flushed
VTC enabled; VDMA MM2S started. Check HDMI OUT.
VDMA SR=........ ERR=00000000 VTC CTRL=........ HPDN(raw)=...
```

Status repeats every two seconds. `ERR` must be zero and SR bit 0 (HALTED) must
be clear. Other status bits can legitimately be set; do not expect SR to be zero.
HPDN is printed raw and active-low; it is a diagnostic, not a condition used to
start video. A running DMA alone does not prove the monitor receives HDMI.

If reset times out, check PS initialization, FCLK, and reset/clock wiring. If DMA
has errors, record SR/ERR and check the DDR/HP0 path and stream configuration.
If DMA is running without errors but the monitor says No Signal, check clock
wizard lock, video output lock, reset, DE/HSync/VSync and TMDS with ILA or suitable
measurement hardware. These video status signals are not exposed to ARM in this
BD; the program cannot report them directly.

Build/link and DDR allocation have been checked locally. Actual video output must
be confirmed on the board. No new bitstream is required for this software-only
test when using the matching current hardware design.
