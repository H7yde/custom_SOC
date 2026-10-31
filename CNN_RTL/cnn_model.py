"""The 412-weight, bias-free RGB32 network and its RTL fixed-point arithmetic."""
from __future__ import annotations

import numpy as np
import torch
from torch import nn
from torch.nn import functional as F

FRAC_BITS = 4
SCALE = 1 << FRAC_BITS
WEIGHT_FILES = {"conv1": "conv1_rgb_weight.mem", "conv2": "conv2_weight.mem",
                "conv3": "conv3_weight.mem", "fc": "fc_weight.mem"}


def straight_through(source, quantized):
    return source + (quantized - source).detach()


class CNN3LayerBinary(nn.Module):
    def __init__(self):
        super().__init__()
        self.conv1 = nn.Conv2d(3, 4, 3, bias=False)
        self.conv2 = nn.Conv2d(4, 4, 3, bias=False)
        self.conv3 = nn.Conv2d(4, 4, 3, bias=False)
        self.fc = nn.Linear(16, 1, bias=False)
        for layer in (self.conv1, self.conv2, self.conv3):
            nn.init.kaiming_normal_(layer.weight, nonlinearity="relu")
        nn.init.normal_(self.fc.weight, std=0.3)

    def forward(self, pixels, quantized=False):
        # Exact Verilog input mapping: 255 -> 16, otherwise the upper nibble.
        # Camera RGB bytes are supplied once; no external normalization needed.
        raw = pixels.to(torch.float32)
        x = torch.where(raw == 255, 16.0, torch.floor(raw / 16.0)) / SCALE
        for layer in (self.conv1, self.conv2, self.conv3):
            weight = layer.weight
            if quantized:
                weight = straight_through(weight, torch.round(weight * SCALE).clamp(-128, 127) / SCALE)
            x = F.relu(F.conv2d(x, weight))
            if quantized:
                clipped = x.clamp(0, 127 / SCALE)
                x = straight_through(clipped, torch.floor(clipped * SCALE) / SCALE)
            x = F.max_pool2d(x, 2)
        weight = self.fc.weight
        if quantized:
            weight = straight_through(weight, torch.round(weight * SCALE).clamp(-128, 127) / SCALE)
        return F.linear(x.flatten(1), weight).squeeze(1)


def integer_weights(model):
    return {name: torch.round(getattr(model, name).weight.detach() * SCALE)
            .clamp(-128, 127).cpu().numpy().astype(np.int32) for name in WEIGHT_FILES}


def numpy_conv(x, weights):
    windows = np.lib.stride_tricks.sliding_window_view(x, (3, 3), axis=(1, 2))
    return np.einsum("cyxij,ocij->oyx", windows, weights, dtype=np.int32, optimize=True)


def integer_reference(rgb, weights):
    """Independent integer oracle; returns every activation and signed FC score."""
    pixels = np.asarray(rgb, dtype=np.uint8)
    x = np.where(pixels == 255, 16, pixels.astype(np.int32) >> 4).transpose(2, 0, 1)
    layers = {}
    for index in (1, 2, 3):
        accumulator = numpy_conv(x, weights[f"conv{index}"])
        x = np.clip(np.maximum(accumulator, 0) >> 4, 0, 127).astype(np.int32)
        layers[f"c{index}"] = x.copy()
        height, width = x.shape[1] // 2, x.shape[2] // 2
        x = x[:, :height * 2, :width * 2].reshape(4, height, 2, width, 2).max(axis=(2, 4))
        layers[f"p{index}"] = x.copy()
    score = int(np.dot(x.reshape(-1).astype(np.int64), weights["fc"].reshape(-1)))
    layers.update(score=score, classification=int(score >= 0))
    return layers


def export_weights(model, directory):
    directory.mkdir(parents=True, exist_ok=True)
    weights = integer_weights(model)
    for name, filename in WEIGHT_FILES.items():
        values = weights[name]
        if name == "fc":
            # RTL FC reads feature maps CHW, but its weight ROM is pixel-major.
            values = values.reshape(1, 4, 2, 2).transpose(0, 2, 3, 1)
        (directory / filename).write_text("".join(f"{int(v) & 255:02X}\n" for v in values.flat), encoding="ascii")
    return weights


def read_mem_weights(directory):
    shapes = {"conv1": (4, 3, 3, 3), "conv2": (4, 4, 3, 3),
              "conv3": (4, 4, 3, 3), "fc": (1, 16)}
    result = {}
    for name, filename in WEIGHT_FILES.items():
        values = np.array([int(token, 16) for token in (directory / filename).read_text().split()], dtype=np.int32)
        values = np.where(values >= 128, values - 256, values)
        if name == "fc":
            values = values.reshape(1, 2, 2, 4).transpose(0, 3, 1, 2)
        result[name] = values.reshape(shapes[name])
    return result
