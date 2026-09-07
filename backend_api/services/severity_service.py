"""
Severity classification service.

Model:      ResNet50 (torchvision), fine-tuned end-to-end.
Experiment: Experiment 10 — CSP650 full-image ordinal classifier.
Deployment: two ordinal logits with fixed sigmoid thresholds at 0.5.

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
NUM_ORDINAL_OUTPUTS = 2

INPUT_SIZE = 224
IMAGENET_MEAN = [0.485, 0.456, 0.406]
IMAGENET_STD = [0.229, 0.224, 0.225]

WEIGHTS_PATH = "weight/severity_resnet50_ordinal_csp650_v1.pth"

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
    model.fc = nn.Linear(model.fc.in_features, NUM_ORDINAL_OUTPUTS)

    checkpoint = torch.load(WEIGHTS_PATH, map_location=DEVICE)

    # The deployed Experiment 10 file is a raw state_dict. Strict loading is
    # intentional: a legacy 3-logit checkpoint must fail clearly.
    if not isinstance(checkpoint, dict):
        raise RuntimeError(f"Unsupported severity checkpoint format: {type(checkpoint)!r}")
    state_dict = checkpoint.get("model_state", checkpoint.get("model_state_dict", checkpoint))
    if not isinstance(state_dict, dict) or "fc.weight" not in state_dict:
        raise RuntimeError("Severity checkpoint does not contain a ResNet50 state_dict with fc.weight")
    if tuple(state_dict["fc.weight"].shape) != (NUM_ORDINAL_OUTPUTS, model.fc.in_features):
        raise RuntimeError(
            f"Expected an ordinal ResNet50 head with shape "
            f"({NUM_ORDINAL_OUTPUTS}, {model.fc.in_features}); "
            f"found {tuple(state_dict['fc.weight'].shape)}. "
            "The old 3-class softmax checkpoint cannot be deployed here."
        )
    model.load_state_dict(state_dict, strict=True)
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
            "confidence": float,          # ordinal decision confidence
            "ordinalProbabilities": {
                "greaterThanMinor": float,
                "greaterThanModerate": float,
            },
        }
    Raises on unreadable images — the caller decides how to handle it.
    """
    # .convert("RGB") matches ImageFolder's default loader. Without it a
    # PNG with an alpha channel would produce a 4-channel tensor and fail.
    image = Image.open(image_path).convert("RGB")

    tensor = INFERENCE_TF(image).unsqueeze(0).to(DEVICE)  # add batch dimension

    with torch.inference_mode():
        logits = severity_model(tensor)
        probabilities = torch.sigmoid(logits)[0]

    p_gt_minor = float(probabilities[0])
    p_gt_moderate = float(probabilities[1])
    if p_gt_minor < 0.5:
        severity = "minor"
        decision_confidence = 1.0 - p_gt_minor
    elif p_gt_moderate < 0.5:
        severity = "moderate"
        decision_confidence = min(p_gt_minor, 1.0 - p_gt_moderate)
    else:
        severity = "severe"
        decision_confidence = p_gt_moderate

    return {
        "severity": severity,
        "confidence": round(decision_confidence, 2),
        "ordinalProbabilities": {
            "greaterThanMinor": round(p_gt_minor, 4),
            "greaterThanModerate": round(p_gt_moderate, 4),
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
