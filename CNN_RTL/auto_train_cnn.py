"""One command: setup dependencies, train COCO person presence, print results.

python CNN_RTL/auto_train_cnn.py
python CNN_RTL/auto_train_cnn.py --verify-rtl --deploy
python CNN_RTL/auto_train_cnn.py --report-only CNN_RTL/runs/<run>
"""
import argparse
from datetime import datetime
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

HERE = Path(__file__).resolve().parent


def setup_dependencies(no_install=False):
    required = {"numpy": "numpy>=1.24", "PIL": "Pillow>=10", "torch": "torch>=2.5"}
    missing = [package for module, package in required.items()
               if importlib.util.find_spec(module) is None]
    if missing:
        if no_install:
            raise RuntimeError("Missing dependencies: " + ", ".join(missing))
        subprocess.run([sys.executable, "-m", "pip", "install", *missing], check=True)
    # Probe in a fresh process, so newly installed packages are visible.
    subprocess.run([sys.executable, "-c",
                    "import numpy, PIL, torch; "
                    "print('PyTorch:', torch.__version__); "
                    "print('Device:', torch.cuda.get_device_name(0) "
                    "if torch.cuda.is_available() else 'CPU (slower)')"], check=True)


def check_dataset(root):
    """Check ZIP directories, without decoding the full dataset a second time."""
    for split in ("train2017", "val2017"):
        archive = root / (split + ".zip")
        annotation = root / "annotations" / ("instances_" + split + ".json")
        if not archive.is_file() or not annotation.is_file():
            raise RuntimeError(f"Missing {archive} or {annotation}. "
                               "Place the dataset here, or run with --download.")
        with zipfile.ZipFile(archive) as stream:
            if not any(name.startswith(split + "/") and name.endswith(".jpg")
                       for name in stream.namelist()):
                raise RuntimeError(f"No images found in {archive}")
    print("Dataset: COCO train2017 + val2017 ready.", flush=True)


