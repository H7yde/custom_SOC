#ifndef HUFLIT_ARM_CNN_BRIDGE_H
#define HUFLIT_ARM_CNN_BRIDGE_H
#include <stdint.h>
#include <stddef.h>
#define ARM_CNN_BASE 0x40004000u
#define ARM_CNN_RGB_BYTES 3072u
struct arm_cnn_result {
    uint32_t classification;
    uint32_t cycles;
    uint32_t status;
};
/* One ARM caller at a time. Return 0 on success; negative on error.
 * -1 invalid argument, -2 wrong bitstream, -3 ownership timeout,
 * -4 inference timeout, -5 hardware watchdog fault (lock retained).
 * Call arm_cnn_recover(), then resend the entire frame/configuration.
 * Input is a full-frame bilinear resize to RGB 32x32, byte range 0..255.
 * Call after PS initialization. Map ARM_CNN_BASE as device memory.
 */
int arm_cnn_classify_rgb(const uint8_t *rgb, size_t length,
                         uint32_t poll_limit, struct arm_cnn_result *result);
/* Aborts own inference, clears fault and releases ownership after reset.
 * Never aborts the Pico owner's job. Same return codes as above.
 * AXI SLVERR can raise an ARM Data Abort: install a platform exception handler
 * for bus-fault testing; a C polling timeout cannot catch a CPU exception.
 */
int arm_cnn_recover(uint32_t poll_limit);
#endif
