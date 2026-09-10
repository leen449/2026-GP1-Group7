"""
Associate damage-detection boxes with segmented vehicle parts for cost estimation.

The damage model owns the damage TYPE. The segmentation model owns the costed PART for
panels and glass. Najm is not a general costing key; its only association input is an
optional front/rear hint for wheel dents because the current segmentation taxonomy
collapses wheel position while the expert dent hours differ.

Rules:
  1. Panel damage is assigned to every distinct segmented panel whose mask overlaps the
     damage box by IoA >= IOA_THRESHOLD. Duplicate masks of the same canonical part are
     billed once, using the best-IoA instance.
  2. If no panel clears the threshold, a mask containing the damage centroid may be used.
  3. Glass is priced only when exactly one distinct glass cost bucket clears the IoA
     threshold: windshield, window/door glass, or trunk. Missing/conflicting evidence is
     left unpriced for review; generic door masks are not evidence of broken door glass.
  4. Lamp and tire-flat detections use their location-independent expert values once per
     damage-model detection. Their part masks do not change the price.

IoA = |damage_box ∩ part_mask| / |damage_box|.

⚠️ STAGING: real-domain segmentation accuracy remains under evaluation. Ambiguous visual
assignments fail visibly instead of selecting a cost row from Najm.
"""
from dataclasses import dataclass, field
from typing import List, Optional

import numpy as np

IOA_THRESHOLD = 0.20

PANELS = {
    "door", "front_bumper", "back_bumper", "fender", "hood", "trunk", "roof",
    "sill", "wheel",
}

# raw damage label -> normalized damage type (the value labor_hours_lookup expects)
_NORMALIZE = {
    "dent": "dent", "scratch": "scratch", "crack": "crack",
    "glass shatter": "glass", "glass_shatter": "glass",
    "lamp broken": "lamp", "lamp_broken": "lamp",
    "tire flat": "tire", "tire_flat": "tire",
}
_CATEGORY = {
    "dent": "panel", "scratch": "panel", "crack": "panel",
    "glass": "glass", "lamp": "lamp", "tire": "tire",
}

# Model-level canonical part -> logical labor lookup key. Common-value logical keys are
# resolved against the exact expert rows in labor_hours_lookup.py.
_PANEL_TO_LOOKUP_KEY = {
    "door": "door",
    "fender": "fender",
    "sill": "sill",
    "roof": "roof",
    "front_bumper": "front_bumper",
    "back_bumper": "back_bumper",
    "hood": "hood",
    "trunk": "trunk",
    "wheel": "wheel",
}

_GLASS_BUCKETS = {
    "windshield": ("windshield", "windshield"),
    "window": ("door_glass", "door_glass"),
    "trunk": ("trunk", "trunk"),
}


@dataclass
class CostLine:
    damage_index: int
    damage_type: str
    part: Optional[str]
    lookup_key: Optional[str]
    source: str
    ioa: float = 0.0
    part_conf: float = 0.0
    flags: List[str] = field(default_factory=list)
    wheel_position: Optional[str] = None


def _norm(s: str) -> str:
    return (s or "").strip().lower().replace("-", "_").replace(" ", "_")


def ioa_box_mask(box, mask) -> float:
    """Intersection of part mask with the damage box, over the box area."""
    x1, y1, x2, y2 = [int(v) for v in box]
    x1, y1 = max(0, x1), max(0, y1)
    x2 = min(mask.shape[1], x2)
    y2 = min(mask.shape[0], y2)
    area = (x2 - x1) * (y2 - y1)
    if area <= 0:
        return 0.0
    return float(mask[y1:y2, x1:x2].sum()) / float(area)


def _wheel_position_from_label(label: str) -> Optional[str]:
    label = _norm(label)
    if label.startswith("front_") or label == "front_wheel":
        return "front"
    if label.startswith("back_") or label.startswith("rear_") or label in (
        "back_wheel", "rear_wheel",
    ):
        return "rear"
    return None


def _panel_identity(label: str):
    """Return (canonical part, lookup key, visual wheel position), or None."""
    label = _norm(label)
    if label in PANELS:
        return label, _PANEL_TO_LOOKUP_KEY[label], _wheel_position_from_label(label)

    if label in {
        "front_wheel", "rear_wheel", "back_wheel",
        "front_left_wheel", "front_right_wheel",
        "back_left_wheel", "back_right_wheel",
        "rear_left_wheel", "rear_right_wheel",
    }:
        return "wheel", "wheel", _wheel_position_from_label(label)
    return None


def _wheel_fields(damage_type: str, visual_position: Optional[str],
                  wheel_position_hint: Optional[str]):
    if damage_type != "dent":
        return None, []

    position = visual_position or (
        wheel_position_hint if wheel_position_hint in ("front", "rear") else None
    )
    if position is None:
        return None, ["wheel_position_ambiguous_fallback"]
    return position, []


