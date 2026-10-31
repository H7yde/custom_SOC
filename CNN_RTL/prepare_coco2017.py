"""Download the official COCO 2017 archives with resumable, verified ranges.

The S3 path is the HTTPS endpoint of the images.cocodataset.org public bucket.
No certificate verification is disabled. Original image archives are kept so
training can read them without duplicating 20+ GB of extracted JPEG files.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import os
from pathlib import Path
import subprocess
import threading
import time
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent / "data" / "coco2017"
BASE_URL = "https://s3.amazonaws.com/images.cocodataset.org"
ARCHIVES = {
    "annotations_trainval2017.zip": "annotations/annotations_trainval2017.zip",
    "val2017.zip": "zips/val2017.zip",
    "train2017.zip": "zips/train2017.zip",
}


def request(url, **kwargs):
    return urllib.request.urlopen(urllib.request.Request(
        url, headers={"User-Agent": "HUFLIT-COCO2017/1.0", **kwargs.pop("headers", {})},
        **kwargs), timeout=90)


def download_archive(root: Path, name: str, workers: int):
    destination = root / name
    url = BASE_URL + "/" + ARCHIVES[name]
    with request(url, method="HEAD") as response:
        size = int(response.headers["Content-Length"])
        etag = response.headers.get("ETag", "")
    if destination.is_file() and destination.stat().st_size == size:
        with zipfile.ZipFile(destination) as archive:
            archive.infolist()  # Validate the central directory before reuse.
        print(f"Already downloaded: {name} ({size:,} bytes)", flush=True)
        return destination

    partial = destination.with_suffix(".zip.partial")
    state_path = destination.with_suffix(".zip.progress.json")
    chunk_size = 16 * 1024 * 1024
    count = (size + chunk_size - 1) // chunk_size
    state = {"url": url, "size": size, "etag": etag,
             "chunk_size": chunk_size, "completed": []}
    if partial.exists() and state_path.exists():
        previous = json.loads(state_path.read_text())
        if all(previous.get(key) == state[key]
               for key in ("url", "size", "etag", "chunk_size")):
            state = previous
    if not partial.exists() or partial.stat().st_size != size:
        with partial.open("wb") as stream:
            if os.name == "nt":
                # Avoid physically writing 19 GB of zeroes before downloading.
                subprocess.run(["fsutil", "sparse", "setflag", str(partial)],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            stream.truncate(size)
        state["completed"] = []
    done = set(state["completed"])
    lock = threading.Lock()
    started = time.monotonic()
    last_report = [0.0]
    initial_bytes = sum(min(chunk_size, size - i * chunk_size) for i in done)

    def save_state():
        state["completed"] = sorted(done)
        temporary = state_path.with_suffix(".json.tmp")
        temporary.write_text(json.dumps(state), encoding="utf-8")
        temporary.replace(state_path)

    save_state()

    def fetch(index):
        first = index * chunk_size
        last = min(size, first + chunk_size) - 1
        for attempt in range(5):
            try:
                with request(url, headers={"Range": f"bytes={first}-{last}"}) as response:
                    expected = f"bytes {first}-{last}/{size}"
                    if response.status != 206 or response.headers.get("Content-Range") != expected:
                        raise RuntimeError(f"Unexpected HTTP range response: {response.headers}")
                    remaining = last - first + 1
                    with partial.open("r+b", buffering=0) as stream:
                        stream.seek(first)
                        while remaining:
                            block = response.read(min(1024 * 1024, remaining))
                            if not block:
                                raise EOFError("Incomplete range download")
                            stream.write(block)
                            remaining -= len(block)
                with lock:
                    done.add(index)
                    save_state()
                    now = time.monotonic()
                    if now - last_report[0] >= 10 or len(done) == count:
                        completed = sum(min(chunk_size, size - i * chunk_size) for i in done)
                        speed = (completed - initial_bytes) / max(now - started, 0.01)
                        print(f"{name}: {completed / size:.1%} "
                              f"({completed / 1e9:.2f}/{size / 1e9:.2f} GB), "
                              f"{speed / 1e6:.1f} MB/s", flush=True)
                        last_report[0] = now
                return
            except Exception:
                if attempt == 4:
                    raise
                time.sleep(min(2 ** attempt, 15))

    print(f"Downloading {name}: {size / 1e9:.2f} GB, {workers} connections", flush=True)
    with ThreadPoolExecutor(max_workers=workers) as executor:
        for future in as_completed([executor.submit(fetch, i)
                                    for i in range(count) if i not in done]):
            future.result()
    with zipfile.ZipFile(partial) as archive:
        archive.infolist()
    partial.replace(destination)
    state_path.unlink(missing_ok=True)
    print(f"Completed: {destination}", flush=True)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--workers", type=int, default=16)
    parser.add_argument("--archives", nargs="+", choices=list(ARCHIVES), default=list(ARCHIVES))
    args = parser.parse_args()
    if args.workers < 1:
        parser.error("--workers must be positive")
    root = args.root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    for name in args.archives:
        path = download_archive(root, name, args.workers)
        if name.startswith("annotations"):
            with zipfile.ZipFile(path) as archive:
                for split in ("train2017", "val2017"):
                    member = f"annotations/instances_{split}.json"
                    target = root / member
                    if not target.exists() or target.stat().st_size != archive.getinfo(member).file_size:
                        target.parent.mkdir(parents=True, exist_ok=True)
                        temporary = target.with_suffix(".json.tmp")
                        with archive.open(member) as source, temporary.open("wb") as output:
                            import shutil
                            shutil.copyfileobj(source, output)
                        temporary.replace(target)
    print("COCO 2017 download finished.", flush=True)


if __name__ == "__main__":
    main()
