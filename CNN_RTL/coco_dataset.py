"""Build reproducible RGB32 caches from official COCO 2017 instance labels.

Frame mode labels the whole scene: any annotated person (including crowds) is
positive. Crop mode uses a non-crowd person box, or a background rectangle that
has zero overlap with every annotated person, including small/crowd regions.
Train and validation always use the official, disjoint image splits.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import json
from pathlib import Path
import random
import time
import zipfile

import numpy as np
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parent / "data" / "coco2017"
CACHE_VERSION = 1


def overlaps(a, b):
    """Positive-area rectangle intersection; IoU thresholds can miss tiny people."""
    return min(a[2], b[2]) > max(a[0], b[0]) and min(a[3], b[3]) > max(a[1], b[1])


def person_crop(image, box):
    x, y, width, height = box
    # Padding, rather than clipping the square to image dimensions, preserves
    # the entire person even for tall boxes at the image boundary.
    side = max(width, height) * 1.15
    cx, cy = x + width / 2, y + height / 2
    return image.crop((int(cx - side / 2), int(cy - side / 2),
                       int(cx + side / 2 + 0.999), int(cy + side / 2 + 0.999)))


def background_crop(image, boxes, rng):
    width, height = image.size
    short = min(width, height)
    for _ in range(80):
        maximum = max(1, int(short * 0.5))
        side = rng.randint(min(24, maximum), maximum)
        left, top = rng.randint(0, width - side), rng.randint(0, height - side)
        rect = (left, top, left + side, top + side)
        if all(not overlaps(rect, box) for box in boxes):
            return image.crop(rect)
    return None


def load_annotations(path):
    print(f"Reading {path}", flush=True)
    raw = path.read_bytes()
    source_sha = hashlib.sha256(raw).hexdigest()
    data = json.loads(raw)
    person_ids = {category["id"] for category in data["categories"]
                  if category["name"] == "person"}
    if len(person_ids) != 1:
        raise ValueError("COCO instances must contain exactly one person category")
    boxes = {entry["id"]: [] for entry in data["images"]}
    for annotation in data["annotations"]:
        if annotation["category_id"] in person_ids:
            # Keep ALL person annotations for presence labels/exclusion masks.
            boxes[annotation["image_id"]].append(annotation)
    return sorted(data["images"], key=lambda item: item["id"]), boxes, source_sha


def prepare_split(root, split, mode="frame", workers=8, seed=42):
    root = Path(root).resolve()
    cache = root / "cache" / f"{split}_{mode}_rgb32_v{CACHE_VERSION}.npz"
    manifest = cache.with_suffix(".json")
    annotations = root / "annotations" / f"instances_{split}.json"
    images, boxes, annotation_sha = load_annotations(annotations)
    specification = {"version": CACHE_VERSION, "split": split, "mode": mode,
                     "annotation_sha256": annotation_sha, "seed": seed,
                     "resize": "Pillow bilinear RGB 32x32", "image_size": 32}
    if cache.exists() and manifest.exists():
        previous = json.loads(manifest.read_text(encoding="utf-8"))
        if all(previous.get(key) == value for key, value in specification.items()):
            print(f"Using cache: {cache}", flush=True)
            return cache
    archive_path = root / f"{split}.zip"
    image_directory = root / split
    if not archive_path.exists() and not image_directory.is_dir():
        raise FileNotFoundError(f"Missing {archive_path}; run prepare_coco2017.py first")
    archive = zipfile.ZipFile(archive_path) if archive_path.exists() else None
    background_images = [entry for entry in images if not boxes[entry["id"]]]
    records = [(entry, -1) for entry in images] if mode == "frame" else []
    if mode == "crop":
        for entry in images:
            regular = [a for a in boxes[entry["id"]]
                       if not a.get("iscrowd", 0) and a["bbox"][2] > 1 and a["bbox"][3] > 1]
            if regular:
                records.extend([(entry, 1), (entry, 0)])
    if not records or not background_images:
        raise ValueError("No usable person/background examples in COCO split")

    def read_image(entry):
        if archive:
            with Image.open(io.BytesIO(archive.read(f"{split}/{entry['file_name']}"))) as image:
                return ImageOps.exif_transpose(image).convert("RGB")
        with Image.open(image_directory / entry["file_name"]) as image:
            return ImageOps.exif_transpose(image).convert("RGB")

    def process(record):
        entry, label = record
        rng = random.Random(seed + entry["id"] * 3 + max(label, 0))
        image = read_image(entry)
        source_id = entry["id"]
        if mode == "frame":
            label = int(bool(boxes[source_id]))
        elif label == 1:
            regular = [a for a in boxes[source_id]
                       if not a.get("iscrowd", 0) and a["bbox"][2] > 1 and a["bbox"][3] > 1]
            image = person_crop(image, rng.choice(regular)["bbox"])
        else:
            exclusion = [(a["bbox"][0], a["bbox"][1],
                          a["bbox"][0] + a["bbox"][2], a["bbox"][1] + a["bbox"][3])
                         for a in boxes[source_id]]
            crop = background_crop(image, exclusion, rng)
            if crop is None:
                fallback = rng.choice(background_images)
                source_id = fallback["id"]
                crop = read_image(fallback)
            image = crop
        image = image.resize((32, 32), Image.Resampling.BILINEAR)
        return np.asarray(image, dtype=np.uint8), label, source_id

    pixels = np.empty((len(records), 32, 32, 3), dtype=np.uint8)
    labels = np.empty(len(records), dtype=np.uint8)
    ids = np.empty(len(records), dtype=np.int64)
    started = time.monotonic()
    try:
        with ThreadPoolExecutor(max_workers=workers) as executor:
            for index, (image, label, image_id) in enumerate(executor.map(process, records)):
                pixels[index], labels[index], ids[index] = image, label, image_id
                if (index + 1) % 5000 == 0 or index + 1 == len(records):
                    print(f"{split}/{mode}: {index + 1}/{len(records)} examples, "
                          f"{(index + 1) / max(time.monotonic() - started, 0.01):.0f}/s", flush=True)
    finally:
        if archive:
            archive.close()
    cache.parent.mkdir(parents=True, exist_ok=True)
    temporary = cache.with_suffix(".npz.tmp")
    with temporary.open("wb") as stream:
        np.savez(stream, images=pixels, labels=labels, image_ids=ids)
    temporary.replace(cache)
    specification.update({"examples": len(labels), "person": int(labels.sum()),
                          "background": int((labels == 0).sum()),
                          "official_source_images": len(images),
                          "cache_sha256": hashlib.sha256(cache.read_bytes()).hexdigest()})
    manifest.write_text(json.dumps(specification, indent=2) + "\n", encoding="utf-8")
    print(f"Saved {cache}: {specification}", flush=True)
    return cache


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--mode", choices=("frame", "crop"), default="frame")
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--splits", nargs="+", choices=("train2017", "val2017"),
                        default=["val2017", "train2017"])
    args = parser.parse_args()
    if args.workers < 1:
        parser.error("--workers must be positive")
    for split in args.splits:
        prepare_split(args.root, split, args.mode, args.workers)


if __name__ == "__main__":
    main()
