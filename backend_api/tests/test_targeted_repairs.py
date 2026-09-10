import asyncio
from copy import deepcopy

import numpy as np
import pytest

from services import labor_hours_lookup as labor
from services import cost_estimation_services as cost
from services.part_association_service import CostLine, associate
from services import staging_pipeline_api as staging
from routes import reports


class _Snapshot:
    def __init__(self, data=None, doc_id="doc", exists=True, reference=None):
        self._data = data or {}
        self.id = doc_id
        self.exists = exists
        self.reference = reference

    def to_dict(self):
        return deepcopy(self._data)


class _Doc:
    def __init__(self, data=None, doc_id="doc"):
        self.data = data
        self.id = doc_id
        self.reference = self

    def get(self, **_kwargs):
        return _Snapshot(self.data, self.id, self.data is not None, self)


class _Collection:
    def __init__(self, docs=None):
        self.docs = docs or {}

    def document(self, doc_id):
        return self.docs.setdefault(doc_id, _Doc(None, doc_id))


class _Db:
    def __init__(self, collections):
        self.collections = collections

    def collection(self, name):
        return self.collections[name]


def test_labor_lookup_rejects_partial_remote_table(monkeypatch):
    partial = {"front_bumper": deepcopy(labor.LOOKUP["front_bumper"])}
    db = _Db({"config": _Collection({"laborHours": _Doc(partial, "laborHours")})})
    monkeypatch.setattr(labor, "_db", lambda: db)
    labor._cache = None

    loaded = labor.load_lookup(force_refresh=True)

    assert loaded == labor.LOOKUP
    assert loaded is not labor.LOOKUP
    assert loaded["fender"]["hours"]["crack"] == 2.2


def test_labor_lookup_accepts_complete_copy_and_rejects_bad_hours(monkeypatch):
    complete = deepcopy(labor.LOOKUP)
    complete["roof"]["hours"]["dent"] = 4.5
    db = _Db({"config": _Collection({"laborHours": _Doc(complete, "laborHours")})})
    monkeypatch.setattr(labor, "_db", lambda: db)
    labor._cache = None
    assert labor.load_lookup(force_refresh=True)["roof"]["hours"]["dent"] == 4.5

    complete["roof"]["hours"]["dent"] = 0
    db.collection("config").document("laborHours").data = complete
    loaded = labor.load_lookup(force_refresh=True)
    assert loaded == labor.LOOKUP


def test_firestore_lookup_includes_and_overrides_all_wheel_rows(monkeypatch):
    complete = deepcopy(labor.LOOKUP)
    wheel_rows = (
        "front_left_wheel", "front_right_wheel",
        "back_left_wheel", "back_right_wheel",
    )
    assert all("tire" in complete[row]["hours"] for row in wheel_rows)
    for row in wheel_rows:
        complete[row]["hours"]["tire"] = 0.75

    db = _Db({"config": _Collection({"laborHours": _Doc(complete, "laborHours")})})
    monkeypatch.setattr(labor, "_db", lambda: db)
    labor._cache = None

    assert labor.get_hours("wheel", "tire") == 0.75
    labor._cache = None


def _part(label, mask=None, confidence=0.9):
    return {
        "label": label,
        "mask": np.ones((20, 20), dtype=bool) if mask is None else mask,
        "bbox": (0, 0, 20, 20),
        "confidence": confidence,
    }


def _damage(label, bbox=(0, 0, 10, 10)):
    return {"label": label, "bbox": bbox, "confidence": 0.9}


def test_glass_uses_one_segmentation_cost_bucket():
    windshield = associate(
        [_damage("glass shatter")], [_part("windshield")], (20, 20),
    )[0]
    window = associate(
        [_damage("glass shatter")], [_part("window")], (20, 20),
    )[0]
    trunk = associate(
        [_damage("glass shatter")], [_part("trunk")], (20, 20),
    )[0]

    assert (windshield.part, windshield.lookup_key) == ("windshield", "windshield")
    assert (window.part, window.lookup_key) == ("door_glass", "door_glass")
    assert (trunk.part, trunk.lookup_key) == ("trunk", "trunk")


