"""
Cost estimation service (request-path) — mirrors damage_detection.py.

Runs AFTER damage detection, on a case_id. It reuses the damage boxes already stored
in each image's `detections` subcollection (no re-running the damage model), adds part
segmentation on the same images, associates damage->part(s), looks up labor hours, and
writes the itemized cost + a separate confidence score back onto the case.

Cost model:
    per line:   hours x 165 x F_severity(image severity) x F_vehicle x F_paint
    per image:  sum(line costs)
    case total: sum(images)
    confidence: separate 100-minus-deductions score; never changes the cost.

    Factors are applied per LINE (not just to the aggregate) so each costItem's
    lineCostSar is the damage's real, final contribution to the total — see
    build_line_items().

⚠️ STAGING: the part model has no measured real-domain panel accuracy yet. Wire this in
   and exercise it, but treat the numbers as provisional until that number exists.
"""
import os
import uuid
import cv2
import tempfile
import urllib.parse
from datetime import datetime

import firebase_admin
from firebase_admin import firestore, credentials, storage
from services.part_segmentation_service import segment_parts
from services.part_association_service import associate
from services.labor_hours_lookup import get_hours, get_unmapped_hours
from services.severity_factor_services import get_severity_factor
from services.vehicle_factor_services import get_vehicle_factor
from services.paint_factor_services import get_paint_factor
from services.confidence_service import assess_confidence
from services.vehicle_valuation_services import get_vehicle_value
from services.confidence_signals import detect_airbag, parse_zone

RATE_SAR = 165.0
BUCKET = "crashlens-233bf.firebasestorage.app"
FIRESTORE_MAX_WRITES = 500
VALID_SEVERITIES = {"minor", "moderate", "severe"}
REVIEWED_STATUSES = {"تمت المراجعة", "تم المراجعة"}
COMPLETED_COST_STATUSES = {"تم حساب التكلفة", "تم الفحص"}
BLOCKING_COST_STATES = {"running", "failed"}

# A case referred to the human specialist (Sheikh Al-Ma'aredh) is a final admin
# decision, same as an approved review — it must not be silently overwritten by
# a later re-run of cost estimation. Kept separate from REVIEWED_STATUSES itself
# because a referred case was never admin-approved, so _is_eligible_prior() must
# keep treating it as ineligible prior-accident history.
REFERRED_STATUS = "محالة لشيخ المعارض"
LOCKED_STATUSES = REVIEWED_STATUSES | {REFERRED_STATUS}


class CostEstimationAbort(Exception):
    """Visible cost-run failure that must not invent an estimate."""


class CostRunSuperseded(Exception):
    """Another retry claimed this case before finalization."""


class CostWriteLimitExceeded(Exception):
    """The intended snapshot would exceed Firestore's per-transaction write cap."""


def _ensure_firebase_initialized():
    if not firebase_admin._apps:
        cred = credentials.Certificate("serviceAccountKey.json")
        firebase_admin.initialize_app(cred, {"storageBucket": BUCKET})


def _download(image_url, bucket, temp_path):
    # same URL->storage-path logic as damage_detection.py
    path_part = image_url.split("/o/")[1].split("?")[0]
    storage_path = urllib.parse.unquote(path_part)
    bucket.blob(storage_path).download_to_filename(temp_path)


def _wheel_position_from_najm(damage_location: str):
    """Najm's only cost-routing role: front/rear for a segmented wheel dent."""
    zone = parse_zone(damage_location)
    if zone and zone.startswith("front"):
        return "front"
    if zone and zone.startswith("rear"):
        return "rear"
    return None


def _hours_for(line):
    if line.lookup_key is None:
        return None
    h = get_hours(
        line.lookup_key,
        line.damage_type,
        wheel_position=getattr(line, "wheel_position", None),
    )
    if h is None and "promote_lookup" in line.flags:
        h = get_unmapped_hours(line.lookup_key, line.damage_type)   # fender/sill/roof
    return h


def _image_severity_state(raw):
    """Return (severity, flag). Flag is set when this damaged image cannot be priced."""
    if raw is None or not str(raw).strip():
        return None, "missing_image_severity"
    key = str(raw).strip().lower()
    if key not in VALID_SEVERITIES:
        return None, "invalid_image_severity"
    return key, None


