"""
Mask-based severity fusion for CrashLens (production).

Supersedes the box-based severity_fusion.py. Severity is graded from the TRUE damage
extent: the damage-segmentation MASK area over the associated part mask area, fused with
the ResNet appearance grade (take the higher severity). Validated on the 31 real
expert-priced photos: mask-ratio severity = 0.667 LOOCV / 0.677 fixed-threshold, vs 0.39
appearance and 0.58 box-fusion.

PIPELINE CHANGE THIS IMPLIES: the damage-segmentation model (yolov8s-seg, the PREVIOUS /
best run -- NOT the tuned v2, which was worse on real photos) must run at analyze time to
produce damage MASKS. Detection, association, and cost stay unchanged; the seg masks are
used ONLY to compute the severity extent ratio.

INPUTS (all already available at analyze time):
  p_ge_moderate, p_ge_severe : ResNet ordinal sigmoids (for the minor fallback / fusion)
  damages : list of (damage_mask_area, associated_part_mask_area) for panel/glass damages
            that were associated to a part. damage_mask_area = seg mask pixel count;
            part_mask_area = associated part mask pixel count. tire/lamp/unassigned -> omit.

THRESHOLDS are pilot-calibrated on the 31 photos (fit-on-all) -- PROVISIONAL, to be
re-tuned when more real labelled data exists. Note T_MODERATE = 0.0: the mask ratio does
not assign 'minor' on its own; 'minor' comes from the ResNet branch via the fusion when a
damage is tiny or no mask is produced.
"""
from __future__ import annotations

LEVELS = ["minor", "moderate", "severe"]
RANK = {l: i for i, l in enumerate(LEVELS)}

# --- provisional pilot-calibrated thresholds (31-photo fit; see docstring) ---
T_MODERATE = 0.0     # mask ratio >= this -> at least moderate
T_SEVERE = 0.60      # mask ratio >= this -> severe
C0 = 0.20            # ResNet p(>=moderate) cutoff
C1 = 0.40            # ResNet p(>=severe) cutoff


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
    if ratio_g is None:
        return resnet_g
    return resnet_g if RANK[resnet_g] >= RANK[ratio_g] else ratio_g


def image_max_ratio(damages) -> float | None:
    """damages: iterable of (damage_mask_area, part_mask_area). Returns max clipped ratio."""
    rs = [min(d / p, 1.0) for d, p in damages if p and p > 0]
    return max(rs) if rs else None


def fused_image_severity(p_ge_moderate, p_ge_severe, damages) -> str:
    r = image_max_ratio(damages)
    return fuse(resnet_grade(p_ge_moderate, p_ge_severe),
                ratio_grade(r) if r is not None else None)