def test_glass_rejects_missing_conflicting_and_generic_door_support():
    missing = associate([_damage("glass shatter")], [], (20, 20))[0]
    door_only = associate(
        [_damage("glass shatter")], [_part("door")], (20, 20),
    )[0]
    conflicting = associate(
        [_damage("glass shatter")], [_part("windshield"), _part("window")], (20, 20),
    )[0]

    assert missing.lookup_key is None
    assert "glass_no_part_support" in missing.flags
    assert door_only.lookup_key is None
    assert "glass_no_part_support" in door_only.flags
    assert conflicting.lookup_key is None
    assert "glass_ambiguous_part" in conflicting.flags


def test_duplicate_glass_masks_in_same_bucket_are_billed_once():
    lines = associate(
        [_damage("glass shatter")],
        [_part("window", confidence=0.7), _part("window", confidence=0.9)],
        (20, 20),
    )
    assert len(lines) == 1
    assert lines[0].lookup_key == "door_glass"
    assert lines[0].part_conf == 0.9


def test_lamp_and_tire_are_location_independent_per_detection():
    damages = [_damage("lamp broken"), _damage("lamp broken"), _damage("tire flat")]
    lines = associate(
        damages, [], (20, 20), najm_zone="front",
        wheel_position_hint="rear",
    )

    assert [(line.damage_type, line.lookup_key) for line in lines] == [
        ("lamp", "lamp"), ("lamp", "lamp"), ("tire", "wheel"),
    ]
    assert all(line.wheel_position is None for line in lines)
    assert all("seg_no_support" not in line.flags for line in lines)


def test_wheel_dent_uses_najm_hint_or_flagged_average_fallback():
    damage = _damage("dent")
    parts = [_part("wheel")]

    front = associate(
        [damage], parts, (20, 20), wheel_position_hint="front",
    )[0]
    rear = associate(
        [damage], parts, (20, 20), wheel_position_hint="rear",
    )[0]
    fallback = associate([damage], parts, (20, 20))[0]

    assert front.wheel_position == "front"
    assert rear.wheel_position == "rear"
    assert fallback.wheel_position is None
    assert "wheel_position_ambiguous_fallback" in fallback.flags

    labor._cache = deepcopy(labor.LOOKUP)
    assert labor.get_hours("wheel", "dent", wheel_position="front") == 4.5
    assert labor.get_hours("wheel", "dent", wheel_position="rear") == 4.0
    assert labor.get_hours("wheel", "dent") == 4.25
    assert labor.get_hours("wheel", "tire") == 0.5
    assert labor.get_hours("wheel", "scratch") == 0.5
    assert labor.get_hours("lamp", "lamp") == 0.5
    assert labor.get_hours("windshield", "glass") == 2.0
    assert labor.get_hours("door_glass", "glass") == 0.8
    labor._cache = None


def test_cost_hours_for_passes_wheel_position(monkeypatch):
    seen = {}

    def fake_get_hours(part, damage_type, *, wheel_position=None):
        seen["args"] = (part, damage_type, wheel_position)
        return 4.5 if wheel_position == "front" else 4.25

    monkeypatch.setattr(cost, "get_hours", fake_get_hours)
    line = CostLine(0, "dent", "wheel", "wheel", "seg_ioa", wheel_position="front")
    built = cost.build_line_items([line])
    assert seen["args"] == ("wheel", "dent", "front")
    assert built["items"][0]["wheelPosition"] == "front"
    assert built["items"][0]["hours"] == 4.5


def test_linked_vehicle_wins_over_conflicting_najm(monkeypatch):
    vehicle = {"vehicle-1": _Doc({
        "make": "Toyota", "model": "Camry", "year": 2019,
        "paintCategory": "pearl",
    }, "vehicle-1")}
    db = _Db({"vehicles": _Collection(vehicle)})
    resolved = cost._resolve_linked_vehicle(db, {"vehicleId": "vehicle-1", "najimReport": {
        "vehicleMake": "Wrong", "vehicleModel": "Wrong", "manuYear": 2001,
    }})
    assert resolved["make"] == "Toyota"
    assert resolved["model"] == "Camry"
    assert resolved["year"] == 2019
    assert resolved["paintCategory"] == "pearl"


