"""
backend_api/tests/cost_v2_parity_harness.py — offline parity check for the cost v2
shadow hook (services/cost_estimation_services.py's _compute_cost_v2_shadow), run
against the REAL pipeline on local image files. No Firestore reads or writes, no
network calls -- same "local, no server" spirit as tests/local_harness.py.

Runs the real damage detector (weight/best.pt, via services.damage_detection.model),
the real exp04 part model (weight/part_seg_exp04.pt, via
services.part_segmentation_service.segment_parts), and the real association logic
(services.part_association_service.associate) on each of the 31 Tagdeer photos,
treating each photo as its own one-image case (case_id = image_id = "IMG-XX") -- the
same convention used to build the offline reference CSV
(experiments/exp05_hitl_panels_split/cost_e2e_exp04_vs_exp05.csv, model=exp04 rows).

Two severity modes:
  --mode override    : use SEVERITY_OVERRIDE below (matches the task's per-image dict)
  --mode production  : run the REAL severity pipeline (ResNet50 ordinal classifier +
    mask-based fusion), mirroring services/cost_estimation_services.py's _stage_image()
    lines ~712-744 exactly (duplicated here, not imported, since that logic lives
    inline inside a Firebase-coupled function -- see that function's docstring for
    the fusion rationale this harness reproduces).

Also prints/saves the cost DISPLAY SWITCH columns (integration step 1-2, part 2 --
see services/cost_v2/spec/DECISION_cost_rule_v2.md §7-8): estimated_cost_sar (v1,
this one-image "case" total), cost_v2_sar, display_cost_sar, display_cost_source --
computed via the real _resolve_display_cost() under whichever --display-source the
caller picks, so a before/after run with --display-source v1 reproduces today's
exact numbers and --display-source v2 (the default) shows what ships.

Usage:
  python tests/cost_v2_parity_harness.py --photos-dir <path> --mode override
  python tests/cost_v2_parity_harness.py --photos-dir <path> --mode production
  python tests/cost_v2_parity_harness.py --photos-dir <path> --display-source v1
"""
from __future__ import annotations

import argparse
import csv
import os
import re
import sys
from pathlib import Path

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

import cv2  # noqa: E402

from services.damage_detection import model as damage_model  # noqa: E402
from services.part_segmentation_service import segment_parts  # noqa: E402
from services.part_association_service import associate  # noqa: E402
from services.damage_mask_service import segment_damages  # noqa: E402
from services.severity_service import classify_severity  # noqa: E402
from services.severity_fusion_mask import fused_image_severity  # noqa: E402
import services.cost_estimation_services as ces  # noqa: E402
from services.cost_estimation_services import (  # noqa: E402
    build_line_items, _safe_cost_v2_shadow, _resolve_display_cost,
)

SEVERITY_OVERRIDE = {
    "IMG-01": "moderate", "IMG-02": "moderate", "IMG-03": "severe", "IMG-04": "minor",
    "IMG-05": "moderate", "IMG-06": "moderate", "IMG-07": "moderate", "IMG-08": "severe",
    "IMG-09": "moderate", "IMG-10": "severe", "IMG-11": "severe", "IMG-12": "moderate",
    "IMG-14": "moderate", "IMG-15": "severe", "IMG-16": "severe", "IMG-17": "severe",
    "IMG-18": "severe", "IMG-19": "severe", "IMG-20": "moderate", "IMG-21": "moderate",
    "IMG-22": "severe", "IMG-23": "severe", "IMG-24": "moderate", "IMG-25": "severe",
    "IMG-26": "severe", "IMG-27": "severe", "IMG-28": "severe", "IMG-29": "severe",
    "IMG-30": "moderate", "IMG-31": "moderate", "IMG-32": "moderate",
}


def _extract_num(s):
    m = re.search(r"(\d+)", str(s))
    return int(m.group(1)) if m else None


def _detect_damages(image_path):
    """Mirrors damage_detection.py's YOLO call + detection-dict shape exactly
    (process_damage_detection(), lines ~104-144), minus the Firestore writes."""
    results = damage_model(image_path)
    damages = []
    for r in results:
        for box in r.boxes:
            cls_id = int(box.cls[0])
            x1, y1, x2, y2 = box.xyxy[0].tolist()
            damages.append({
                "label": damage_model.names[cls_id],
                "bbox": (int(x1), int(y1), int(x2), int(y2)),
                "confidence": round(float(box.conf[0]), 2),
            })
    return damages


