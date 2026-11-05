# HUFLIT 125 MHz SoC with CNN

The active Vivado project is
`SOC_HUFLIT_2026_parallel_125MHz/SOC_HUFLIT_2026.xpr`.
The combined `soc_top` includes PicoRV32/CNN and the Zynq PS USB/HDMI block
design, with an ARM-to-CNN AXI4-Lite bridge at `0x40004000`.
See [ARM/CNN integration](fpga_usb_hdmi/ARM_CNN_BRIDGE.md),
[ARM driver](firmware_arm/README.md), and
[COCO 2017 training](CNN_RTL/COCO2017.md) for the current workflow.
CNN input remains RGB 32x32. Dataset downloads, Vivado build outputs and
local backup snapshots are excluded from version control.

The Digilent `vivado-library` IP repository is included under
[`third_party/vivado-library`](third_party/vivado-library), with its original
licenses. The Vivado project uses a relative path to this copy. After cloning,
refresh the IP catalog and regenerate the block design output products.
PS initialization and ARM application software
are required to use USB/HDMI; programming the bitstream alone does not start video.

## Nạp và chạy trên board Zynq PYNQ-Z2

Hướng dẫn đầy đủ bằng tiếng Việt: **[Nạp lên board từng bước](firmware_arm/BOARD_SETUP.md)**.
Hướng dẫn dùng board PYNQ-Z2 (`xc7z020clg400-1`), Vivado/Vitis 2025.2 theo
project hiện tại; board Zynq khác cần cấu hình PS, chân và image riêng.

| Mục tiêu | Cách nạp | File cần có |
| --- | --- | --- |
| Thử HDMI bằng thanh màu | JTAG + Vitis standalone | `.bit`, `.xsa`, PS7 init và `arm_test.elf` cùng thiết kế |
| Webcam USB → HDMI → CNN | Boot SD PYNQ/Linux, rồi nạp overlay bằng Python | SD image PYNQ-Z2 và gói `camera_hdmi_pynq.zip` tự tạo |
| Bật nguồn tự chạy thanh màu | SD standalone với `BOOT.BIN` | FSBL + `.bit` + `arm_test.elf` |
| Gửi ảnh từ PC cho PicoRV32/CNN | Nạp `.bit`, giao tiếp UART PL | `firmware.hex` đã nhúng trong bitstream, USB–TTL 3,3 V |

Trình tự cho lần đầu:

1. Chuẩn bị cáp USB **PROG/UART**, nguồn, HDMI OUT và driver JTAG.
2. Mở `SOC_HUFLIT_2026_parallel_125MHz/SOC_HUFLIT_2026.xpr`, cập nhật IP
   catalog từ `third_party/vivado-library`, kiểm tra clock 125 MHz và build bitstream.
3. Export hardware **Include bitstream** thành `soc_top.xsa`.
4. Kiểm tra HDMI qua Vitis với `arm_test`, hoặc boot SD PYNQ để chạy webcam.
5. Với webcam, tạo gói trên Windows:

   ```powershell
   python firmware_arm/linux_camera_hdmi/prepare_package.py --xsa SOC_HUFLIT_2026_parallel_125MHz/soc_top.xsa
   ```

6. Chép ZIP lên board, giải nén rồi chạy trong terminal **Linux của board**:

   ```bash
   sudo bash run_camera_hdmi.sh --bars --frames 180
   sudo bash run_camera_hdmi.sh --device /dev/video0 --fourcc MJPG --fps 15 --cnn --cnn-every 5
   ```

Lệnh bước 6 chạy từ thư mục đã giải nén. Xem hướng dẫn chi tiết để ghi SD,
kết nối mạng, tạo platform Vitis, chọn file nạp và xử lý lỗi.
Các file `.bit`, `.xsa`, `.bin` và thư mục build được `.gitignore` bỏ qua;
sau khi clone cần build/export và tạo lại ZIP. Mỗi lần chạy Python launcher
sẽ nạp overlay; ứng dụng chưa được cấu hình tự chạy khi bật nguồn.

This repository contains the HUFLIT SoC FPGA project running directly from the PYNQ-Z2 H16 125 MHz clock. It integrates a PicoRV32 CPU, AXI/APB peripherals, a parallel/DDR interface, and a CNN accelerator for binary human/non-human classification.

