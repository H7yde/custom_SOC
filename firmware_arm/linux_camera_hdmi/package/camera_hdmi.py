#!/usr/bin/env python3
"""USB UVC camera -> custom SoC VDMA -> HDMI on PYNQ-Z2 Linux.

Uses the custom overlay, not base.bit/base.video.hdmi_out. --cnn enables PL CNN.
Run with the board's PYNQ Python environment and access to /dev/mem/CMA.
"""
import argparse
from pathlib import Path
import time

WIDTH, HEIGHT, STRIDE = 640, 480, 1920
VDMA_BASE, VTC_BASE = 0x43000000, 0x43C00000
# Same register values as XVtc_SetGeneratorTiming/SetSource in the working BSP.
VTC_SOURCE = 0x07F7EF00
VTC_REGISTERS = {
    0x60: (HEIGHT << 16) | WIDTH,
    0x68: 0,  # Progressive RGB encoding.
    0x6C: 0x7F,  # Positive internal sync; PL NOT gates invert H/V before TMDS.
    0x70: 800,
    0x74: (525 << 16) | 525,
    0x78: (752 << 16) | 656,
    0x7C: (640 << 16) | 640,
    0x80: (491 << 16) | 489,
    0x84: (656 << 16) | 656,
    0x88: (640 << 16) | 640,
    0x8C: (491 << 16) | 489,
    0x90: (656 << 16) | 656,
    0x94: HEIGHT << 16,
}


def pack_bgr_for_display(bgr, destination):
    """OpenCV BGR -> AXI video's byte order G,B,R (not the CNN RGB order)."""
    destination[:, :, 0] = bgr[:, :, 1]
    destination[:, :, 1] = bgr[:, :, 0]
    destination[:, :, 2] = bgr[:, :, 2]


def wait_for(predicate, message, timeout=1.0):
    deadline = time.monotonic() + timeout
    while not predicate():
        if time.monotonic() >= deadline:
            raise TimeoutError(message)
        time.sleep(0.001)


