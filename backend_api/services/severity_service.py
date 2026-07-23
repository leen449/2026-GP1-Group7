"""
Severity classification service.

Model:      ResNet50 (torchvision), fine-tuned end-to-end.
Experiment: exp05D_label_smoothing (Label Smoothing CE, eps=0.1)
Val macro F1: 0.8850   |   Test macro F1: 0.9172

IMPORTANT — scope of this model:
    It was trained with torchvision ImageFolder on FULL vehicle photos,
    resized straight to 224x224. It has never seen a cropped bounding box.
    Therefore it is called here on the WHOLE image, not on YOLO crops.
    See docs/severity_integration_decisions.md before changing this.
"""

import torch
import torch.nn as nn
from torchvision import models, transforms
from PIL import Image

# ─────────────────────────────────────────────────────────────────────
# [1] Constants — these MUST match the training notebook exactly.
#     The class order is the alphabetical order produced by ImageFolder
#     (minor -> moderate -> severe). Do not sort or reorder this list:
#     index 0 = minor, 1 = moderate, 2 = severe.
# ─────────────────────────────────────────────────────────────────────
SEVERITY_CLASSES = ["minor", "moderate", "severe"]
NUM_CLASSES = len(SEVERITY_CLASSES)

INPUT_SIZE = 224
IMAGENET_MEAN = [0.485, 0.456, 0.406]
IMAGENET_STD = [0.229, 0.224, 0.225]

WEIGHTS_PATH = "weight/severity_resnet50.pth"

# Rank used to aggregate several image-level severities into one case-level
# severity. Higher number = worse. Aggregation rule is MAX (see [5]).
SEVERITY_RANK = {"minor": 0, "moderate": 1, "severe": 2}

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")


# ─────────────────────────────────────────────────────────────────────
# [2] Build and load the model ONCE at import time.
#     Same pattern as damage_detection.py, which loads YOLO at import.
#
#     weights=None is deliberate: we do NOT want torchvision downloading
#     ImageNet weights on every server start. Our checkpoint overwrites
#     every layer anyway.
# ─────────────────────────────────────────────────────────────────────
def _build_severity_model():
    model = models.resnet50(weights=None)
    model.fc = nn.Linear(model.fc.in_features, NUM_CLASSES)

    checkpoint = torch.load(WEIGHTS_PATH, map_location=DEVICE)

    # Accept either the full training checkpoint (dict with 'model_state')
    # or a slimmed deployment file (raw state_dict).
    if isinstance(checkpoint, dict) and "model_state" in checkpoint:
        state_dict = checkpoint["model_state"]
    else:
        state_dict = checkpoint

    model.load_state_dict(state_dict)
    model.to(DEVICE)
    model.eval()  # disables dropout / batchnorm updates — required for inference
    print(f"✅ Severity model loaded on {DEVICE}")
    return model


severity_model = _build_severity_model()


# ─────────────────────────────────────────────────────────────────────
# [3] Inference transform.
#     This is VAL_TF from the notebook, NOT TRAIN_TF. Training used random
#     flips, rotations and colour jitter; applying those at inference would
#     make the same image return different answers on each run.
# ─────────────────────────────────────────────────────────────────────
INFERENCE_TF = transforms.Compose([
    transforms.Resize((INPUT_SIZE, INPUT_SIZE)),
    transforms.ToTensor(),
    transforms.Normalize(mean=IMAGENET_MEAN, std=IMAGENET_STD),
])


# ─────────────────────────────────────────────────────────────────────
# [4] Classify a single local image file.
#     Takes a LOCAL PATH, not a URL — the caller has already downloaded
#     the image to a temp file for YOLO, so we reuse that file.
# ─────────────────────────────────────────────────────────────────────
def classify_severity(image_path: str) -> dict:
    """
    Returns:
        {
            "severity": "minor" | "moderate" | "severe",
            "confidence": float,          # probability of the predicted class
            "probabilities": {class: float}
        }
    Raises on unreadable images — the caller decides how to handle it.
    """
    # .convert("RGB") matches ImageFolder's default loader. Without it a
    # PNG with an alpha channel would produce a 4-channel tensor and fail.
    image = Image.open(image_path).convert("RGB")

    tensor = INFERENCE_TF(image).unsqueeze(0).to(DEVICE)  # add batch dimension

    with torch.no_grad():
        logits = severity_model(tensor)
        probabilities = torch.softmax(logits, dim=1)[0]

    predicted_index = int(torch.argmax(probabilities))

    return {
        "severity": SEVERITY_CLASSES[predicted_index],
        "confidence": round(float(probabilities[predicted_index]), 2),
        "probabilities": {
            cls: round(float(probabilities[i]), 4)
            for i, cls in enumerate(SEVERITY_CLASSES)
        },
    }


# ─────────────────────────────────────────────────────────────────────
# [5] Aggregate image-level severities into one case-level severity.
#
#     Rule: MAXIMUM, not average.
#     Justification: a case with one severe damage and eight minor ones
#     averages to "minor", which is dangerously misleading. Insurance
#     decisions follow the worst damage present. Max is also trivially
#     explainable to the user: "your case is severe because of this photo".
# ─────────────────────────────────────────────────────────────────────
def aggregate_case_severity(severities: list) -> str | None:
    """
    severities: list of severity strings; None entries are ignored
                (images where no damage was detected).
    Returns the worst severity present, or None if the list has none.
    """
    valid = [s for s in severities if s in SEVERITY_RANK]
    if not valid:
        return None
    return max(valid, key=lambda s: SEVERITY_RANK[s])
