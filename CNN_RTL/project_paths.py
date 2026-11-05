"""Resolve the unique local Vivado project; never silently use a stale copy."""
from pathlib import Path


def design_directory(root=None):
    root = Path(root) if root is not None else Path(__file__).resolve().parents[1]
    projects = sorted(root.glob("SOC_HUFLIT_2026_parallel_*/SOC_HUFLIT_2026.xpr"))
    if len(projects) != 1:
        raise RuntimeError(f"Expected exactly one SoC .xpr under {root}, found {len(projects)}")
    design = projects[0].parent / "SOC_HUFLIT_2026.srcs/sources_1/new"
    if not (design / "cnn_docx_reference.v").is_file():
        raise FileNotFoundError(f"Missing CNN RTL in {design}")
    return design