def summarize(output):
    report = json.loads((output / "report.json").read_text(encoding="utf-8"))
    lines = ["# Ket qua CNN COCO 2017", "",
             "Bai toan: ca khung hinh co nguoi / khong co nguoi (RGB 32x32).", "",
             f"Train: {report['train']['examples']:,} anh; "
             f"validation: {report['validation']['examples']:,} anh.", "",
             "| Model | Accuracy | Balanced accuracy | Precision | Recall |",
             "| --- | --- | --- | --- | --- |"]
    for label, key in (("Float", "float"), ("Q4.4 FPGA", "rtl_q44")):
        metric = report[key]
        values = " | ".join(f"{metric[name] * 100:.2f}%" for name in
                            ("accuracy", "balanced_accuracy", "precision", "recall"))
        lines.append(f"| {label} | {values} |")
    metric = report["rtl_q44"]
    lines += ["", f"Q4.4: TP={metric['tp']}, TN={metric['tn']}, "
              f"FP={metric['fp']}, FN={metric['fn']}.", ""]
    verification = output / "rtl_verification.json"
    if verification.exists():
        result = json.loads(verification.read_text(encoding="utf-8"))
        lines.append("Mo phong RTL: " + ("PASS" if result.get("passed") else "FAIL"))
    else:
        lines.append("Chua chay mo phong RTL cho luot nay.")
    decision = output / "deployment_decision.json"
    if decision.exists():
        result = json.loads(decision.read_text(encoding="utf-8"))
        lines.append("ROM nguon: " + ("da cap nhat" if result.get("deployed")
                                       else "giu model cu tot hon hoac bang"))
    else:
        lines.append("Chua cap nhat ROM cua project FPGA tu luot nay.")
    lines += ["", "Validation duoc dung de chon checkpoint; chua do tren camera doc lap.",
              "Script khong build bitstream hoac nap board.", "",
              "Checkpoint: cnn_coco2017_best_float.pth, cnn_coco2017_best_q44.pth.",
              "Trong so: conv1_rgb_weight.mem, conv2_weight.mem, conv3_weight.mem, fc_weight.mem.",
              "Chi tiet: report.json va history.csv."]
    content = "\n".join(lines) + "\n"
    (output / "AUTO_RESULTS.md").write_text(content, encoding="utf-8")
    print("\n" + content)
    print("Output:", output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-root", type=Path, default=HERE / "data/coco2017")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--epochs", type=int, default=30)
    parser.add_argument("--qat-epochs", type=int, default=20)
    parser.add_argument("--batch-size", type=int, default=512)
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--patience", type=int, default=10)
    parser.add_argument("--learning-rate", type=float, default=0.001)
    parser.add_argument("--qat-learning-rate", type=float, default=0.0002)
    parser.add_argument("--device", default="auto")
    parser.add_argument("--resume", type=Path)
    parser.add_argument("--download", action="store_true", help="Download missing COCO archives (~20 GB)")
    parser.add_argument("--no-install", action="store_true")
    parser.add_argument("--check-only", action="store_true", help="Setup and check; do not train")
    parser.add_argument("--report-only", type=Path, help="Print results of an existing run; do not train")
    parser.add_argument("--verify-rtl", action="store_true")
    parser.add_argument("--deploy", action="store_true", help="Verify RTL and install improved ROMs; no bitstream build")
    parser.add_argument("--vivado-bin", type=Path, default=Path("D:/Vivado_data/2025.2/Vivado/bin"))
    args = parser.parse_args()
    if args.report_only:
        summarize(args.report_only.resolve(strict=True))
        return
    if min(args.epochs, args.qat_epochs, args.batch_size, args.workers, args.patience) < 1:
        parser.error("Epochs, batch size, workers and patience must be positive.")
    if args.learning_rate <= 0 or args.qat_learning_rate <= 0:
        parser.error("Learning rates must be positive.")
    if args.resume:
        args.resume = args.resume.resolve(strict=True)
    if args.verify_rtl or args.deploy:
        for name in ("xvlog", "xelab", "xsim"):
            if not any((args.vivado_bin / (name + ext)).exists() for ext in (".bat", "")):
                raise RuntimeError(f"Missing {name} in {args.vivado_bin}; set --vivado-bin.")
    setup_dependencies(args.no_install)
    from run_coco2017 import run
    root = args.data_root.resolve()
    if args.download:
        root.mkdir(parents=True, exist_ok=True)
        run([sys.executable, "-u", str(HERE / "prepare_coco2017.py"),
             "--root", str(root), "--workers", str(args.workers)], root / "auto_download.log")
    check_dataset(root)
    if args.check_only:
        return
    output = (args.output_dir or HERE / "runs" /
              datetime.now().strftime("auto_coco2017_%Y%m%d_%H%M%S_%f")).resolve()
    if output.exists() and any(output.iterdir()):
        raise RuntimeError(f"Output directory must be empty: {output}")
    output.mkdir(parents=True, exist_ok=True)
    shutil.copy2(__file__, output / "auto_train_cnn_source.py")
    command = [sys.executable, "-u", str(HERE / "train_coco2017.py"),
               "--data-root", str(root), "--output-dir", str(output), "--mode", "frame"]
    for name in ("epochs", "qat_epochs", "batch_size", "workers", "patience",
                 "learning_rate", "qat_learning_rate", "device"):
        command += ["--" + name.replace("_", "-"), str(getattr(args, name))]
    if args.resume:
        command += ["--resume", str(args.resume)]
    try:
        run(command, output / "training.log")
        if args.verify_rtl or args.deploy:
            run([sys.executable, "-u", str(HERE / "verify_coco_rtl.py"), str(output),
                 "--vivado-bin", str(args.vivado_bin)], output / "verification.log")
        if args.deploy:
            run([sys.executable, "-u", str(HERE / "deploy_coco_model.py"), str(output)],
                output / "deployment.log")
    finally:
        if (output / "report.json").exists():
            summarize(output)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError,
            zipfile.BadZipFile) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