def _glass_line(damage_index, damage_type, damage, parts, ioa_threshold):
    """Build one glass line from one unambiguous segmentation cost bucket."""
    hits = {}
    for segmented in parts:
        bucket = _GLASS_BUCKETS.get(_norm(segmented.get("label")))
        if bucket is None:
            continue
        ioa = ioa_box_mask(damage["bbox"], segmented["mask"])
        if ioa < ioa_threshold:
            continue
        part, lookup_key = bucket
        current = hits.get(part)
        if (
            current is None
            or ioa > current[1]
            or (
                ioa == current[1]
                and segmented.get("confidence", 0.0) > current[0].get("confidence", 0.0)
            )
        ):
            hits[part] = (segmented, ioa, lookup_key)

    if not hits:
        return CostLine(
            damage_index, damage_type, None, None, "unassigned",
            flags=["glass_no_part_support"],
        )
    if len(hits) > 1:
        return CostLine(
            damage_index, damage_type, None, None, "unassigned",
            flags=["glass_ambiguous_part"],
        )

    part, (segmented, ioa, lookup_key) = next(iter(hits.items()))
    return CostLine(
        damage_index, damage_type, part, lookup_key, "seg_ioa",
        ioa=ioa, part_conf=float(segmented.get("confidence", 0.0)),
    )


def associate(damages, parts, image_hw, najm_zone: Optional[str] = None,
              ioa_threshold: float = IOA_THRESHOLD,
              wheel_position_hint: Optional[str] = None) -> List[CostLine]:
    """
    Associate stored damage boxes with segmentation masks.

    `najm_zone` remains as a deprecated compatibility argument and is deliberately
    ignored. Callers may provide only `wheel_position_hint` for the wheel-dent exception.
    """
    del image_hw, najm_zone
    lines: List[CostLine] = []

    for damage_index, damage in enumerate(damages):
        raw = _norm(damage.get("label"))
        damage_type = _NORMALIZE.get(raw, raw)
        category = _CATEGORY.get(damage_type, "panel")

        if category == "glass":
            lines.append(_glass_line(
                damage_index, damage_type, damage, parts, ioa_threshold,
            ))
            continue

        if category == "lamp":
            lines.append(CostLine(
                damage_index, damage_type, "lamp", "lamp", "damage_class",
                part_conf=1.0,
            ))
            continue

        if category == "tire":
            lines.append(CostLine(
                damage_index, damage_type, "wheel", "wheel", "damage_class",
                part_conf=1.0,
            ))
            continue

        # Panel-like damage: retain one best mask per distinct canonical part.
        hits_by_part = {}
        for segmented in parts:
            identity = _panel_identity(segmented.get("label"))
            if identity is None:
                continue
            part, lookup_key, visual_wheel_position = identity
            ioa = ioa_box_mask(damage["bbox"], segmented["mask"])
            if ioa < ioa_threshold:
                continue
            current = hits_by_part.get(part)
            if current is None or ioa > current[1]:
                hits_by_part[part] = (
                    segmented, ioa, lookup_key, visual_wheel_position,
                )

        if hits_by_part:
            for part, (segmented, ioa, lookup_key, visual_position) in hits_by_part.items():
                wheel_position, flags = (None, [])
                if part == "wheel":
                    wheel_position, flags = _wheel_fields(
                        damage_type, visual_position, wheel_position_hint,
                    )
                lines.append(CostLine(
                    damage_index, damage_type, part, lookup_key, "seg_ioa",
                    ioa=ioa,
                    part_conf=float(segmented.get("confidence", 0.0)),
                    flags=flags,
                    wheel_position=wheel_position,
                ))
            continue

        # Centroid fallback is permitted for panel-like damage only.
        cx = int((damage["bbox"][0] + damage["bbox"][2]) / 2)
        cy = int((damage["bbox"][1] + damage["bbox"][3]) / 2)
        containing = []
        for segmented in parts:
            identity = _panel_identity(segmented.get("label"))
            mask = segmented.get("mask")
            if identity is None or mask is None:
                continue
            if 0 <= cy < mask.shape[0] and 0 <= cx < mask.shape[1] and mask[cy, cx]:
                containing.append((segmented, identity))

        if containing:
            segmented, (part, lookup_key, visual_position) = max(
                containing, key=lambda item: item[0].get("confidence", 0.0),
            )
            wheel_position, flags = (None, ["centroid_fallback"])
            if part == "wheel":
                wheel_position, wheel_flags = _wheel_fields(
                    damage_type, visual_position, wheel_position_hint,
                )
                flags.extend(wheel_flags)
            lines.append(CostLine(
                damage_index, damage_type, part, lookup_key, "centroid_fallback",
                part_conf=float(segmented.get("confidence", 0.0)),
                flags=flags,
                wheel_position=wheel_position,
            ))
        else:
            lines.append(CostLine(
                damage_index, damage_type, None, None, "unassigned",
                flags=["unassigned_admin_review"],
            ))

    return lines


if __name__ == "__main__":
    height, width = 100, 200

    def mask_rect(x1, y1, x2, y2):
        mask = np.zeros((height, width), bool)
        mask[y1:y2, x1:x2] = True
        return mask

    sample_parts = [
        {"label": "door", "mask": mask_rect(0, 0, 100, 100), "confidence": 0.9},
        {"label": "fender", "mask": mask_rect(80, 0, 130, 100), "confidence": 0.7},
        {"label": "windshield", "mask": mask_rect(120, 0, 200, 100), "confidence": 0.95},
    ]
    sample_damages = [
        {"label": "scratch", "bbox": (70, 20, 110, 60), "confidence": 0.8},
        {"label": "glass shatter", "bbox": (130, 10, 190, 90), "confidence": 0.9},
    ]
    for line in associate(sample_damages, sample_parts, (height, width)):
        print(line)