def _production_severity(image_path, parts, H, W):
    """Mirrors cost_estimation_services.py's _stage_image(), lines ~712-744 exactly
    (duplicated here since that logic is inline inside a Firebase-coupled function --
    see this harness's module docstring)."""
    severity_result = classify_severity(image_path)
    raw_sev = severity_result["severity"]
    p_ge_moderate = severity_result["ordinalProbabilities"]["greaterThanMinor"]
    p_ge_severe = severity_result["ordinalProbabilities"]["greaterThanModerate"]

    seg_damages = segment_damages(image_path)
    seg_lines = associate(seg_damages, parts, (H, W)) if seg_damages else []

    best_by_seg_damage = {}
    for ln in seg_lines:
        if ln.part_mask_area is None:
            continue
        current = best_by_seg_damage.get(ln.damage_index)
        if current is None or ln.ioa > current.ioa:
            best_by_seg_damage[ln.damage_index] = ln

    fusion_damages = [
        (int(seg_damages[ln.damage_index]["mask"].sum()), ln.part_mask_area)
        for ln in best_by_seg_damage.values()
    ]
    return fused_image_severity(p_ge_moderate, p_ge_severe, fusion_damages), raw_sev


def run(photos_dir, mode, output_csv, display_source="v2"):
    ces.COST_DISPLAY_SOURCE = display_source
    available_files = [
        p for p in Path(photos_dir).iterdir()
        if p.is_file() and p.suffix.lower() in (".jpg", ".jpeg", ".png")
    ]
    by_num = {}
    for p in available_files:
        n = _extract_num(p.stem)
        if n is not None:
            by_num.setdefault(n, []).append(p)

    rows = []
    for n in sorted(set(k for k in range(1, 33) if k != 13)):
        image_id = f"IMG-{n:02d}"
        if n not in by_num:
            print(f"⚠️  {image_id} not found under {photos_dir} -- skipping")
            continue
        image_path = str(by_num[n][0])
        image = cv2.imread(image_path)
        if image is None:
            print(f"⚠️  {image_id}: unreadable image -- skipping")
            continue
        H, W = image.shape[:2]

        damages = _detect_damages(image_path)
        parts = segment_parts(image_path)
        lines = associate(damages, parts, (H, W))

        if mode == "override":
            sev = SEVERITY_OVERRIDE.get(image_id)
            raw_sev = sev
        else:
            sev, raw_sev = _production_severity(image_path, parts, H, W)

        built = build_line_items(lines, factor=1.0, severity=sev, damages=damages)
        items = built["items"]
        v1_total = built["cost_sar"]

        v2_fields = _safe_cost_v2_shadow([(image_id, items)], image_id)
        display_fields = _resolve_display_cost(v1_total, v2_fields)

        lines_str = ";".join(
            f"{l['panel_id'].split(':', 1)[1]}|{l['damage']}|{l['hours']}"
            for l in v2_fields.get("costV2Lines", [])
        )
        rows.append({
            "image_id": image_id, "mode": mode, "severity_used": sev, "raw_severity": raw_sev,
            "n_damages": len(damages), "lines": lines_str,
            "hours": v2_fields.get("costV2Hours"), "cost_sar": v2_fields.get("costV2Sar"),
            "warnings": ";".join(v2_fields.get("costV2Warnings", [])),
            "estimated_cost_sar_v1": v1_total,
            "display_source_config": display_source,
            "display_cost_sar": display_fields.get("displayCostSar"),
            "display_cost_source": display_fields.get("displayCostSource"),
        })
        print(
            f"{image_id}: v1={v1_total}  costV2Sar={v2_fields.get('costV2Sar')}  "
            f"display={display_fields.get('displayCostSar')}"
            f"({display_fields.get('displayCostSource')})  lines={lines_str}"
        )

    os.makedirs(os.path.dirname(output_csv), exist_ok=True) if os.path.dirname(output_csv) else None
    with open(output_csv, "w", newline="", encoding="utf-8") as f:
        fieldnames = [
            "image_id", "mode", "severity_used", "raw_severity", "n_damages", "lines",
            "hours", "cost_sar", "warnings", "estimated_cost_sar_v1",
            "display_source_config", "display_cost_sar", "display_cost_source",
        ]
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows)
    print(f"\n{len(rows)} image(s) processed. Saved: {output_csv}")
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("Usage:")[0])
    parser.add_argument("--photos-dir", required=True)
    parser.add_argument("--mode", choices=["override", "production"], default="override")
    parser.add_argument("--display-source", choices=["v1", "v2"], default="v2")
    parser.add_argument("--output", default=None)
    args = parser.parse_args()
    output_csv = args.output or os.path.join(
        BACKEND_DIR, "services", "test",
        f"cost_v2_parity_{args.mode}_{args.display_source}.csv",
    )
    run(args.photos_dir, args.mode, output_csv, display_source=args.display_source)


if __name__ == "__main__":
    main()
