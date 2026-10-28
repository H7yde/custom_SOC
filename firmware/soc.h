#ifndef HUFLIT_SOC_H
#define HUFLIT_SOC_H

#include <stdint.h>

#define MMIO32(address) (*(volatile uint32_t *)(uintptr_t)(address))
#define UART_TX         MMIO32(0x40000000u)
#define UART_RX         MMIO32(0x40000004u)
#define UART_STATUS     MMIO32(0x40000008u)
#define UART_TX_READY   (1u << 0)
#define UART_RX_READY   (1u << 1)

#define CNN_FRAME       0x40004000u
#define CNN_DMA_BASE    MMIO32(0x40004fe0u)
#define CNN_CONFIG      MMIO32(0x40004fe4u)
#define CNN_CYCLES      MMIO32(0x40004fe8u)
#define CNN_READS       MMIO32(0x40004fecu)
#define CNN_RESULT      MMIO32(0x40004ff4u)
#define CNN_STATUS      MMIO32(0x40004ff8u)
#define CNN_CONTROL     MMIO32(0x40004ffcu)
#define CNN_BUFFER0     0x40006000u
#define CNN_BUFFER1     0x40006c00u
#define FRAME_WORDS     768u
#define CNN_BUSY        (1u << 0)
#define CNN_DONE        (1u << 1)
#define CNN_DMA         (1u << 16)
#define CNN_PINGPONG    (1u << 17)
#define CNN_BUFFER_1    (1u << 18)

/* Inspect this global in the ELF/map or the corresponding BRAM words. */
struct firmware_report {
    uint32_t magic;
    uint32_t stage;
    uint32_t classification;
    uint32_t status;
    uint32_t cycles;
    uint32_t dma_reads;
    uint32_t passes;
    uint32_t failures;
};

extern volatile struct firmware_report fw_report;
#endif
