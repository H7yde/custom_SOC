"""Protect the active FPGA ROMs when a continuation run fails to improve."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from cnn_model import CNN3LayerBinary, export_weights, WEIGHT_FILES
import deploy_coco_model as deployment


class DeploymentTests(unittest.TestCase):
    def test_worse_model_keeps_existing_roms_and_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, active_dir, design = root / "candidate", root / "active", root / "design"
            for directory in (source, active_dir, design):
                directory.mkdir()
            export_weights(CNN3LayerBinary(), source)
            rtl = design / "cnn_docx_reference.v"
            rtl.write_text("// unchanged RTL fixture\n")
            (source / "examples.json").write_text("[]")
            hashes = {filename: hashlib.sha256((source / filename).read_bytes()).hexdigest()
                      for filename in WEIGHT_FILES.values()}
            report = {"configuration": {"dataset": "COCO 2017", "task": "whole-frame person presence"},
                      "validation": {"cache_sha256": "same-validation"},
                      "rtl_q44": {"balanced_accuracy": 0.60, "accuracy": 0.65},
                      "weights": {name: {"sha256": value} for name, value in hashes.items()}}
            verification = {"passed": True, "rtl_sha256": hashlib.sha256(rtl.read_bytes()).hexdigest(),
                            "examples_sha256": hashlib.sha256(b"[]").hexdigest(), "weights": hashes}
            (source / "report.json").write_text(json.dumps(report))
            (source / "rtl_verification.json").write_text(json.dumps(verification))
            active = {**report, "rtl_q44": {"balanced_accuracy": 0.70, "accuracy": 0.70},
                      "deployment": {"training_run": "previous-run"}}
            active_path = active_dir / "coco2017_model.json"
            active_path.write_text(json.dumps(active))
            before = active_path.read_bytes()
            for directory in (active_dir, design):
                for filename in WEIGHT_FILES.values():
                    (directory / filename).write_bytes(b"ORIGINAL ROM")
            with patch.object(deployment, "HERE", active_dir), patch.object(deployment, "DESIGN", design):
                deployment.deploy(source)
            self.assertEqual(active_path.read_bytes(), before)
            for directory in (active_dir, design):
                for filename in WEIGHT_FILES.values():
                    self.assertEqual((directory / filename).read_bytes(), b"ORIGINAL ROM")
            decision = json.loads((source / "deployment_decision.json").read_text())
            self.assertFalse(decision["deployed"])
            self.assertEqual(decision["previous_run"], "previous-run")


if __name__ == "__main__":
    unittest.main()
