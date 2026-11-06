"""
backend_api/tests/test_cost_display_switch.py — unit tests for the cost rule v2
DISPLAY SWITCH (integration step 1-2, part 2; see
services/cost_v2/spec/DECISION_cost_rule_v2.md §7-8). Covers:

  - _resolve_display_cost: both COST_DISPLAY_SOURCE values, and the v2-unavailable
    fallback-to-v1 path.
  - _recompute_display_cost_for_case: the shared helper admin-edit paths use to
    recompute v2 + display from fresh Firestore state, including the v2-exception
    fallback and old-case (no costItems) behaviour.
  - _recalculate_admin_totals: confirms the display fields it writes follow the
    switch, while estimatedCostSar/calibratedEstimatedCostSar keep being written
    exactly as before (storage is unconditional; only DISPLAY follows the switch).

No Firestore, no network, no model calls -- Firestore is faked with the minimal
shape these functions actually read/write (collection/stream/to_dict/update), same
spirit as test_cost_v2_shadow.py's pure-function style.
"""
import os
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
BACKEND_DIR = os.path.dirname(TESTS_DIR)
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

import services.cost_estimation_services as ces  # noqa: E402


def _item(**kwargs):
    base = {"damageType": None, "part": None, "source": "seg_ioa", "severity": None}
    base.update(kwargs)
    return base


# ---- Fakes: just enough Firestore shape for the functions under test -------

class _FakeItemDoc:
    def __init__(self, data):
        self._data = data

    def to_dict(self):
        return self._data


class _FakeCostItemsCollection:
    def __init__(self, items):
        self._items = items

    def stream(self):
        return iter(_FakeItemDoc(i) for i in self._items)


class _FakeImageRef:
    """Doubles as both the image DocumentReference and (via to_dict) the data
    a later .to_dict() read sees -- so an update() made by one function is
    visible to the next function that reads this same ref."""

    def __init__(self, image_id, items, data=None):
        self.id = image_id
        self._items = items
        self._data = dict(data or {})
        self.updates = []

    def collection(self, name):
        assert name == "costItems"
        return _FakeCostItemsCollection(self._items)

    def update(self, fields):
        self.updates.append(fields)
        self._data.update(fields)

    def to_dict(self):
        return self._data


class _FakeImageDoc:
    def __init__(self, image_ref):
        self.id = image_ref.id
        self.reference = image_ref

    def to_dict(self):
        return self.reference.to_dict()


class _FakeImagesCollection:
    def __init__(self, image_refs):
        self._image_refs = image_refs

    def stream(self):
        return iter(_FakeImageDoc(ref) for ref in self._image_refs)


class _FakeCaseRef:
    def __init__(self, case_id, image_refs):
        self.id = case_id
        self._image_refs = image_refs
        self.updates = []

    def collection(self, name):
        assert name == "images"
        return _FakeImagesCollection(self._image_refs)

    def update(self, fields):
        self.updates.append(fields)


# ---- _resolve_display_cost ---------------------------------------------------

def test_resolve_display_cost_v2_active_and_available(monkeypatch):
    monkeypatch.setattr(ces, "COST_DISPLAY_SOURCE", "v2")
    fields = ces._resolve_display_cost(100.0, {"costV2Sar": 123.45})
    assert fields == {"displayCostSar": 123.45, "displayCostSource": "v2"}


def test_resolve_display_cost_v2_active_but_unavailable_falls_back_to_v1(monkeypatch):
    """Old case (no costV2 fields yet) or a v2 exception this turn -- both look
    identical to this function: v2_fields has no costV2Sar."""
    monkeypatch.setattr(ces, "COST_DISPLAY_SOURCE", "v2")
    fields = ces._resolve_display_cost(100.0, {})
    assert fields["displayCostSar"] == 100.0
    assert fields["displayCostSource"] == "v1"
    assert fields["displayCostFallbackReason"] == [
        "cost_v2_unavailable_display_fallback_to_v1"
    ]


def test_resolve_display_cost_v1_active_ignores_v2_data_entirely(monkeypatch):
    """COST_DISPLAY_SOURCE='v1' restores today's behaviour exactly -- even a
    perfectly valid v2 result must not be shown, and this is NOT a fallback (it's
    the configured default), so no fallback-reason key is added."""
    monkeypatch.setattr(ces, "COST_DISPLAY_SOURCE", "v1")
    fields = ces._resolve_display_cost(100.0, {"costV2Sar": 123.45})
    assert fields == {"displayCostSar": 100.0, "displayCostSource": "v1"}
    assert "displayCostFallbackReason" not in fields


def test_cost_display_source_module_default_is_a_valid_value():
    """Whatever the process environment set it to, the sanitized module constant
    is always one of the two real values -- never an unrecognized string."""
    assert ces.COST_DISPLAY_SOURCE in ("v1", "v2")


# ---- _recompute_display_cost_for_case ----------------------------------------

def test_recompute_display_cost_for_case_v2_success(monkeypatch):
    monkeypatch.setattr(ces, "COST_DISPLAY_SOURCE", "v2")
    image1 = _FakeImageRef(
        "img1", [_item(damageType="dent", part="fender", severity="moderate")]
    )
    image_doc = _FakeImageDoc(image1)
    case_ref = _FakeCaseRef("case1", [image1])
    # _recompute_display_cost_for_case reads case_ref.collection("images") itself,
    # so image_doc above isn't passed in directly -- it's exercised via case_ref.
    del image_doc

    fields = ces._recompute_display_cost_for_case(case_ref, v1_total=999.0)

    assert fields["displayCostSource"] == "v2"
    assert fields["displayCostSar"] == fields["costV2Sar"]
    assert fields["costV2Sar"] != 999.0  # proves it's really v2's number, not v1's
    assert len(fields["costV2Lines"]) == 1


