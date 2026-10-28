/* Bare-metal RV32I firmware for the active soc_top, 50 MHz / UART 115200 8N1.
 * Images stream from UART directly into CNN/MMIO memory, not the 4 KiB BRAM.
 * No libc, interrupts, multiply/divide instructions, or heap are required.
 */
#include "soc.h"

volatile struct firmware_report fw_report;
static volatile uint32_t scratch[4];
static volatile uint32_t data_cookie = 0x12345678u;
static uint32_t loaded_buffers;

static void uart_putc(unsigned char value)
{
    while (!(UART_STATUS & UART_TX_READY)) {}
    UART_TX = value;
}

static void uart_puts(const char *text)
{
    while (*text) uart_putc((unsigned char)*text++);
}

static int uart_getc(uint32_t timeout)
{
    do {
        if (UART_STATUS & UART_RX_READY) return (int)(UART_RX & 255u);
    } while (--timeout);
    return -1;
}

static void uart_hex(uint32_t value)
{
    int shift;
    for (shift = 28; shift >= 0; shift -= 4) {
        unsigned digit = (value >> shift) & 15u;
        uart_putc((unsigned char)(digit < 10u ? '0' + digit : 'A' + digit - 10u));
    }
}

static int boot_test(void)
{
    uint32_t i;
    int ok = data_cookie == 0x12345678u && scratch[0] == 0 && loaded_buffers == 0;
    for (i = 0; i < 4; ++i) scratch[i] = 0xa5a50000u ^ i;
    for (i = 0; i < 4; ++i) if (scratch[i] != (0xa5a50000u ^ i)) ok = 0;
    CNN_DMA_BASE = CNN_BUFFER0;
    CNN_CONFIG = FRAME_WORDS | CNN_DMA | CNN_PINGPONG;
    if (CNN_DMA_BASE != CNN_BUFFER0 ||
        CNN_CONFIG != (FRAME_WORDS | CNN_DMA | CNN_PINGPONG)) ok = 0;
    CNN_CONFIG = FRAME_WORDS;
    return ok;
}

/* Configuration is written by the caller; this permits automatic ping-pong. */
static int cnn_run(void)
{
    uint32_t timeout = 2000000u;
    if (CNN_STATUS & CNN_BUSY) {
        uart_puts("ERROR BUSY\r\n");
        return 0;
    }
    fw_report.stage = 2;
    CNN_CONTROL = 1;
    do {
        fw_report.status = CNN_STATUS;
        if (fw_report.status & CNN_DONE) break;
    } while (--timeout);
    if (!timeout) {
        uart_puts("ERROR CNN TIMEOUT; RESET REQUIRED\r\n");
        return 0;
    }
    fw_report.classification = CNN_RESULT & 1u;
    fw_report.cycles = CNN_CYCLES;
    fw_report.dma_reads = CNN_READS;
    uart_puts("RESULT ");
    uart_putc((unsigned char)('0' + fw_report.classification));
    uart_puts(" STATUS "); uart_hex(fw_report.status);
    uart_puts(" CYCLES "); uart_hex(fw_report.cycles);
    uart_puts(" READS "); uart_hex(fw_report.dma_reads);
    uart_puts("\r\n");
    return 1;
}

static int upload_frame(int command)
{
    uint32_t word_index, byte_index, value;
    uint32_t address = command == 'B' ? CNN_FRAME :
                       command == '0' ? CNN_BUFFER0 : CNN_BUFFER1;
    uint32_t buffer_bit = command == '0' ? 1u : 2u;
    if (CNN_STATUS & CNN_BUSY) { uart_puts("ERROR BUSY\r\n"); return 0; }
    if (command != 'B') loaded_buffers &= ~buffer_bit;
    uart_puts("SEND\r\n");
    for (word_index = 0; word_index < FRAME_WORDS; ++word_index) {
        value = 0;
        for (byte_index = 0; byte_index < 4; ++byte_index) {
            int byte = uart_getc(2000000u);
            if (byte < 0) {
                uart_puts("ERROR RX TIMEOUT; RESET BEFORE RETRY\r\n");
                return 0;
            }
            value = (value << 8) | (uint32_t)byte;
        }
        MMIO32(address + (word_index << 2)) = value;
    }
    if (command != 'B') loaded_buffers |= buffer_bit;
    CNN_DMA_BASE = CNN_BUFFER0;
    CNN_CONFIG = FRAME_WORDS | (command == 'B' ? 0u : CNN_DMA) |
                 (command == '1' ? CNN_BUFFER_1 : 0u);
    return cnn_run();
}

