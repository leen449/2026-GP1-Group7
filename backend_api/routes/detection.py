from fastapi import APIRouter, BackgroundTasks
from firebase_admin import firestore
from services.damage_detection import process_damage_detection
from services.cost_estimation_services import process_cost_estimation
router = APIRouter()

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

    On success, `status` is re-set to "تم الفحص" once cost estimation finishes,
    REGARDLESS of the cost step's own outcome: neither the mobile app nor the
    report currently key off cost's own status values ("تم حساب التكلفة" /
    "فشل حساب التكلفة"), so "تم الفحص" stays the single terminal signal existing
    (and eventually report/case-details) screens rely on. Cost's own success or
    failure is still fully recorded on the case (costError/costStartedAt/
    estimatedCostSar/needsAdminReview) for backend and future UI use — only the
    outward `status` string is pinned back.
    """
    try:
        detection_result = await process_damage_detection(case_id)
        if detection_result.get("status") != "success":
            return
        await process_cost_estimation(case_id)
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