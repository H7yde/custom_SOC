"""Train the fixed 32x32 RGB RTL CNN using COCO 2017 person crops.

COCO boxes are converted into balanced binary examples:
  1 = a crop centered on a person box
  0 = a crop that does not overlap any person box

Set the train/validation paths below to the extracted COCO instance files.
"""

import json
import os
import random

import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from PIL import Image
from torch.utils.data import Dataset, DataLoader
from torchvision import transforms


# Dataset paths and training-size controls.
COCO_IMAGE_DIR = r"C:\Users\Nick\Downloads\train2017"
COCO_ANNOTATIONS = r"C:\Users\Nick\Downloads\annotations\instances_train2017.json"
COCO_VAL_IMAGE_DIR = r"C:\Users\Nick\Downloads\val2017"
COCO_VAL_ANNOTATIONS = r"C:\Users\Nick\Downloads\annotations\instances_val2017.json"
SEED = 42
MAX_PERSON_IMAGES = 20000  # set None to use every available person image
MAX_BACKGROUND_IMAGES = 20000  # set None to use every available background image
BATCH_SIZE = 64
EPOCHS = 30
LEARNING_RATE = 0.0002
NUM_WORKERS = 0
IMAGE_SIZE = 32  # RTL captures exactly 32x32 RGB pixels
FRAC_BITS = 4
EVAL_ONLY = os.environ.get("COCO_EVAL_ONLY", "0") == "1"
CHECKPOINT_PATH = os.environ.get("COCO_CHECKPOINT", "cnn_docx_best_float.pth")

random.seed(SEED)
np.random.seed(SEED)
torch.manual_seed(SEED)
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")


class CNN3LayerBinary(nn.Module):
    """RTL-matched architecture: RGB32 -> 4 -> 4 -> 4 -> 2x2x4 -> 1."""

    def __init__(self):
        super().__init__()
        # The current Verilog core has no convolution or FC bias terms.
        self.conv1 = nn.Conv2d(3, 4, 3, padding=0, bias=False)
        self.conv2 = nn.Conv2d(4, 4, 3, padding=0, bias=False)
        self.conv3 = nn.Conv2d(4, 4, 3, padding=0, bias=False)
        self.relu = nn.ReLU()
        self.pool = nn.MaxPool2d(2, 2)
        self.fc = nn.Linear(4 * 2 * 2, 1, bias=False)

    def forward(self, x):
        x = self.pool(self.relu(self.conv1(x)))  # 32 -> 30 -> 15
        x = self.pool(self.relu(self.conv2(x)))  # 15 -> 13 -> 6
        x = self.pool(self.relu(self.conv3(x)))  # 6 -> 4 -> 2
        return self.fc(torch.flatten(x, 1))


def cap_ids(ids, rng, limit=None):
    ids = list(ids)
    rng.shuffle(ids)
    if limit is not None:
        ids = ids[:limit]
    return ids


def load_coco_records(image_dir, annotations_path):
    if not os.path.isdir(image_dir):
        raise FileNotFoundError(f"COCO image directory not found: {image_dir}")
    if not os.path.isfile(annotations_path):
        raise FileNotFoundError(
            "COCO instance annotations are required. Extract the matching "
            "instances_*.json file from annotations_trainval2017.zip to: "
            f"{os.path.dirname(annotations_path)}"
        )

    print(f"Reading COCO annotations: {annotations_path}")
    with open(annotations_path, "r", encoding="utf-8") as f:
        coco = json.load(f)

    image_info = {
        image["id"]: image
        for image in coco["images"]
        if os.path.isfile(os.path.join(image_dir, image["file_name"]))
    }
    person_boxes = {image_id: [] for image_id in image_info}
    for ann in coco["annotations"]:
        image_id = ann.get("image_id")
        if ann.get("category_id") != 1 or image_id not in image_info:
            continue
        x, y, w, h = ann.get("bbox", [0, 0, 0, 0])
        if w <= 1 or h <= 1:
            continue
        # Use regular person instances as positives. Crowd regions are still
        # retained below as exclusion areas for background crop sampling.
        person_boxes[image_id].append((x, y, w, h, bool(ann.get("iscrowd", 0))))

    person_ids = [image_id for image_id, boxes in person_boxes.items()
                  if any(not box[4] for box in boxes)]
    background_ids = [image_id for image_id, boxes in person_boxes.items()
                      if not boxes]
    if not person_ids or not background_ids:
        raise ValueError("COCO annotations need person images and images with no person boxes.")
    return image_info, person_boxes, person_ids, background_ids


def crop_person(image, box, rng):
    """Square crop around a full-body COCO box, with modest surrounding context."""
    x, y, w, h, _ = box
    image_w, image_h = image.size
    side = min(max(w, h) * 1.15, image_w, image_h)
    cx, cy = x + w / 2.0, y + h / 2.0
    left = min(max(0, cx - side / 2.0), image_w - side)
    top = min(max(0, cy - side / 2.0), image_h - side)
    # Small random shifts augment training crops while keeping the person box
    # inside the crop. Validation uses a fixed RNG seed per sample.
    shift = side * 0.04
    left = min(max(0, left + rng.uniform(-shift, shift)), image_w - side)
    top = min(max(0, top + rng.uniform(-shift, shift)), image_h - side)
    return image.crop((int(left), int(top), int(left + side), int(top + side)))


