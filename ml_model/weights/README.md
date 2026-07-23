# Model Card — CrashLens Damage Severity Classifier

Vehicle damage severity classification (minor / moderate / severe)  of a damaged vehicle.

| | |
|---|---|
| **Model** | `severity_resnet50.pth` |
| **Task** | Multi-class image classification (3 classes) |
| **Architecture** | ResNet50 (torchvision), ImageNet-pretrained, fine-tuned end-to-end |
| **Framework** | PyTorch |
| **Size** | ~90 MB |
| **Status** | Deployed in the CrashLens backend inference service |

---

## Download

Weights are distributed separately from the repository to keep clone size small.

<div align="center">
<a href="https://drive.google.com/drive/folders/1wlfG1X5T6JGNLoL_eehLfLXLdQz9bg49?usp=sharing">
<img src="https://img.shields.io/badge/Download-Severity%20Model%20Weights-4285F4?style=for-the-badge&logo=googledrive&logoColor=white">
</a>
</div>

After downloading, place the file at:

```
backend_api/weight/severity_resnet50.pth
```

The backend loads this path at startup and will fail to start if it is
missing — this is intentional, so a misconfiguration is caught immediately
rather than at request time.

---

## Loading the model

The training checkpoint is a dictionary, not a bare state dict. The
deployment file has the optimizer state stripped, roughly halving its size.

```python
import torch
import torch.nn as nn
from torchvision import models

model = models.resnet50(weights=None)          # do not download ImageNet
model.fc = nn.Linear(model.fc.in_features, 3)

checkpoint = torch.load("weight/severity_resnet50.pth", map_location="cpu")
state_dict = checkpoint.get("model_state", checkpoint)   # accepts both formats

model.load_state_dict(state_dict)
model.eval()
```

`weights=None` is required — otherwise torchvision downloads ImageNet weights
on every server start, which the checkpoint immediately overwrites.
---

*CrashLens — 2026 Graduation Project, Group 7*
