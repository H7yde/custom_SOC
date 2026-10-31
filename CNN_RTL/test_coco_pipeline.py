"""Check COCO presence labels and exact compatibility with RTL arithmetic."""
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

import numpy as np
from PIL import Image
import torch

from cnn_model import CNN3LayerBinary, SCALE, export_weights, integer_reference, integer_weights, read_mem_weights
from coco_dataset import overlaps, prepare_split


class CocoPipelineTests(unittest.TestCase):
    def test_whole_frame_labels_include_small_and_crowd_people(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "annotations").mkdir()
            images = [{"id": i, "file_name": f"{i:012}.png", "width": 48, "height": 40}
                      for i in range(1, 5)]
            annotations = [
                {"image_id": 1, "category_id": 7, "bbox": [1, 1, 10, 10], "iscrowd": 0},
                {"image_id": 2, "category_id": 7, "bbox": [1, 1, 1, 1], "iscrowd": 0},
                {"image_id": 3, "category_id": 7, "bbox": [0, 0, 48, 40], "iscrowd": 1},
                {"image_id": 4, "category_id": 2, "bbox": [1, 1, 20, 20], "iscrowd": 0},
            ]
            data = {"images": images, "annotations": annotations,
                    "categories": [{"id": 7, "name": "person"}, {"id": 2, "name": "car"}]}
            (root / "annotations/instances_val2017.json").write_text(json.dumps(data))
            with zipfile.ZipFile(root / "val2017.zip", "w") as archive:
                for entry in images:
                    stream = io.BytesIO()
                    Image.new("RGB", (48, 40), (255, entry["id"], 0)).save(stream, format="PNG")
                    archive.writestr("val2017/" + entry["file_name"], stream.getvalue())
            path = prepare_split(root, "val2017", workers=2)
            with np.load(path) as cache:
                np.testing.assert_array_equal(cache["labels"], [1, 1, 1, 0])
                self.assertEqual(cache["images"].shape, (4, 32, 32, 3))
                np.testing.assert_array_equal(cache["images"][0, 0, 0], [255, 1, 0])
            self.assertEqual(prepare_split(root, "val2017", workers=2), path)

    def test_background_rejects_even_tiny_overlaps(self):
        self.assertTrue(overlaps((0, 0, 100, 100), (20, 20, 21, 21)))
        self.assertFalse(overlaps((0, 0, 20, 20), (20, 0, 30, 10)))

    def test_qat_scores_match_independent_integer_oracle(self):
        torch.set_num_threads(2)
        torch.manual_seed(142)
        model = CNN3LayerBinary().eval()
        random = np.random.default_rng(21)
        patterns = [np.zeros((32, 32, 3), np.uint8), np.full((32, 32, 3), 255, np.uint8),
                    np.full((32, 32, 3), 254, np.uint8)]
        patterns.extend(random.integers(0, 256, (5, 32, 32, 3), dtype=np.uint8))
        weights = integer_weights(model)
        tensor = torch.from_numpy(np.stack(patterns).transpose(0, 3, 1, 2).copy())
        with torch.no_grad():
            scores = model(tensor, quantized=True).numpy() * SCALE * SCALE
        for rgb, score in zip(patterns, scores):
            expected = integer_reference(rgb, weights)
            self.assertEqual(float(score), expected["score"])
            self.assertEqual(int(score >= 0), expected["classification"])
        # Large positive weights force the RTL's 127 activation saturation.
        for parameter in model.parameters():
            parameter.data.fill_(127 / SCALE)
        weights = integer_weights(model)
        oracle = integer_reference(patterns[1], weights)
        self.assertTrue(np.all(oracle["c1"] == 127))
        with torch.no_grad():
            self.assertEqual(float(model(tensor[1:2], quantized=True)[0] * SCALE * SCALE), oracle["score"])

    def test_rom_signed_values_and_fc_pixel_major_order(self):
        model = CNN3LayerBinary()
        with torch.no_grad():
            model.fc.weight.copy_(torch.arange(-8, 8).reshape(1, 16) / SCALE)
        expected = integer_weights(model)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            export_weights(model, root)
            actual = read_mem_weights(root)
            for name in expected:
                np.testing.assert_array_equal(actual[name], expected[name])
            tokens = (root / "fc_weight.mem").read_text().split()
            values = expected["fc"].reshape(1, 4, 2, 2).transpose(0, 2, 3, 1).reshape(-1)
            self.assertEqual(tokens, [f"{int(value) & 255:02X}" for value in values])


if __name__ == "__main__":
    unittest.main()
