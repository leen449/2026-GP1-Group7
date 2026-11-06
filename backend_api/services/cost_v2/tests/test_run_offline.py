"""
backend_api/services/cost_v2/tests/test_run_offline.py — unit tests for the panel-identity
fix in run_offline.py (identity from the raw part_label, hours from table_key -- these must
no longer be conflated). Does not touch engine.py/tables.py/test_golden.py -- the 555
golden assertions are unaffected by this file.

Run: pytest backend_api/services/cost_v2/tests/test_run_offline.py -v
"""
import os
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
COST_V2_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, COST_V2_DIR)

import pytest  # noqa: E402

import run_offline  # noqa: E402
from engine import estimate  # noqa: E402
from run_offline import map_detection, load_detections_by_case, MappingError  # noqa: E402


def _price(detections, table="A_100", aggregation="one_panel"):
    mapped = [map_detection(d)[0] for d in detections]
    return estimate(mapped, table=table, aggregation=aggregation)


def test_front_door_and_back_door_both_charged():
    """Two different doors, same hours row ('door'), must stay two separate panels."""
    result = _price([
        {"case_id": "C1", "image_id": "i1", "part_label": "front_door", "damage_class": "Dent"},
        {"case_id": "C1", "image_id": "i1", "part_label": "back_door", "damage_class": "Dent"},
    ])
    assert len(result["lines"]) == 2
    assert result["cost_sar"] == pytest.approx(1400.0, abs=0.01)  # 2 x (7h x 100)
    panel_ids = {l["panel_id"] for l in result["lines"]}
    assert panel_ids == {"C1:front_door", "C1:back_door"}


def test_headlight_and_taillight_both_charged():
    """Two broken lamps with distinct overlapping parts must stay two separate panels,
    even though both are forced onto the generic 'lamp' hours row."""
    result = _price([
        {"case_id": "C2", "image_id": "i1", "part_label": "headlight", "damage_class": "Lamp broken"},
        {"case_id": "C2", "image_id": "i1", "part_label": "taillight", "damage_class": "Lamp broken"},
    ])
    assert len(result["lines"]) == 2
    assert result["cost_sar"] == pytest.approx(200.0, abs=0.01)  # 2 x (1h x 100)
    assert {l["table_key"] for l in result["lines"]} == {"lamp"}
    panel_ids = {l["panel_id"] for l in result["lines"]}
    assert panel_ids == {"C2:headlight", "C2:taillight"}


def test_same_bumper_in_two_images_charged_once():
    result = _price([
        {"case_id": "C3", "image_id": "i1", "part_label": "back_bumper", "damage_class": "dent"},
        {"case_id": "C3", "image_id": "i2", "part_label": "back_bumper", "damage_class": "dent"},
    ])
    assert len(result["lines"]) == 1
    assert result["cost_sar"] == pytest.approx(500.0, abs=0.01)  # 1 x (5h x 100)
    assert result["lines"][0]["panel_id"] == "C3:back_bumper"


def test_windshield_and_back_windshield_both_charged_when_part_label_present():
    """Forward-compat: once the retrain emits side-aware glass labels, identity already
    separates them -- no runner change needed."""
    result = _price([
        {"case_id": "C4", "image_id": "i1", "part_label": "windshield", "damage_class": "Glass shatter"},
        {"case_id": "C4", "image_id": "i1", "part_label": "back_windshield", "damage_class": "Glass shatter"},
    ])
    assert len(result["lines"]) == 2
    panel_ids = {l["panel_id"] for l in result["lines"]}
    assert panel_ids == {"C4:windshield", "C4:back_windshield"}


def test_front_wheel_and_back_wheel_tire_both_charged_when_part_label_present():
    result = _price([
        {"case_id": "C5", "image_id": "i1", "part_label": "front_wheel", "damage_class": "tire_flat"},
        {"case_id": "C5", "image_id": "i1", "part_label": "back_wheel", "damage_class": "tire_flat"},
    ])
    assert len(result["lines"]) == 2
    panel_ids = {l["panel_id"] for l in result["lines"]}
    assert panel_ids == {"C5:front_wheel", "C5:back_wheel"}


def test_lamp_without_overlapping_part_falls_back_per_image_and_warns():
    """No part_label at all on a lamp/glass/tire detection -- conservative per-image
    fallback (may over-count, never silently assumed to be the same physical part)."""
    detections = [
        {"case_id": "C6", "image_id": "i1", "part_label": None, "damage_class": "Lamp broken"},
        {"case_id": "C6", "image_id": "i2", "part_label": None, "damage_class": "Lamp broken"},
    ]
    mapped_0, warning_0 = map_detection(detections[0])
    mapped_1, warning_1 = map_detection(detections[1])
    assert warning_0 is not None and "falling back" in warning_0
    assert warning_1 is not None
    assert mapped_0["panel_id"] == "C6:lamp:i1"
    assert mapped_1["panel_id"] == "C6:lamp:i2"

    result = estimate([mapped_0, mapped_1], table="A_100", aggregation="one_panel")
    assert len(result["lines"]) == 2  # over-counts rather than guessing same part


def test_load_detections_by_case_collects_fallback_warnings(tmp_path):
    import json

    input_path = tmp_path / "detections.json"
    input_path.write_text(json.dumps([
        {"case_id": "C7", "image_id": "i1", "part_label": None, "damage_class": "tire_flat"},
        {"case_id": "C7", "image_id": "i1", "part_label": "door", "damage_class": "dent"},
    ]), encoding="utf-8")

    by_case, warnings = load_detections_by_case(str(input_path))
    assert len(warnings) == 1
    assert "C7" in by_case
    assert len(by_case["C7"]) == 2


