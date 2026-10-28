# HUFLIT 100 MHz SoC with CNN

This repository contains the HUFLIT SoC FPGA project configured for 100 MHz. It integrates a PicoRV32 CPU, AXI4 BRAM, AXI4-Lite peripherals, a parallel/DDR interface, and a CNN accelerator for binary human/non-human classification. APB files are legacy sources outside the active top-level hierarchy.

## Current configuration (2026-10-28)

| Item | Value in the current project |
|---|---|
| Vivado project | `SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.xpr` |
| Target part | `xc7z020iclg400-1L` |
| Board preset | None (`BoardPart` is empty) |
| Synthesis / simulation top | `soc_top` / `tb_CNN` |
| System clock | `CLK_FREQ=100000000`; XDC period 10 ns |
| DDR forwarded-clock option | `DDR_TX_PHASED_CLOCK=1` |
| Active runs | `synth_100MHz`, `impl_100MHz` |
| Active constraints | `constrs_1/new/soc_top.xdc` |

**The device selection and physical constraints are not yet aligned.** The active
XDC still assigns HuMANDATA XCM-208A Artix-7 FBG676 pins and bank voltages. It is
not a Zynq CLG400 board pinout. Replace the physical assignments using the actual
board schematic before implementation/bitstream use. The selected part is also
not the same part string as `xc7z020clg400-1` discussed for XC7Z020-1CLG400C.
This documentation update does not change the device or XDC.

The folder name retains `50MHz` for compatibility; the project currently sets
100 MHz. Old Artix-7 utilization/timing/power reports describe those older runs,
not the current Zynq target.

## Project layout

Paths in this list are relative to the repository root. RTL filenames later in
this document are relative to the active `sources_1/new/` directory.

- `SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.xpr`: Vivado project.
- `SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.srcs/sources_1/new/`: active RTL directory; consult `.xpr` for compiled files.
- `SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.srcs/sources_1/new/source/`: four weight files read by the core; also contains older RTL copies.
- `SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.srcs/constrs_1/new/`: XDC constraints.
- `SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.srcs/sim_2/new/`: simulation testbenches.
- `firmware/`: RV32I firmware, host tool, build and simulation scripts.
- `CNN_RTL/`: training/export files, model assets and example frames.
- `KQ/`, `Luanvan/`: experiment images and design/thesis documents.

## CNN architecture

The CNN accepts one RGB888 frame with 32 x 32 pixels.

    RGB 32x32x3
        -> Conv1: 3 input channels, 4 output channels, 3x3 kernel
        -> ReLU and INT8 requantization
        -> MaxPool 2x2, stride 2
        -> Conv2: 4 input channels, 4 output channels, 3x3 kernel
        -> ReLU and INT8 requantization
        -> MaxPool 2x2, stride 2
        -> Conv3: 4 input channels, 4 output channels, 3x3 kernel
        -> ReLU and INT8 requantization
        -> MaxPool 2x2, stride 2
        -> Flatten 2x2x4 = 16 values
        -> FC 16 -> 1
        -> classification bit

Feature-map sizes:

    Input : 32x32x3
    Conv1 : 30x30x4
    Pool1 : 15x15x4
    Conv2 : 13x13x4
    Pool2 :  6x6x4
    Conv3 :  4x4x4
    Pool3 :  2x2x4
    FC input: 16 values

The CNN RTL uses one shared MAC controlled by an FSM. Address generation, memory
read, normalization, multiplication and accumulation take separate clock phases;
it does not complete one MAC operation every clock.

## Important CNN files

| File | Description |
|---|---|
| CNN.v | AXI4-Lite CNN peripheral, clock gate and frame BRAM |
| cnn_memory_subsystem.v | Two-buffer AXI memory subsystem / DDR surrogate |
| cnn_docx_reference.v | Sequential synthesizable CNN core |
| dma32_to_rgb24.v | Converts 32-bit byte stream to RGB24 pixels |
| conv1_rgb_weight.mem | 108 INT8 Conv1 weights |
| conv2_weight.mem | 144 INT8 Conv2 weights |
| conv3_weight.mem | 144 INT8 Conv3 weights |
| fc_weight.mem | 16 INT8 FC weights |
| Tb_CNN.v | CNN AXI simulation testbench |
| soc_top.v | SoC top-level module |

## AXI address map

The CNN peripheral is mapped at base address 0x40004000.

