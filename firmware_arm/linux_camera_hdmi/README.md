# USB camera -> custom SoC HDMI (PYNQ-Z2 Linux)

## Hướng dẫn nhanh bằng tiếng Việt

Hướng dẫn từ lúc chuẩn bị board, build Vivado, export XSA, ghi SD đến nạp
JTAG hoặc chạy Linux nằm tại
**[Nạp lên board Zynq từng bước](https://github.com/H7yde/custom_SOC/blob/main/firmware_arm/BOARD_SETUP.md)**.
Với webcam/CNN, thực hiện mục 2 rồi mục 4 trong hướng dẫn đó.

1. **Windows:** build thiết kế `soc_top`, export XSA với **Include bitstream**.
   Từ gốc repo, đóng gói bằng lệnh dưới đây (thay đường dẫn nếu XSA ở chỗ khác):

   ```powershell
   python firmware_arm/linux_camera_hdmi/prepare_package.py --xsa SOC_HUFLIT_2026_parallel_125MHz/soc_top.xsa
   ```

2. **Board:** boot thẻ SD PYNQ-Z2, kết nối Ethernet/SSH hoặc Jupyter, cắm màn
   hình vào HDMI OUT và webcam vào USB HOST. Dừng phiên debug Vitis trước khi boot Linux.
3. Upload `camera_hdmi_pynq.zip` vừa tạo lên board. Trong terminal **Linux của
   board**, chuyển tới nơi upload và chạy:

   ```bash
   unzip camera_hdmi_pynq.zip -d camera_hdmi
   cd camera_hdmi
   sudo bash run_camera_hdmi.sh --bars --frames 180
   ```

4. Khi thanh màu đã hiển thị, chạy webcam và CNN:

   ```bash
   sudo bash run_camera_hdmi.sh --device /dev/video0 --fourcc MJPG --fps 15 --cnn --cnn-every 5
   ```

Đổi `/dev/video0` theo webcam thực tế. Launcher thiết lập môi trường PYNQ/XRT,
ứng dụng tự nạp cặp `soc_camera_hdmi.bit`/`.hwh` vào PL. Giữ nguyên basename
và dùng BIT/HWH lấy từ cùng XSA. Nhấn Ctrl+C để dừng; reboot xong cần chạy lại
launcher. Các bước chi tiết và xử lý lỗi ở dưới.

This is a **Linux/PYNQ application**, not a Vitis standalone ELF. The standalone
color-bar application remains unchanged. AMD's Zynq standalone USB driver does
not provide USB host support/UVC webcam capture:
[AMD driver limitations](https://xilinx-wiki.atlassian.net/wiki/spaces/A/pages/18842117/Zynq+Standalone+USB+device+driver).

Pipeline: UVC webcam -> Linux V4L2/OpenCV -> ARM resize to 640x480 -> G/B/R
display buffers in contiguous DDR -> custom MM2S VDMA -> video out -> RGB2DVI.
By default this version displays live camera video. Add `--cnn` to enable the
existing FPGA CNN and display its person/no-person classification.

The custom overlay is used throughout. **Do not load base.bit** to display video:
it would replace your CNN/SoC hardware. The program does not use
`base.video.hdmi_out`, because the custom BD has different names and structure.

## Prepare on Windows

From the repository root:

```powershell
python firmware_arm/linux_camera_hdmi/prepare_package.py --xsa SOC_HUFLIT_2026_parallel_125MHz/soc_top.xsa
```

The script extracts both BIT and HWH from the specified XSA,
renames them to `soc_camera_hdmi.bit`/`.hwh`, copies the program/instructions,
and writes a SHA256 manifest. Output is `camera_hdmi_pynq.zip` in this folder.
It does not rebuild hardware. If hardware changes, export a matching new XSA and
run with `--xsa PATH`. Preserve the BIT/HWH basename pair.

## Boot and connect

1. Stop Vitis debug sessions/disconnect JTAG. Do not run the standalone ELF while
   Linux is running: it would overwrite DDR and reconfigure the active PS.
2. Power off, choose the board's SD boot setting, insert the PYNQ-Z2 Linux SD,
   and power on. Connect through the existing PYNQ network/Jupyter interface.
3. Connect the webcam to **USB HOST**, using the proper host/OTG adapter if
   required. USB PROG/UART is not the webcam port. Use HDMI OUT for the monitor.
4. Upload `camera_hdmi_pynq.zip` through Jupyter to a new directory on the board,
   or use SCP to your existing board account. Extract it in a Linux terminal:

```bash
unzip camera_hdmi_pynq.zip -d camera_hdmi
cd camera_hdmi
```

Do not assume a particular account, password, hostname or board IP; use the
connection that already works for your SD image.

## Verify camera and Python environment

Run on the **board**, not Windows:

```bash
lsusb
ls /dev/video*
python3 -c "import pynq, cv2, numpy; print('PYNQ/OpenCV ready')"
```

If `v4l2-ctl` is installed:

```bash
v4l2-ctl --list-devices
v4l2-ctl -d /dev/video0 --list-formats-ext
```

Some webcams create multiple video nodes; select the node that provides real
capture frames. Use an advertised resolution/format; the program requests
640x480 MJPG at 15 FPS and resizes returned frames for the display. If imports
fail, select the SD image's Python environment used by its PYNQ notebooks before
installing/replacing packages. Root access is normally required for PL MMIO/CMA;
use that same environment under sudo or a root-owned PYNQ notebook.

## Run HDMI first, then camera

Recommended CLI launcher (loads both the PYNQ Python and XRT environments):

```bash
sudo bash run_camera_hdmi.sh --bars --frames 180
sudo bash run_camera_hdmi.sh --device /dev/video0 --fourcc MJPG --fps 15
```

If an earlier package reports `No Devices Found`, enter `sudo -i`, source
`/etc/profile.d/pynq_venv.sh` and `/etc/profile.d/xrt_setup.sh`, then start a new
Python process. Selecting the venv interpreter alone does not initialize XRT.
Missing setup scripts or an empty `Device.devices` after sourcing require checking
the board's runtime/kernel image; installing Python packages alone will not fix it.

First verify the new Linux flow using bars (the command below assumes the board's
system python3 includes PYNQ/OpenCV; use its actual interpreter otherwise):

```bash
sudo python3 camera_hdmi.py --bars --frames 180
```

The display stops and goes blank after this bounded test. Then run the webcam:

```bash
sudo python3 camera_hdmi.py --device /dev/video0 --fourcc MJPG --fps 15
```

If the camera supports YUYV instead of MJPG:

```bash
sudo python3 camera_hdmi.py --device /dev/video0 --fourcc YUYV --fps 15
```

Ctrl+C stops capture, resets the VDMA, disables VTC and frees buffers after the
DMA is quiescent. Runtime prints frame count, measured FPS and VDMA status every
60 frames. FPS is measured, not promised. The monitor refresh remains 60 Hz even
when the camera produces only 15 FPS.

## Run the existing FPGA CNN

First fix `No Devices Found` and confirm that both bars and camera display work.
Update the files on the board from the latest ZIP (it now includes `cnn_fpga.py`).
In a board terminal, from the directory where the ZIP was extracted:

```bash
sudo bash run_camera_hdmi.sh --device /dev/video0 --fourcc MJPG --fps 15 --cnn --cnn-every 5
```

Alternatively enter `sudo -i`, source `/etc/profile.d/pynq_venv.sh` and
`/etc/profile.d/xrt_setup.sh`, then run `python3 camera_hdmi.py ... --cnn` from
that initialized shell. Do not start a Vitis standalone program alongside Linux.

The client takes the untouched full camera frame before drawing overlay text,
converts BGR to RGB, resizes using **Pillow bilinear** to 32x32 (matching training),
packs the 3072 original RGB bytes MSB first into 768 MMIO words, and sends them
to the existing CNN. The PL performs its own Q4.4 input mapping; Python does not
normalize pixels a second time. HDMI remains 640x480.

At `0x40004000`, the client validates bridge ID, claims OWNER as ARM (2), uploads
the image, sets CONFIG=768 with Pico DMA off, writes START, polls DONE/fault,
reads classification/cycles and releases ownership. A busy Pico is not evicted.
Run **one ARM client at a time**; the hardware ownership ID cannot distinguish
two Linux processes. Model weights are embedded in the bitstream, not loaded
from a `.pth` file at runtime; using another bitstream can change the model.

HDMI shows `LAST CNN: CO NGUOI` or `LAST CNN: KHONG CO NGUOI`. UART/terminal prints
`CNN class=... cycles=... core_ms=...`. The core time uses 125 MHz and excludes
image capture, resizing, MMIO upload, polling and display time. `--cnn-every 5`
runs inference once per five displayed frames and retains the most recent label
between inferences. Use `--cnn-every 1` for every frame at the cost of throughput.

This is **whole-frame binary classification**, without boxes or confidence
percentages. It uses the current RGB32 model; its known validation limitations
remain. Tests of the Linux client use mocked registers; live CNN inference still
requires board validation.

On timeout/watchdog fault, the client raises an error and retains the lock rather
than treating a stale result as valid. Acknowledge/reset with `--cnn-recover` on
the next run (the program also reloads the overlay at startup). Recovery never
steals Pico ownership. An actual MMIO bus fault may cause a Linux process signal
instead of a Python exception; fix/reset the hardware before retrying.

## Hardware and buffer ownership

Expected addresses: VDMA `0x43000000`, VTC `0x43C00000`. The HWH is checked before
PL programming. FCLK0 is set to 100 MHz; existing PL generates 25.2 MHz pixel and
126 MHz serial clocks. Video mode matches the successful standalone bars test,
including positive internal H/V sync and existing NOT gates before RGB2DVI.

Three CMA buffers are allocated using `pynq.allocate`. Never use a Python/numpy
virtual pointer or a guessed DDR physical address for DMA: Linux owns DDR.
Current hardware exposes only the first 512 MiB through HP0, so physical addresses
are checked. Frames are stored G,B,R as required by the AXI video/RGB2DVI path.
That is different from the CNN's R,G,B input order.

The driver uses VDMA **parking mode**. It renders into an inactive buffer,
flushes it, changes the park reference, and waits for the hardware's current-frame
index before reusing the old buffer. It does not modify the buffer currently
being scanned. The register recipe is derived from the current working BSP's
`XVtc_SetGeneratorTiming`, `XVtc_SetSource` and VDMA register definitions.

## Troubleshooting / limits

- No `/dev/video*`: inspect `dmesg`/`lsusb`, USB host cable/VBUS, webcam UVC support,
  and the SD image's host/PHY configuration. Python cannot substitute for missing
  USB host/UVC kernel support. Do not use the USB gadget driver as a host driver.
- Missing `pynq`, OpenCV or CMA allocation: use a PYNQ-Z2-compatible image and its
  installed environment; check available CMA memory. This package is not a Linux
  kernel/device-tree installation or a generic desktop-Linux program.
- Bars work but camera does not: test another capture node, MJPG/YUYV, and lower
  camera FPS. The code accepts the actual captured size and resizes to 640x480.
- VDMA errors/park timeout: stop, retain the exact error, confirm the packaged XSA
  matches the hardware/PS configuration. Do not let another overlay/DRM driver or
  notebook own this VDMA/VTC concurrently. Reset the board after shutdown failure.
- PYNQ/Linux must retain compatible PS DDR, USB MIO and FCLK configuration. Do not
  execute `ps7_init.tcl` from Vitis against a running Linux system.

Local tests validate byte order, timing constants, parking protocol, timeout/error
handling, package consistency and syntax. Actual USB capture, PYNQ allocation,
overlay loading and display require testing on the board. Existing HDMI success
under standalone does not by itself validate the Linux launch path.
