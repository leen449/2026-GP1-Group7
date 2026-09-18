from fastapi import APIRouter, BackgroundTasks, HTTPException
from firebase_admin import firestore
from services.damage_detection import process_damage_detection
from pydantic import BaseModel
from services.cost_estimation_services import (
    process_cost_estimation,
    add_admin_damage,
    update_admin_damage,
    delete_admin_damage,
    CostEstimationAbort,
)
router = APIRouter()

# Defines the data sent by the admin when manually adding a missing damage.
# The request includes the selected image, damage type, vehicle part, and severity
class AdminDamageRequest(BaseModel):
    imageId: str
    damageType: str
    part: str
    severity: str


# Receives a manually added damage from the admin interface and sends it to the cost estimation service for validation, cost calculation, and storage in Firestore.
@router.post("/admin/cases/{case_id}/damages")
async def create_admin_damage(
    case_id: str,
    request: AdminDamageRequest,
):
    try:
        return await add_admin_damage(
            case_id=case_id,
            image_id=request.imageId,
            damage_type=request.damageType,
            part=request.part,
            severity=request.severity,
        )
    except CostEstimationAbort as e:
        raise HTTPException(
            status_code=400,
            detail=str(e),
        )
class AdminDamageUpdateRequest(BaseModel):
    damageType: str
    part: str
    severity: str

@router.patch(
    "/admin/cases/{case_id}/images/{image_id}/cost-items/{item_id}"
)
async def edit_admin_damage(
    case_id: str,
    image_id: str,
    item_id: str,
    request: AdminDamageUpdateRequest,
):
    try:
        return await update_admin_damage(
            case_id=case_id,
            image_id=image_id,
            item_id=item_id,
            damage_type=request.damageType,
            part=request.part,
            severity=request.severity,
        )
    except CostEstimationAbort as e:
        raise HTTPException(
            status_code=400,
            detail=str(e),
        )

@router.delete(
    "/admin/cases/{case_id}/images/{image_id}/cost-items/{item_id}"
)
async def remove_admin_damage(
    case_id: str,
    image_id: str,
    item_id: str,
):
    try:
        return await delete_admin_damage(
            case_id=case_id,
            image_id=image_id,
            item_id=item_id,
        )
    except CostEstimationAbort as e:
        raise HTTPException(
            status_code=400,
            detail=str(e),
        )

@router.post("/cost/{case_id}")
async def cost(case_id: str):
    return await process_cost_estimation(case_id)


async def _analyze_and_cost(case_id: str):
    """
    Chains cost estimation onto detection so the pipeline runs as one background
    job: detection -> (part) segmentation -> severity -> cost. Severity is already
    computed inside process_damage_detection on the whole image, independent of
    segmentation (see CLAUDE.md's pipeline note), so nothing about severity itself
    needs to move for this ordering — only cost estimation (which does the
    segmentation) needs to be chained after detection finishes.

    Only proceeds to cost estimation if detection actually succeeded. A detection
    failure is left exactly as process_damage_detection already reports it
    ("فشل الفحص" + detectionError) — nothing chained, status untouched.

    After a finalized complete/partial cost result, `status` is re-set to
    "تم الفحص" so existing screens keep a single terminal signal. A cost error
    keeps the cost step's own failure status ("فشل حساب التكلفة") instead of
    being overwritten as if inspection succeeded.
    """
    try:
        detection_result = await process_damage_detection(case_id)
        if detection_result.get("status") != "success":
            return
        cost_result = await process_cost_estimation(case_id)
        if cost_result.get("status") == "success":
            firestore.client().collection("accidentCase").document(case_id).update({
                "status": "تم الفحص",
            })
    except Exception as e:
        print(f"⚠️ analyze->cost chain failed for {case_id}: {e}")


@router.post("/analyze/{case_id}", status_code=202)
async def analyze_damage(case_id: str, background_tasks: BackgroundTasks):
    """
    Asynchronous Request-Reply.

    Returns 202 Accepted immediately and runs detection -> segmentation -> severity
    -> cost in the background (see _analyze_and_cost). The mobile app does NOT wait
    for the result — it already observes the case through a Firestore snapshot
    listener, so the outcome is pushed to it as soon as the service writes it.

    This makes the backend the single writer of `status`: the app never has to
    guess an outcome from a network timeout, because it is no longer waiting
    for one.

    Note: BackgroundTasks runs the work inside this same uvicorn process. If
    the process is restarted mid-run (including by --reload on file save), the
    task is lost and the case is left at "قيد التحليل" (or, if cost estimation
    was mid-flight, at "قيد حساب التكلفة" internally before status gets pinned
    back). That stalled state is detectable via analysisStartedAt/costStartedAt
    and recoverable by calling this endpoint again (detection re-runs; cost
    re-runs as part of the chain, or can be retried alone via POST /cost/{case_id}).
    """
    background_tasks.add_task(_analyze_and_cost, case_id)
    return {"status": "accepted", "caseId": case_id}