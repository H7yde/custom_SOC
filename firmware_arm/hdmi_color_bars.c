/* PYNQ-Z2: run after the Vitis launch initializes PS7/DDR/FCLK and loads PL.
 * AXI video RGB888 packs G in bits 7:0, B in 15:8, R in 23:16.
 * The framebuffer therefore contains G,B,R byte triplets on little-endian ARM.
 */
#include <string.h>
#include "xparameters.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xstatus.h"
#include "xaxivdma.h"
#include "xvtc.h"
#include "sleep.h"

#define WIDTH       640U
#define HEIGHT      480U
#define STRIDE      (WIDTH * 3U)
#define FRAME_BYTES (STRIDE * HEIGHT)
#define RESET_POLLS 100U

/* Linker places this static allocation in DDR with the application .bss.
 * 64-byte alignment covers the cache line and the 64-bit VDMA bus without DRE.
 * All three read-only VDMA frame slots point to this immutable test image.
 */
static u8 framebuffer[FRAME_BYTES] __attribute__((aligned(64)));
static XAxiVdma vdma;
static XVtc vtc;

static int configure_vdma(void)
{
    XAxiVdma_Config *config = XAxiVdma_LookupConfig(XPAR_XAXIVDMA_0_BASEADDR);
    unsigned int i;
    int status;
    if (config == NULL) {
        xil_printf("ERROR: VDMA configuration missing\r\n");
        return XST_FAILURE;
    }
    if (!config->HasMm2S || config->HasSG || config->Mm2SStreamWidth != 24 ||
        config->MaxFrameStoreNum < 1 || config->MaxFrameStoreNum > XAXIVDMA_MAX_FRAMESTORE) {
        xil_printf("ERROR: expected direct-register MM2S, 24-bit stream\r\n");
        return XST_FAILURE;
    }
    status = XAxiVdma_CfgInitialize(&vdma, config, config->BaseAddress);
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: VDMA initialize=%d\r\n", status);
        return status;
    }
    XAxiVdma_Reset(&vdma, XAXIVDMA_READ);
    for (i = 0; i < RESET_POLLS; ++i) {
        if (!XAxiVdma_ResetNotDone(&vdma, XAXIVDMA_READ)) return XST_SUCCESS;
        usleep(1000);
    }
    xil_printf("ERROR: VDMA reset timeout; check PL clocks/reset and bitstream\r\n");
    return XST_FAILURE;
}

static void draw_color_bars(void)
{
    static const u8 rgb[8][3] = {
        {255,255,255}, {255,255,0}, {0,255,255}, {0,255,0},
        {255,0,255}, {255,0,0}, {0,0,255}, {0,0,0}
    };
    unsigned int x, y;
    for (y = 0; y < HEIGHT; ++y) {
        for (x = 0; x < WIDTH; ++x) {
            unsigned int bar = x / (WIDTH / 8U);
            unsigned int offset = y * STRIDE + x * 3U;
            framebuffer[offset]     = rgb[bar][1]; /* G */
            framebuffer[offset + 1] = rgb[bar][2]; /* B */
            framebuffer[offset + 2] = rgb[bar][0]; /* R */
        }
    }
    Xil_DCacheFlushRange((INTPTR)framebuffer, FRAME_BYTES);
    __asm__ volatile("dsb sy" ::: "memory");
}

static int configure_vtc(void)
{
    XVtc_Config *config = XVtc_LookupConfig(XPAR_XVTC_0_BASEADDR);
    XVtc_Timing timing = {0};
    XVtc_SourceSelect source = {0};
    int status;
    if (config == NULL) return XST_FAILURE;
    status = XVtc_CfgInitialize(&vtc, config, config->BaseAddress);
    if (status != XST_SUCCESS) return status;
    XVtc_DisableGenerator(&vtc);
    XVtc_DisableSync(&vtc);
    XVtc_RegUpdateDisable(&vtc);
    /* 800 x 525 total pixels at 25.2 MHz gives exactly 60 Hz.
     * VTC syncs are positive internally. Existing PL NOT gates make the
     * HDMI output H/V sync negative, as required for this VGA mode.
     */
    timing.HActiveVideo = WIDTH;
    timing.HFrontPorch = 16;
    timing.HSyncWidth = 96;
    timing.HBackPorch = 48;
    timing.HSyncPolarity = 1;
    timing.VActiveVideo = HEIGHT;
    timing.V0FrontPorch = timing.V1FrontPorch = 10;
    timing.V0SyncWidth = timing.V1SyncWidth = 2;
    timing.V0BackPorch = timing.V1BackPorch = 33;
    timing.VSyncPolarity = 1;
    timing.Interlaced = 0;
    source.FieldIdPolSrc = 1;
    source.ActiveChromaPolSrc = source.ActiveVideoPolSrc = 1;
    source.HSyncPolSrc = source.VSyncPolSrc = 1;
    source.HBlankPolSrc = source.VBlankPolSrc = 1;
    source.VChromaSrc = source.VActiveSrc = source.VBackPorchSrc = 1;
    source.VSyncSrc = source.VFrontPorchSrc = source.VTotalSrc = 1;
    source.HActiveSrc = source.HBackPorchSrc = source.HSyncSrc = 1;
    source.HFrontPorchSrc = source.HTotalSrc = 1;
    source.InterlacedMode = 0;
    XVtc_SetGeneratorTiming(&vtc, &timing);
    XVtc_SetSource(&vtc, &source);
    XVtc_RegUpdateEnable(&vtc);
    return XST_SUCCESS;
}

