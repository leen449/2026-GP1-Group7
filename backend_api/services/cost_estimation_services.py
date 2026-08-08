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
from services.confidence_signals import detect_airbag, parse_zone, zones_compatible

RATE_SAR = 165.0
BUCKET = "crashlens-233bf.firebasestorage.app"


def _ensure_firebase_initialized():
    if not firebase_admin._apps:
        cred = credentials.Certificate("serviceAccountKey.json")
        firebase_admin.initialize_app(cred, {"storageBucket": BUCKET})


def _clear_collection(db, collection_ref) -> None:
    """Delete every existing doc in a subcollection before writing fresh ones,
    so re-running cost estimation on a case (e.g. retrying POST /cost/{case_id}
    alone) REPLACES its cost items instead of appending a duplicate copy on
    top of the old ones (see technical_observations.md #2.2 / "Re-run
    duplicates")."""
    docs = list(collection_ref.stream())
    if not docs:
        return
    batch = db.batch()
    for doc in docs:
        batch.delete(doc.reference)
    batch.commit()


def _download(image_url, bucket, temp_path):
    # same URL->storage-path logic as damage_detection.py
    path_part = image_url.split("/o/")[1].split("?")[0]
    storage_path = urllib.parse.unquote(path_part)
    bucket.blob(storage_path).download_to_filename(temp_path)


def _najm_zone(damage_location: str):
    z = damage_location or ""
    low = z.lower()
    if "front" in low or "مقدم" in z or "امام" in z or "أمام" in z:
        return "front"
    if "rear" in low or "back" in low or "خلف" in z or "مؤخر" in z:
        return "rear"
    return None


def _hours_for(line):
    if line.lookup_key is None:
        return None
    h = get_hours(line.lookup_key, line.damage_type)
    if h is None and "promote_lookup" in line.flags:
        h = get_unmapped_hours(line.lookup_key, line.damage_type)   # fender/sill/roof
    return h


def build_line_items(lines, factor: float = 1.0):
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
    items = []
    cost_sar = 0.0
    for ln in lines:
        h = _hours_for(ln)
        item = {
            "damageType": ln.damage_type, "part": ln.part,
            "lookupKey": ln.lookup_key, "source": ln.source,
            "hours": h, "lineCostSar": None, "flags": list(ln.flags),
        }
        if h is None:
            item["flags"].append("no_hours" if ln.lookup_key else "unassigned")
        else:
            item["lineCostSar"] = round(h * RATE_SAR * factor, 2)
            cost_sar += item["lineCostSar"]
        items.append(item)
    return {"items": items, "cost_sar": cost_sar}


def _find_prior_accident(db, case_id, vehicle_id, owner_id, current_zone, current_items):
    """
    FIX B input: same vehicle + same owner, a prior COMPLETED ("تم الفحص") case
    (excluding this one, excluding an archived vehicle) that matches the current
    case on part + damage type + Najm-zone.

    Returns (matched, note):
        matched: True (found a match) | False (checked, nothing matched) |
                 None (couldn't determine — missing scoping ids, or the lookup failed)
        note:    short human-readable string when matched=True, else None.

    Every Firestore read here is guarded — a lookup failure must never break the
    cost estimate, so any exception falls back to (None, None), same as "unknown."
    """
    if not vehicle_id or not owner_id:
        return None, None

    try:
        # archived vehicle -> its history isn't considered (field lives on
        # `vehicles`, not on the case — accidentCase has no archive flag).
        vehicle_snap = db.collection("vehicles").document(vehicle_id).get()
        if vehicle_snap.exists and bool((vehicle_snap.to_dict() or {}).get("isArchived")):
            return False, None

        current_pairs = {(it.get("part"), it.get("damageType"))
                          for it in current_items if it.get("part")}
        if not current_pairs:
            return False, None   # nothing on this case to match against

        prior_stream = (
            db.collection("accidentCase")
              .where("vehicleId", "==", vehicle_id)
              .where("ownerId", "==", owner_id)
              .where("status", "==", "تم الفحص")
              .stream()
        )
        for prior_doc in prior_stream:
            if prior_doc.id == case_id:
                continue   # exclude self — critical
            prior = prior_doc.to_dict() or {}
            prior_najm = prior.get("najimReport", {}) or {}
            prior_zone = parse_zone(prior_najm.get("damageLocation"))
            if not zones_compatible(current_zone, prior_zone):
                continue

            for img_doc in prior_doc.reference.collection("images").stream():
                for item_doc in img_doc.reference.collection("costItems").stream():
                    item = item_doc.to_dict() or {}
                    part, dtype = item.get("part"), item.get("damageType")
                    if part and (part, dtype) in current_pairs:
                        note = f"prior تم الفحص case {prior_doc.id}: {part} {dtype}"
                        return True, note
        return False, None
    except Exception as e:
        print(f"⚠️ prior-accident lookup failed: {e}")
        return None, None