The CPU, BRAM, AXI, CNN, and DDR data logic share the 125 MHz core clock
(8 ns period). One MMCM remains in the DDR transmitter to shift the forwarded
125 MHz clock; the core no longer uses a frequency-conversion MMCM. UART keeps
its configured baud rate using `CLK_FREQ=125000000`. SPI and I2C run their logic
at 125 MHz and generate slower serial signals using their existing dividers.
Build the combined design using the Vivado flow in
[the board setup guide](firmware_arm/BOARD_SETUP.md#2-build-bitstream-và-export-xsa-trên-windows).
The older `firmware/run_project_125MHz.tcl` checks the Pico/DDR clock topology
and is not the build entry point for the combined USB/HDMI design.
See [firmware/CLOCK_125MHZ.md](firmware/CLOCK_125MHZ.md) for core-clock details
and external I/O limits.

## Project layout

- `SOC_HUFLIT_2026_parallel_125MHz/SOC_HUFLIT_2026.xpr`: active Vivado project
- `SOC_HUFLIT_2026_parallel_125MHz/SOC_HUFLIT_2026.srcs/sources_1/new`: RTL and memory files
- `SOC_HUFLIT_2026_parallel_125MHz/SOC_HUFLIT_2026.srcs/constrs_1/new`: XDC constraints
- `SOC_HUFLIT_2026_parallel_125MHz/SOC_HUFLIT_2026.srcs/sim_2/new`: CNN simulation testbench
- `firmware`: PicoRV32 firmware, build tools and UART host client
- `firmware_arm`: ARM driver, board setup and Linux webcam/HDMI application
- `arm_test`: standalone ARM HDMI color-bar application
- `soc_platform`: Vitis platform sources; generated outputs must be rebuilt
- `CNN_RTL`: training, quantization, weights and RTL validation tools
- `third_party/vivado-library`: bundled Digilent IP cores and interface definitions

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

BRAM firmware for the PicoRV32 CPU is available in [firmware/README.md](firmware/README.md).
Run `py firmware/build.py` to build the RV32I program and update `firmware.hex`.
It boots from the 4 KiB BRAM, reports over UART, and controls CNN baseline/DMA/ping-pong runs.

Open:

    SOC_HUFLIT_2026_parallel_125MHz/SOC_HUFLIT_2026.xpr

Or use Tcl:

    open_project SOC_HUFLIT_2026_parallel_125MHz/SOC_HUFLIT_2026.xpr

Recommended flow:

1. Set soc_top as the synthesis top.
2. Check that soc_top.xdc is active.
3. Check that all .mem files are present.
4. Run Synthesis.
5. Run Implementation.
6. Review timing and utilization reports.
7. Generate Bitstream.

The active `soc_top.xdc` constrains the H16 PL clock to 125 MHz:

    create_clock -name clk_125m -period 8.000 -waveform {0.000 4.000} [get_ports clk]

PS FCLK0 for the video/AXI path is 100 MHz. It is separate from the 125 MHz
PicoRV32/CNN clock. Export a matching XSA after generating the bitstream;
follow [BOARD_SETUP.md](firmware_arm/BOARD_SETUP.md) to load it on hardware.

## COCO 2017 training and export

The active dataset is COCO 2017. The model classifies the entire RGB32 frame:
1 means at least one annotated person (including crowd annotations), and 0
means no person annotation. Training uses train2017; validation uses val2017,
with disjoint source image IDs. It is a binary classifier, not a box detector.

See [CNN_RTL/COCO2017.md](CNN_RTL/COCO2017.md) for downloading the official
archives, training from scratch, Q4.4 quantization-aware training, real RTL
verification, and installing the exported weights in the Vivado source tree.

`CNN_RTL/CNN_layer.py` is the training entry point. Data and output paths are
relative to the scripts rather than the current working directory. Exported
weights preserve the RTL architecture and FC ROM order.

## Notes

- The RTL uses fixed-point INT8 data, so results can differ from floating-point training.
- RGB byte order must be identical in Python, the testbench, DMA, and CNN.
- classification is valid only when STATUS.done is set.
- If synthesis takes too long, verify that the sequential FSM core is used instead of the old task-based process_frame model.
- After changing weights, run simulation before synthesis.
- Vivado build/cache directories and generated BIT/XSA files are ignored by Git and must be regenerated locally.

## Repository

https://github.com/H7yde/custom_SOC

