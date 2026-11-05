import unittest
from unittest.mock import patch
import numpy as np
from PIL import Image
from cnn_fpga import CnnFpga, image_words, OWNER, ID, RECOVERY, CONFIG, CYCLES, RESULT, STATUS, START


class Bridge:
    def __init__(self):
        self.owner, self.fault, self.polls = 0, 0, 0
        self.started = False
        self.values, self.writes = {}, []

    def read(self, offset):
        if offset == ID: return 0x434E4E42
        if offset == OWNER: return self.owner
        if offset == RECOVERY: return self.fault
        if offset == STATUS:
            # DONE from the previous job must not short-circuit the new job.
            if not self.started: return 2
            self.polls += 1
            return 1 if self.polls < 2 else 2
        if offset == RESULT: return 1
        if offset == CYCLES: return 768123
        return self.values.get(offset, 0)

    def write(self, offset, value):
        self.writes.append((offset, value))
        if offset == OWNER:
            if value == 1 and self.owner == 0: self.owner = 2
            if value == 0 and self.owner == 2: self.owner = 0
        elif offset == RECOVERY:
            if self.owner == 2 and value == 1: self.fault = 0
        else:
            if self.owner != 2: raise AssertionError("Write without ownership")
            self.values[offset] = value
            if offset == START: self.started = True


class CnnClientTests(unittest.TestCase):
    def test_preprocess_matches_training_and_word_order(self):
        bgr = np.random.default_rng(42).integers(0, 256, (37, 53, 3), dtype=np.uint8)
        words = image_words(bgr)
        self.assertEqual(len(words), 768)
        expected = Image.fromarray(bgr[:, :, ::-1].copy(), "RGB").resize(
            (32, 32), getattr(Image, "Resampling", Image).BILINEAR).tobytes()
        self.assertEqual(b"".join(w.to_bytes(4, "big") for w in words), expected)
        solid = np.full((32, 32, 3), [1, 2, 255], dtype=np.uint8)
        self.assertEqual(image_words(solid)[0], 0xFF0201FF)

    def test_complete_job_claim_configure_start_read_release(self):
        bridge = Bridge()
        label, cycles = CnnFpga(bridge).classify(np.zeros((480,640,3), np.uint8))
        self.assertEqual((label, cycles), (1, 768123))
        self.assertEqual(bridge.owner, 0)
        self.assertEqual(bridge.writes[0], (OWNER, 1))
        self.assertEqual(bridge.writes[-1], (OWNER, 0))
        writes = [(a,v) for a,v in bridge.writes if a < 0xC00]
        self.assertEqual(writes, [(i*4, 0) for i in range(768)])
        self.assertLess(bridge.writes.index((CONFIG, 768)), bridge.writes.index((START, 1)))
        self.assertGreaterEqual(bridge.polls, 2)

    def test_does_not_steal_pico_lock(self):
        bridge = Bridge(); bridge.owner = 1
        with patch("cnn_fpga.time.monotonic", side_effect=[0, 2]):
            with self.assertRaises(TimeoutError):
                CnnFpga(bridge).classify(np.zeros((32,32,3),np.uint8))
        self.assertEqual(bridge.owner, 1)
        self.assertFalse(bridge.started)

    def test_fault_retains_lock_and_recovery_releases(self):
        bridge = Bridge(); bridge.fault = 2
        client = CnnFpga(bridge)
        with self.assertRaisesRegex(RuntimeError, "watchdog"):
            client.classify(np.zeros((32,32,3),np.uint8))
        self.assertEqual(bridge.owner, 2)
        self.assertFalse(bridge.started)
        client.recover()
        self.assertEqual((bridge.fault, bridge.owner), (0, 0))

    def test_timeout_retains_lock(self):
        bridge = Bridge()
        original_read = bridge.read
        def read(offset):
            return 1 if offset == STATUS else original_read(offset)
        bridge.read = read
        with patch("cnn_fpga.time.monotonic", side_effect=[0,0,2]):
            with self.assertRaisesRegex(TimeoutError, "inference"):
                CnnFpga(bridge).classify(np.zeros((32,32,3),np.uint8))
        self.assertEqual(bridge.owner, 2)

    def test_bad_image_rejected_before_lock(self):
        bridge = Bridge()
        with self.assertRaises(ValueError):
            CnnFpga(bridge).classify(np.zeros((32,32), np.uint8))
        self.assertEqual(bridge.writes, [])


if __name__ == "__main__":
    unittest.main()