static int start_vdma(void)
{
    XAxiVdma_DmaSetup setup = {0};
    UINTPTR addresses[XAXIVDMA_MAX_FRAMESTORE] = {0};
    int i, status;
    setup.VertSizeInput = HEIGHT;
    setup.HoriSizeInput = STRIDE;
    setup.Stride = STRIDE;
    setup.EnableCircularBuf = 1;
    setup.EnableSync = 0;
    setup.EnableFrameCounter = 0;
    status = XAxiVdma_DmaConfig(&vdma, XAXIVDMA_READ, &setup);
    if (status != XST_SUCCESS) return status;
    for (i = 0; i < vdma.MaxNumFrames; ++i) addresses[i] = (UINTPTR)framebuffer;
    status = XAxiVdma_DmaSetBufferAddr(&vdma, XAXIVDMA_READ, addresses);
    if (status != XST_SUCCESS) return status;
    return XAxiVdma_DmaStart(&vdma, XAXIVDMA_READ);
}

static void print_status(void)
{
    u32 dma_status = Xil_In32(XPAR_XAXIVDMA_0_BASEADDR + XAXIVDMA_SR_OFFSET);
    u32 errors = XAxiVdma_GetDmaChannelErrors(&vdma, XAXIVDMA_READ);
    xil_printf("VDMA SR=%08x ERR=%08x VTC CTRL=%08x",
               dma_status, errors, Xil_In32(XPAR_XVTC_0_BASEADDR));
#ifdef XPAR_HDMI_HPD_BASEADDR
    xil_printf(" HPDN(raw)=%d", (int)(Xil_In32(XPAR_HDMI_HPD_BASEADDR) & 1U));
#endif
    xil_printf("\r\n");
    if (errors || (dma_status & XAXIVDMA_SR_HALTED_MASK)) {
        xil_printf("ERROR: video DMA fault/halted; check DDR/HP0/stream clocks.\r\n");
    }
}

int main(void)
{
    int status;
    UINTPTR address = (UINTPTR)framebuffer;
    xil_printf("\r\nHDMI COLOR BARS 640x480 @60Hz\r\n");
    if ((address & 63U) || address < XPAR_PS7_DDR_0_BASEADDRESS ||
        address > XPAR_PS7_DDR_0_HIGHADDRESS - FRAME_BYTES + 1U) {
        xil_printf("ERROR: framebuffer is not aligned/in PS DDR: %08x\r\n", (u32)address);
        return XST_FAILURE;
    }
    xil_printf("Framebuffer=%08x bytes=%d stride=%d\r\n", (u32)address,
               (int)FRAME_BYTES, (int)STRIDE);
    /* Stop the previous DMA job before modifying its framebuffer on relaunch. */
    if (configure_vdma() != XST_SUCCESS) return XST_FAILURE;
    draw_color_bars();
    xil_printf("DDR color bars written; cache flushed\r\n");
    status = configure_vtc();
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: VTC configure=%d\r\n", status);
        return status;
    }
    status = start_vdma();
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: VDMA start=%d\r\n", status);
        return status;
    }
    XVtc_EnableGenerator(&vtc);
    XVtc_Enable(&vtc); /* Global software-enable is separate from generator enable. */
    xil_printf("VTC enabled; VDMA MM2S started. Check HDMI OUT.\r\n");
    usleep(500000);
    while (1) {
        print_status();
        sleep(2);
    }
}