def test_recompute_display_cost_for_case_excludes_removed_items(monkeypatch):
    monkeypatch.setattr(ces, "COST_DISPLAY_SOURCE", "v2")
    image1 = _FakeImageRef(
        "img1",
        [
            _item(damageType="dent", part="fender", severity="moderate"),
            _item(
                damageType="dent", part="hood", severity="severe",
                removedByAdmin=True,
            ),
        ],
    )
    case_ref = _FakeCaseRef("case1", [image1])

    fields = ces._recompute_display_cost_for_case(case_ref, v1_total=999.0)

    assert len(fields["costV2Lines"]) == 1
    assert fields["costV2Lines"][0]["panel_id"].endswith("fender")


def test_recompute_display_cost_for_case_v2_exception_falls_back_to_v1(monkeypatch):
    """A v2 failure for this case (e.g. a bad detection the engine rejects) must
    fall back to v1's total for THIS case, same contract _safe_cost_v2_shadow
    already guarantees -- this just confirms the recompute wrapper preserves it."""
    monkeypatch.setattr(ces, "COST_DISPLAY_SOURCE", "v2")

    def _boom(*args, **kwargs):
        raise RuntimeError("simulated v2 failure")

    monkeypatch.setattr(ces, "_compute_cost_v2_shadow", _boom)
    image1 = _FakeImageRef(
        "img1", [_item(damageType="dent", part="fender", severity="moderate")]
    )
    case_ref = _FakeCaseRef("case1", [image1])

    fields = ces._recompute_display_cost_for_case(case_ref, v1_total=321.0)

    assert fields == {
        "displayCostSar": 321.0,
        "displayCostSource": "v1",
        "displayCostFallbackReason": ["cost_v2_unavailable_display_fallback_to_v1"],
    }


def test_recompute_display_cost_for_case_no_active_items_is_a_valid_zero(monkeypatch):
    """No images, or every item removedByAdmin, means zero detections go into the
    v2 engine -- that's a legitimate v2 answer of 0 SAR (nothing left to charge
    for), not a v2 failure, so this does NOT fall back to the v1 total. This is
    distinct from an old (pre-v2) case: those simply never get this function
    called with their real costItems in the first place."""
    monkeypatch.setattr(ces, "COST_DISPLAY_SOURCE", "v2")
    case_ref = _FakeCaseRef("case_old", [])

    fields = ces._recompute_display_cost_for_case(case_ref, v1_total=50.0)

    assert fields["displayCostSource"] == "v2"
    assert fields["displayCostSar"] == 0.0
    assert fields["costV2Lines"] == []


def test_recompute_display_cost_for_case_v1_mode_ignores_valid_v2(monkeypatch):
    monkeypatch.setattr(ces, "COST_DISPLAY_SOURCE", "v1")
    image1 = _FakeImageRef(
        "img1", [_item(damageType="dent", part="fender", severity="moderate")]
    )
    case_ref = _FakeCaseRef("case1", [image1])

    fields = ces._recompute_display_cost_for_case(case_ref, v1_total=999.0)

    assert fields["displayCostSar"] == 999.0
    assert fields["displayCostSource"] == "v1"
    # v2_fields are still computed and returned (so costV2* stay fresh in storage
    # for whenever the switch flips back) -- only the DISPLAY ignores them.
    assert fields["costV2Sar"] is not None
    assert fields["costV2Sar"] != 999.0


# ---- _recalculate_admin_totals: display follows the switch, storage doesn't --

def test_recalculate_admin_totals_v2_mode(monkeypatch):
    monkeypatch.setattr(ces, "COST_DISPLAY_SOURCE", "v2")
    monkeypatch.setattr(ces, "calibrate_total", lambda x: x)

    image1 = _FakeImageRef(
        "img1",
        [_item(damageType="dent", part="fender", severity="moderate", lineCostSar=350.0)],
    )
    case_ref = _FakeCaseRef("case1", [image1])

    result = ces._recalculate_admin_totals(case_ref, image1)

    assert result["caseTotalSar"] == 350.0
    assert result["displayCostSource"] == "v2"
    assert result["displayCostSar"] != 350.0  # v2's own number, not the v1 sum

    final_update = case_ref.updates[-1]
    # Storage keeps writing the v1 numbers exactly as before the display switch
    # existed -- only displayCostSar/displayCostSource are new.
    assert final_update["estimatedCostSar"] == 350.0
    assert "calibratedEstimatedCostSar" in final_update
    assert final_update["displayCostSource"] == "v2"


def test_recalculate_admin_totals_v1_mode(monkeypatch):
    monkeypatch.setattr(ces, "COST_DISPLAY_SOURCE", "v1")
    monkeypatch.setattr(ces, "calibrate_total", lambda x: x)

    image1 = _FakeImageRef(
        "img1",
        [_item(damageType="dent", part="fender", severity="moderate", lineCostSar=500.0)],
    )
    case_ref = _FakeCaseRef("case1", [image1])

    result = ces._recalculate_admin_totals(case_ref, image1)

    assert result["caseTotalSar"] == 500.0
    assert result["displayCostSource"] == "v1"
    assert result["displayCostSar"] == 500.0

    final_update = case_ref.updates[-1]
    assert final_update["estimatedCostSar"] == 500.0
    assert final_update["displayCostSar"] == 500.0
    assert final_update["displayCostSource"] == "v1"