def intersection_over_union(a, b):
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    ix1, iy1 = max(ax, bx), max(ay, by)
    ix2, iy2 = min(ax + aw, bx + bw), min(ay + ah, by + bh)
    inter = max(0.0, ix2 - ix1) * max(0.0, iy2 - iy1)
    union = aw * ah + bw * bh - inter
    return inter / union if union > 0 else 0.0


class CocoPersonBinary(Dataset):
    """Balanced person/background crops, split by source image."""

    def __init__(self, image_dir, image_info, person_boxes, ids, train):
        person_ids, background_ids = ids
        self.image_dir = image_dir
        self.image_info = image_info
        self.person_boxes = person_boxes
        self.person_ids = list(person_ids)
        self.background_ids = list(background_ids)
        self.train = train
        self.to_tensor = transforms.ToTensor()  # RGB float values in [0, 1]

        # Balance classes. Half of the negatives come from images containing
        # people (hard backgrounds); the other half come from person-free scenes.
        self.negative_sources = []
        for i in range(len(self.person_ids)):
            if i % 2 == 0:
                self.negative_sources.append(("person_scene", self.person_ids[i]))
            else:
                bg_id = self.background_ids[i % len(self.background_ids)]
                self.negative_sources.append(("background_scene", bg_id))

    def __len__(self):
        return 2 * len(self.person_ids)

    def _open_image(self, image_id):
        filename = self.image_info[image_id]["file_name"]
        return Image.open(os.path.join(self.image_dir, filename)).convert("RGB")

    def _negative_crop(self, image_id, image, rng):
        width, height = image.size
        boxes = [box[:4] for box in self.person_boxes[image_id]]
        min_side = min(width, height)
        for _ in range(60):
            side = rng.uniform(max(24.0, min_side * 0.08), min_side * 0.45)
            left = rng.uniform(0, max(0.0, width - side))
            top = rng.uniform(0, max(0.0, height - side))
            candidate = (left, top, side, side)
            if all(intersection_over_union(candidate, box) == 0.0 for box in boxes):
                return image.crop((int(left), int(top), int(left + side), int(top + side)))
        # If a person scene is too crowded to find a clean crop, sample from a
        # scene with no annotated people instead of introducing a false label.
        if boxes and self.background_ids:
            fallback_id = self.background_ids[rng.randrange(len(self.background_ids))]
            fallback = self._open_image(fallback_id)
            return self._negative_crop(fallback_id, fallback, rng)
        side = min(width, height)
        left = rng.uniform(0, max(0.0, width - side))
        top = rng.uniform(0, max(0.0, height - side))
        return image.crop((int(left), int(top), int(left + side), int(top + side)))

    def __getitem__(self, index):
        positive = index < len(self.person_ids)
        local_index = index if positive else index - len(self.person_ids)
        if self.train:
            rng = random
        else:
            rng = random.Random(SEED + index)

        if positive:
            image_id = self.person_ids[local_index]
            image = self._open_image(image_id)
            boxes = [box for box in self.person_boxes[image_id] if not box[4]]
            crop = crop_person(image, boxes[rng.randrange(len(boxes))], rng)
            label = 1.0
        else:
            _, image_id = self.negative_sources[local_index]
            image = self._open_image(image_id)
            crop = self._negative_crop(image_id, image, rng)
            label = 0.0

        crop = crop.resize((IMAGE_SIZE, IMAGE_SIZE), Image.Resampling.BILINEAR)
        return self.to_tensor(crop), torch.tensor([label], dtype=torch.float32)


val_info, val_boxes, val_people, val_background = load_coco_records(
    COCO_VAL_IMAGE_DIR, COCO_VAL_ANNOTATIONS
)
print(
    f"COCO validation: {len(val_info)} images; {len(val_people)} with people, "
    f"{len(val_background)} without people."
)
val_set = CocoPersonBinary(
    COCO_VAL_IMAGE_DIR, val_info, val_boxes,
    (val_people, val_background), train=False
)
val_loader = DataLoader(
    val_set, batch_size=BATCH_SIZE, shuffle=False, num_workers=NUM_WORKERS
)

if not EVAL_ONLY:
    train_info, train_boxes, train_people, train_background = load_coco_records(
        COCO_IMAGE_DIR, COCO_ANNOTATIONS
    )
    rng = random.Random(SEED)
    train_people = cap_ids(train_people, rng, MAX_PERSON_IMAGES)
    train_background = cap_ids(train_background, rng, MAX_BACKGROUND_IMAGES)
    print(
        f"COCO training: {len(train_info)} images; using {len(train_people)} "
        f"person and {len(train_background)} person-free images."
    )
    train_set = CocoPersonBinary(
        COCO_IMAGE_DIR, train_info, train_boxes,
        (train_people, train_background), train=True
    )
    train_loader = DataLoader(
        train_set, batch_size=BATCH_SIZE, shuffle=True, num_workers=NUM_WORKERS
    )

