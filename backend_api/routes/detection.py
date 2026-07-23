from fastapi import APIRouter, BackgroundTasks
from services.damage_detection import process_damage_detection

router = APIRouter()


@router.post("/analyze/{case_id}", status_code=202)
async def analyze_damage(case_id: str, background_tasks: BackgroundTasks):
    """
    Asynchronous Request-Reply.

    Returns 202 Accepted immediately and runs the analysis in the background.
    The mobile app does NOT wait for the result — it already observes the case
    through a Firestore snapshot listener, so the outcome is pushed to it as
    soon as the service writes it.

    This makes the backend the single writer of `status`: the app never has to
    guess an outcome from a network timeout, because it is no longer waiting
    for one.

    Note: BackgroundTasks runs the work inside this same uvicorn process. If
    the process is restarted mid-analysis (including by --reload on file save),
    the task is lost and the case is left at "قيد التحليل". That stalled state
    is detectable via analysisStartedAt and recoverable by calling this
    endpoint again.
    """
    background_tasks.add_task(process_damage_detection, case_id)
    return {"status": "accepted", "caseId": case_id}