def _required_text(data: dict, field: str):
    value = data.get(field)
    if value is None or not str(value).strip():
        return None
    return str(value).strip()


def _vehicle_year(raw):
    if raw is None or not str(raw).strip():
        return None
    try:
        return int(str(raw).strip())
    except (TypeError, ValueError):
        return None


def _resolve_linked_vehicle(db, case: dict) -> dict:
    """Authoritative make/model/year/paint come from vehicles/{case.vehicleId}, never Najm."""
    vehicle_id = _required_text(case, "vehicleId")
    if not vehicle_id:
        raise CostEstimationAbort("Case is missing vehicleId")

    snap = db.collection("vehicles").document(vehicle_id).get()
    if not snap.exists:
        raise CostEstimationAbort(f"Vehicle document not found: {vehicle_id}")

    data = snap.to_dict() or {}
    make = _required_text(data, "make")
    model = _required_text(data, "model")
    year = _vehicle_year(data.get("year"))
    if not make or not model or year is None:
        raise CostEstimationAbort(
            f"Vehicle {vehicle_id} is missing usable make/model/year"
        )

    paint = data.get("paintCategory")
    paint_category = str(paint).strip() if paint is not None and str(paint).strip() else ""
    return {
        "vehicleId": vehicle_id,
        "make": make,
        "model": model,
        "year": year,
        "paintCategory": paint_category,
        "isArchived": bool(data.get("isArchived")),
        "data": data,
    }


def build_line_items(lines, factor: float = 1.0, *, price: bool = True, extra_flags=None):
    """
    Pure: CostLines -> cost line-item dicts + total SAR for this image. No
    Firestore I/O — the caller writes items to costItems and accumulates
    reviewReasons.

    `factor` folds in ALL of F_severity x F_vehicle x F_paint, so each line's
    lineCostSar is the damage's real, final contribution to the case total —
    not a pre-factor intermediate value. Previously only the per-image/case
    AGGREGATE was scaled by these factors, so a single line could show a
    bigger number than the final estimate (e.g. a 495 SAR line under a 420.75
    SAR total) — correct arithmetic, but a misleading field: lineCostSar meant
    "raw labor at the moderate baseline," not "what this damage costs."
    """
    extra_flags = list(extra_flags or [])
    items = []
    cost_sar = 0.0
    for ln in lines:
        h = _hours_for(ln)
        flags = list(ln.flags)
        for flag in extra_flags:
            if flag not in flags:
                flags.append(flag)
        item = {
            "damageType": ln.damage_type, "part": ln.part,
            "lookupKey": ln.lookup_key, "source": ln.source,
            "hours": h, "lineCostSar": None, "flags": flags,
            "wheelPosition": getattr(ln, "wheel_position", None),
        }
        if h is None:
            item["flags"].append("no_hours" if ln.lookup_key else "unassigned")
        elif price:
            item["lineCostSar"] = round(h * RATE_SAR * factor, 2)
            cost_sar += item["lineCostSar"]
        items.append(item)
    return {"items": items, "cost_sar": cost_sar}


def _canonical_history_part(part, lookup_key, damage_type):
    """Normalize current and legacy stored cost keys for Firestore history matching."""
    raw = str(part or lookup_key or "").strip().lower().replace("-", "_").replace(" ", "_")
    damage = str(damage_type or "").strip().lower().replace("-", "_").replace(" ", "_")
    if not raw:
        return None

    if damage == "glass":
        if raw in {"front_glass", "back_glass", "windshield", "front_windshield", "back_windshield"}:
            return "windshield"
        if raw in {
            "window", "door_glass", "front_window", "back_window",
            "front_left_door", "front_right_door", "back_left_door", "back_right_door",
            "door",
        }:
            return "door_glass"
        if raw in {"trunk", "tailgate"}:
            return "trunk"

    if damage == "lamp" and (
        raw == "lamp" or "light" in raw or raw in {"headlight", "taillight"}
    ):
        return "lamp"
    if "wheel" in raw or raw == "tire":
        return "wheel"
    if raw in {"front_left_door", "front_right_door", "back_left_door", "back_right_door"}:
        return "door"
    if "fender" in raw:
        return "fender"
    if "sill" in raw:
        return "sill"
    if raw == "tailgate":
        return "trunk"
    return raw


