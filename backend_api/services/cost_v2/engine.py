"""
backend_api/services/cost_v2/engine.py — CrashLens cost rule v2 (STANDALONE, OFFLINE).

Pure function: no Firestore, no network, no model calls. Must match
spec/cost_rule_v2_reference.py exactly -- that file is the spec-by-code; this is the
production module (reads tables from tables.py instead of a copy baked into the file).
See spec/DECISION_cost_rule_v2.md, decisions D1-D9.

    cost_sar = round( RATE * sum_over_lines( H(table_key, damage) * F(severity) ), 2 )

aggregation="one_panel" (default): one line per panel_id -- the damage with the highest
  hours on that panel wins (ties keep whichever was seen first).
aggregation="summed": one line per (panel_id, damage) -- duplicates of the same type on
  the same panel still collapse to one line (D4).
Severity factor F is applied to EVERY line, including lamp/glass/tyre (D6). Panel/line
  severity = the highest severity among the detections merged into it. severity=None
  (via severity_default, or absent per-detection) disables the factor (F=1.0) for that
  line -- used for assessor-comparison runs where no severity signal is being tested.

NOT wired into the live pipeline. cost_estimation_services.py, cost_calibration.py, and
Firestore are untouched by this module.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tables import TABLES, SEV_F, SEV_ORDER, VERSION  # noqa: E402

__all__ = ["estimate", "CostV2Error", "VERSION"]


class CostV2Error(ValueError):
    """Unknown table/table_key/damage/aggregation -- raised instead of silently pricing as 0."""


def estimate(detections, table="A_100", aggregation="one_panel", severity_default=None):
    """
    detections: list of dicts, each {panel_id, table_key, damage, severity?}.
      severity, if present, overrides severity_default for that one detection.
    table: "A_100" | "B_130" | "O_165".
    aggregation: "one_panel" | "summed".
    severity_default: fallback severity ("minor"/"moderate"/"severe") for detections
      with no "severity" key; None disables the severity factor for those detections.

    Returns {lines, hours, weighted_hours, cost_sar, table, rate, aggregation}.
    `lines` items: {panel_id, table_key, damage, hours, severity, factor, weighted_hours,
      line_sar}. line_sar is per-line display only -- D1 requires hours*factor to be
      summed across ALL lines first, then multiplied by rate once (see cost_sar below),
      not the sum of line_sar (same total algebraically, but cost_sar is computed the
      spec's way, not derived from the per-line figures).
    """
    if table not in TABLES:
        raise CostV2Error(f"Unknown table: {table!r}")
    if aggregation not in ("one_panel", "summed"):
        raise CostV2Error(f"Unknown aggregation: {aggregation!r}")

    t = TABLES[table]
    hours_table = t["hours"]
    rate = t["rate"]

    groups = {}
    for d in detections:
        table_key, damage = d["table_key"], d["damage"]
        if table_key not in hours_table:
            raise CostV2Error(f"Unknown table_key {table_key!r} for table {table!r}")
        if damage not in hours_table[table_key]:
            raise CostV2Error(
                f"Unknown damage {damage!r} for table_key {table_key!r} in table {table!r}"
            )
        h = hours_table[table_key][damage]
        sev = d.get("severity", severity_default)

        key = d["panel_id"] if aggregation == "one_panel" else (d["panel_id"], damage)
        g = groups.get(key)
        if g is None:
            groups[key] = dict(
                panel_id=d["panel_id"], table_key=table_key, damage=damage,
                hours=h, severity=sev,
            )
        else:
            if h > g["hours"]:  # one_panel: keep the strictly-higher-hour damage (D3)
                g.update(table_key=table_key, damage=damage, hours=h)
            if sev is not None and (g["severity"] is None or SEV_ORDER[sev] > SEV_ORDER[g["severity"]]):
                g["severity"] = sev  # panel severity = max on that panel (D6)

    lines = []
    for g in groups.values():
        f = 1.0 if g["severity"] is None else SEV_F[g["severity"]]
        weighted_hours = g["hours"] * f
        lines.append(dict(
            g, factor=f, weighted_hours=weighted_hours,
            line_sar=round(g["hours"] * f * rate, 2),
        ))

    hours_total = sum(l["hours"] for l in lines)
    weighted_total = sum(l["weighted_hours"] for l in lines)
    return dict(
        lines=lines,
        hours=round(hours_total, 4),
        weighted_hours=round(weighted_total, 4),
        cost_sar=round(rate * weighted_total, 2),
        table=table,
        rate=rate,
        aggregation=aggregation,
    )
