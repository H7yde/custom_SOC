"""Install a trained COCO model only after its exported ROMs pass real RTL tests."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import shutil

from cnn_model import WEIGHT_FILES, read_mem_weights

HERE = Path(__file__).resolve().parent
DESIGN = HERE.parent / "SOC_HUFLIT_2026_parallel_50MHz/SOC_HUFLIT_2026.srcs/sources_1/new"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def deploy(source):
    source = source.resolve()
    report = json.loads((source / "report.json").read_text())
    verified = json.loads((source / "rtl_verification.json").read_text())
    if report["configuration"]["dataset"] != "COCO 2017" or not verified.get("passed"):
        raise ValueError("A completed COCO training run and passing RTL verification are required")
    if sha(DESIGN / "cnn_docx_reference.v") != verified["rtl_sha256"]:
        raise ValueError("RTL changed since verification; rerun verify_coco_rtl.py")
    if sha(source / "examples.json") != verified["examples_sha256"]:
        raise ValueError("Examples changed since verification")
    read_mem_weights(source)  # Validate ROM lengths, signed encoding and FC order.
    for filename in WEIGHT_FILES.values():
        if sha(source / filename) != verified["weights"][filename] or sha(source / filename) != report["weights"][filename]["sha256"]:
            raise ValueError(f"Weight file changed since verification: {filename}")
    active_path = HERE / "coco2017_model.json"
    decision = {"candidate_run": str(source), "deployed": True}
    if active_path.exists():
        active = json.loads(active_path.read_text(encoding="utf-8"))
        comparable = (active.get("validation", {}).get("cache_sha256") == report["validation"]["cache_sha256"]
                      and active.get("configuration", {}).get("task") == report["configuration"]["task"])
        if comparable:
            previous = active["rtl_q44"]
            candidate = report["rtl_q44"]
            decision.update({"previous_run": active.get("deployment", {}).get("training_run"),
                             "previous_metrics": previous, "candidate_metrics": candidate})
            if (candidate["balanced_accuracy"], candidate["accuracy"]) <= (previous["balanced_accuracy"], previous["accuracy"]):
                decision.update({"deployed": False, "reason": "Existing model has equal or better validation balanced accuracy/accuracy"})
                (source / "deployment_decision.json").write_text(json.dumps(decision, indent=2) + "\n", encoding="utf-8")
                print("Training and RTL validation completed; retained the existing, better model.")
                return
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup = HERE / "legacy_models" / f"before_deploy_{timestamp}"
    for label, target in (("CNN_RTL", HERE), ("design", DESIGN)):
        directory = backup / label
        directory.mkdir(parents=True, exist_ok=True)
        filenames = list(WEIGHT_FILES.values())
        if target == HERE:
            filenames += ["human_frame.mem", "human_frames.mem", "nonhuman_frame.mem",
                          "cnn_coco2017_best_float.pth", "cnn_coco2017_best_q44.pth", "coco2017_model.json"]
        for filename in filenames:
            if (target / filename).exists():
                shutil.copy2(target / filename, directory / filename)
        for filename in WEIGHT_FILES.values():
            shutil.copy2(source / filename, target / filename)
    for filename in ("human_frame.mem", "human_frames.mem", "nonhuman_frame.mem",
                     "cnn_coco2017_best_float.pth", "cnn_coco2017_best_q44.pth"):
        shutil.copy2(source / filename, HERE / filename)
    retired = []
    for filename in ("cnn_docx_best.pth", "cnn_docx_best_float.pth", "cnn_docx_best_q44.pth"):
        legacy = HERE / filename
        if legacy.is_file():
            shutil.copy2(legacy, backup / "CNN_RTL" / filename)
            legacy.unlink()
            retired.append(filename)
    report["rtl_verification"] = verified
    report["deployment"] = {"training_run": str(source), "backup": str(backup),
                            "retired_legacy_checkpoints": retired,
                            "bitstream_rebuilt": False, "firmware_changed": False}
    (HERE / "coco2017_model.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    (HERE / "active_training_run.txt").write_text(str(source) + "\n", encoding="utf-8")
    (source / "deployment_decision.json").write_text(json.dumps(decision, indent=2) + "\n", encoding="utf-8")
    print(f"COCO ROMs and examples installed. Backup: {backup}")
    print("The existing .bit still contains the old ROM data. Rebuild synthesis/implementation/bitstream to use COCO on the board.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_directory", type=Path)
    deploy(parser.parse_args().run_directory)