| Address | Function |
|---|---|
| 0x40004000 - 0x40004BFC | 768 image words, 32 bits each |
| 0x40004FF4 | RESULT, bit 0 = classification |
| 0x40004FE0 | DMA base address, default 0x40006000 |
| 0x40004FE4 | CONFIG: words[9:0], DMA[16], ping-pong[17], buffer[18] |
| 0x40004FE8 | Compute-cycle counter for the last run |
| 0x40004FEC | DMA read-address transaction counter |
| 0x40004FF0 | Baseline AXI-Lite frame-write counter |
| 0x40004FF8 | STATUS: busy[0], done[1], DMA[2], buffer[3], ping-pong[4] |
| 0x40004FFC | CONTROL, write bit 0 = START |

The CNN memory subsystem is mapped at 0x40006000-0x40007FFF:

| Address | Function |
|---|---|
| 0x40006000 - 0x40006BFC | Ping-pong buffer 0, 768 words |
| 0x40006C00 - 0x400077FC | Ping-pong buffer 1, 768 words |

The current implementation is a synthesizable on-chip memory subsystem used
as a DDR-equivalent interface.  Its CNN-side read channel is an AXI master
channel.  A board-specific AXI DDR controller can replace this subsystem
without changing the CNN register interface.

One RGB frame contains:

    32 x 32 x 3 = 3072 bytes
    3072 / 4 = 768 AXI words

Result encoding:

    classification = 1: human
    classification = 0: non-human

## Data flow

    Baseline:
        CPU -> CNN AXI-Lite -> frame_mem[0:767]
                               -> dma32_to_rgb24 -> CNN FSM

    DMA / ping-pong mode:
        CPU -> memory subsystem buffer 0/1
             -> CNN AXI master read channel
             -> dma32_to_rgb24 -> CNN FSM
             -> result_valid and classification

The DMA path launches one read after the previous 32-bit word is accepted by
the RGB packer.  When the configured source length is smaller than a full
frame, the remaining words are zero-padded.  Ping-pong selection changes the
active frame buffer after each completed inference.

The byte stream is continuous. Since one RGB pixel uses three bytes, a pixel can cross a 32-bit word boundary. dma32_to_rgb24 preserves and repacks these bytes correctly.

## Weight memory files

Weights are trained in Python/PyTorch, quantized to INT8, and exported to memory files.

    Train model
        -> Quantize INT8
        -> Export .mem files
        -> $readmemh in Verilog

Negative INT8 values use two's complement representation:

    -1 = FF
    -2 = FE

The four `$readmemh` calls in the active `cnn_docx_reference.v` currently use
absolute paths under:

```text
D:/LAB/custom_SOC-main/SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.srcs/sources_1/new/source/
```

When cloning elsewhere, update those paths and check synthesis logs for all four
files. Copies also exist directly under `new/`; the core explicitly reads
`new/source/`. Keep the intended weight set consistent across build and tests.
The clock-gating runner stages the `new/` copies and localizes paths in a
simulation-only copy of the core.

`firmware.hex` is separate: `soc_top.v` loads the CPU program with
`$readmemh("firmware.hex", bram)`. `py firmware/build.py` deploys the firmware image
to the registered `new/firmware.hex`. At this update it matches
`firmware/firmware.hex` (1024 words); it is not `firmware/bram_test.hex`.

## Simulation

Add these files to Simulation Sources:

    CNN.v
    cnn_docx_reference.v
    dma32_to_rgb24.v
    cnn_memory_subsystem.v
    Tb_CNN.v

The file is `Tb_CNN.v`, but its module name and the project simulation top are
`tb_CNN`. Include the Xilinx primitive library for `BUFGCE`.

The testbench:

1. Loads RGB frame data.
2. Packs the frame into 768 32-bit words.
3. Runs the baseline AXI-Lite path.
4. Runs DMA using memory buffers 0 and 1.
5. Checks runtime configuration readback and zero-length-frame defaulting.
6. Switches baseline/DMA mode without reset.
7. Checks automatic ping-pong buffer selection across two START commands.
8. Polls STATUS until DONE and reads RESULT.
9. Prints end-to-end cycles, compute cycles and DMA read count.

Typical frame files are:

    CNN_RTL/human_frames.mem
    CNN_RTL/nonhuman_frame.mem

## Open and build with Vivado

BRAM firmware for the PicoRV32 CPU is available in [firmware/README.md](firmware/README.md).
Run `py firmware/build.py` to build the RV32I program and update `firmware.hex`.
It boots from the 4 KiB BRAM, reports over UART, and controls CNN baseline/DMA/ping-pong runs.

Open:

    SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.xpr

Or use Tcl:

    open_project SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.xpr

Recommended flow:

1. Set soc_top as the synthesis top.
2. Align the target device, board pin assignments and I/O voltages, then check that `soc_top.xdc` is active.
3. Check that all .mem files are present.
4. Run Synthesis.
5. Run Implementation using `impl_100MHz` after the board constraints are aligned.
6. Review timing and utilization reports.
7. Generate Bitstream.