def _canonical_history_pair(item):
    damage_type = item.get("damageType")
    part = _canonical_history_part(item.get("part"), item.get("lookupKey"), damage_type)
    if not part or not damage_type:
        return None
    return part, str(damage_type).strip().lower().replace("-", "_").replace(" ", "_")


def _created_at_value(value):
    if value is None:
        return None
    if hasattr(value, "timestamp") and callable(value.timestamp):
        return value
    return value


def _prior_has_priced_items(prior_doc, prior: dict) -> bool:
    revision = prior.get("costRevision")
    for img_doc in prior_doc.reference.collection("images").stream():
        for item_doc in img_doc.reference.collection("costItems").stream():
            item = item_doc.to_dict() or {}
            if revision is not None and item.get("costRevision") != revision:
                continue
            if item.get("lineCostSar") is not None:
                return True
    return False


def _prior_matching_note(prior_doc, prior: dict, current_pairs):
    revision = prior.get("costRevision")
    for img_doc in prior_doc.reference.collection("images").stream():
        for item_doc in img_doc.reference.collection("costItems").stream():
            item = item_doc.to_dict() or {}
            if revision is not None and item.get("costRevision") != revision:
                continue
            if item.get("lineCostSar") is None:
                continue
            pair = _canonical_history_pair(item)
            if pair and pair in current_pairs:
                return f"prior case {prior_doc.id}: {pair[0]} {pair[1]}"
    return None


def _is_eligible_prior(prior_doc, prior: dict, case_id: str, current_created_at) -> bool:
    if prior_doc.id == case_id:
        return False
    if prior.get("costEstimateStale") or prior.get("costState") in BLOCKING_COST_STATES:
        return False
    if prior.get("costError"):
        # revisioned/failed records keep any leftover error string off history
        if prior.get("costState") == "failed" or str(prior.get("status") or "").strip() == "فشل حساب التكلفة":
            return False

    prior_created = _created_at_value(prior.get("createdAt"))
    current_created = _created_at_value(current_created_at)
    if current_created is None or prior_created is None or prior_created >= current_created:
        return False

    status = str(prior.get("status") or "").strip()
    cost_state = prior.get("costState")
    if cost_state == "failed" or status == "فشل حساب التكلفة":
        return False

    has_priced = _prior_has_priced_items(prior_doc, prior)
    if not has_priced:
        return False

    if status in REVIEWED_STATUSES:
        return True

    if cost_state == "partial":
        return False

    if status in COMPLETED_COST_STATUSES or cost_state == "complete":
        if prior.get("costRevision") is None and prior.get("costError"):
            return False
        return True

    return False


def _find_prior_accident(
    db,
    case_id,
    vehicle_id,
    owner_id,
    current_items,
    current_created_at=None,
):
    """
    Find an older eligible Firestore case for the same vehicle and owner with a
    matching visually derived canonical part + damage type.

    Returns (matched, note): True/False when checked, or None when the query could
    not be evaluated. Najm location is deliberately not part of this comparison.
    """
    if not vehicle_id or not owner_id:
        return None, None

    try:
        vehicle_snap = db.collection("vehicles").document(vehicle_id).get()
        if vehicle_snap.exists and bool((vehicle_snap.to_dict() or {}).get("isArchived")):
            return False, None

        current_pairs = {
            pair
            for item in current_items
            if item.get("lineCostSar") is not None
            for pair in [_canonical_history_pair(item)]
            if pair is not None
        }
        if not current_pairs:
            return False, None

        prior_stream = (
            db.collection("accidentCase")
              .where("vehicleId", "==", vehicle_id)
              .where("ownerId", "==", owner_id)
              .stream()
        )
        for prior_doc in prior_stream:
            prior = prior_doc.to_dict() or {}
            if not _is_eligible_prior(prior_doc, prior, case_id, current_created_at):
                continue
            note = _prior_matching_note(prior_doc, prior, current_pairs)
            if note:
                return True, note
        return False, None
    except Exception as e:
        print(f"⚠️ prior-accident lookup failed: {e}")
        return None, None


def _append_reason(review_reasons, flag):
    if flag and flag not in review_reasons:
        review_reasons.append(flag)


