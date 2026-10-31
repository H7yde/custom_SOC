#include "cnn_bridge.h"
#define REG(offset) (*(volatile uint32_t *)(uintptr_t)(ARM_CNN_BASE + (offset)))
static void barrier(void)
{
#if defined(__arm__) || defined(__aarch64__)
    __asm__ volatile("dmb sy" ::: "memory");
#else
    __asm__ volatile("" ::: "memory");
#endif
}
int arm_cnn_classify_rgb(const uint8_t *rgb, size_t length,
                         uint32_t poll_limit, struct arm_cnn_result *result)
{
    uint32_t left, status = 0;
    size_t i;
    if (!rgb || !result || length != ARM_CNN_RGB_BYTES || !poll_limit) return -1;
    if (REG(0xF04) != 0x434E4E42u) return -2;
    for (left = poll_limit; left; --left) {
        REG(0xF00) = 1;
        barrier();
        status = REG(0xF00);
        if ((status & 3u) == 2u) {
            if (status & 0x100u) return -4;
            break;
        }
    }
    if (!left) return -3;
    /* The stream unpacks the most significant byte first. Do not memcpy
     * little-endian RGB bytes directly into the AXI word aperture. */
    for (i = 0; i < length; i += 4) {
        REG(i) = ((uint32_t)rgb[i] << 24) | ((uint32_t)rgb[i+1] << 16) |
                 ((uint32_t)rgb[i+2] << 8) | (uint32_t)rgb[i+3];
    }
    REG(0xFE4) = 768; /* Baseline path; CNN-local image RAM, not ARM DDR DMA. */
    barrier();
    REG(0xFFC) = 1;
    barrier();
    /* CNN clears DONE before completing the START write response. Device
     * memory ordering plus the barrier prevents polling an older DONE. */
    for (left = poll_limit; left; --left) {
        status = REG(0xFF8);
        if ((status & 3u) == 2u) break;
    }
    if (!left) return -4;
    result->status = status;
    result->classification = REG(0xFF4) & 1u;
    result->cycles = REG(0xFE8);
    barrier();
    REG(0xF00) = 0;
    barrier();
    return 0;
}