async def process_cost_estimation(case_id: str) -> dict:
    try:
        print(f"--- COST ESTIMATION REQUEST: {case_id} ---")
        _ensure_firebase_initialized()
        db = firestore.client()
        case_ref = db.collection("accidentCase").document(case_id)
        case_doc = case_ref.get()
        if not case_doc.exists:
            return {"status": "error", "message": f"Case {case_id} not found"}
        case = case_doc.to_dict()

        case_ref.update({
            "status": "قيد حساب التكلفة",
            "costStartedAt": firestore.SERVER_TIMESTAMP,
            "costError": None,
        })

        # ---- case-level inputs (from the Najm OCR already stored on the case) ----
        najm = case.get("najimReport", {}) or {}
        make  = najm.get("vehicleMake") or najm.get("make") or case.get("vehicleMake", "")
        model = najm.get("vehicleModel", "")
        year  = najm.get("manuYear") or najm.get("vehicleYear")
        color = najm.get("vehicleColor", "")
        zone  = _najm_zone(najm.get("damageLocation", ""))
        overall_sev = case.get("overallSeverity")

        value_sar, low_conf = None, False
        try:
            if make and model and year:
                rec = get_vehicle_value(make, model, int(year))
                if rec:
                    value_sar = rec.get("value_sar")
                    low_conf = rec.get("low_confidence", False)
        except Exception as e:
            print(f"⚠️ vehicle value lookup failed: {e}")

        # Computed here (before the per-image loop) rather than after it, so
        # build_line_items() can bake F_vehicle/F_paint into each line's
        # lineCostSar alongside that image's F_severity — see build_line_items.
        f_veh = float(get_vehicle_factor(value_sar))
        f_paint = float(get_paint_factor(color)) if color else 1.0

        bucket = storage.bucket(BUCKET)
        subtotal = 0.0
        all_items = []
        review_reasons = []  # dedup'd tokens explaining WHY needsAdminReview fired

        # ---- per image: reuse saved boxes + part seg -> associate -> hours ----
        for img_doc in case_ref.collection("images").stream():
            img = img_doc.to_dict()
            if not img.get("hasDamage"):
                continue
            url = img.get("downloadUrl")
            if not url:
                continue

            damages = []
            for det in img_doc.reference.collection("detections").stream():
                d = det.to_dict()
                damages.append({
                    "label": d.get("label"),
                    "bbox": (int(d["x1"]), int(d["y1"]), int(d["x2"]), int(d["y2"])),
                    "confidence": d.get("confidence", 0),
                })
            if not damages:
                continue

            temp_path = None
            try:
                with tempfile.NamedTemporaryFile(delete=False, suffix=".jpg") as tmp:
                    temp_path = tmp.name
                _download(url, bucket, temp_path)
                image = cv2.imread(temp_path)
                H, W = image.shape[:2]

                parts = segment_parts(temp_path)
                lines = associate(damages, parts, (H, W), najm_zone=zone)

                sev = img.get("severity") or overall_sev or "moderate"
                f_sev_img = get_severity_factor(sev)

                built = build_line_items(lines, f_sev_img * f_veh * f_paint)

                # Clear this image's prior cost items only now that the new
                # ones are successfully built, so a failure above (download,
                # segmentation, association) leaves the previous good items
                # in place instead of wiping them for nothing.
                _clear_collection(db, img_doc.reference.collection("costItems"))

                for item in built["items"]:
                    for flag in item["flags"]:
                        if flag not in review_reasons:
                            review_reasons.append(flag)
                    img_doc.reference.collection("costItems").add(item)
                    all_items.append(item)

                img_cost = built["cost_sar"]
                subtotal += img_cost
                img_doc.reference.update({
                    "estimatedLaborCostSar": round(img_cost, 2),
                    "severityFactorApplied": f_sev_img,
                })
            except Exception as img_err:
                # Isolate a single bad image (corrupt download, model hiccup, etc.)
                # so the case still rolls up an estimate from the images that DID
                # succeed, instead of losing the whole case's cost the way an
                # unhandled exception here used to (see technical_observations.md).
                print(f"⚠️ cost estimation failed for image {img_doc.id}: {img_err}")
                if "image_cost_failed" not in review_reasons:
                    review_reasons.append("image_cost_failed")
                try:
                    img_doc.reference.update({"costError": str(img_err)})
                except Exception as write_err:
                    print(f"❌ failed to write costError on image {img_doc.id}: {write_err}")
            finally:
                if temp_path and os.path.exists(temp_path):
                    os.remove(temp_path)

        # ---- confidence (f_veh/f_paint already folded into each line above) ----
        total = round(subtotal, 2)

        # ---- FIX A: airbag, from Najm's free-text damage location ----
        airbag_deployed = detect_airbag(najm.get("damageLocation"))

        # ---- FIX B: prior accident, same vehicle + same owner + same part/damage/zone ----
        current_zone = parse_zone(najm.get("damageLocation"))
        prior_accident_same_location, prior_note = _find_prior_accident(
            db, case_id, case.get("vehicleId"), case.get("ownerId"),
            current_zone, all_items,
        )
        if prior_note and prior_note not in review_reasons:
            review_reasons.append(prior_note)

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

        if conf.get("requires_admin_review") and "low_cost_confidence" not in review_reasons:
            review_reasons.append("low_cost_confidence")
        needs_review = bool(review_reasons)

        case_ref.update({
            "status": "تم حساب التكلفة",
            "estimatedCostSar": total,
            "costFactors": {"paint": f_paint, "vehicle": f_veh, "rateSar": RATE_SAR},
            "costConfidence": conf,
            # costConfidenceScore: this cost estimate's own 0-100 confidence
            # (confidence_service). Distinct from severityConfidence, which the damage
            # step writes per-image for the severity CLASSIFIER — different score, same
            # word "confidence"; kept under separate keys so they can't collide.
            "costConfidenceScore": conf.get("confidence_score"),
            "needsAdminReview": needs_review,
            "reviewReasons": review_reasons,
            "costError": None,
        })

        return {
            "status": "success",
            "estimatedCostSar": total,
            "confidence": conf.get("confidence_score"),
            "needsAdminReview": needs_review,
            "reviewReasons": review_reasons,
            "lineItems": all_items,
        }

    except Exception as e:
        msg = f"Cost Estimation Error: {str(e)}"
        print(f"!!! {msg}")
        try:
            _ensure_firebase_initialized()
            firestore.client().collection("accidentCase").document(case_id).update({
                "status": "فشل حساب التكلفة", "costError": msg,
            })
        except Exception as ue:
            print(f"❌ failed to update case after cost error: {ue}")
        return {"status": "error", "message": msg}