def _empty_image_stage(img_ref):
    return {
        "ref": img_ref,
        "items": [],
        "update": {
            "estimatedLaborCostSar": None,
            "severityFactorApplied": None,
            "costError": None,
        },
        "failed": False,
        "unpriced": False,
    }


def _claim_cost_run(db, case_ref, cost_run_id: str) -> dict:
    claimed = {}

    @firestore.transactional
    def _claim(txn):
        snap = case_ref.get(transaction=txn)
        if not snap.exists:
            raise CostEstimationAbort("Case not found")
        case = snap.to_dict() or {}
        status = str(case.get("status") or "").strip()
        if status in LOCKED_STATUSES or case.get("reportId"):
            raise CostEstimationAbort(
                "Cost estimation is locked after review or report issuance"
            )
        update = {
            "status": "قيد حساب التكلفة",
            "costState": "running",
            "costRunId": cost_run_id,
            "costStartedAt": firestore.SERVER_TIMESTAMP,
            "costError": None,
            "costEstimateComplete": False,
        }
        if case.get("costState") in ("complete", "partial") or case.get("costRevision") is not None:
            update["costEstimateStale"] = True
        txn.update(case_ref, update)
        claimed["case"] = case

    _claim(db.transaction())
    return claimed["case"]


def _mark_cost_run_failed(db, case_ref, cost_run_id: str, message: str) -> None:
    @firestore.transactional
    def _fail(txn):
        snap = case_ref.get(transaction=txn)
        if not snap.exists:
            return
        data = snap.to_dict() or {}
        if data.get("costRunId") != cost_run_id:
            return
        txn.update(case_ref, {
            "status": "فشل حساب التكلفة",
            "costState": "failed",
            "costError": message,
            "costEstimateStale": True,
            "costEstimateComplete": False,
        })

    _fail(db.transaction())


def _collect_old_item_refs(case_ref, txn=None):
    refs = []
    image_stream = case_ref.collection("images").stream(transaction=txn) if txn else case_ref.collection("images").stream()
    for img_snap in image_stream:
        item_stream = img_snap.reference.collection("costItems").stream(transaction=txn) if txn else img_snap.reference.collection("costItems").stream()
        for item_snap in item_stream:
            refs.append(item_snap.reference)
    return refs


def _finalize_cost_snapshot(
    db,
    case_ref,
    *,
    cost_run_id: str,
    claimed_image_ids,
    staged_images: dict,
    case_update: dict,
):
    @firestore.transactional
    def _commit(txn):
        snap = case_ref.get(transaction=txn)
        if not snap.exists:
            raise CostEstimationAbort("Case not found during cost finalization")
        current = snap.to_dict() or {}
        if current.get("costRunId") != cost_run_id:
            raise CostRunSuperseded(
                "Another cost run claimed this case before finalization"
            )
        if str(current.get("status") or "").strip() in LOCKED_STATUSES or current.get("reportId"):
            raise CostEstimationAbort(
                "Cost estimation is locked after review or report issuance"
            )

        live_ids = tuple(sorted(doc.id for doc in case_ref.collection("images").stream(transaction=txn)))
        if live_ids != tuple(claimed_image_ids):
            raise CostEstimationAbort("Case image set changed during cost estimation")

        old_refs = _collect_old_item_refs(case_ref, txn=txn)
        new_writes = []
        image_updates = []
        revision = int(current.get("costRevision") or 0) + 1

        for image_id in claimed_image_ids:
            stage = staged_images[image_id]
            img_update = dict(stage["update"])
            img_update["costRevision"] = revision
            img_update["costRunId"] = cost_run_id
            image_updates.append((stage["ref"], img_update))
            items_col = stage["ref"].collection("costItems")
            for item in stage["items"]:
                payload = dict(item)
                payload["costRevision"] = revision
                payload["costRunId"] = cost_run_id
                new_writes.append((items_col.document(), payload))

        write_count = len(old_refs) + len(new_writes) + len(image_updates) + 1
        if write_count > FIRESTORE_MAX_WRITES:
            raise CostWriteLimitExceeded(
                f"Cost snapshot requires {write_count} writes; "
                f"limit is {FIRESTORE_MAX_WRITES}"
            )

        for ref in old_refs:
            txn.delete(ref)
        for ref, payload in new_writes:
            txn.set(ref, payload)
        for ref, payload in image_updates:
            txn.update(ref, payload)

        final_case = dict(case_update)
        final_case["costRevision"] = revision
        final_case["costRunId"] = cost_run_id
        final_case["costCompletedAt"] = firestore.SERVER_TIMESTAMP
        final_case["costEstimateStale"] = False
        final_case["costError"] = None
        txn.update(case_ref, final_case)
        return revision

    return _commit(db.transaction())


