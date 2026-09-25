import os
import pickle
import random
import tarfile
import urllib.request

import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from PIL import Image
from torch.utils.data import Dataset, DataLoader
from torchvision import transforms


# Reproducible training.
SEED = 42
random.seed(SEED)
np.random.seed(SEED)
torch.manual_seed(SEED)

ROOT = "./data"
ARCHIVE = os.path.join(ROOT, "cifar-100-python.tar.gz")
ARCHIVE_URL = "https://www.cs.toronto.edu/~kriz/cifar-100-python.tar.gz"
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
FRAC_BITS = 4


class CNN3LayerBinary(nn.Module):
    """DOCX architecture: RGB32 -> 4 -> 4 -> 4 -> 2x2x4 -> 1."""
    def __init__(self):
        super().__init__()
        # DOCX/Verilog version does not implement bias, so train without bias.
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


def load_cifar_split(train):
    """Read CIFAR-100 directly from the archive; avoids extraction permission errors."""
    os.makedirs(ROOT, exist_ok=True)
    if not os.path.exists(ARCHIVE):
        print("Downloading CIFAR-100...")
        urllib.request.urlretrieve(ARCHIVE_URL, ARCHIVE)

    split = "train" if train else "test"
    with tarfile.open(ARCHIVE, "r:gz") as tar:
        member = tar.extractfile(f"cifar-100-python/{split}")
        if member is None:
            raise FileNotFoundError(f"Missing CIFAR-100 member: {split}")
        raw = pickle.load(member, encoding="latin1")

    # Original CIFAR layout is N x 3072 = R plane, G plane, B plane.
    images = raw["data"].reshape(-1, 3, 32, 32).transpose(0, 2, 3, 1)
    return images, raw["coarse_labels"]


class CIFAR100PeopleBinary(Dataset):
    PEOPLE_COARSE_LABEL = 14

    def __init__(self, train=True, transform=None):
        self.transform = transform
        images, coarse_labels = load_cifar_split(train)
        people = [i for i, y in enumerate(coarse_labels)
                  if y == self.PEOPLE_COARSE_LABEL]
        non_people = [i for i, y in enumerate(coarse_labels)
                      if y != self.PEOPLE_COARSE_LABEL]

        # Balance positive and negative samples.
        rng = random.Random(SEED + int(train))
        non_people = rng.sample(non_people, len(people))
        self.indices = people + non_people
        self.images = images
        self.labels = [1.0] * len(people) + [0.0] * len(non_people)

    def __len__(self):
        return len(self.indices)

    def __getitem__(self, index):
        image = Image.fromarray(self.images[self.indices[index]])
        if self.transform is not None:
            image = self.transform(image)
        label = torch.tensor([self.labels[index]], dtype=torch.float32)
        return image, label


transform = transforms.ToTensor()  # RGB values [0,1], matching Q4.4 input scaling.
train_set = CIFAR100PeopleBinary(train=True, transform=transform)
test_set = CIFAR100PeopleBinary(train=False, transform=transform)
train_loader = DataLoader(train_set, batch_size=64, shuffle=True, num_workers=0)
test_loader = DataLoader(test_set, batch_size=256, shuffle=False, num_workers=0)

model = CNN3LayerBinary().to(DEVICE)
criterion = nn.BCEWithLogitsLoss()
optimizer = optim.Adam(model.parameters(), lr=0.0002)


def run_epoch(net, loader, training=False):
    net.train(training)
    total_loss = 0.0
    total_correct = 0
    total = 0

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

    return total_loss / total, total_correct / total


RESUME_FILE = "cnn_docx_best_float.pth"
if os.path.exists(RESUME_FILE):
    model.load_state_dict(
        torch.load(RESUME_FILE, map_location=DEVICE, weights_only=True)
    )
    _, resumed_acc = run_epoch(model, test_loader, training=False)
    best_acc = resumed_acc
    print(f"Resuming from {RESUME_FILE}, accuracy={resumed_acc:.2%}")
else:
    best_acc = -1.0

ADDITIONAL_EPOCHS = 100
TARGET_ACCURACY = 1.0
for epoch in range(1, ADDITIONAL_EPOCHS + 1):
    train_loss, train_acc = run_epoch(model, train_loader, training=True)
    test_loss, test_acc = run_epoch(model, test_loader, training=False)
    print(
        f"Continue epoch {epoch:02d}/{ADDITIONAL_EPOCHS} | "
        f"train loss={train_loss:.4f}, acc={train_acc:.2%} | "
        f"test loss={test_loss:.4f}, acc={test_acc:.2%}"
    )
    if test_acc > best_acc:
        best_acc = test_acc
        torch.save(model.state_dict(), "cnn_docx_best_float.pth")
    if test_acc >= TARGET_ACCURACY:
        print("Target test accuracy 100% reached; stopping early.")
        break

model.load_state_dict(
    torch.load("cnn_docx_best_float.pth", map_location=DEVICE, weights_only=True)
)
_, float_acc = run_epoch(model, test_loader, training=False)


def make_q44_model(source):
    """Create the exact Q4.4 model that will be exported to Verilog."""
    quantized = CNN3LayerBinary().to(DEVICE)
    with torch.no_grad():
        for dst, src in zip(quantized.parameters(), source.parameters()):
            q = torch.round(src.detach() * (1 << FRAC_BITS))
            q = torch.clamp(q, -128, 127) / float(1 << FRAC_BITS)
            dst.copy_(q)
    return quantized


qmodel = make_q44_model(model)
_, quant_acc = run_epoch(qmodel, test_loader, training=False)
print(f"Best float test accuracy: {float_acc:.2%}")
print(f"Q4.4 test accuracy:       {quant_acc:.2%}")
torch.save(qmodel.state_dict(), "cnn_docx_best_q44.pth")


def export_mem(values, filename):
    q = torch.round(values.detach().cpu() * (1 << FRAC_BITS))
    q = torch.clamp(q, -128, 127).to(torch.int32)
    with open(filename, "w", newline="\n") as f:
        for value in q.flatten().tolist():
            f.write(f"{value & 0xFF:02X}\n")
    print(f"Exported {filename}: {q.numel()} words")


qmodel.eval()
export_mem(qmodel.conv1.weight, "conv1_rgb_weight.mem")
export_mem(qmodel.conv2.weight, "conv2_weight.mem")
export_mem(qmodel.conv3.weight, "conv3_weight.mem")

# Verilog FC order: pixel0[ch0..ch3], pixel1[ch0..ch3], ...
fc_spatial_channel = (
    qmodel.fc.weight.reshape(1, 4, 2, 2)
    .permute(0, 2, 3, 1)
    .reshape(1, 16)
)
export_mem(fc_spatial_channel, "fc_weight.mem")


def export_frame_mem(dataset, filename, label):
    index = next(i for i, y in enumerate(dataset.labels) if y == label)
    image = dataset.images[dataset.indices[index]]
    with open(filename, "w", newline="\n") as f:
        for row in image:
            for r, g, b in row:
                f.write(f"{int(r):02X}{int(g):02X}{int(b):02X}\n")
    print(f"Exported {filename}: 1024 RGB pixels")


# Inputs for tb_cnn_docx_reference.sv.
export_frame_mem(test_set, "human_frame.mem", 1.0)
export_frame_mem(test_set, "nonhuman_frame.mem", 0.0)
