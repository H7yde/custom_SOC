"""Train COCO 2017 whole-frame person presence for the RTL CNN.

Both labels come from instance annotations: any annotated person, including
crowds, makes the entire image positive. QAT emulates the RTL INT8 Q4.4 weights,
input lookup and activation truncation/saturation. No detector is introduced.
"""
from __future__ import annotations

import argparse
import csv
from datetime import datetime
import hashlib
import json
from pathlib import Path
import random
import time

import numpy as np
import torch
from torch import nn
from torch.nn import functional as F

from cnn_model import CNN3LayerBinary, SCALE, export_weights, integer_reference, integer_weights
from coco_dataset import ROOT, prepare_split

HERE = Path(__file__).resolve().parent


def evaluate(model, pixels, labels, batch_size, quantized=False, pos_weight=None):
    model.eval()
    predictions, scores = [], []
    loss_sum = torch.zeros((), device=pixels.device)
    with torch.no_grad():
        for first in range(0, len(labels), batch_size):
            target = labels[first:first + batch_size]
            output = model(pixels[first:first + batch_size], quantized=quantized)
            loss_sum += F.binary_cross_entropy_with_logits(output, target, pos_weight=pos_weight, reduction="sum")
            predictions.append(output >= 0)
            scores.append(output)
        predicted, output = torch.cat(predictions), torch.cat(scores)
        confusion = torch.bincount(labels.to(torch.int64) * 2 + predicted.to(torch.int64), minlength=4)
    tn, fp, fn, tp = confusion.cpu().tolist()
    recall, specificity = tp / max(tp + fn, 1), tn / max(tn + fp, 1)
    return {"loss": float(loss_sum / len(labels)), "accuracy": (tp + tn) / len(labels),
            "balanced_accuracy": (recall + specificity) / 2,
            "precision": tp / max(tp + fp, 1), "recall": recall,
            "specificity": specificity, "tn": tn, "fp": fp, "fn": fn, "tp": tp,
            "zero_score_count": int((output == 0).sum())}, predicted.cpu().numpy()


def load_cache(path, device):
    with np.load(path, allow_pickle=False) as cache:
        rgb, labels, ids = cache["images"], cache["labels"], cache["image_ids"]
    tensor = torch.from_numpy(rgb.transpose(0, 3, 1, 2).copy()).to(device)
    target = torch.from_numpy(labels.astype(np.float32)).to(device)
    return tensor, target, ids, rgb


def augment(pixels):
    # Keep the whole scene: a random crop could remove the annotated person.
    flip = torch.rand((len(pixels), 1, 1, 1), device=pixels.device) < 0.5
    pixels = torch.where(flip, pixels.flip(-1), pixels).to(torch.float32)
    brightness = 0.85 + torch.rand((len(pixels), 1, 1, 1), device=pixels.device) * 0.3
    return (pixels * brightness).round().clamp(0, 255).to(torch.uint8)


def train_stage(model, train_x, train_y, val_x, val_y, args, output, stage, epochs, lr, history):
    quantized = stage == "qat"
    optimizer = torch.optim.Adam(model.parameters(), lr=lr)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=max(epochs, 1), eta_min=lr * 0.1)
    positives = int(train_y.sum())
    pos_weight = torch.tensor((len(train_y) - positives) / positives, device=train_y.device)
    best, no_improvement = -1.0, 0
    checkpoint = output / f"best_{stage}.pth"
    if quantized or args.resume is not None:
        best = evaluate(model, val_x, val_y, args.batch_size, quantized=quantized)[0]["balanced_accuracy"]
        torch.save(model.state_dict(), checkpoint)
        print(f"{stage.upper()} starting candidate: balanced accuracy={best:.2%}", flush=True)
    for epoch in range(1, epochs + 1):
        started = time.monotonic()
        model.train()
        order = torch.randperm(len(train_y), device=train_y.device)
        loss_sum = torch.zeros((), device=train_y.device)
        correct = torch.zeros((), device=train_y.device, dtype=torch.int64)
        for first in range(0, len(order), args.batch_size):
            indices = order[first:first + args.batch_size]
            pixels, labels = train_x[indices], train_y[indices]
            if not args.no_augment:
                pixels = augment(pixels)
            optimizer.zero_grad(set_to_none=True)
            logits = model(pixels, quantized=quantized)
            loss = F.binary_cross_entropy_with_logits(logits, labels, pos_weight=pos_weight)
            if not torch.isfinite(loss):
                raise RuntimeError("Non-finite training loss; no weights deployed")
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 5.0)
            optimizer.step()
            loss_sum += loss.detach() * len(indices)
            correct += ((logits.detach() >= 0) == labels.bool()).sum()
        metrics, _ = evaluate(model, val_x, val_y, args.batch_size, quantized, pos_weight)
        row = {"stage": stage, "epoch": epoch, "train_loss": float(loss_sum / len(train_y)),
               "train_accuracy": float(correct / len(train_y)),
               **{f"val_{key}": value for key, value in metrics.items()},
               "seconds": time.monotonic() - started, "learning_rate": optimizer.param_groups[0]["lr"]}
        history.append(row)
        with (output / "history.jsonl").open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(row) + "\n")
        print(f"{stage.upper()} {epoch:02}/{epochs}: train loss={row['train_loss']:.4f}, "
              f"acc={row['train_accuracy']:.2%}; val acc={metrics['accuracy']:.2%}, "
              f"balanced={metrics['balanced_accuracy']:.2%}, recall={metrics['recall']:.2%}, "
              f"specificity={metrics['specificity']:.2%}; {row['seconds']:.1f}s", flush=True)
        if metrics["balanced_accuracy"] > best:
            best, no_improvement = metrics["balanced_accuracy"], 0
            torch.save(model.state_dict(), checkpoint)
        else:
            no_improvement += 1
        scheduler.step()
        if args.patience and no_improvement >= args.patience:
            print(f"Early stopping {stage} after {no_improvement} epochs without improvement", flush=True)
            break
    model.load_state_dict(torch.load(checkpoint, map_location=train_x.device, weights_only=True))
    return evaluate(model, val_x, val_y, args.batch_size, quantized)[0]