def _stage_image(img_doc, wheel_position_hint, f_veh, f_paint, bucket, review_reasons):
    stage = _empty_image_stage(img_doc.reference)
    img = img_doc.to_dict() or {}
    if not img.get("hasDamage"):
        return stage

    url = img.get("downloadUrl")
    if not url:
        stage["failed"] = True
        stage["update"]["costError"] = "missing_download_url"
        _append_reason(review_reasons, "image_cost_failed")
        return stage

    damages = []
    for det in img_doc.reference.collection("detections").stream():
        d = det.to_dict() or {}
        damages.append({
            "label": d.get("label"),
            "bbox": (int(d["x1"]), int(d["y1"]), int(d["x2"]), int(d["y2"])),
            "confidence": d.get("confidence", 0),
        })
    if not damages:
        return stage

    sev, sev_flag = _image_severity_state(img.get("severity"))
    temp_path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".jpg") as tmp:
            temp_path = tmp.name
        _download(url, bucket, temp_path)
        image = cv2.imread(temp_path)
        if image is None:
            raise RuntimeError("unreadable image")
        H, W = image.shape[:2]
        parts = segment_parts(temp_path)
        lines = associate(
            damages, parts, (H, W), wheel_position_hint=wheel_position_hint,
        )

        if sev_flag:
            built = build_line_items(lines, price=False, extra_flags=[sev_flag])
            stage["items"] = built["items"]
            stage["unpriced"] = True
            _append_reason(review_reasons, sev_flag)
            for item in built["items"]:
                for flag in item["flags"]:
                    _append_reason(review_reasons, flag)
            return stage

        f_sev_img = get_severity_factor(sev)
        built = build_line_items(lines, f_sev_img * f_veh * f_paint)
        stage["items"] = built["items"]
        stage["update"]["estimatedLaborCostSar"] = round(built["cost_sar"], 2)
        stage["update"]["severityFactorApplied"] = f_sev_img
        for item in built["items"]:
            for flag in item["flags"]:
                _append_reason(review_reasons, flag)
            if item.get("lineCostSar") is None:
                stage["unpriced"] = True
        return stage
    except Exception as img_err:
        print(f"⚠️ cost estimation failed for image {img_doc.id}: {img_err}")
        stage = _empty_image_stage(img_doc.reference)
        stage["failed"] = True
        stage["update"]["costError"] = str(img_err)
        _append_reason(review_reasons, "image_cost_failed")
        return stage
    finally:
        if temp_path and os.path.exists(temp_path):
            os.remove(temp_path)


