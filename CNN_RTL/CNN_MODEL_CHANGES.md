# CNN Model and Training Changes

## Summary

The RTL CNN architecture is still a binary image-crop classifier. The training
pipeline was changed from CIFAR-100 labels to COCO 2017 person annotations so
the examples better represent real people and backgrounds. COCO boxes are
converted into 32x32 RGB crops to match the input size accepted by the current
RTL.

## Model architecture

| Stage | Operation | Output shape |
|---|---|---|
| Input | RGB crop | 32 x 32 x 3 |
| Conv1 | 3 input channels, 4 output channels, 3 x 3, valid padding; ReLU; 2 x 2 max-pool | 15 x 15 x 4 |
| Conv2 | 4 input channels, 4 output channels, 3 x 3, valid padding; ReLU; 2 x 2 max-pool | 6 x 6 x 4 |
| Conv3 | 4 input channels, 4 output channels, 3 x 3, valid padding; ReLU; 2 x 2 max-pool | 2 x 2 x 4 |
| Fully connected | 16 inputs to 1 logit, no bias | 1 logit |
| Output | Sigmoid threshold at 0.5 | person / background |

Convolution and fully connected layers have no bias terms because the current
Verilog core does not implement them. The model uses the same fixed-point Q4.4
weight export path as before.

## Dataset and crop generation

The trainer reads these COCO 2017 files:

- `C:\Users\Nick\Downloads\train2017`
- `C:\Users\Nick\Downloads\annotations\instances_train2017.json`
- `C:\Users\Nick\Downloads\val2017`
- `C:\Users\Nick\Downloads\annotations\instances_val2017.json`

Only COCO category `person` (category ID 1) is used. Positive examples are
square crops centered on non-crowd person boxes, with a small amount of
surrounding context. Negative examples are sampled from person-free images or
from regions of person-containing images that do not intersect annotated
person boxes. The classes are balanced. The official COCO train and validation
splits are kept separate by source image.

The training run is capped at 20,000 person-containing images and 20,000
person-free images by default. Validation uses the available `val2017` images.
Each crop is RGB, resized to 32 x 32, and converted to float values in [0, 1].

## Training configuration

| Setting | Value |
|---|---:|
| Random seed | 42 |
| Optimizer | Adam |
| Learning rate | 0.0002 |
| Loss | Binary cross-entropy with logits |
| Batch size | 64 |
| Epoch limit | 30 |
| Training device | Automatically selects CUDA when available, otherwise CPU |
| Weight quantization | Signed INT8, Q4.4 |

The best floating-point checkpoint is selected by validation accuracy. A Q4.4
copy is then evaluated on the same validation crop set. The script exports
convolution and fully connected `.mem` files plus one positive and one
negative validation crop for RTL simulation.

## Accuracy result

Best floating-point validation accuracy observed: **77.50%** after one completed
training epoch.

Q4.4 validation accuracy for that checkpoint: **72.87%**.

The run used the configured 20,000-person-image and 20,000-person-free-image
training caps. It ran on CPU because CUDA was unavailable. The first epoch took
about 14 minutes before its checkpoint was saved; the 30-epoch training limit
was not completed. These numbers are therefore the best measured so far, not a
claim that 77.50% is the model's maximum possible validation accuracy.
Continuing training may improve or reduce validation accuracy; a complete run
with checkpoint selection is needed to estimate the best validation score for
this configuration.

The evaluated checkpoint and its Q4.4 weights are preserved in
`CNN_RTL/coco_32px_epoch1/` with the exported `.mem` files and sample frames.
The trainer also supports checkpoint-only evaluation: set `COCO_EVAL_ONLY=1`
and `COCO_CHECKPOINT` to a checkpoint path to evaluate it against `val2017`
without loading the COCO training annotations.

These are binary crop-classification accuracies on a balanced set of 5,386
validation crops (2,693 positive and 2,693 negative).
They are not COCO object-detection average precision, and they do not measure
whether the RTL can locate people across a full-resolution frame. The current
RTL returns one classification bit for one 32 x 32 crop; full-frame detection
still needs a crop-scanning/localization stage.

## Main changes from the previous trainer

| Area | Previous pipeline | Updated pipeline |
|---|---|---|
| Training data | CIFAR-100 coarse “people” class versus other classes | COCO 2017 person boxes and person-free/background crops |
| Positive sample | A complete 32 x 32 CIFAR image | A 32 x 32 crop centered on a person box |
| Negative sample | An image from a non-people CIFAR coarse class | A person-free scene or a crop outside annotated people |
| Validation | CIFAR test data used during training | Official COCO `val2017` split |
| RTL architecture | 32 x 32 RGB, 3 conv/pool stages, 16-to-1 FC | Unchanged |
