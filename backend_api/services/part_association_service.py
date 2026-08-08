"""
part_association_service.py — associate detected damage with car parts (STAGING).

Turns the two vision models into cost line-items:
    damage detection (YOLO boxes, damage TYPE)  +  part segmentation (masks, PART)
    -> for each damage, the part(s) it sits on  -> labor_hours_lookup

RULES (as agreed):
  1. MULTI-PART, COUNTED IN FULL. A damage box is assigned to EVERY DISTINCT part
     whose mask overlaps it by IoA >= IOA_THRESHOLD, and each part's hours are charged
     IN FULL (no area splitting) — the labor table is whole-part values and the
     estimator bills per part. A scratch across a door and a fender = door hours +
     fender hours. "Distinct" is by CANONICAL PART LABEL: if the part-seg model emits
     more than one overlapping mask instance with the SAME label over the SAME damage
     box (duplicate/noisy detections of one physical part — a known behavior on
     close-up photos), only the best-IoA instance is billed once, never once per
     instance — otherwise one damage on one fender can get billed as if there were
     two fenders.
  2. CENTROID FALLBACK. If no part clears the IoA threshold, assign to the part mask
     that contains the damage box centroid. If none, mark unassigned -> admin review.
  3. DAMAGE-MODEL PRIORITY for glass / lamp / tire. These come from the DAMAGE class,
     never from the part model:
         glass shatter -> glass   (front_glass/back_glass via Najm zone)
         lamp broken   -> lamp    (front/back + left/right light)
         tire flat     -> wheel
     The part model's own glass/window/wheel prediction only RAISES or LOWERS
     confidence (agreement vs conflict). It does not decide. This is what stops the
     exp03 failure (glass mislabeled as door) from re-entering through the part model.
  4. PANELS (dent/scratch/crack) come from the part-seg IoA association in rule 1.

IoA = |damage_box ∩ part_mask| / |damage_box|  (intersection over the DAMAGE area).

⚠️ STAGING ONLY — produces line-items for end-to-end testing, not for costing real
   user claims. See part_segmentation_service.py.
"""
from dataclasses import dataclass, field
from typing import List, Optional
import numpy as np

IOA_THRESHOLD = 0.20

PANELS = {"door", "front_bumper", "back_bumper", "fender", "hood", "trunk", "roof", "sill"}

# raw damage label -> normalized damage type (the value labor_hours_lookup expects)
_NORMALIZE = {
    "dent": "dent", "scratch": "scratch", "crack": "crack",
    "glass shatter": "glass", "glass_shatter": "glass",
    "lamp broken": "lamp", "lamp_broken": "lamp",
    "tire flat": "tire", "tire_flat": "tire",
}
# normalized damage type -> category (routing bucket)
_CATEGORY = {
    "dent": "panel", "scratch": "panel", "crack": "panel",
    "glass": "glass", "lamp": "lamp", "tire": "tire",
}

# generic seg class -> a representative labor_hours_lookup key ("door" still uses one
# side as a stand-in — all sides cost the same, so any representative is fine for HOURS;
# fender/sill/roof resolve to their own canonical (sideless) LOOKUP rows directly)
_PANEL_TO_LOOKUP_KEY = {
    "door": "front_left_door",
    "fender": "fender",
    "sill": "sill",
    "roof": "roof",
    "front_bumper": "front_bumper",
    "back_bumper": "back_bumper",
    "hood": "hood",
    "trunk": "trunk",
}


@dataclass
class CostLine:
    damage_index: int
    damage_type: str            # normalized: dent/scratch/crack/glass/lamp/tire
    part: Optional[str]         # canonical part (None if unassigned)
    lookup_key: Optional[str]   # key to pass to labor_hours_lookup.get_hours
    source: str                 # damage_class | seg_ioa | centroid_fallback | unassigned
    ioa: float = 0.0
    part_conf: float = 0.0
    flags: List[str] = field(default_factory=list)


def _norm(s: str) -> str:
    return (s or "").strip().lower()


def ioa_box_mask(box, mask) -> float:
    """Intersection of part mask with the damage box, over the box area."""
    x1, y1, x2, y2 = [int(v) for v in box]
    x1, y1 = max(0, x1), max(0, y1)
    x2 = min(mask.shape[1], x2); y2 = min(mask.shape[0], y2)
    area = (x2 - x1) * (y2 - y1)
    if area <= 0:
        return 0.0
    return float(mask[y1:y2, x1:x2].sum()) / float(area)


def _resolve_special(cat, najm_zone, box, image_hw):
    """Resolve glass/lamp/tire to a labor-lookup key from the damage class + Najm zone."""
    z = _norm(najm_zone)
    front = "front" in z or "مقدم" in z
    rear = "rear" in z or "back" in z or "مؤخر" in z or "خلف" in z
    flags = []
    if cat == "tire":
        return "wheel", "wheel", flags
    if cat == "glass":
        if front: return "front_glass", "front_glass", flags
        if rear:  return "back_glass", "back_glass", flags
        flags.append("glass_side_assumed_front")
        return "front_glass", "front_glass", flags
    if cat == "lamp":
        # left/right from the damage box centre; front/rear from Najm
        _, _, W = *image_hw[:1], None
        H, W = image_hw
        cx = (box[0] + box[2]) / 2.0
        side = "left" if cx < W / 2.0 else "right"
        if not (front or rear):
            flags.append("lamp_frontback_assumed_front")
        fb = "back" if rear else "front"
        key = f"{fb}_{side}_light"
        return "lamp", key, flags
    return None, None, ["unknown_category"]


