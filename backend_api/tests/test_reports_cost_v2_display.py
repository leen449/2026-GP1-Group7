"""
backend_api/tests/test_reports_cost_v2_display.py — unit tests for routes/reports.py's
cost rule v2 DISPLAY SWITCH branch (integration step 1-2, part 2; see
services/cost_v2/spec/DECISION_cost_rule_v2.md §7-8):

  - _part_from_panel_id
  - _read_damage_items_from_v2
  - _build_report_input: the use_v2 branch (displayCostSource == "v2") vs. the
    unchanged v1 branch for old cases (no displayCostSource at all).

Same minimal-Firestore-fixture style as test_targeted_repairs.py.
"""
from copy import deepcopy

import pytest

from routes import reports


class _Snapshot:
    def __init__(self, data=None, doc_id="doc", exists=True, reference=None):
        self._data = data or {}
        self.id = doc_id
        self.exists = exists
        self.reference = reference

    def to_dict(self):
        return deepcopy(self._data)


# ---- _part_from_panel_id -----------------------------------------------------

def test_part_from_panel_id_normal_identity():
    assert reports._part_from_panel_id("case1:fender") == "fender"


def test_part_from_panel_id_per_image_fallback_identity():
    """"{case_id}:{table_key}:{image_id}" -- the part/hours-key name is still the
    SECOND segment, the trailing image_id is irrelevant here."""
    assert reports._part_from_panel_id("case1:door:img7") == "door"


def test_part_from_panel_id_missing_or_malformed():
    assert reports._part_from_panel_id(None) == ""
    assert reports._part_from_panel_id("") == ""
    assert reports._part_from_panel_id("no_colon_at_all") == "no_colon_at_all"


# ---- _read_damage_items_from_v2 ----------------------------------------------

def test_read_damage_items_from_v2_builds_damages():
    case_data = {
        "costV2Lines": [
            {
                "panel_id": "case1:fender", "table_key": "front_fender",
                "damage": "dent", "severity": "moderate", "line_sar": 500.0,
            },
            {
                "panel_id": "case1:door:img2", "table_key": "door",
                "damage": "glass", "severity": "severe", "line_sar": 412.5,
            },
        ],
    }
    damages = reports._read_damage_items_from_v2(case_data)
    assert len(damages) == 2
    assert damages[0].type == "dent"
    assert damages[0].part == "fender"
    assert damages[0].severity == "moderate"
    assert damages[0].cost_sar == 500.0
    assert damages[1].part == "door"  # per-image fallback identity, 2nd segment


def test_read_damage_items_from_v2_skips_unpriced_lines():
    case_data = {
        "costV2Lines": [
            {"panel_id": "case1:fender", "damage": "dent", "severity": "moderate",
             "line_sar": None},
            {"panel_id": "case1:hood", "damage": "scratch", "severity": "minor",
             "line_sar": 100.0},
        ],
    }
    damages = reports._read_damage_items_from_v2(case_data)
    assert len(damages) == 1
    assert damages[0].part == "hood"


def test_read_damage_items_from_v2_no_priced_lines_raises_422():
    with pytest.raises(reports.HTTPException) as exc:
        reports._read_damage_items_from_v2({"costV2Lines": []})
    assert exc.value.status_code == 422


# ---- _build_report_input: use_v2 branch vs. the unchanged v1 branch --------

_USER_DATA = {"name": "Sara", "nationalID": "1000000000", "phoneNumber": "0500000000"}
_VEHICLE_DATA = {
    "make": "Toyota", "model": "Camry", "color": "White", "year": 2020,
    "chassisNumber": "ABC123",
}


class _NoImagesRef:
    """A case_reference that errors if .collection() is ever called -- used to
    prove the v2 path's cost-snapshot gate short-circuits on costRevision=None
    without touching Firestore, exactly like the v1 path already does."""

    def collection(self, name):
        raise AssertionError(
            "case_reference.collection() should not be called for a legacy "
            "(costRevision=None) case snapshot check"
        )


def test_build_report_input_uses_v2_lines_when_display_source_is_v2():
    case_data = {
        "najimReport": {"accidentNumber": "NAJM-1"},
        "displayCostSource": "v2",
        "displayCostSar": 500.0,
        "costV2Lines": [
            {"panel_id": "case1:fender", "damage": "dent", "severity": "moderate",
             "line_sar": 500.0},
        ],
        "costV2Config": {"rule_version": "v2.0", "table": "A_100", "rate": 100},
        "overallSeverity": "moderate",
    }

    result = reports._build_report_input(
        case_reference=_NoImagesRef(),
        case_data=case_data,
        user_data=_USER_DATA,
        vehicle_data=_VEHICLE_DATA,
    )

    assert result.cost_source == "v2"
    assert result.total_cost_sar_override == 500.0
    assert result.cost_rule_version == "v2.0"
    assert result.cost_table == "A_100"
    assert result.cost_rate_sar == 100
    assert len(result.damages) == 1
    assert result.damages[0].part == "fender"


def test_build_report_input_old_case_without_display_cost_source_uses_v1_path():
    """An old case has no displayCostSource field at all -- use_v2 must be False,
    so this still goes through the original v1 costItems path, completely
    unaffected by cost rule v2 ever having been added."""
    image_doc = _Snapshot({"hasDamage": True}, "img1")
    image_doc.reference = image_doc

    cost_item = _Snapshot(
        {"part": "fender", "damageType": "dent", "severity": "moderate",
         "lineCostSar": 500.0},
        "item1",
    )

    class _Images:
        def stream(self):
            image_doc.reference.collection = lambda name: _Items()
            return [image_doc]

    class _Items:
        def stream(self):
            return [cost_item]

    class _Ref:
        def collection(self, name):
            assert name == "images"
            return _Images()

    case_data = {
        "najimReport": {"accidentNumber": "NAJM-2"},
        "estimatedCostSar": 500.0,
        "overallSeverity": "moderate",
        # no costRevision -> _assert_current_cost_snapshot short-circuits,
        # no displayCostSource -> use_v2 is False
    }

    result = reports._build_report_input(
        case_reference=_Ref(),
        case_data=case_data,
        user_data=_USER_DATA,
        vehicle_data=_VEHICLE_DATA,
    )

    assert result.cost_source == "v1"  # ReportInput's own default, untouched
    assert result.total_cost_sar_override is None
    assert len(result.damages) == 1
    assert result.damages[0].part == "fender"
    assert result.damages[0].cost_sar == 500.0
