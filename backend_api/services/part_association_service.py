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
  3. Glass buckets (windshield, window/door glass, trunk) are matched against the damage
     box by containment (see `containment_box_mask`), not plain IoA, since glass-shatter
     boxes are often looser/larger than the true break and would otherwise unfairly
     exclude an accurate, well-fitted part mask. When exactly one bucket clears the
     threshold, it's priced normally. When more than one does, their masks are compared
     against EACH OTHER: if they substantially overlap, they're one real break with a
     labeling disagreement, so hours are averaged across the candidates (flagged
     `glass_part_ambiguous_fallback`, same precedent as the wheel front/rear average
     below); if they're spatially distinct, they're genuinely separate damaged parts and
     each is billed, same as the panel multi-part rule above. No supported bucket at all
     is left unpriced for review; generic door masks are not evidence of broken door glass.
  4. Lamp and tire-flat detections use their location-independent expert values once per
     damage-model detection. Their part masks do not change the price.

IoA = |damage_box ∩ part_mask| / |damage_box|. Used for panel matching (rule 1) and as
the admission threshold's VALUE for glass (rule 3), though glass measures containment
(IoA with the smaller of the two regions as the denominator) rather than plain IoA.

⚠️ STAGING: real-domain segmentation accuracy remains under evaluation. Ambiguous visual
assignments either average across a confirmed single spot or bill every confirmed
distinct part — never guess a single cost row from Najm.
"""
from dataclasses import dataclass, field
from typing import List, Optional

import numpy as np

from services.labor_hours_lookup import get_hours

IOA_THRESHOLD = 0.40

# When more than one glass bucket clears IOA_THRESHOLD, this decides whether the
# competing candidates are the same physical spot (one real break, segmentation
# just disagreed on its label -> average their hours, same precedent as the wheel
# front/rear fallback in labor_hours_lookup.py) or genuinely different spots (both
# billed, same precedent as the panel-damage multi-part path below). Chosen from a
# single real example (two duplicate masks of one window measured at 0.978) — not
# independently tuned. Revisit once more glass-ambiguous cases have been observed.
GLASS_SAME_SPOT_OVERLAP = 0.60

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
    # Set only for the glass same-spot-average fallback, where no single lookup_key
    # applies. When present, the cost step uses this instead of looking up hours.
    hours_override: Optional[float] = None
    # Pixel area (mask.sum()) of the single part this line's damage was associated
    # to. None whenever there is no single resolved part mask behind the line
    # (lamp/tire damage_class rows, unassigned rows, and the glass same-spot
    # average, which has no one mask to point to). Consumed by the severity
    # fusion layer (services/severity_fusion.py) as the denominator of its
    # damage-box/part-mask extent ratio; does not affect pricing.
    part_mask_area: Optional[int] = None


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


def containment_box_mask(box, mask) -> float:
    """
    Intersection over the SMALLER of {damage box, part mask} (Szymkiewicz-Simpson
    overlap coefficient), instead of always over the damage box. A loose/oversized
    damage box (common for glass-shatter detections) otherwise unfairly penalizes an
    accurate, well-fitted part mask just for being smaller than the box — see
    docs/cost_estimation.md's glass-association notes.

    Mathematically >= ioa_box_mask always, and identical to it whenever the damage
    box is the smaller region (the normal case for dent/scratch panel damage), so
    this only changes behavior for the oversized-box glass case it targets.
    """
    x1, y1, x2, y2 = [int(v) for v in box]
    x1, y1 = max(0, x1), max(0, y1)
    x2 = min(mask.shape[1], x2)
    y2 = min(mask.shape[0], y2)
    box_area = (x2 - x1) * (y2 - y1)
    mask_area = int(mask.sum())
    smaller = min(box_area, mask_area)
    if smaller <= 0:
        return 0.0
    intersection = float(mask[y1:y2, x1:x2].sum())
    return intersection / float(smaller)


def _mask_pair_overlap(mask_a, mask_b) -> float:
    """Overlap coefficient between two part masks themselves (not vs. a damage box).
    High value -> the two masks describe essentially the same physical region
    (duplicate/disagreeing labels for one spot). Low value -> genuinely distinct
    regions that both happen to sit inside one (likely oversized) damage box."""
    area_a, area_b = int(mask_a.sum()), int(mask_b.sum())
    smaller = min(area_a, area_b)
    if smaller <= 0:
        return 0.0
    intersection = int((mask_a & mask_b).sum())
    return intersection / float(smaller)


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


def _glass_line(damage_index, damage_type, damage, parts, ioa_threshold) -> List[CostLine]:
    """Build glass line(s) from the segmentation cost buckets that clear threshold."""
    hits = {}
    for segmented in parts:
        bucket = _GLASS_BUCKETS.get(_norm(segmented.get("label")))
        if bucket is None:
            continue
        containment = containment_box_mask(damage["bbox"], segmented["mask"])
        if containment < ioa_threshold:
            continue
        part, lookup_key = bucket
        current = hits.get(part)
        # Among duplicate instances of the SAME bucket label, containment is a poor
        # tiebreaker once it's saturated near 1.0 for most candidates (the usual
        # state once a damage box is oversized enough to trigger this branch at
        # all) -- comparing confidence between same-label guesses is apples-to-apples
        # and meaningfully informative here, unlike comparing confidence ACROSS
        # different bucket labels (see the same-spot check below, which never trusts
        # confidence across labels for exactly that reason).
        if (
            current is None
            or segmented.get("confidence", 0.0) > current[0].get("confidence", 0.0)
            or (
                segmented.get("confidence", 0.0) == current[0].get("confidence", 0.0)
                and containment > current[1]
            )
        ):
            hits[part] = (segmented, containment, lookup_key)

    if not hits:
        return [CostLine(
            damage_index, damage_type, None, None, "unassigned",
            flags=["glass_no_part_support"],
        )]

    if len(hits) == 1:
        part, (segmented, containment, lookup_key) = next(iter(hits.items()))
        return [CostLine(
            damage_index, damage_type, part, lookup_key, "seg_ioa",
            ioa=containment, part_conf=float(segmented.get("confidence", 0.0)),
            part_mask_area=int(segmented["mask"].sum()),
        )]

    # More than one bucket cleared threshold. Check whether the candidates'
    # masks substantially overlap EACH OTHER (not the damage box): if so, they're
    # one real spot that segmentation disagreed on how to label -> average, same
    # precedent as the wheel front/rear fallback. If the masks are spatially
    # distinct, they're genuinely separate damaged parts -> bill each, same
    # precedent as the panel-damage multi-part path further below.
    entries = list(hits.values())
    same_spot = all(
        _mask_pair_overlap(a[0]["mask"], b[0]["mask"]) >= GLASS_SAME_SPOT_OVERLAP
        for i, a in enumerate(entries) for b in entries[i + 1:]
    )

    if same_spot:
        hour_values = [
            h for h in (
                get_hours(lookup_key, damage_type) for _, _, lookup_key in entries
            ) if h is not None
        ]
        if hour_values:
            avg_hours = round(sum(hour_values) / len(hour_values), 2)
            avg_conf = sum(s.get("confidence", 0.0) for s, _, _ in entries) / len(entries)
            return [CostLine(
                damage_index, damage_type, "glass_ambiguous", None,
                "glass_part_ambiguous_fallback",
                part_conf=float(avg_conf),
                flags=["glass_part_ambiguous_fallback"],
                hours_override=avg_hours,
            )]
        # None of the candidate buckets had configured hours (shouldn't happen for
        # windshield/door_glass/trunk) -- fall through to the conservative refusal.
        return [CostLine(
            damage_index, damage_type, None, None, "unassigned",
            flags=["glass_ambiguous_part"],
        )]

    return [
        CostLine(
            damage_index, damage_type, part, lookup_key, "seg_ioa",
            ioa=containment, part_conf=float(segmented.get("confidence", 0.0)),
            part_mask_area=int(segmented["mask"].sum()),
        )
        for part, (segmented, containment, lookup_key) in hits.items()
    ]


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
            lines.extend(_glass_line(
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
                    part_mask_area=int(segmented["mask"].sum()),
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
                part_mask_area=int(segmented["mask"].sum()),
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