class Display:
    def __init__(self, dma, vtc, buffers):
        self.dma, self.vtc, self.buffers = dma, vtc, buffers
        self.current = 0

    def check(self):
        status = self.dma.read(0x04)
        if status & 0xFF0:
            raise RuntimeError(f"VDMA MM2S error: SR=0x{status:08x}")
        if status & 1:
            raise RuntimeError(f"VDMA MM2S halted: SR=0x{status:08x}")

    def start(self):
        self.dma.write(0x00, 4)  # Reset MM2S before changing buffer addresses.
        wait_for(lambda: not self.dma.read(0x00) & 4, "VDMA reset timed out")
        self.vtc.write(0x00, 0)
        for offset, value in VTC_REGISTERS.items():
            self.vtc.write(offset, value)
        self.vtc.write(0x00, VTC_SOURCE | 2)  # Sources + register update.
        for i, frame in enumerate(self.buffers):
            address = int(frame.physical_address)
            if address & 63 or address < 0x100000 or address + frame.nbytes > 0x20000000:
                raise RuntimeError(f"Framebuffer outside current 512 MiB DDR aperture: {address:#x}")
            frame.flush()
            self.dma.write(0x5C + i * 4, address)
        self.dma.write(0x04, 0xFFFFFFFF)  # Clear old sticky status.
        self.dma.write(0x28, self.dma.read(0x28) & ~0x1F)  # Park at frame 0.
        self.dma.write(0x00, 1)  # Run, PARK mode (circular/genlock disabled).
        self.dma.write(0x58, STRIDE)
        self.dma.write(0x54, STRIDE)
        self.dma.write(0x50, HEIGHT)  # VSIZE last starts transfer.
        self.vtc.write(0x00, VTC_SOURCE | 7)  # Global + generator + update.
        time.sleep(0.1)
        self.check()
        wait_for(lambda: (self.dma.read(0x28) >> 16) & 0x1F == 0,
                 "VDMA did not park at initial frame")

    def present(self, bgr):
        self.check()
        index = (self.current + 1) % len(self.buffers)
        # The previous present waited for its park switch; this is not scanned.
        frame = self.buffers[index]
        pack_bgr_for_display(bgr, frame)
        frame.flush()
        self.dma.write(0x28, (self.dma.read(0x28) & ~0x1F) | index)

        def switched():
            self.check()
            return ((self.dma.read(0x28) >> 16) & 0x1F) == index

        wait_for(switched, "VDMA frame switch timed out; check stream/pixel clocks")
        self.current = index

    def stop(self):
        # Reset, and wait for completion BEFORE freeing any CMA buffers.
        self.dma.write(0x00, 4)
        wait_for(lambda: not self.dma.read(0x00) & 4, "VDMA shutdown reset timed out")
        self.vtc.write(0x00, 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bit", type=Path, default=Path(__file__).with_name("soc_camera_hdmi.bit"))
    parser.add_argument("--device", default="/dev/video0")
    parser.add_argument("--fourcc", choices=("MJPG", "YUYV"), default="MJPG")
    parser.add_argument("--fps", type=int, default=15)
    parser.add_argument("--frames", type=int, default=0, help="Stop after N frames; 0 runs until Ctrl+C")
    parser.add_argument("--bars", action="store_true", help="Test custom overlay HDMI without camera")
    parser.add_argument("--cnn", action="store_true", help="Run existing FPGA CNN and draw person/no-person result")
    parser.add_argument("--cnn-every", type=int, default=5, help="Infer once per N displayed camera frames")
    parser.add_argument("--cnn-recover", action="store_true", help="Abort/acknowledge own old CNN job before use")
    args = parser.parse_args()
    if args.fps <= 0 or args.frames < 0:
        parser.error("--fps must be positive and --frames nonnegative")
    if args.cnn_every <= 0 or (args.cnn and args.bars) or (args.cnn_recover and not args.cnn):
        parser.error("--cnn-every must be positive; --cnn needs camera; --cnn-recover requires --cnn")
    if not args.bit.is_file() or not args.bit.with_suffix(".hwh").is_file():
        parser.error("Matching .bit and .hwh with identical basenames are required")
    import cv2
    import numpy as np
    from pynq import Overlay, MMIO, allocate, Clocks, Device
    if not Device.devices:
        raise RuntimeError(
            "PYNQ found no FPGA devices. In a root bash shell, source "
            "/etc/profile.d/pynq_venv.sh and /etc/profile.d/xrt_setup.sh, "
            "then run again in a NEW Python process. This is not a camera error."
        )

    capture = None
    buffers = []
    display = None
    safe_to_free = True
    try:
        if not args.bars:
            capture = cv2.VideoCapture(args.device, cv2.CAP_V4L2)
            if not capture.isOpened():
                raise RuntimeError(f"Cannot open {args.device}; check UVC enumeration with v4l2-ctl/lsusb")
            capture.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*args.fourcc))
            capture.set(cv2.CAP_PROP_FRAME_WIDTH, WIDTH)
            capture.set(cv2.CAP_PROP_FRAME_HEIGHT, HEIGHT)
            capture.set(cv2.CAP_PROP_FPS, args.fps)
            capture.set(cv2.CAP_PROP_BUFFERSIZE, 1)
            ok, first = capture.read()
            if not ok or first is None:
                raise RuntimeError("Camera opened but no frame received; try --fourcc YUYV or another video node")
            print(f"Camera: {first.shape[1]}x{first.shape[0]} -> HDMI {WIDTH}x{HEIGHT}")
        overlay = Overlay(str(args.bit.resolve()), download=False)
        addresses = {int(v["phys_addr"]) for v in overlay.ip_dict.values() if "phys_addr" in v}
        if not {VDMA_BASE, VTC_BASE}.issubset(addresses):
            raise RuntimeError("HWH is not this SoC: expected VDMA 0x43000000 and VTC 0x43c00000")
        overlay.download()
        Clocks.fclk0_mhz = 100.0
        cnn = None
        last_label = last_cycles = None
        if args.cnn:
            from cnn_fpga import CnnFpga, CNN_BASE
            cnn = CnnFpga(MMIO(CNN_BASE, 0x1000))
            if args.cnn_recover:
                cnn.recover()
            print("FPGA CNN enabled: full-frame RGB32 person presence, no bounding boxes.", flush=True)
        dma, vtc = MMIO(VDMA_BASE, 0x10000), MMIO(VTC_BASE, 0x10000)
        display = Display(dma, vtc, buffers)
        # Stop a previous display before allocating/reusing CMA memory.
        display.stop()
        for _ in range(3):
            buffer = allocate(shape=(HEIGHT, WIDTH, 3), dtype=np.uint8)
            buffers.append(buffer)
            buffer[:] = 0
        safe_to_free = False
        display.start()
        print("Custom SoC HDMI active, 640x480/60 Hz. Ctrl+C to stop.", flush=True)
        count, start = 0, time.monotonic()
        while args.frames == 0 or count < args.frames:
            if args.bars:
                bgr = np.zeros((HEIGHT, WIDTH, 3), dtype=np.uint8)
                for i, color in enumerate(((255,255,255),(0,255,255),(255,255,0),(0,255,0),
                                           (255,0,255),(0,0,255),(255,0,0),(0,0,0))):
                    bgr[:, i*80:(i+1)*80] = color
            else:
                ok, bgr = capture.read()
                if not ok or bgr is None:
                    raise RuntimeError("Camera frame read failed/disconnected")
                # Infer on the untouched full camera frame, before adding text.
                if cnn is not None and count % args.cnn_every == 0:
                    last_label, last_cycles = cnn.classify(bgr)
                    print(f"CNN class={last_label} "
                          f"{'CO_NGUOI' if last_label else 'KHONG_CO_NGUOI'} "
                          f"cycles={last_cycles} core_ms={last_cycles/125000:.3f}", flush=True)
                bgr = cv2.resize(bgr, (WIDTH, HEIGHT), interpolation=cv2.INTER_LINEAR)
                cv2.putText(bgr, "USB CAMERA -> FPGA HDMI", (16, 28),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0,255,0), 1)
                if last_label is not None:
                    text = "LAST CNN: " + ("CO NGUOI" if last_label else "KHONG CO NGUOI")
                    cv2.rectangle(bgr, (8, 38), (550, 78), (0,0,0), -1)
                    cv2.putText(bgr, text, (16, 65), cv2.FONT_HERSHEY_SIMPLEX,
                                0.8, (0,255,255) if last_label else (0,255,0), 2)
            display.present(bgr)
            count += 1
            if count % 60 == 0:
                print(f"Frames={count} average_fps={count/(time.monotonic()-start):.1f} "
                      f"VDMA_SR=0x{dma.read(4):08x}", flush=True)
    except KeyboardInterrupt:
        print("Stopping camera/display")
    finally:
        if capture is not None:
            capture.release()
        if display is not None:
            try:
                display.stop()
                safe_to_free = True
            except Exception as error:
                print(f"Display stop failed: {error}. Reset board before restarting.")
        if safe_to_free:
            for frame in buffers:
                frame.freebuffer()


if __name__ == "__main__":
    main()