The XDC contains the 100 MHz clock constraint:

    create_clock -period 10.000 -name sys_clk [get_ports clk]

## Python and export files

The CNN training/export files are maintained in this repository under `CNN_RTL/`:

    CNN_layer.py
    CNN_MEM.py
    export_cifar_frames.py
    tb_CNN.v

They are used to train the model, quantize weights, export .mem files, and generate frame test data.

## Notes

- The RTL uses fixed-point INT8 data, so results can differ from floating-point training.
- RGB byte order must be identical in Python, the testbench, DMA, and CNN.
- classification is valid only when STATUS.done is set.
- If synthesis takes too long, verify that the sequential FSM core is used instead of the old task-based process_frame model.
- After changing weights, run simulation before synthesis.
- Build/cache/log changes and new generated outputs are excluded by `.gitignore`. Some generated files remain tracked from older commits. Files absent from the local folder were removed from `main` during the latest synchronization; Git history remains available.
- Do not rewrite CONFIG, source frame data or DMA buffers while the current inference is using them. The current RTL does not snapshot every CONFIG field at START.

## CNN clock gating and frame BRAM

`CNN.v` uses `BUFGCE` with `SIM_DEVICE="7SERIES"`. It gates the RGB packer and
CNN core with `rst | start_pending | busy_reg | cnn_result_valid`. AXI registers,
frame BRAM and the DMA controller stay on the original system clock, so software
can read status and issue START while the compute clock is stopped.

The baseline `frame_mem` is 768 x 32 bits, with byte writes and synchronous reads
using `ram_style="block"`. START fetches word 0; each accepted word prefetches the
next word. Data remains stable under backpressure. Reset does not clear the RAM;
software must upload a valid frame before its first use.

Matched synthesis on **Artix-7 `xc7a200tfbg676-1`**, Vivado 2025.2, 100 MHz,
phased DDR enabled, without XDC:

| Resource | Before frame BRAM | After frame BRAM |
|---|---:|---:|
| Total LUT | 5097 | 4235 |
| LUT as memory | 1734 | 966 |
| Flip-flops | 2426 | 2398 |
| BRAM tiles | 7 | 8 |

The frame RAM mapped to one RAMB36E1. These are historical synthesis results,
not post-route results or resource predictions for the current Zynq target.

Run the dedicated regression from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File firmware/sim/run_cnn_clock_gating.ps1 -VivadoBin D:/Vivado_data/2025.2/Vivado/bin
```

Adjust `-VivadoBin` to the installed location. The latest recorded regression
passed five frames with full pixel/classification checks, baseline/DMA mode
switches, partial writes, zero strobes, backpressure, RAM retention across reset,
idle AXI access and idle/busy reset. Success marker: `CNN CLOCK GATING PASS`.
Logs are generated locally under `firmware/build/sim_cnn_clock_gating/`.
See [firmware instructions](firmware/README.md) for CPU/UART integration tests.

## DDR MMCM and power results

The MMCM in `parallel.v` shifts only the forwarded DDR output clock; CPU, CNN,
AXI and data ODDR use the system clock. At 100 MHz the current RTL uses a 1.2 GHz
VCO and 219 fine phase steps (about 3.259 ns, 117.054 degrees). The clock ODDR
also inverts that waveform. `soc_top.v` defaults `DDR_TX_PHASED_CLOCK` to 0, but
the `.xpr` overrides it to 1. Disabling it requires rechecking DDR timing.

Earlier vectorless power reports showed I/O estimates rising from about
79 to 104 mW. The DDR data bus accounted for 98.9% of that increase through a
changed propagated activity estimate. The reports used different Artix parts
and clock/netlist configurations, with low activity confidence; they do not
isolate a power penalty from frame BRAM. Compare the same device, clocks,
constraints and workload using realistic simulation activity/SAIF.

## Known limitations and documentation

[SoC review](SOC_REVIEW_2026-10-27.md) records reproduced issues including CPU/DMA
simultaneous-read deadlock, memory writes using live AWADDR, parallel-result
capture and I2C sequencing. The weight paths were subsequently fixed for the
current workspace; the other findings have not been resolved by this update.
Old timing scripts referencing `synth_1`, `impl_1` or `constrs_100MHz` require
adaptation to the current run structure before reuse.

- [CNN architecture and optimizations](CNN_documentation_optimization.md)
- [Firmware and host usage](firmware/README.md)
- [AXI4 BRAM interface](firmware/AXI4_BRAM.md)
- [Historical pipeline experiment](firmware/PIPELINE_100MHZ_TRIAL.md)
- [Historical timing changes](firmware/NOTE_CHINH_SUA_TIMING_100MHZ.md)

## Repository

[H7yde/custom_SOC](https://github.com/H7yde/custom_SOC)

