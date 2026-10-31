# ARM CNN client

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
Use one ARM caller at a time. Timeout -4 requires recovery/reset; the hardware
retains the lock while CNN is busy. See [ARM_CNN_BRIDGE.md](../fpga_usb_hdmi/ARM_CNN_BRIDGE.md).
