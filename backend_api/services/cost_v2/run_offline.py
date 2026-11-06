"""
backend_api/services/cost_v2/run_offline.py — offline runner for cost rule v2.

STANDALONE / OFFLINE. Reads a JSON file of per-detection pipeline outputs (one entry per
detected damage, already produced by the existing pipeline -- this script does not run
any model), maps pipeline labels to engine.py's (table_key, damage) vocabulary, builds a
case-wide panel_id, calls engine.estimate() once per case, and writes CSV + itemized JSON.

Does not touch Firestore, cost_estimation_services.py, cost_calibration.py, the mobile
app, or the admin panel.

---------------------------------------------------------------------------------------
INPUT SCHEMA (JSON array, one object per detected damage):
  {
    "case_id": str,                     required
    "image_id": str,                    required (used for traceability AND as the
                                         identity fallback scope -- see PANEL IDENTITY)
    "part_label": str,                  the segmentation/association layer's raw,
                                         position-aware part label where available, e.g.
                                         "front_bumper", "door", "fender", "headlight",
                                         "windshield", "front_wheel". Required for
                                         dent/scratch/crack; optional for lamp/glass/tire
                                         (used for identity only when present -- see below)
    "damage_class": str,                required, e.g. "Dent", "Lamp broken", "tire_flat"
    "severity": "minor"|"moderate"|"severe"|null,   optional, defaults to None
    "box": [x1, y1, x2, y2]              optional, unused, kept for traceability only
  }

---------------------------------------------------------------------------------------
TWO SEPARATE THINGS DERIVED FROM part_label -- DO NOT CONFLATE (this is the fix from the
first version of this file, which used table_key for both and silently merged panels
that the vision layer could already tell apart, or would be able to after a retrain):

  1. HOURS KEY (table_key) -- which row of tables.py prices this detection. Many-to-one
     by design: front_door and back_door both price off the generic "door" row (dent/
     scratch/crack hours are side-independent there; only the per-side door-GLASS cells
     differ, and glass is priced off the forced generic "glass" key anyway, so the split
     doesn't matter for hours). See PART_TO_TABLE_KEY / FORCED_TABLE_KEY_BY_DAMAGE.

  2. PANEL IDENTITY (what panel_id is built from) -- which PHYSICAL panel this detection
     belongs to, for de-duplication (D5). Must be position-aware and must NOT collapse
     through the hours key. Built from the raw part_label directly, not from table_key.

LABEL MAPPING (update PART_TO_TABLE_KEY after the part-model retrain -- see
DECISION_cost_rule_v2.md's O1 and CLAUDE.local.md's retrain plan):

  part_label -> table_key (HOURS KEY ONLY; used for dent/scratch/crack):
    front_bumper -> front_bumper
    back_bumper  -> back_bumper
    hood         -> hood
    trunk        -> trunk
    roof         -> roof
    sill         -> sill
    door         -> door
    fender       -> front_fender   TEMPORARY: the part model (exp04) merges Fender and
                                    Quarter-panel into one canonical `fender` class, so a
                                    real rear-quarter crack (25h in A_100) is currently
                                    indistinguishable from a front fender dent (5h) at the
                                    vision layer. Routing every `fender` detection to
                                    front_fender is a deliberate, documented
                                    UNDER-estimate until the retrain (O1) splits the class.
                                    Once the retrain lands and the model emits a separate
                                    `quarter_panel` label, add "quarter_panel": "rear_quarter"
                                    here -- panel IDENTITY already handles the split (it
                                    uses the raw label), this dict only needs the new hours
                                    row added.

  damage_class -> engine "damage" key (case/spacing normalization only):
    dent -> dent, scratch -> scratch, crack -> crack
    "lamp broken" / lamp_broken -> lamp
    "glass shatter" / glass_shatter -> glass
    "tire flat" / tire_flat -> tire

  Forced table_key override (D6: lamp/tire hours are location-independent in production
  today, same precedent as labor_hours_lookup.py. This affects HOURS ONLY -- identity
  below still uses whatever part_label came in):
    damage == "lamp" -> table_key "lamp"   (ignores part_label for HOURS)
    damage == "tire" -> table_key "tire"   (ignores part_label for HOURS)

  GLASS is a partial exception (the small fix in this revision): a door or trunk mask
  has its OWN glass cell in tables.py (door glass != trunk glass != generic windshield
  glass in B_130/O_165, e.g. O_165 door glass=0.8h, trunk glass=1h, generic glass=2h --
  pricing all three the same was a real simplification, not a no-op, for those tables).
  So glass now checks GLASS_PART_SPECIFIC_TABLE_KEY first (door/front_door/back_door ->
  "door", trunk -> "trunk") and only falls through to the generic "glass" row for
  windshield/back_windshield/window or an unmatched/missing part -- mirroring
  part_association_service.py's _GLASS_BUCKETS (windshield/door_glass/trunk) more closely
  than the previous always-generic rule, though still collapsed to one row per bucket
  rather than the live pipeline's per-side door-glass cells (no side signal here either).

  MERGE_REAR_WINDSHIELD (default False): a pure identity-time remap, back_windshield ->
  windshield, applied before anything else in map_detection. Exists as a documented,
  one-line fallback if exp05's back_windshield class (271 raw HITL instances, the
  thinnest of the four new splits -- see CLAUDE.local.md) turns out too weak to ship:
  flip it to True to fall back to exp04's merged behavior WITHOUT retraining. Does not
  affect hours (glass hours for both were already generic before this flag exists),
  only identity/de-duplication.

---------------------------------------------------------------------------------------
PANEL IDENTITY (D5 -- the same physical panel across images of one case is charged once):

  dent/scratch/crack (part_label always required -> always has identity):
    panel_id = f"{case_id}:{normalized part_label}"
    e.g. case:front_door vs case:back_door, case:fender vs case:quarter_panel,
    case:front_bumper -- these are DISTINCT panels even though front_door/back_door both
    use the "door" hours row, and fender/quarter_panel currently both use "front_fender".

  lamp/glass/tire (part_label is OPTIONAL -- it is only ever a bonus identity signal here,
  never required for hours, since hours are forced):
    - part_label PRESENT (an overlapping part was found, e.g. "headlight" vs "taillight",
      "windshield" vs "back_windshield", "front_wheel" vs "back_wheel" -- works today for
      headlight/taillight, which exp04 already trains as separate classes; works for the
      windshield/wheel sides only after the O1/O2 retrain splits them):
        panel_id = f"{case_id}:{normalized part_label}"
    - part_label ABSENT (no part mask overlapped the damage box -- the current
      association layer doesn't even look for one on lamp/tire detections, see
      part_association_service.py's damage_class path): no case-wide identity is safe to
      assume, so this FALLS BACK to a per-image panel_id and logs a warning:
        panel_id = f"{case_id}:{table_key}:{image_id}"
      This is intentionally conservative -- it may OVER-count (same lamp seen in two
      photos, no part signal, priced twice) rather than silently guessing it's the same
      physical part and UNDER-counting two different broken lamps as one.

  REMAINING LIMITATION (real, not fixed by this file -- it is a vision-model ceiling):
  before the O1/O2 retrain, the part model only ever emits the merged labels "door",
  "fender", "windshield", "window", "wheel" (no side). Two real but visually-identical-
  label panels (e.g. two different doors) will still share one identity and merge, same
  as before -- but ONLY because the model cannot currently tell them apart, not because
  this runner forces them through a shared hours key. Once the model emits side-aware
  labels, this file requires zero changes to start separating them correctly.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import sys

RUN_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, RUN_DIR)
from engine import estimate, CostV2Error  # noqa: E402

PART_TO_TABLE_KEY = {
    "front_bumper": "front_bumper",
    "back_bumper": "back_bumper",
    "hood": "hood",
    "trunk": "trunk",
    "roof": "roof",
    "sill": "sill",
    "door": "door",
    "fender": "front_fender",  # TEMPORARY -- see module docstring
    # Forward-compat rows: the part model does not emit these labels yet (pre-retrain),
    # but identity (panel_id) already keys off the raw label, not this hours mapping -- so
    # once the O1 retrain starts emitting them, pricing needs no runner change, only this
    # table to already have a row. Side-independent hours (front_door/back_door both price
    # as "door"; quarter_panel prices as the real "rear_quarter" row, fixing the current
    # fender->front_fender under-estimate for that specific part once it's distinguishable).
    "front_door": "door",
    "back_door": "door",
    "quarter_panel": "rear_quarter",
    # Wheel-panel dent/scratch/crack (approved 2026-11-07) -- tyre-flat damage stays
    # forced to the separate "tire" table_key (FORCED_TABLE_KEY_BY_DAMAGE below),
    # unaffected by this. front_wheel/back_wheel forward-compat the same way the door/
    # fender split rows above do -- the model doesn't emit them yet, but identity
    # already keys off the raw label, so no runner change needed once it does.
    "wheel": "wheel",
    "front_wheel": "wheel",
    "back_wheel": "wheel",
}

DAMAGE_CLASS_NORMALIZE = {
    "dent": "dent", "scratch": "scratch", "crack": "crack",
    "lamp broken": "lamp", "lamp_broken": "lamp", "lamp": "lamp",
    "glass shatter": "glass", "glass_shatter": "glass", "glass": "glass",
    "tire flat": "tire", "tire_flat": "tire", "tire": "tire",
}

# Damage classes whose HOURS KEY is unconditionally forced regardless of the associated
# part label. Identity (panel_id) is NOT forced -- see module docstring's "PANEL IDENTITY".
# Glass is handled separately (GLASS_PART_SPECIFIC_TABLE_KEY below) since door/trunk glass
# have their own, different hours cells -- see module docstring.
FORCED_TABLE_KEY_BY_DAMAGE = {"lamp": "lamp", "tire": "tire"}

# Glass-only: if the overlapping part is a door or trunk, price off THAT part's own glass
# cell instead of the generic "glass" row. windshield/back_windshield/window and any
# unmatched/missing part fall through to the generic "glass" key (see .get(..., "glass")
# at the call site) -- see module docstring for why this is a partial exception, not a
# full per-part-and-side glass table.
GLASS_PART_SPECIFIC_TABLE_KEY = {
    "door": "door", "front_door": "door", "back_door": "door",
    "trunk": "trunk",
}

# Pure identity-time fallback switch -- see module docstring. Does not affect hours.
MERGE_REAR_WINDSHIELD = False


class MappingError(ValueError):
    """An input detection could not be mapped to a (table_key, damage) pair."""


def _norm(s) -> str:
    return (s or "").strip().lower().replace("-", "_").replace(" ", "_")


def map_detection(raw: dict) -> tuple[dict, str | None]:
    """
    raw pipeline detection -> (engine detection {panel_id, table_key, damage, severity?},
    warning or None). The warning is non-fatal -- it flags a per-image identity fallback,
    not a mapping failure (those raise MappingError).
    """
    case_id = raw["case_id"]
    image_id = raw.get("image_id")
    damage_class = _norm(raw["damage_class"])
    damage = DAMAGE_CLASS_NORMALIZE.get(damage_class)
    if damage is None:
        raise MappingError(f"Unknown damage_class {raw['damage_class']!r} (case {case_id})")

    part_label = _norm(raw.get("part_label")) or None
    if MERGE_REAR_WINDSHIELD and part_label == "back_windshield":
        part_label = "windshield"
    warning = None

    if damage == "glass":
        table_key = GLASS_PART_SPECIFIC_TABLE_KEY.get(part_label, "glass")
        if part_label:
            panel_id = f"{case_id}:{part_label}"
        else:
            panel_id = f"{case_id}:{table_key}:{image_id}"
            warning = (
                f"No overlapping part for {damage!r} damage (case {case_id!r}, "
                f"image {image_id!r}) -- falling back to per-image panel_id {panel_id!r}"
            )
    elif damage in FORCED_TABLE_KEY_BY_DAMAGE:
        table_key = FORCED_TABLE_KEY_BY_DAMAGE[damage]
        if part_label:
            panel_id = f"{case_id}:{part_label}"
        else:
            panel_id = f"{case_id}:{table_key}:{image_id}"
            warning = (
                f"No overlapping part for {damage!r} damage (case {case_id!r}, "
                f"image {image_id!r}) -- falling back to per-image panel_id {panel_id!r}"
            )
    else:
        table_key = PART_TO_TABLE_KEY.get(part_label)
        if table_key is None:
            raise MappingError(
                f"Unknown/missing part_label {raw.get('part_label')!r} for damage "
                f"{damage!r} (case {case_id!r}, image {image_id!r})"
            )
        panel_id = f"{case_id}:{part_label}"

    detection = {"panel_id": panel_id, "table_key": table_key, "damage": damage}
    severity = raw.get("severity")
    if severity is not None:
        detection["severity"] = severity
    return detection, warning


def load_detections_by_case(input_path: str) -> tuple[dict, list]:
    with open(input_path, encoding="utf-8") as f:
        raw_detections = json.load(f)

    by_case: dict[str, list] = {}
    warnings = []
    errors = []
    for raw in raw_detections:
        try:
            mapped, warning = map_detection(raw)
        except MappingError as e:
            errors.append(str(e))
            continue
        if warning:
            warnings.append(warning)
        by_case.setdefault(raw["case_id"], []).append(mapped)

    if errors:
        raise MappingError(
            f"{len(errors)} detection(s) could not be mapped:\n  " + "\n  ".join(errors)
        )
    for w in warnings:
        print(f"⚠️  {w}")
    return by_case, warnings


def run(input_path, output_dir, table, aggregation, severity_default):
    by_case, warnings = load_detections_by_case(input_path)
    os.makedirs(output_dir, exist_ok=True)

    summary_rows = []
    itemized = {}
    for case_id, detections in by_case.items():
        result = estimate(
            detections, table=table, aggregation=aggregation,
            severity_default=severity_default,
        )
        summary_rows.append({
            "case_id": case_id,
            "table": result["table"],
            "aggregation": result["aggregation"],
            "n_detections": len(detections),
            "n_lines": len(result["lines"]),
            "hours": result["hours"],
            "weighted_hours": result["weighted_hours"],
            "cost_sar": result["cost_sar"],
        })
        itemized[case_id] = result

    csv_path = os.path.join(output_dir, "cost_v2_offline_summary.csv")
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        fieldnames = [
            "case_id", "table", "aggregation", "n_detections", "n_lines",
            "hours", "weighted_hours", "cost_sar",
        ]
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(summary_rows)

    json_path = os.path.join(output_dir, "cost_v2_offline_itemized.json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(itemized, f, indent=2, ensure_ascii=False)

    if warnings:
        warn_path = os.path.join(output_dir, "cost_v2_offline_identity_fallback_warnings.txt")
        with open(warn_path, "w", encoding="utf-8") as f:
            f.write("\n".join(warnings) + "\n")
        print(f"{len(warnings)} identity-fallback warning(s) -- see {warn_path}")

    print(f"{len(summary_rows)} case(s) priced. Wrote:\n  {csv_path}\n  {json_path}")
    return summary_rows, itemized


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("---")[0])
    parser.add_argument("--input", required=True, help="Path to per-detection pipeline-output JSON")
    parser.add_argument("--output-dir", required=True, help="Directory to write the CSV/JSON into")
    parser.add_argument("--table", default="A_100", choices=["A_100", "B_130", "O_165"])
    parser.add_argument("--aggregation", default="one_panel", choices=["one_panel", "summed"])
    parser.add_argument(
        "--severity-default", default=None, choices=[None, "minor", "moderate", "severe"],
        help="Fallback severity for detections with no 'severity' field; omit to disable "
             "the severity factor (F=1.0) for those detections.",
    )
    args = parser.parse_args()
    run(args.input, args.output_dir, args.table, args.aggregation, args.severity_default)


if __name__ == "__main__":
    main()
