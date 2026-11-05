import unittest
from unittest.mock import patch
import numpy as np
from camera_hdmi import Display, pack_bgr_for_display, wait_for, VTC_SOURCE, VTC_REGISTERS


class Buffer(np.ndarray):
    def __new__(cls, address):
        obj = np.zeros((480, 640, 3), np.uint8).view(cls)
        obj.physical_address = address
        obj.flushed = False
        return obj

    def flush(self):
        self.flushed = True


class MMIO:
    def __init__(self):
        self.values, self.writes = {}, []

    def read(self, offset):
        return self.values.get(offset, 0)

    def write(self, offset, value):
        self.writes.append((offset, value))
        self.values[offset] = value
        if offset == 0 and value == 4:
            self.values[0] = 0
        if offset == 4:
            self.values[4] = 0
        if offset == 0x28:
            # Model switch acknowledgement after the requested park slot.
            self.values[offset] = (value & ~0x1F0000) | ((value & 31) << 16)


class CameraDisplayTests(unittest.TestCase):
    def test_unacknowledged_switch_times_out(self):
        dma, vtc = MMIO(), MMIO()
        buffers = [Buffer(0x1000000 + i * 0x100000) for i in range(3)]
        display = Display(dma, vtc, buffers)
        display.start()
        # Hardware does not acknowledge the requested slot: never reuse old one.
        with patch.object(dma, "write"), patch("camera_hdmi.time.monotonic", side_effect=[0, 2]):
            with self.assertRaisesRegex(TimeoutError, "switch"):
                display.present(np.zeros((480, 640, 3), np.uint8))
        self.assertEqual(display.current, 0)
        with self.assertRaises(TimeoutError):
            wait_for(lambda: False, "reset timeout", timeout=0)

    def test_bgr_to_axi(self):
        source = np.array([[[1, 2, 3], [255, 0, 0]]], np.uint8)
        result = np.empty_like(source)
        pack_bgr_for_display(source, result)
        np.testing.assert_array_equal(result, [[[2, 1, 3], [0, 255, 0]]])
        np.testing.assert_array_equal(source, [[[1, 2, 3], [255, 0, 0]]])

    def test_parking_does_not_write_active_frame(self):
        dma, vtc = MMIO(), MMIO()
        buffers = [Buffer(0x1000000 + i * 0x100000) for i in range(3)]
        display = Display(dma, vtc, buffers)
        display.start()
        self.assertEqual(vtc.values[0], VTC_SOURCE | 7)
        self.assertEqual(dma.values[0], 1)  # Park mode, not circular.
        self.assertEqual(dma.values[0x50], 480)
        self.assertEqual(dma.values[0x54], 1920)
        for index in (1, 2, 0):
            previous = display.current
            snapshot = buffers[previous].copy()
            display.present(np.full((480, 640, 3), index + 10, np.uint8))
            self.assertEqual(display.current, index)
            np.testing.assert_array_equal(buffers[previous], snapshot)
            self.assertTrue(buffers[index].flushed)
        display.stop()
        self.assertEqual(vtc.values[0], 0)

    def test_fault_and_out_of_aperture(self):
        dma, vtc = MMIO(), MMIO()
        dma.values[4] = 0x40
        with self.assertRaisesRegex(RuntimeError, "error"):
            Display(dma, vtc, []).check()
        dma.values[4] = 0
        with self.assertRaisesRegex(RuntimeError, "outside"):
            Display(dma, vtc, [Buffer(0x20000000)]).start()

    def test_vtc_against_working_mode(self):
        self.assertEqual(VTC_REGISTERS[0x70], 640 + 16 + 96 + 48)
        self.assertEqual(VTC_REGISTERS[0x74] & 0xFFFF, 480 + 10 + 2 + 33)
        # All explicit source fields selected; interlace bit stays clear.
        masks = [0x04000000,0x02000000,0x01000000,0x00800000,0x00400000,
                 0x00200000,0x00100000,0x40000,0x20000,0x10000,0x8000,
                 0x4000,0x2000,0x800,0x400,0x200,0x100]
        self.assertEqual(VTC_SOURCE, sum(masks))
        self.assertFalse(VTC_SOURCE & 0x80000)


if __name__ == "__main__":
    unittest.main()
