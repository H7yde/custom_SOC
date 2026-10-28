/* BRAM-only RV32I firmware: no UART, CNN, DMA, or other MMIO accesses.
 * soc_top now routes CPU instruction/data accesses through an AXI4 bridge.
 * The bridge emits one 32-bit beat per request, with WSTRB for byte/half stores.
 * AXI IDs, LEN/SIZE/BURST, LAST and response handshakes are handled in RTL.
 * Code is below 0x400; scratch words occupy 0x400..0x7ff; results start at 0x800.
 * The linker keeps code/data away from the test region and the stack.
 */
#include <stdint.h>

#define TEST_WORDS 256u
#define TEST_BASE  0x00000400u
#define WORD(address) (*(volatile uint32_t *)(uintptr_t)(address))

struct bram_result {
    uint32_t magic;
    uint32_t status;       /* 0: running, 1: PASS, 2: FAIL */
    uint32_t errors;
    uint32_t fail_address; /* first failing location */
    uint32_t expected;
    uint32_t observed;
    uint32_t phase;
    uint32_t checks;
    uint32_t heartbeat;
};

/* The linker places this external object at 0x800, outside code and scratch. */
extern volatile struct bram_result bram_report;
#define RESULT bram_report

static void check_word(uint32_t address, uint32_t expected)
{
    uint32_t observed = WORD(address);
    if (observed != expected) {
        if (RESULT.errors == 0u) {
            RESULT.fail_address = address;
            RESULT.expected = expected;
            RESULT.observed = observed;
        }
        ++RESULT.errors;
    }
    ++RESULT.checks;
}

int main(void)
{
    uint32_t index, phase, address, pattern;
    RESULT.magic = 0x4252414du; /* "BRAM" in the waveform's hexadecimal display */
    RESULT.status = 0;
    RESULT.errors = 0;
    RESULT.fail_address = 0;
    RESULT.expected = 0;
    RESULT.observed = 0;
    RESULT.phase = 0;
    RESULT.checks = 0;
    RESULT.heartbeat = 0;

    /* Complete each write sweep before reading, to exercise address decoding. */
    for (phase = 1; phase <= 5; ++phase) {
        RESULT.phase = phase;
        pattern = phase == 1 ? 0u : phase == 2 ? 0xffffffffu :
                  phase == 3 ? 0xaaaaaaaau : 0x55555555u;
        for (index = 0; index < TEST_WORDS; ++index) {
            address = TEST_BASE + (index << 2);
            WORD(address) = phase == 5 ? (address ^ 0x5a5a0000u) : pattern;
        }
        for (index = 0; index < TEST_WORDS; ++index) {
            address = TEST_BASE + (index << 2);
            check_word(address, phase == 5 ? (address ^ 0x5a5a0000u) : pattern);
        }
    }

    /* Byte and halfword stores also check the BRAM's four write strobes. */
    RESULT.phase = 6;
    for (index = 0; index < TEST_WORDS; ++index) {
        volatile uint8_t *bytes = (volatile uint8_t *)(uintptr_t)(TEST_BASE + (index << 2));
        bytes[0] = 0x12;
        bytes[1] = 0x34;
        bytes[2] = 0x56;
        bytes[3] = 0x78;
    }
    for (index = 0; index < TEST_WORDS; ++index)
        check_word(TEST_BASE + (index << 2), 0x78563412u);

    RESULT.phase = 7;
    for (index = 0; index < TEST_WORDS; ++index) {
        volatile uint16_t *halves = (volatile uint16_t *)(uintptr_t)(TEST_BASE + (index << 2));
        halves[0] = 0x1234;
        halves[1] = 0xabcd;
    }
    for (index = 0; index < TEST_WORDS; ++index)
        check_word(TEST_BASE + (index << 2), 0xabcd1234u);

    RESULT.status = RESULT.errors == 0u ? 1u : 2u;
    for (;;) ++RESULT.heartbeat;
}
