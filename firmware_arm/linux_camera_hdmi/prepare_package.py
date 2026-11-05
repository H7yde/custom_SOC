"""Package a matching BIT/HWH pair from the working Vitis platform XSA."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
from zipfile import ZipFile, ZIP_DEFLATED

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xsa", type=Path, default=ROOT / "soc_platform/export/soc_platform/hw/soc_top.xsa")
    args = parser.parse_args()
    output = HERE / "package"
    output.mkdir(exist_ok=True)
    with ZipFile(args.xsa) as archive:
        bits = [n for n in archive.namelist() if n.endswith(".bit")]
        hwhs = [n for n in archive.namelist() if n.endswith(".hwh")]
        if len(bits) != 1 or len(hwhs) != 1:
            raise RuntimeError("Expected exactly one BIT/HWH in this XSA")
        (output / "soc_camera_hdmi.bit").write_bytes(archive.read(bits[0]))
        (output / "soc_camera_hdmi.hwh").write_bytes(archive.read(hwhs[0]))
    for name in ("camera_hdmi.py", "README.md"):
        shutil.copyfile(HERE / name, output / name)
    manifest = {"source_xsa": str(args.xsa.resolve()),
                "xsa_sha256": hashlib.sha256(args.xsa.read_bytes()).hexdigest(),
                "files": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in output.iterdir() if p.name in
                          ("soc_camera_hdmi.bit", "soc_camera_hdmi.hwh", "camera_hdmi.py", "README.md")}}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    package = HERE / "camera_hdmi_pynq.zip"
    with ZipFile(package, "w", ZIP_DEFLATED) as archive:
        for name in (*manifest["files"], "manifest.json"):
            archive.write(output / name, name)
    print(package)
    print("Matching BIT/HWH extracted from", args.xsa)


if __name__ == "__main__":
    main()
