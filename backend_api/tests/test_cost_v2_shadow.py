"""
backend_api/tests/test_cost_v2_shadow.py — unit tests for the cost rule v2 shadow hook
in services/cost_estimation_services.py (integration step 1-2; see
services/cost_v2/spec/DECISION_cost_rule_v2.md). Pure-function tests against
_v2_detection_from_item / _compute_cost_v2_shadow / _safe_cost_v2_shadow -- no Firestore,
no network, no model calls (the shadow hook itself only transforms already-computed
costItem dicts; it never does I/O on its own).
"""
import os
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
BACKEND_DIR = os.path.dirname(TESTS_DIR)
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

import pytest  # noqa: E402

from services.cost_estimation_services import (  # noqa: E402
    _v2_detection_from_item, _compute_cost_v2_shadow, _safe_cost_v2_shadow,
)


def _item(**kwargs):
    base = {"damageType": None, "part": None, "source": "seg_ioa", "severity": None}
    base.update(kwargs)
    return base


# ---- _v2_detection_from_item ----

def test_panel_item_keeps_real_part_label():
    item = _item(damageType="dent", part="fender", source="seg_ioa", severity="moderate")
    raw, hours_override = _v2_detection_from_item(item, "case1", "img1")
    assert raw == {
        "case_id": "case1", "image_id": "img1", "part_label": "fender",
        "damage_class": "dent", "severity": "moderate",
    }
    assert hours_override is None


def test_lamp_damage_class_source_drops_part_identity():
    """part='lamp' from the damage_class source is a generic category, not a real
    segmented part -- must become part_label=None so run_offline's own fallback applies
    instead of wrongly collapsing every lamp in the case into one shared panel_id."""
    item = _item(damageType="lamp", part="lamp", source="damage_class", severity="severe")
    raw, _ = _v2_detection_from_item(item, "case1", "img1")
    assert raw["part_label"] is None


def test_tire_damage_class_source_drops_part_identity():
    item = _item(damageType="tire", part="wheel", source="damage_class", severity="minor")
    raw, _ = _v2_detection_from_item(item, "case1", "img1")
    assert raw["part_label"] is None


def test_door_glass_bucket_identity_is_window_not_door():
    """part_association_service.py's window bucket emits the BILLING key 'door_glass'
    (legacy labor_hours_lookup.py name), but the REAL part is a window -- identity/
    display must say 'window', never 'door' (2026-11-07 bug fix)."""
    item = _item(damageType="glass", part="door_glass", source="seg_ioa", severity="moderate")
    raw, hours_override = _v2_detection_from_item(item, "case1", "img1")
    assert raw["part_label"] == "window"
    assert hours_override == "door"  # hours still route to the door's glass cell


def test_windshield_and_trunk_glass_need_no_override():
    for part in ("windshield", "trunk"):
        item = _item(damageType="glass", part=part, source="seg_ioa", severity="moderate")
        raw, hours_override = _v2_detection_from_item(item, "case1", "img1")
        assert raw["part_label"] == part
        assert hours_override is None


def test_glass_ambiguous_identity_left_as_is():
    """Genuinely unrecoverable from the stored CostLine -- not fabricated as a specific
    bucket. See the module-level comment next to _V1_GLASS_IDENTITY_LABEL."""
    item = _item(damageType="glass", part="glass_ambiguous",
                 source="glass_part_ambiguous_fallback", severity="moderate")
    raw, hours_override = _v2_detection_from_item(item, "case1", "img1")
    assert raw["part_label"] == "glass_ambiguous"
    assert hours_override is None


def test_unassigned_item_has_no_part_label():
    item = _item(damageType="dent", part=None, source="unassigned", severity="moderate")
    raw, _ = _v2_detection_from_item(item, "case1", "img1")
    assert raw["part_label"] is None


# ---- _compute_cost_v2_shadow ----