async def process_cost_estimation(case_id: str) -> dict:
    cost_run_id = None
    case_ref = None
    db = None
    try:
        print(f"--- COST ESTIMATION REQUEST: {case_id} ---")
        _ensure_firebase_initialized()
        db = firestore.client()
        case_ref = db.collection("accidentCase").document(case_id)
        case_doc = case_ref.get()
        if not case_doc.exists:
            return {"status": "error", "message": f"Case {case_id} not found"}
        case = case_doc.to_dict() or {}

        status = str(case.get("status") or "").strip()
        if status in LOCKED_STATUSES or case.get("reportId"):
            return {
                "status": "error",
                "message": "Cost estimation is locked after review or report issuance",
            }

        vehicle = _resolve_linked_vehicle(db, case)
        make, model, year = vehicle["make"], vehicle["model"], vehicle["year"]
        paint_category = vehicle["paintCategory"]

        najm = case.get("najimReport", {}) or {}
        damage_location = najm.get("damageLocation", "")
        wheel_position_hint = _wheel_position_from_najm(damage_location)

        value_sar, low_conf = None, False
        review_reasons = []
        try:
            rec = get_vehicle_value(make, model, int(year))
            if rec:
                value_sar = rec.get("value_sar")
                low_conf = rec.get("low_confidence", False)
        except Exception as e:
            print(f"⚠️ vehicle value lookup failed: {e}")
        if value_sar is None:
            _append_reason(review_reasons, "vehicle_value_unavailable")

        f_veh = float(get_vehicle_factor(value_sar))
        f_paint = float(get_paint_factor(paint_category) if paint_category else 1.0)

        cost_run_id = str(uuid.uuid4())
        _claim_cost_run(db, case_ref, cost_run_id)

        image_snaps = list(case_ref.collection("images").stream())
        claimed_image_ids = tuple(sorted(doc.id for doc in image_snaps))

        bucket = storage.bucket(BUCKET)
        staged_images = {}
        all_items = []
        subtotal = 0.0
        any_failed = False
        any_unpriced = False

        for img_doc in image_snaps:
            stage = _stage_image(
                img_doc, wheel_position_hint, f_veh, f_paint, bucket, review_reasons,
            )
            staged_images[img_doc.id] = stage
            all_items.extend(stage["items"])
            img_cost = stage["update"].get("estimatedLaborCostSar")
            if img_cost is not None:
                subtotal += img_cost
            any_failed = any_failed or stage["failed"]
            any_unpriced = any_unpriced or stage["unpriced"]

        total = round(subtotal, 2)
        airbag_deployed = detect_airbag(damage_location)
        prior_accident_same_location, prior_note = _find_prior_accident(
            db, case_id, vehicle["vehicleId"], case.get("ownerId"),
            all_items, current_created_at=case.get("createdAt"),
        )
        if prior_note:
            _append_reason(review_reasons, prior_note)

        conf = assess_confidence(
            vehicle_year=int(year) if year else None,
            current_year=datetime.now().year,
            estimated_cost=total,
            vehicle_value_sar=value_sar,
            airbag_deployed=airbag_deployed,
            prior_accident_same_location=prior_accident_same_location,
        )
        if low_conf:
            conf.setdefault("reasons_ar", []).append("قيمة المركبة تقديرية (ثقة منخفضة)")

        if conf.get("requires_admin_review"):
            _append_reason(review_reasons, "low_cost_confidence")

        incomplete = any_failed or any_unpriced
        cost_state = "partial" if incomplete else "complete"
        needs_review = bool(review_reasons) or incomplete
        if incomplete:
            _append_reason(review_reasons, "incomplete_cost_estimate")

        case_update = {
            "status": "تم حساب التكلفة",
            "costState": cost_state,
            "estimatedCostSar": total,
            "costFactors": {"paint": f_paint, "vehicle": f_veh, "rateSar": RATE_SAR},
            "costConfidence": conf,
            "costConfidenceScore": conf.get("confidence_score"),
            "needsAdminReview": needs_review,
            "reviewReasons": review_reasons,
            "costEstimateComplete": not incomplete,
        }

        revision = _finalize_cost_snapshot(
            db,
            case_ref,
            cost_run_id=cost_run_id,
            claimed_image_ids=claimed_image_ids,
            staged_images=staged_images,
            case_update=case_update,
        )

        return {
            "status": "success",
            "costState": cost_state,
            "costRevision": revision,
            "estimatedCostSar": total,
            "confidence": conf.get("confidence_score"),
            "needsAdminReview": needs_review,
            "reviewReasons": review_reasons,
            "lineItems": all_items,
        }

    except CostRunSuperseded as e:
        msg = f"Cost Estimation Error: {str(e)}"
        print(f"!!! {msg}")
        return {"status": "error", "message": msg}
    except Exception as e:
        msg = f"Cost Estimation Error: {str(e)}"
        print(f"!!! {msg}")
        try:
            if cost_run_id and case_ref is not None and db is not None:
                _mark_cost_run_failed(db, case_ref, cost_run_id, msg)
            else:
                _ensure_firebase_initialized()
                firestore.client().collection("accidentCase").document(case_id).update({
                    "status": "فشل حساب التكلفة",
                    "costState": "failed",
                    "costError": msg,
                    "costEstimateComplete": False,
                })
        except Exception as ue:
            print(f"❌ failed to update case after cost error: {ue}")
        return {"status": "error", "message": msg}