def test_missing_severity_never_prices_with_moderate_or_overall(monkeypatch):
    monkeypatch.setattr(cost, "get_hours", lambda *_args, **_kwargs: 2.0)
    line = CostLine(0, "dent", "hood", "hood", "seg_ioa")
    built = cost.build_line_items([line], factor=99, price=False,
                                  extra_flags=["missing_image_severity"])
    assert built["cost_sar"] == 0
    assert built["items"][0]["lineCostSar"] is None
    assert "missing_image_severity" in built["items"][0]["flags"]


def test_reports_do_not_inherit_case_severity():
    assert reports._severity_label(None) == "غير محدد"
    assert reports._severity_label("") == "غير محدد"
    assert reports._severity_label("severe") == "severe"


def test_staging_missing_severity_is_unpriced(monkeypatch):
    line = CostLine(0, "dent", "hood", "hood", "seg_ioa")
    monkeypatch.setattr(staging, "associate", lambda *_args, **_kwargs: [line])
    monkeypatch.setattr(staging, "get_hours", lambda *_args, **_kwargs: 2.0)
    result = staging.build_estimate([{}], [], (20, 20), severity=None)
    assert result["estimated_cost_sar"] == 0.0
    assert result["line_items"][0]["line_cost_sar"] is None
    assert result["needs_admin_review"] is True


def test_current_revision_report_rejects_mismatch():
    class Ref:
        def collection(self, name):
            assert name == "images"
            return self

        def stream(self):
            return []

    with pytest.raises(reports.HTTPException) as exc:
        reports._assert_current_cost_snapshot(
            Ref(),
            {
                "costRevision": 3,
                "costState": "complete",
                "costEstimateComplete": True,
                "estimatedCostSar": 10,
            },
        )
    assert exc.value.status_code == 422


def test_prior_history_accepts_reviewed_priced_case(monkeypatch):
    class Items:
        def stream(self):
            return [_Snapshot({"part": "hood", "damageType": "dent", "lineCostSar": 100,
                               "costRevision": 2}, "item")]

    class Images:
        def stream(self):
            image = _Snapshot({}, "image")
            image.reference = image
            image.reference.collection = lambda name: Items()
            return [image]

    class PriorRef:
        def collection(self, name):
            return Images()

    prior = _Snapshot({
        "vehicleId": "v", "ownerId": "o", "status": "تمت المراجعة",
        "createdAt": 1, "costRevision": 2,
        "najimReport": {"damageLocation": "المقدمة"},
    }, "prior", reference=PriorRef())

    class Cases:
        def where(self, *_args):
            return self

        def stream(self):
            return [prior]

    class Vehicles:
        def document(self, _id):
            return _Doc({"isArchived": False})

    db = _Db({"accidentCase": Cases(), "vehicles": Vehicles()})
    matched, note = cost._find_prior_accident(
        db, "current", "v", "o",
        [{"part": "hood", "damageType": "dent", "lineCostSar": 100}],
        current_created_at=3,
    )
    assert matched is True
    assert "prior case" in note


def test_history_canonicalizes_legacy_visual_parts_without_najm():
    assert cost._canonical_history_pair({
        "part": "front_glass", "damageType": "glass",
    }) == ("windshield", "glass")
    assert cost._canonical_history_pair({
        "part": "window", "damageType": "glass",
    }) == ("door_glass", "glass")
    assert cost._canonical_history_pair({
        "part": "front_left_light", "damageType": "lamp",
    }) == ("lamp", "lamp")
    assert cost._canonical_history_pair({
        "lookupKey": "back_right_wheel", "damageType": "dent",
    }) == ("wheel", "dent")