model = CNN3LayerBinary().to(DEVICE)
criterion = nn.BCEWithLogitsLoss()
optimizer = optim.Adam(model.parameters(), lr=LEARNING_RATE)


def run_epoch(net, loader, training=False):
    net.train(training)
    total_loss = total_correct = total = 0
    context = torch.enable_grad() if training else torch.no_grad()
    with context:
        for inputs, labels in loader:
            inputs, labels = inputs.to(DEVICE), labels.to(DEVICE)
            if training:
                optimizer.zero_grad()
            logits = net(inputs)
            loss = criterion(logits, labels)
            if training:
                loss.backward()
                optimizer.step()
            total_loss += loss.item() * inputs.size(0)
            prediction = (torch.sigmoid(logits) >= 0.5).float()
            total_correct += (prediction == labels).sum().item()
            total += inputs.size(0)
    return total_loss / max(total, 1), total_correct / max(total, 1)


if EVAL_ONLY:
    if not os.path.isfile(CHECKPOINT_PATH):
        raise FileNotFoundError(f"Checkpoint not found: {CHECKPOINT_PATH}")
    model.load_state_dict(
        torch.load(CHECKPOINT_PATH, map_location=DEVICE, weights_only=True)
    )
    val_loss, best_acc = run_epoch(model, val_loader, training=False)
    print(f"Checkpoint float validation loss={val_loss:.4f}, accuracy={best_acc:.2%}")
else:
    best_acc = -1.0
    for epoch in range(1, EPOCHS + 1):
        train_loss, train_acc = run_epoch(model, train_loader, training=True)
        val_loss, val_acc = run_epoch(model, val_loader, training=False)
        print(
            f"Epoch {epoch:02d}/{EPOCHS} | "
            f"train loss={train_loss:.4f}, acc={train_acc:.2%} | "
            f"val loss={val_loss:.4f}, acc={val_acc:.2%}",
            flush=True,
        )
        if val_acc > best_acc:
            best_acc = val_acc
            torch.save(model.state_dict(), "cnn_docx_best_float.pth")

    model.load_state_dict(
        torch.load("cnn_docx_best_float.pth", map_location=DEVICE, weights_only=True)
    )


def make_q44_model(source):
    quantized = CNN3LayerBinary().to(DEVICE)
    with torch.no_grad():
        for dst, src in zip(quantized.parameters(), source.parameters()):
            q = torch.round(src.detach() * (1 << FRAC_BITS))
            q = torch.clamp(q, -128, 127) / float(1 << FRAC_BITS)
            dst.copy_(q)
    return quantized


qmodel = make_q44_model(model)
_, quant_acc = run_epoch(qmodel, val_loader, training=False)
print(f"Best float validation accuracy: {best_acc:.2%}")
print(f"Q4.4 validation accuracy:      {quant_acc:.2%}")
torch.save(qmodel.state_dict(), "cnn_docx_best_q44.pth")


def export_mem(values, filename):
    q = torch.round(values.detach().cpu() * (1 << FRAC_BITS))
    q = torch.clamp(q, -128, 127).to(torch.int32)
    with open(filename, "w", newline="\n") as f:
        for value in q.flatten().tolist():
            f.write(f"{value & 0xFF:02X}\n")
    print(f"Exported {filename}: {q.numel()} weights")


export_mem(qmodel.conv1.weight, "conv1_rgb_weight.mem")
export_mem(qmodel.conv2.weight, "conv2_weight.mem")
export_mem(qmodel.conv3.weight, "conv3_weight.mem")
fc_spatial_channel = (
    qmodel.fc.weight.reshape(1, 4, 2, 2)
    .permute(0, 2, 3, 1)
    .reshape(1, 16)
)
export_mem(fc_spatial_channel, "fc_weight.mem")


def export_frame_mem(dataset, filename, label):
    for index in range(len(dataset)):
        tensor, target = dataset[index]
        if int(target.item()) == int(label):
            pixels = (
                tensor.permute(1, 2, 0).mul(255).round().clamp(0, 255)
                .to(torch.uint8).numpy()
            )
            with open(filename, "w", newline="\n") as f:
                for row in pixels:
                    for r, g, b in row:
                        f.write(f"{int(r):02X}{int(g):02X}{int(b):02X}\n")
            print(f"Exported {filename}: {IMAGE_SIZE * IMAGE_SIZE} RGB pixels")
            return
    raise RuntimeError(f"No validation example found for label {label}")


export_frame_mem(val_set, "human_frame.mem", 1)
export_frame_mem(val_set, "nonhuman_frame.mem", 0)
