# HUFLIT 50 MHz SoC with CNN

This repository contains the HUFLIT SoC FPGA project running at 50 MHz. It integrates a PicoRV32 CPU, AXI/APB peripherals, a parallel/DDR interface, and a CNN accelerator for binary human/non-human classification.

## Project layout

- SOC_HUFLIT_2026.xpr: Vivado project
- SOC_HUFLIT_2026.srcs/sources_1/new: RTL source files
- SOC_HUFLIT_2026.srcs/constrs_1/new: XDC constraints
- SOC_HUFLIT_2026.srcs/sim_2/new: simulation testbenches
- KQ: waveforms, images, and experiment results
- Luanvan: thesis and design documents

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

The CNN RTL uses an FSM and one MAC per clock to reduce synthesis resources.

## Important CNN files

| File | Description |
|---|---|
| SOC_HUFLIT_2026.srcs/sources_1/new/CNN.v | AXI4-Lite CNN peripheral |
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

The four weight files must be added to Vivado as Design Sources or Memory Initialization Files.

## Simulation

Add these files to Simulation Sources:

    CNN.v
    cnn_docx_reference.v
    dma32_to_rgb24.v
    Tb_CNN.v

Set the simulation top to Tb_CNN.

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

    human_frame.mem
    nonhuman_frame.mem

## Open and build with Vivado

Open:

    SOC_HUFLIT_2026.xpr

Or use Tcl:

    open_project SOC_HUFLIT_2026.xpr

Recommended flow:

1. Set soc_top as the synthesis top.
2. Check that soc_top.xdc is active.
3. Check that all .mem files are present.
4. Run Synthesis.
5. Run Implementation.
6. Review timing and utilization reports.
7. Generate Bitstream.

The XDC contains the 50 MHz clock constraint:

    create_clock -period 20.000 -name sys_clk [get_ports clk]

## Python and export files

The CNN training/export files are maintained in the CNN_RTL repository:

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
- Vivado build and cache directories are included in this repository because the complete project was requested. They may be regenerated by Vivado.

## Repository

https://github.com/H7yde/Soc_Huflit_50MHz