def export_frame(rgb, path):
    path.write_text("".join(f"{int(r):02X}{int(g):02X}{int(b):02X}\n"
                            for r, g, b in rgb.reshape(-1, 3)), encoding="ascii")


def export_examples(model, rgb, labels, ids, predictions, output, device):
    weights = integer_weights(model)
    examples = []
    # Demo frames demonstrate both successful classes. Reported accuracy always
    # includes ALL validation images and never uses this example selection.
    for label, name in ((1, "human_frame.mem"), (0, "nonhuman_frame.mem")):
        candidates = np.flatnonzero((labels == label) & (predictions == label))
        if not len(candidates):
            raise RuntimeError(f"No correctly classified validation example for class {label}")
        index = int(candidates[0])
        reference = integer_reference(rgb[index], weights)
        if reference["classification"] != label:
            raise AssertionError("Integer reference disagrees with Q4.4 prediction")
        export_frame(rgb[index], output / name)
        examples.append({"file": name, "image_id": int(ids[index]), "ground_truth": label,
                         "rtl_expected": reference["classification"], "integer_score": reference["score"],
                         "selection": "first correctly classified example by official validation image ID"})
    (output / "human_frames.mem").write_bytes((output / "human_frame.mem").read_bytes())
    patterns = [("black_frame.mem", np.zeros((32, 32, 3), np.uint8)),
                ("white_frame.mem", np.full((32, 32, 3), 255, np.uint8)),
                ("random_frame.mem", np.random.default_rng(42).integers(0, 256, (32, 32, 3), dtype=np.uint8))]
    for name, image in patterns:
        reference = integer_reference(image, weights)
        export_frame(image, output / name)
        examples.append({"file": name, "ground_truth": None, "rtl_expected": reference["classification"],
                         "integer_score": reference["score"], "selection": "synthetic arithmetic check"})
    indices = np.linspace(0, len(rgb) - 1, min(64, len(rgb)), dtype=int)
    with torch.no_grad():
        selected = torch.from_numpy(rgb[indices].transpose(0, 3, 1, 2).copy()).to(device)
        scores = model(selected, quantized=True).cpu().numpy() * SCALE * SCALE
    for index, score in zip(indices, scores):
        oracle = integer_reference(rgb[index], weights)
        if abs(float(score) - oracle["score"]) > 0.01:
            raise AssertionError(f"Integer/QAT mismatch for image {ids[index]}: {score} != {oracle['score']}")
    (output / "examples.json").write_text(json.dumps(examples, indent=2) + "\n", encoding="utf-8")
    return examples, len(indices)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-root", type=Path, default=ROOT)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--mode", choices=("frame", "crop"), default="frame")
    parser.add_argument("--epochs", type=int, default=30)
    parser.add_argument("--qat-epochs", type=int, default=20)
    parser.add_argument("--batch-size", type=int, default=512)
    parser.add_argument("--learning-rate", type=float, default=0.001)
    parser.add_argument("--qat-learning-rate", type=float, default=0.0002)
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--patience", type=int, default=10)
    parser.add_argument("--device", default="auto")
    parser.add_argument("--resume", type=Path, help="Continue from a compatible weight checkpoint; Adam and its schedule restart")
    parser.add_argument("--no-augment", action="store_true")
    args = parser.parse_args()
    if min(args.epochs, args.qat_epochs, args.batch_size, args.workers) < 1:
        parser.error("epochs, qat-epochs, batch-size and workers must be positive")
    random.seed(args.seed)
    np.random.seed(args.seed)
    torch.manual_seed(args.seed)
    torch.set_num_threads(6)
    torch.backends.cuda.matmul.allow_tf32 = False
    torch.backends.cudnn.allow_tf32 = False
    torch.backends.cudnn.benchmark = False
    torch.backends.cudnn.deterministic = True
    device = torch.device("cuda" if args.device == "auto" and torch.cuda.is_available()
                          else "cpu" if args.device == "auto" else args.device)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output = (args.output_dir or HERE / "runs" / f"coco2017_{args.mode}_{timestamp}").resolve()
    if (output / "history.jsonl").exists():
        raise FileExistsError(f"Training output exists; choose a new --output-dir: {output}")
    output.mkdir(parents=True, exist_ok=True)
    configuration = {key: str(value) if isinstance(value, Path) else value for key, value in vars(args).items()}
    configuration.update({"dataset": "COCO 2017", "task": "whole-frame person presence" if args.mode == "frame" else "person/background crops",
                          "from_scratch": args.resume is None, "architecture": "RGB32 Conv3-4 Conv4-4 Conv4-4 FC16-1, no biases",
                          "device": str(device), "torch": torch.__version__,
                          "cuda": torch.version.cuda,
                          "gpu": torch.cuda.get_device_name(device) if device.type == "cuda" else None,
                          "source": "https://cocodataset.org/#download"})
    configuration["training_code_sha256"] = {
        name: hashlib.sha256((HERE / name).read_bytes()).hexdigest()
        for name in ("train_coco2017.py", "cnn_model.py", "coco_dataset.py")}
    if args.resume is not None:
        args.resume = args.resume.resolve(strict=True)
        configuration["resume"] = str(args.resume)
        configuration["resume_sha256"] = hashlib.sha256(args.resume.read_bytes()).hexdigest()
        configuration["optimizer_restarted"] = True
    (output / "config.json").write_text(json.dumps(configuration, indent=2) + "\n", encoding="utf-8")
    initialization = f"continue weights from {args.resume}" if args.resume else "from scratch"
    print(f"COCO 2017 {args.mode}, {initialization}, device={device}, output={output}", flush=True)
    val_path = prepare_split(args.data_root, "val2017", args.mode, args.workers, args.seed)
    train_path = prepare_split(args.data_root, "train2017", args.mode, args.workers, args.seed)
    train_x, train_y, train_ids, train_rgb = load_cache(train_path, device)
    del train_rgb
    val_x, val_y, val_ids, val_rgb = load_cache(val_path, device)
    if set(train_ids.tolist()) & set(val_ids.tolist()):
        raise AssertionError("Train/validation source image leakage")
    if not (0 < float(train_y.sum()) < len(train_y)) or not (0 < float(val_y.sum()) < len(val_y)):
        raise ValueError("Both splits must contain both classes")
    print(f"Train {len(train_y)} images, person={int(train_y.sum())}; "
          f"validation {len(val_y)}, person={int(val_y.sum())}; disjoint IDs", flush=True)
    model = CNN3LayerBinary().to(device)
    if args.resume is not None:
        model.load_state_dict(torch.load(args.resume, map_location=device, weights_only=True), strict=True)
    history = []
    float_metrics = train_stage(model, train_x, train_y, val_x, val_y, args, output,
                                "float", args.epochs, args.learning_rate, history)
    torch.save(model.state_dict(), output / "cnn_coco2017_best_float.pth")
    before_qat, _ = evaluate(model, val_x, val_y, args.batch_size, quantized=True)
    print(f"Before QAT: integer balanced accuracy={before_qat['balanced_accuracy']:.2%}", flush=True)
    qat_metrics = train_stage(model, train_x, train_y, val_x, val_y, args, output,
                              "qat", args.qat_epochs, args.qat_learning_rate, history)
    export_weights(model, output)
    quantized_model = CNN3LayerBinary().to(device)
    with torch.no_grad():
        for dst, src in zip(quantized_model.parameters(), model.parameters()):
            dst.copy_(torch.round(src * SCALE).clamp(-128, 127) / SCALE)
    torch.save(quantized_model.state_dict(), output / "cnn_coco2017_best_q44.pth")
    rtl_metrics, predictions = evaluate(quantized_model, val_x, val_y, args.batch_size, quantized=True)
    if rtl_metrics["balanced_accuracy"] <= 0.5 or not rtl_metrics["tp"] or not rtl_metrics["tn"]:
        raise RuntimeError(f"Degenerate integer model; no deployment: {rtl_metrics}")
    examples, oracle_checks = export_examples(quantized_model, val_rgb, val_y.cpu().numpy(),
                                               val_ids, predictions, output, device)
    report = {"configuration": configuration,
              "train": json.loads(train_path.with_suffix(".json").read_text()),
              "validation": json.loads(val_path.with_suffix(".json").read_text()),
              "float": float_metrics, "before_qat": before_qat, "qat": qat_metrics,
              "rtl_q44": rtl_metrics, "integer_oracle_checks": oracle_checks,
              "examples": examples, "weights": {},
              "limitation": "Binary classification, not detection. Validation selects checkpoints; no independent camera test set measured."}
    for path in output.glob("*_weight.mem"):
        report["weights"][path.name] = {"sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                                      "count": len(path.read_text().split())}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    with (output / "history.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(history[0]))
        writer.writeheader()
        writer.writerows(history)
    print("TRAINING COMPLETE", json.dumps(rtl_metrics), flush=True)
    print(f"Report: {output / 'report.json'}", flush=True)


if __name__ == "__main__":
    main()