def test_wheel_najm_parser_rejects_missing_or_contradictory_text():
    assert cost._wheel_position_from_najm("المقدمة") == "front"
    assert cost._wheel_position_from_najm("المؤخرة") == "rear"
    assert cost._wheel_position_from_najm("المقدمة والمؤخرة") is None
    assert cost._wheel_position_from_najm("") is None


class _AtomicRef:
    def __init__(self, data=None, doc_id="doc"):
        self.data = data if data is not None else {}
        self.id = doc_id
        self.reference = self
        self.children = {}

    def get(self, **_kwargs):
        return _Snapshot(self.data, self.id, True, self)

    def update(self, values):
        self.data.update(values)

    def collection(self, name):
        return self.children.setdefault(name, _AtomicCollection())


class _AtomicCollection:
    def __init__(self):
        self.docs = {}
        self.counter = 0

    def stream(self, **_kwargs):
        return list(self.docs.values())

    def document(self, doc_id=None):
        if doc_id is None:
            self.counter += 1
            doc_id = f"generated-{self.counter}"
        if doc_id not in self.docs:
            self.docs[doc_id] = _AtomicRef({}, doc_id)
        return self.docs[doc_id]


class _AtomicTxn:
    def update(self, ref, values):
        ref.update(values)

    def set(self, ref, values):
        ref.data = dict(values)

    def delete(self, ref):
        for collection in _all_collections:
            collection.docs.pop(ref.id, None)


class _AtomicDb:
    def __init__(self, case_ref):
        self.case_ref = case_ref

    def transaction(self):
        return _AtomicTxn()


_all_collections = []


def test_atomic_finalize_replaces_old_items_and_stamps_one_revision(monkeypatch):
    case_ref = _AtomicRef({"costRevision": 4, "costRunId": "run-1"}, "case")
    images = case_ref.collection("images")
    image = images.document("image-1")
    old_items = image.collection("costItems")
    old_item = old_items.document("old")
    old_item.data = {"lineCostSar": 999, "costRevision": 4}
    _all_collections[:] = [old_items]
    db = _AtomicDb(case_ref)
    monkeypatch.setattr(cost.firestore, "transactional", lambda fn: fn)

    staged = {
        "image-1": {
            "ref": image,
            "items": [{"damageType": "dent", "lineCostSar": 100}],
            "update": {"estimatedLaborCostSar": 100, "severityFactorApplied": 1.0},
            "failed": False,
            "unpriced": False,
        }
    }
    revision = cost._finalize_cost_snapshot(
        db, case_ref, cost_run_id="run-1", claimed_image_ids=("image-1",),
        staged_images=staged,
        case_update={"estimatedCostSar": 100, "costState": "complete",
                     "costEstimateComplete": True},
    )
    assert revision == 5
    assert old_item.id not in old_items.docs
    new_items = old_items.stream()
    assert len(new_items) == 1
    assert new_items[0].data["costRevision"] == 5
    assert case_ref.data["costRevision"] == 5
    assert case_ref.data["estimatedCostSar"] == 100


def test_atomic_finalize_checks_write_limit_before_mutating(monkeypatch):
    case_ref = _AtomicRef({"costRevision": 1, "costRunId": "run-1"}, "case")
    image = case_ref.collection("images").document("image-1")
    old_items = image.collection("costItems")
    old_item = old_items.document("old")
    old_item.data = {"lineCostSar": 12, "costRevision": 1}
    _all_collections[:] = [old_items]
    db = _AtomicDb(case_ref)
    monkeypatch.setattr(cost.firestore, "transactional", lambda fn: fn)
    monkeypatch.setattr(cost, "FIRESTORE_MAX_WRITES", 1)

    with pytest.raises(cost.CostWriteLimitExceeded):
        cost._finalize_cost_snapshot(
            db, case_ref, cost_run_id="run-1", claimed_image_ids=("image-1",),
            staged_images={"image-1": {
                "ref": image, "items": [{"lineCostSar": 100}],
                "update": {}, "failed": False, "unpriced": False,
            }},
            case_update={"estimatedCostSar": 100},
        )
    assert old_items.docs["old"].data["lineCostSar"] == 12
    assert case_ref.data["costRevision"] == 1
