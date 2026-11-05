# USB camera -> custom SoC HDMI (PYNQ-Z2 Linux)

This is a **Linux/PYNQ application**, not a Vitis standalone ELF. The standalone
color-bar application remains unchanged. AMD's Zynq standalone USB driver does
not provide USB host support/UVC webcam capture:
[AMD driver limitations](https://xilinx-wiki.atlassian.net/wiki/spaces/A/pages/18842117/Zynq+Standalone+USB+device+driver).

Pipeline: UVC webcam -> Linux V4L2/OpenCV -> ARM resize to 640x480 -> G/B/R
display buffers in contiguous DDR -> custom MM2S VDMA -> video out -> RGB2DVI.
This version displays live camera video; CNN inference is not enabled yet.

The custom overlay is used throughout. **Do not load base.bit** to display video:
it would replace your CNN/SoC hardware. The program does not use
`base.video.hdmi_out`, because the custom BD has different names and structure.

## Prepare on Windows

From the repository root:

```powershell
python firmware_arm/linux_camera_hdmi/prepare_package.py
```

The script extracts both BIT and HWH from the same XSA used by `soc_platform`,
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
