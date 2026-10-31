"""Download, train, verify the actual RTL and install a COCO 2017 model."""
import argparse
from datetime import datetime
import os
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent


def run(command, log):
    print("Running:", subprocess.list2cmdline(command), flush=True)
    environment = {**os.environ, "PYTHONUNBUFFERED": "1", "PYTHONIOENCODING": "utf-8"}
    with log.open("w", encoding="utf-8") as stream:
        with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              text=True, encoding="utf-8", errors="replace", env=environment) as process:
            for line in process.stdout:
                stream.write(line)
                stream.flush()
                print(line, end="", flush=True)
            if process.wait():
                raise RuntimeError(f"Command failed ({process.returncode}); see {log}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--wait-for-download", action="store_true")
    parser.add_argument("--skip-download", action="store_true")
    parser.add_argument("--epochs", type=int, default=30)
    parser.add_argument("--qat-epochs", type=int, default=20)
    parser.add_argument("--resume", type=Path)
    parser.add_argument("--learning-rate", type=float, default=0.001)
    parser.add_argument("--qat-learning-rate", type=float, default=0.0002)
    parser.add_argument("--patience", type=int, default=10)
    parser.add_argument("--workers", type=int, default=16)
    parser.add_argument("--no-deploy", action="store_true")
    parser.add_argument("--vivado-bin", type=Path, default=Path("D:/Vivado_data/2025.2/Vivado/bin"))
    args = parser.parse_args()
    output = (args.output_dir or HERE / "runs" /
              f"coco2017_frame_{datetime.now():%Y%m%d_%H%M%S}").resolve()
    output.mkdir(parents=True, exist_ok=True)
    if args.wait_for_download:
        required = [HERE / "data/coco2017" / name for name in ("train2017.zip", "val2017.zip")]
        while not all(path.is_file() for path in required):
            print("Waiting for official image archives to finish downloading...", flush=True)
            time.sleep(30)
    elif not args.skip_download:
        run([sys.executable, "-u", str(HERE / "prepare_coco2017.py"), "--workers", str(args.workers)], output / "download.log")
    training_command = [sys.executable, "-u", str(HERE / "train_coco2017.py"), "--mode", "frame",
         "--output-dir", str(output), "--epochs", str(args.epochs),
         "--qat-epochs", str(args.qat_epochs), "--learning-rate", str(args.learning_rate),
         "--qat-learning-rate", str(args.qat_learning_rate), "--patience", str(args.patience)]
    if args.resume is not None:
        training_command += ["--resume", str(args.resume.resolve(strict=True))]
    run(training_command, output / "training.log")
    run([sys.executable, "-u", str(HERE / "verify_coco_rtl.py"), str(output),
         "--vivado-bin", str(args.vivado_bin)], output / "verification.log")
    if not args.no_deploy:
        run([sys.executable, "-u", str(HERE / "deploy_coco_model.py"), str(output)], output / "deployment.log")
    print(f"COCO PIPELINE COMPLETE: {output}", flush=True)


if __name__ == "__main__":
    main()
