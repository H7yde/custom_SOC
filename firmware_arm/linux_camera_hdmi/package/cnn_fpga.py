"""Linux MMIO client for the existing ARM/CNN bridge at 0x40004000.

One ARM caller only. Inference executes in PL, not in Python/PyTorch.
Image preprocessing matches training: full-frame Pillow bilinear RGB32 bytes.
"""
import time

CNN_BASE = 0x40004000
OWNER, ID, RECOVERY = 0xF00, 0xF04, 0xF08
CONFIG, CYCLES, RESULT, STATUS, START = 0xFE4, 0xFE8, 0xFF4, 0xFF8, 0xFFC


def image_words(bgr):
    import numpy as np
    from PIL import Image
    if bgr.dtype != np.uint8 or bgr.ndim != 3 or bgr.shape[2] != 3:
        raise ValueError("Expected OpenCV HxWx3 uint8 BGR frame")
    rgb = Image.fromarray(np.ascontiguousarray(bgr[:, :, ::-1]), "RGB")
    # Pillow <9 and >=9 support the same bilinear mode under different names.
    bilinear = getattr(Image, "Resampling", Image).BILINEAR
    payload = rgb.resize((32, 32), resample=bilinear).tobytes()
    return [int.from_bytes(payload[i:i+4], "big") for i in range(0, 3072, 4)]


class CnnFpga:
    def __init__(self, mmio, timeout=1.0):
        if timeout <= 0:
            raise ValueError("CNN timeout must be positive")
        self.reg = mmio
        self.timeout = timeout
        if self.reg.read(ID) != 0x434E4E42:
            raise RuntimeError("Wrong FPGA bitstream: ARM/CNN bridge signature missing")

    def claim(self):
        deadline = time.monotonic() + self.timeout
        while True:
            self.reg.write(OWNER, 1)
            status = self.reg.read(OWNER)
            if status & 3 == 2:
                return status
            if time.monotonic() >= deadline:
                raise TimeoutError("CNN ownership timeout; PicoRV32/another client may own CNN")
            time.sleep(0.001)

    def recover(self):
        # Same recovery protocol as firmware_arm/cnn_bridge.c. Never steals Pico.
        self.claim()
        self.reg.write(RECOVERY, 1)
        deadline = time.monotonic() + self.timeout
        while self.reg.read(RECOVERY) & 0x103:
            if time.monotonic() >= deadline:
                raise TimeoutError("CNN recovery timeout; reset board")
            time.sleep(0.001)
        self.reg.write(OWNER, 0)

    def classify(self, bgr):
        words = image_words(bgr)
        owner_status = self.claim()
        if owner_status & 0x100:
            raise RuntimeError("ARM owns an unfinished CNN job; recover before retry")
        fault = self.reg.read(RECOVERY)
        if fault & 0x103:
            raise RuntimeError(f"CNN watchdog/reset status=0x{fault:08x}; recover before retry")
        success = False
        try:
            for index, word in enumerate(words):
                self.reg.write(index * 4, word)
            self.reg.write(CONFIG, 768)  # Baseline local image RAM, no Pico DMA.
            if self.reg.read(CONFIG) != 768:
                raise RuntimeError("CNN configuration readback mismatch")
            self.reg.write(START, 1)
            deadline = time.monotonic() + self.timeout
            while True:
                fault = self.reg.read(RECOVERY)
                if fault & 0x103:
                    raise RuntimeError(f"CNN watchdog/reset status=0x{fault:08x}")
                status = self.reg.read(STATUS)
                if status & 3 == 2:
                    break
                if time.monotonic() >= deadline:
                    raise TimeoutError("CNN inference timed out; lock retained for recovery")
                time.sleep(0.001)
            label = self.reg.read(RESULT) & 1
            cycles = self.reg.read(CYCLES)
            if self.reg.read(RECOVERY) & 0x103:
                raise RuntimeError("CNN fault while retrieving result")
            success = True
            return label, cycles
        finally:
            # Preserve failed job ownership until an explicit abort/reset, so
            # another client cannot overwrite an inference still in progress.
            if success:
                self.reg.write(OWNER, 0)
