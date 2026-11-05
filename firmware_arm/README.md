# ARM CNN client

For live USB webcam video on the custom SoC HDMI, boot the PYNQ/Linux SD and see
[linux_camera_hdmi/README.md](linux_camera_hdmi/README.md). The matching overlay
and Python app are packaged in `linux_camera_hdmi/camera_hdmi_pynq.zip`.
This path uses Linux USB Host/UVC and does not run as a standalone Vitis ELF.

For the HDMI-only color-bar test now installed in `arm_test/src/main.c`, see
[HDMI_COLOR_BARS.md](HDMI_COLOR_BARS.md). Build and run `arm_test.elf` using the
existing Vitis hardware launch. `hdmi_color_bars.c` is a reusable copy with its
own `main`; do not add it alongside a second application `main.c`.

Add `cnn_bridge.c` and `cnn_bridge.h` to a Vitis standalone application targeting
`ps7_cortexa9_0`, using a newly exported XSA containing the ARM/CNN bridge.
PS7 initialization must enable DDR and FCLK before calling the driver.

```c
#include "cnn_bridge.h"

/* rgb32 is 3072 RGB8 bytes, bilinear-resized full frame, not BGR. */
struct arm_cnn_result result;
int rc = arm_cnn_classify_rgb(rgb32, ARM_CNN_RGB_BYTES, 1000000u, &result);
if (rc == 0) {
    /* result.classification: 1 = person, 0 = no person.
       Draw this result into your separate HDMI framebuffer. */
}
```

This is a driver, not an HDMI application or a standalone boot image. Keep the
AXI register window at `0x40004000` mapped as device/non-cacheable memory.
Use one ARM caller at a time. On -4 (software timeout) or -5 (watchdog fault), call
`arm_cnn_recover(1000000u)`. After success, reload a complete frame and classify
again; do not use the failed frame's result. Recovery resets CNN/configuration,
waits for completion, and releases ARM ownership. It cannot abort a Pico owner.
The new bitstream is required. AXI SLVERR can cause a Cortex-A9 Data Abort; bus
fault injection requires an application exception handler. The driver polling
loop does not catch CPU exceptions. See [ARM_CNN_BRIDGE.md](../fpga_usb_hdmi/ARM_CNN_BRIDGE.md).