def test_panel_damage_still_requires_part_label():
    with pytest.raises(MappingError):
        map_detection({"case_id": "C8", "image_id": "i1", "part_label": None, "damage_class": "dent"})


def test_fender_identity_distinct_from_front_fender_hours_key():
    """Identity must use the raw part_label ('fender'), not the hours key
    ('front_fender') -- this was the original bug this task fixes."""
    mapped, _ = map_detection(
        {"case_id": "C9", "image_id": "i1", "part_label": "fender", "damage_class": "dent"}
    )
    assert mapped["panel_id"] == "C9:fender"
    assert mapped["table_key"] == "front_fender"


def test_wheel_dent_maps_to_wheel_table_key():
    mapped, _ = map_detection(
        {"case_id": "C17", "image_id": "i1", "part_label": "wheel", "damage_class": "dent"}
    )
    assert mapped["panel_id"] == "C17:wheel"
    assert mapped["table_key"] == "wheel"


def test_front_wheel_and_back_wheel_dent_both_charged():
    """Same hours row ('wheel'), but distinct panels -- same pattern as front/back door."""
    result = _price([
        {"case_id": "C18", "image_id": "i1", "part_label": "front_wheel", "damage_class": "dent"},
        {"case_id": "C18", "image_id": "i1", "part_label": "back_wheel", "damage_class": "dent"},
    ], table="O_165")
    assert len(result["lines"]) == 2
    panel_ids = {l["panel_id"] for l in result["lines"]}
    assert panel_ids == {"C18:front_wheel", "C18:back_wheel"}
    assert result["cost_sar"] == pytest.approx(2 * 4.25 * 165, abs=0.01)


def test_tire_flat_stays_forced_to_tire_key_not_wheel():
    """Tyre-flat damage on a wheel part must still price off the generic 'tire' key,
    unaffected by the new wheel dent/scratch/crack row."""
    mapped, _ = map_detection(
        {"case_id": "C19", "image_id": "i1", "part_label": "wheel", "damage_class": "tire_flat"}
    )
    assert mapped["table_key"] == "tire"
    assert mapped["panel_id"] == "C19:wheel"


def test_door_glass_uses_door_glass_cell_not_generic():
    """O_165: door glass=0.8h vs generic glass=2h -- the fix must pick the door row."""
    mapped, _ = map_detection(
        {"case_id": "C10", "image_id": "i1", "part_label": "door", "damage_class": "Glass shatter"}
    )
    assert mapped["table_key"] == "door"
    result = estimate([mapped], table="O_165")
    assert result["cost_sar"] == pytest.approx(0.8 * 165, abs=0.01)


def test_front_door_and_back_door_glass_both_use_door_hours_key():
    for label in ("front_door", "back_door"):
        mapped, _ = map_detection(
            {"case_id": "C10b", "image_id": "i1", "part_label": label, "damage_class": "glass"}
        )
        assert mapped["table_key"] == "door"
        assert mapped["panel_id"] == f"C10b:{label}"


def test_trunk_glass_uses_trunk_glass_cell_not_generic():
    """O_165: trunk glass=1h vs generic glass=2h -- the fix must pick the trunk row."""
    mapped, _ = map_detection(
        {"case_id": "C11", "image_id": "i1", "part_label": "trunk", "damage_class": "glass_shatter"}
    )
    assert mapped["table_key"] == "trunk"
    result = estimate([mapped], table="O_165")
    assert result["cost_sar"] == pytest.approx(1.0 * 165, abs=0.01)


def test_windshield_glass_stays_on_generic_glass_key():
    mapped, _ = map_detection(
        {"case_id": "C12", "image_id": "i1", "part_label": "windshield", "damage_class": "glass shatter"}
    )
    assert mapped["table_key"] == "glass"
    assert mapped["panel_id"] == "C12:windshield"


def test_glass_without_overlapping_part_falls_back_to_generic_key_and_per_image_identity():
    mapped, warning = map_detection(
        {"case_id": "C13", "image_id": "i1", "part_label": None, "damage_class": "glass"}
    )
    assert mapped["table_key"] == "glass"
    assert mapped["panel_id"] == "C13:glass:i1"
    assert warning is not None


def test_merge_rear_windshield_switch_default_false_keeps_separate_identity():
    assert run_offline.MERGE_REAR_WINDSHIELD is False
    mapped, _ = map_detection(
        {"case_id": "C14", "image_id": "i1", "part_label": "back_windshield", "damage_class": "glass"}
    )
    assert mapped["panel_id"] == "C14:back_windshield"


def test_merge_rear_windshield_switch_true_merges_identity(monkeypatch):
    monkeypatch.setattr(run_offline, "MERGE_REAR_WINDSHIELD", True)
    mapped, _ = map_detection(
        {"case_id": "C15", "image_id": "i1", "part_label": "back_windshield", "damage_class": "glass"}
    )
    assert mapped["panel_id"] == "C15:windshield"
    assert mapped["table_key"] == "glass"  # hours unaffected -- both were already generic


def test_merge_rear_windshield_switch_true_actually_collapses_duplicate_lines(monkeypatch):
    monkeypatch.setattr(run_offline, "MERGE_REAR_WINDSHIELD", True)
    detections = [
        map_detection({"case_id": "C16", "image_id": "i1", "part_label": "windshield", "damage_class": "glass"})[0],
        map_detection({"case_id": "C16", "image_id": "i2", "part_label": "back_windshield", "damage_class": "glass"})[0],
    ]
    result = estimate(detections, table="A_100")
    assert len(result["lines"]) == 1