def associate(damages, parts, image_hw, najm_zone: Optional[str] = None,
              ioa_threshold: float = IOA_THRESHOLD) -> List[CostLine]:
    """
    damages: [{label, bbox:(x1,y1,x2,y2), confidence}]  from damage_detection
    parts:   [{label, mask:boolHxW, bbox, confidence}]  from part_segmentation_service
    image_hw: (H, W)
    Returns a flat list of CostLine (a damage may yield several — one per overlapping part).
    """
    lines: List[CostLine] = []
    for di, d in enumerate(damages):
        raw = _norm(d.get("label"))
        dtype = _NORMALIZE.get(raw, raw)            # dent/scratch/crack/glass/lamp/tire
        cat = _CATEGORY.get(dtype, "panel")

        if cat in ("glass", "lamp", "tire"):
            part, key, flags = _resolve_special(cat, najm_zone, d["bbox"], image_hw)
            # confidence support: does any overlapping seg part agree with the category?
            support = any(
                ioa_box_mask(d["bbox"], p["mask"]) >= ioa_threshold
                and _seg_supports(cat, _norm(p["label"]))
                for p in parts
            )
            if not support:
                flags = flags + ["seg_no_support"]
            lines.append(CostLine(di, dtype, part, key, "damage_class",
                                  part_conf=1.0, flags=flags))
            continue

        # PANEL damage -> IoA-multi, counted in full, ONCE PER DISTINCT canonical
        # label. Duplicate/overlapping mask instances of the same part (segmentation
        # noise) collapse to their single best-IoA instance instead of double-billing.
        hits_by_label = {}
        for p in parts:
            lbl = _norm(p["label"])
            if lbl in PANELS:
                io = ioa_box_mask(d["bbox"], p["mask"])
                if io >= ioa_threshold:
                    best = hits_by_label.get(lbl)
                    if best is None or io > best[1]:
                        hits_by_label[lbl] = (p, io)
        if hits_by_label:
            for lbl, (p, io) in hits_by_label.items():
                key = _PANEL_TO_LOOKUP_KEY.get(lbl, lbl)
                lines.append(CostLine(di, dtype, lbl, key, "seg_ioa",
                                      ioa=io, part_conf=float(p["confidence"]), flags=[]))
        else:
            # centroid fallback
            cx = int((d["bbox"][0] + d["bbox"][2]) / 2)
            cy = int((d["bbox"][1] + d["bbox"][3]) / 2)
            containing = [p for p in parts
                          if _norm(p["label"]) in PANELS
                          and 0 <= cy < p["mask"].shape[0] and 0 <= cx < p["mask"].shape[1]
                          and p["mask"][cy, cx]]
            if containing:
                p = max(containing, key=lambda q: q["confidence"])
                lbl = _norm(p["label"])
                key = _PANEL_TO_LOOKUP_KEY.get(lbl, lbl)
                lines.append(CostLine(di, dtype, lbl, key, "centroid_fallback",
                                      part_conf=float(p["confidence"]), flags=["centroid_fallback"]))
            else:
                lines.append(CostLine(di, dtype, None, None, "unassigned",
                                      flags=["unassigned_admin_review"]))
    return lines


def _seg_supports(cat, seg_label):
    if cat == "glass": return seg_label in ("windshield", "window")
    if cat == "lamp":  return seg_label in ("headlight", "taillight")
    if cat == "tire":  return seg_label == "wheel"
    return False


# ---------------------------------------------------------------- self-test
if __name__ == "__main__":
    H, W = 100, 200
    def mask_rect(x1, y1, x2, y2):
        m = np.zeros((H, W), bool); m[y1:y2, x1:x2] = True; return m

    # a door mask (left half) and a fender mask (overlapping strip)
    door   = {"label": "door",   "mask": mask_rect(0, 0, 100, 100), "bbox": (0,0,100,100),   "confidence": 0.9}
    fender = {"label": "fender", "mask": mask_rect(80, 0, 130, 100), "bbox": (80,0,130,100),  "confidence": 0.7}
    windshield = {"label": "windshield", "mask": mask_rect(120,0,200,100), "bbox":(120,0,200,100), "confidence": 0.95}
    parts = [door, fender, windshield]

    dmgs = [
        {"label": "scratch", "bbox": (70, 20, 110, 60), "confidence": 0.8},   # spans door + fender
        {"label": "glass shatter", "bbox": (130, 10, 190, 90), "confidence": 0.9},  # glass
        {"label": "dent", "bbox": (5, 5, 15, 15), "confidence": 0.6},         # door only
        {"label": "dent", "bbox": (150, 95, 160, 99), "confidence": 0.5},     # overlaps nothing panel -> fallback/unassigned
    ]
    for ln in associate(dmgs, parts, (H, W), najm_zone="front"):
        print(f"dmg{ln.damage_index} {ln.damage_type:6s} -> part={ln.part} key={ln.lookup_key} "
              f"src={ln.source} ioa={ln.ioa:.2f} flags={ln.flags}")