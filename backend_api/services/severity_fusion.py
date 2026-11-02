"""
Severity fusion layer for CrashLens.

PURPOSE: raise real-photo severity accuracy without touching the architecture.
It KEEPS the full-image ResNet severity model and ADDS a geometry signal computed
from outputs the pipeline ALREADY produces:
    - damage bounding boxes  (from the existing YOLOv8s damage detector)
    - part segmentation masks (from the existing YOLOv8s-seg part model)
No damage segmentation, no retraining, no new model. This is a rule layer.

SIGNAL: extent ratio r = damage_box_area / part_mask_area  (clipped to 1.0),
aggregated per image as the MAX over that image's panel/glass damages (worst
damage drives the image grade -- same granularity as the current image-level
ResNet grade, so it drops into the exact place the ResNet label is used today).

GRADES:
    ratio_grade  = minor   if r <  T_MODERATE
                   moderate if T_MODERATE <= r < T_SEVERE
                   severe   if r >= T_SEVERE
    resnet_grade = decode the two ordinal sigmoids at recalibrated cutoffs C0,C1
FUSION: fused = the HIGHER severity of (resnet_grade, ratio_grade).

Damages with no part geometry (tire, lamp) carry no ratio; they keep their
existing damage-class severity and are unaffected by this layer.

THRESHOLDS below are calibrated on the 31-photo pilot (fit-on-all). They are
PROVISIONAL -- documented as such -- and should be re-tuned when more real
labelled photos are available. They do not come from a held-out benchmark.
"""
from __future__ import annotations

LEVELS = ["minor", "moderate", "severe"]
RANK = {l: i for i, l in enumerate(LEVELS)}

# --- provisional pilot-calibrated thresholds (see module docstring) ---
T_MODERATE = 0.06    # ratio below this -> minor
T_SEVERE = 0.69      # ratio at/above this -> severe
C0 = 0.08            # recalibrated cutoff on p(>=moderate)  (was 0.5)
C1 = 0.30            # recalibrated cutoff on p(>=severe)     (was 0.5)


def ratio_grade(max_ratio: float) -> str:
    if max_ratio < T_MODERATE:
        return "minor"
    if max_ratio < T_SEVERE:
        return "moderate"
    return "severe"


def resnet_grade(p_ge_moderate: float, p_ge_severe: float) -> str:
    if p_ge_moderate <= C0:
        return "minor"
    if p_ge_severe <= C1:
        return "moderate"
    return "severe"


def fuse(resnet_g: str, ratio_g: str | None) -> str:
    """Take the higher severity. If no ratio (tire/lamp), keep the ResNet grade."""
    if ratio_g is None:
        return resnet_g
    return resnet_g if RANK[resnet_g] >= RANK[ratio_g] else ratio_g


def image_max_ratio(damages) -> float | None:
    """damages: iterable of (damage_box_area, part_mask_area) for panel/glass damages
    that were associated to a part. Returns max clipped ratio, or None if none."""
    rs = [min(da / pa, 1.0) for da, pa in damages if pa and pa > 0]
    return max(rs) if rs else None


def fused_image_severity(p_ge_moderate, p_ge_severe, damages) -> str:
    """The one call the pipeline makes: same inputs it already has."""
    r = image_max_ratio(damages)
    return fuse(resnet_grade(p_ge_moderate, p_ge_severe),
                ratio_grade(r) if r is not None else None)
