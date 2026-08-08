"""
CrashLens · report generation route.

Creates one official report for a reviewed accident case, stores the report
record, builds the PDF with the real verification QR, saves its SHA-256 hash,
uploads the exact PDF to Firebase Storage, and links it to the accident case.

If the case already has a report, the same stored PDF information is returned
without allocating a new report number.
"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException
from firebase_admin import firestore

from models.report import DamageItem, ReportInput, UserInfo, VehicleInfo
from routes.verify import BASE_URL
from services import report_verification_service as verification_service
from services.report_pdf_service import build_report_pdf
from services.report_storage_service import upload_report_pdf
from services.report_store import get_store


router = APIRouter()

_ALLOWED_STATUS = "تم المراجعة"


def _required_text(
    data: dict[str, Any],
    field_name: str,
    *,
    source_name: str,
) -> str:
    value = data.get(field_name)

    if value is None or not str(value).strip():
        raise HTTPException(
            status_code=422,
            detail=f"Missing required field '{field_name}' in {source_name}",
        )

    return str(value).strip()


def _vehicle_year(vehicle_data: dict[str, Any]) -> int:
    raw_year = vehicle_data.get("year")

    if raw_year is None or not str(raw_year).strip():
        raise HTTPException(
            status_code=422,
            detail="Missing required field 'year' in vehicle document",
        )

    try:
        return int(str(raw_year).strip())
    except (TypeError, ValueError) as exc:
        raise HTTPException(
            status_code=422,
            detail=f"Invalid vehicle year: {raw_year}",
        ) from exc


def _read_damage_items(
    case_reference,
    case_data: dict[str, Any],
) -> list[DamageItem]:
    """
    Read PRICED damage line-items from either:

    1) case document field:
       accidentCase/{caseId}.damageAnalysis[*].detections[*]
       (legacy case shape — no cost data exists for it, so cost_sar stays 0.0
       here; unrelated to cost estimation, which only the current shape below has)

    or, for the current case structure:

    2) images subcollection:
       accidentCase/{caseId}/images/{imageId}/costItems/{itemId}
       (written by cost_estimation_services.py — the same priced damageType/
       lineCostSar line items the Case Details screen already shows)

    A costItem whose lineCostSar is still null (unassigned / no matching
    labor-hours row — see the case's reviewReasons) is left OFF the official
    report rather than shown as a misleading "0.00 SAR" on a signed document;
    that case should be resolved administratively before its report is issued.
    """
    damages: list[DamageItem] = []

    # ── First: read the structure currently used by existing cases ──────────
    damage_analysis = case_data.get("damageAnalysis")

    if isinstance(damage_analysis, list):
        for analysis_item in damage_analysis:
            if not isinstance(analysis_item, dict):
                continue

            detections = analysis_item.get("detections")

            if not isinstance(detections, list):
                continue

            item_severity = analysis_item.get("severity")

            if item_severity is None or not str(item_severity).strip():
                item_severity = case_data.get("overallSeverity")

            severity = (
                str(item_severity).strip()
                if item_severity is not None and str(item_severity).strip()
                else "غير محدد"
            )

            for detection in detections:
                if not isinstance(detection, dict):
                    continue

                damage_type = detection.get("label")

                if damage_type is None or not str(damage_type).strip():
                    continue

                damages.append(
                    DamageItem(
                        type=str(damage_type).strip(),
                        severity=severity,
                        cost_sar=0.0,
                    )
                )

    # ── Second: current structure — PRICED costItems per image ──────────────
    any_cost_items_seen = False

    if not damages:
        for image_snapshot in case_reference.collection("images").stream():
            image_data = image_snapshot.to_dict() or {}

            if image_data.get("hasDamage") is False:
                continue

            image_severity = image_data.get("severity")

            if image_severity is None or not str(image_severity).strip():
                image_severity = case_data.get("overallSeverity")

            severity = (
                str(image_severity).strip()
                if image_severity is not None and str(image_severity).strip()
                else "غير محدد"
            )

            cost_item_snapshots = (
                image_snapshot.reference
                .collection("costItems")
                .stream()
            )

            for cost_item_snapshot in cost_item_snapshots:
                any_cost_items_seen = True
                cost_item_data = cost_item_snapshot.to_dict() or {}
                damage_type = cost_item_data.get("damageType")

                if damage_type is None or not str(damage_type).strip():
                    continue

                line_cost = cost_item_data.get("lineCostSar")

                if line_cost is None:
                    continue   # not priced yet — leave off the official report

                damages.append(
                    DamageItem(
                        type=str(damage_type).strip(),
                        severity=severity,
                        cost_sar=float(line_cost),
                    )
                )

    if not damages:
        if any_cost_items_seen:
            raise HTTPException(
                status_code=422,
                detail=(
                    "Cost estimation has run for this case but produced no priced "
                    "line items (all damages are unassigned or missing labor-hours "
                    "data). Resolve this administratively before generating the report."
                ),
            )
        raise HTTPException(
            status_code=422,
            detail=(
                "No priced damage line items were found for this case. "
                "Run cost estimation (POST /cost/{case_id}) before generating the report."
            ),
        )

    return damages

def _build_report_input(
    *,
    case_reference,
    case_data: dict[str, Any],
    user_data: dict[str, Any],
    vehicle_data: dict[str, Any],
) -> ReportInput:
    najm_report = case_data.get("najimReport") or {}

    if not isinstance(najm_report, dict):
        raise HTTPException(
            status_code=422,
            detail="'najimReport' must be an object in the case document",
        )

    accident_number = _required_text(
        najm_report,
        "accidentNumber",
        source_name="case.najimReport",
    )

    user = UserInfo(
        name=_required_text(
            user_data,
            "name",
            source_name="user document",
        ),
        national_id=_required_text(
            user_data,
            "nationalID",
            source_name="user document",
        ),
        phone=_required_text(
            user_data,
            "phoneNumber",
            source_name="user document",
        ),
    )

    vehicle = VehicleInfo(
        make=_required_text(
            vehicle_data,
            "make",
            source_name="vehicle document",
        ),
        model=_required_text(
            vehicle_data,
            "model",
            source_name="vehicle document",
        ),
        color=_required_text(
            vehicle_data,
            "color",
            source_name="vehicle document",
        ),
        year=_vehicle_year(vehicle_data),
        vin=_required_text(
            vehicle_data,
            "chassisNumber",
            source_name="vehicle document",
        ),
    )

    damages = _read_damage_items(
        case_reference,
        case_data,
    )

    return ReportInput(
        accident_number=accident_number,
        user=user,
        vehicle=vehicle,
        damages=damages,
    )


@router.post("/cases/{case_id}/generate")
def generate_case_report(case_id: str):
    """
    Generate an official report once for a reviewed accident case.

    First request:
      * creates and stores the signed report record,
      * creates the real verification QR,
      * builds the final PDF,
      * saves the PDF fingerprint,
      * uploads the exact PDF to Firebase Storage,
      * links the report to the accident case.

    Later requests:
      * return the same reportId and reportPdfUrl,
      * do not allocate a new report number.
    """
    case_id = case_id.strip()

    if not case_id:
        raise HTTPException(
            status_code=400,
            detail="case_id is required",
        )

    db = firestore.client()

    case_reference = (
        db.collection("accidentCase")
        .document(case_id)
    )

    case_snapshot = case_reference.get()

    if not case_snapshot.exists:
        raise HTTPException(
            status_code=404,
            detail=f"Case not found: {case_id}",
        )

    case_data = case_snapshot.to_dict() or {}

    # The report was already issued for this case:
    # return the same stored PDF instead of creating another report number.
    existing_report_id = case_data.get("reportId")
    existing_pdf_url = case_data.get("reportPdfUrl")
    existing_pdf_path = case_data.get("reportPdfPath")

    if existing_report_id and existing_pdf_url:
        return {
            "created": False,
            "message": "Report already exists",
            "caseId": case_id,
            "reportId": existing_report_id,
            "reportNumber": case_data.get("reportNumber"),
            "verifyUrl": case_data.get("reportVerifyUrl"),
            "pdfUrl": existing_pdf_url,
            "pdfPath": existing_pdf_path,
        }

    current_status = str(case_data.get("status") or "").strip()

    if current_status != _ALLOWED_STATUS:
        raise HTTPException(
            status_code=409,
            detail=(
                "The report can only be generated when the case status is "
                f"'{_ALLOWED_STATUS}'. "
                f"Current status: '{current_status or 'غير محدد'}'"
            ),
        )

    owner_id = _required_text(
        case_data,
        "ownerId",
        source_name="case document",
    )

    vehicle_id = _required_text(
        case_data,
        "vehicleId",
        source_name="case document",
    )

    user_snapshot = (
        db.collection("users")
        .document(owner_id)
        .get()
    )

    if not user_snapshot.exists:
        raise HTTPException(
            status_code=404,
            detail=f"User document not found: {owner_id}",
        )

    vehicle_snapshot = (
        db.collection("vehicles")
        .document(vehicle_id)
        .get()
    )

    if not vehicle_snapshot.exists:
        raise HTTPException(
            status_code=404,
            detail=f"Vehicle document not found: {vehicle_id}",
        )

    user_data = user_snapshot.to_dict() or {}
    vehicle_data = vehicle_snapshot.to_dict() or {}

    # Validate all required case data before allocating an official report number.
    report_input = _build_report_input(
        case_reference=case_reference,
        case_data=case_data,
        user_data=user_data,
        vehicle_data=vehicle_data,
    )

    store = get_store()

    try:
        # Handoff Step B:
        # create, sign and store the report record, then create its real QR.
        record, verify_url, qr_png = verification_service.create_report(
            report_input,
            BASE_URL,
            store,
        )

        # Build the final PDF using that exact QR image.
        pdf_bytes = build_report_pdf(
            record=record,
            qr_png=qr_png,
        )

        # Handoff Step C:
        # attach the SHA-256 fingerprint of this exact finalized PDF.
        record = verification_service.attach_pdf_hash(
            report_id=record.report_id,
            pdf_bytes=pdf_bytes,
            store=store,
        )

        # Keep the exact PDF so later requests open the same file.
        pdf_path, pdf_url = upload_report_pdf(
            case_id=case_id,
            report_id=record.report_id,
            pdf_bytes=pdf_bytes,
        )

        # Link the active report to the accident case.
        case_reference.update({
            "reportId": record.report_id,
            "reportNumber": record.report_number,
            "reportPdfPath": pdf_path,
            "reportPdfUrl": pdf_url,
            "reportVerifyUrl": verify_url,
            "reportCreatedAt": firestore.SERVER_TIMESTAMP,
        })

        return {
            "created": True,
            "message": "Report generated successfully",
            "caseId": case_id,
            "reportId": record.report_id,
            "reportNumber": record.report_number,
            "verifyUrl": verify_url,
            "pdfUrl": pdf_url,
            "pdfPath": pdf_path,
        }

    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to generate report: {exc}",
        ) from exc