static int pingpong_test(void)
{
    if (loaded_buffers != 3u) {
        uart_puts("ERROR LOAD BUFFERS 0 AND 1 FIRST\r\n");
        return 0;
    }
    CNN_DMA_BASE = CNN_BUFFER0;
    CNN_CONFIG = FRAME_WORDS | CNN_DMA | CNN_PINGPONG;
    if (!cnn_run() || (fw_report.status & 0x1cu) != 0x14u ||
        fw_report.dma_reads != FRAME_WORDS) return 0;
    /* Leave CONFIG untouched: hardware must choose buffer 1 next. */
    if (!cnn_run() || (fw_report.status & 0x1cu) != 0x1cu ||
        fw_report.dma_reads != FRAME_WORDS) return 0;
    return 1;
}

static int smoke_test(void)
{
    uint32_t i, baseline;
    if (CNN_STATUS & CNN_BUSY) return 0;
    /* A deterministic black frame tests transport consistency, not accuracy. */
    for (i = 0; i < FRAME_WORDS; ++i) {
        MMIO32(CNN_FRAME + (i << 2)) = 0;
        MMIO32(CNN_BUFFER0 + (i << 2)) = 0;
        MMIO32(CNN_BUFFER1 + (i << 2)) = 0;
    }
    loaded_buffers = 3;
    CNN_CONFIG = FRAME_WORDS;
    if (!cnn_run() || fw_report.dma_reads != 0u ||
        (fw_report.status & 0x1cu) != 0u) return 0;
    baseline = fw_report.classification;
    CNN_DMA_BASE = CNN_BUFFER0;
    CNN_CONFIG = FRAME_WORDS | CNN_DMA;
    if (!cnn_run() || fw_report.classification != baseline ||
        fw_report.dma_reads != FRAME_WORDS ||
        (fw_report.status & 0x1cu) != 4u) return 0;
    CNN_CONFIG = FRAME_WORDS | CNN_DMA | CNN_BUFFER_1;
    if (!cnn_run() || fw_report.classification != baseline ||
        fw_report.dma_reads != FRAME_WORDS ||
        (fw_report.status & 0x1cu) != 12u) return 0;
    return 1;
}

int main(void)
{
    int command, ok;
    fw_report.magic = 0x534f4346u; /* "SOCF" */
    fw_report.stage = 1;
    uart_puts("SOC BRAM READY\r\n");
    ok = boot_test();
    if (ok) { ++fw_report.passes; uart_puts("BOOT PASS\r\n"); }
    else { ++fw_report.failures; uart_puts("BOOT FAIL\r\n"); }
    for (;;) {
        fw_report.stage = 3;
        uart_puts("READY\r\n");
        do { command = uart_getc(2000000u); } while (command < 0);
        if (command == '\r' || command == '\n') continue;
        if (command == '?') {
            uart_puts("B: baseline; 0/1: DMA upload (3072 RGB bytes); P: pingpong; z: smoke\r\n");
            continue;
        }
        if (command == 'B' || command == '0' || command == '1')
            ok = upload_frame(command);
        else if (command == 'P') {
            ok = pingpong_test();
            uart_puts(ok ? "PINGPONG PASS\r\n" : "PINGPONG FAIL\r\n");
        } else if (command == 'z') {
            ok = smoke_test();
            uart_puts(ok ? "SMOKE PASS\r\n" : "SMOKE FAIL\r\n");
        } else { uart_puts("ERROR COMMAND\r\n"); continue; }
        if (ok) ++fw_report.passes;
        else ++fw_report.failures;
    }
}
