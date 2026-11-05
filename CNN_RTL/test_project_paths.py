from pathlib import Path
import tempfile
import unittest
from project_paths import design_directory


class ProjectPathsTests(unittest.TestCase):
    def test_missing_ambiguous_and_renamed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaises(RuntimeError):
                design_directory(root)
            project = root / "SOC_HUFLIT_2026_parallel_125MHz"
            rtl = project / "SOC_HUFLIT_2026.srcs/sources_1/new"
            rtl.mkdir(parents=True)
            (project / "SOC_HUFLIT_2026.xpr").touch()
            with self.assertRaises(FileNotFoundError):
                design_directory(root)
            (rtl / "cnn_docx_reference.v").touch()
            self.assertEqual(design_directory(root), rtl)
            second = root / "SOC_HUFLIT_2026_parallel_50MHz"
            second.mkdir()
            (second / "SOC_HUFLIT_2026.xpr").touch()
            with self.assertRaises(RuntimeError):
                design_directory(root)


if __name__ == "__main__":
    unittest.main()