def test_compute_cost_v2_shadow_basic_case():
    items_img1 = [
        _item(damageType="dent", part="fender", source="seg_ioa", severity="moderate"),
        _item(damageType="glass", part="windshield", source="seg_ioa", severity="moderate"),
    ]
    result = _compute_cost_v2_shadow([("img1", items_img1)], "case1")
    assert result["costV2Sar"] > 0
    assert result["costV2Config"]["part_model"] == "exp04"
    assert result["costV2Config"]["table"] == "A_100"
    assert result["costV2Config"]["aggregation"] == "one_panel"
    assert result["costV2Config"]["severity_source"] == "image_level"
    assert len(result["costV2Lines"]) == 2
    assert result["costV2Warnings"] == []


def test_compute_cost_v2_shadow_same_panel_across_two_images_charged_once():
    """D5: the same physical panel seen in two images of one case is one v2 line."""
    items_img1 = [_item(damageType="dent", part="back_bumper", source="seg_ioa", severity="moderate")]
    items_img2 = [_item(damageType="dent", part="back_bumper", source="seg_ioa", severity="moderate")]
    result = _compute_cost_v2_shadow([("img1", items_img1), ("img2", items_img2)], "case1")
    assert len(result["costV2Lines"]) == 1


def test_compute_cost_v2_shadow_unmappable_item_becomes_a_warning_not_a_crash():
    """A dent on a part with no v2 table row at all (e.g. 'mirror' -- not in
    PART_TO_TABLE_KEY) must be skipped with a warning, not raise out of
    _compute_cost_v2_shadow. (Wheel dent/scratch/crack DOES have a row as of
    2026-11-07 -- see test_wheel_dent_* in cost_v2/tests/test_run_offline.py.)"""
    items_img1 = [_item(damageType="dent", part="mirror", source="seg_ioa", severity="moderate")]
    result = _compute_cost_v2_shadow([("img1", items_img1)], "case1")
    assert result["costV2Lines"] == []
    assert len(result["costV2Warnings"]) == 1
    assert "unassigned" in result["costV2Warnings"][0]


def test_compute_cost_v2_shadow_no_severity_signal_reported():
    items_img1 = [_item(damageType="dent", part="fender", source="seg_ioa", severity=None)]
    result = _compute_cost_v2_shadow([("img1", items_img1)], "case1")
    assert result["costV2Config"]["severity_source"] == "none"


# ---- _safe_cost_v2_shadow: the shadow-mode contract ----

def test_safe_cost_v2_shadow_returns_fields_on_success():
    items_img1 = [_item(damageType="dent", part="fender", source="seg_ioa", severity="moderate")]
    fields = _safe_cost_v2_shadow([("img1", items_img1)], "case1")
    assert "costV2Sar" in fields and fields["costV2Sar"] > 0


def test_safe_cost_v2_shadow_never_raises(monkeypatch):
    import services.cost_estimation_services as ces

    def _boom(*args, **kwargs):
        raise RuntimeError("simulated v2 failure")

    monkeypatch.setattr(ces, "_compute_cost_v2_shadow", _boom)
    fields = ces._safe_cost_v2_shadow([("img1", [])], "case1")
    assert fields == {}  # swallowed -- never propagates to the caller


def test_shadow_fields_never_collide_with_existing_case_update_keys():
    """Structural guard: the v1 fields process_cost_estimation's case_update already
    writes must never be overwritten by a v2 field name."""
    existing_case_update_keys = {
        "status", "costState", "estimatedCostSar", "calibratedEstimatedCostSar",
        "costFactors", "needsAdminReview", "adminReviewReasonsAr", "reviewReasons",
        "costEstimateComplete",
    }
    items_img1 = [_item(damageType="dent", part="fender", source="seg_ioa", severity="moderate")]
    v2_fields = _safe_cost_v2_shadow([("img1", items_img1)], "case1")
    assert existing_case_update_keys.isdisjoint(v2_fields.keys())
