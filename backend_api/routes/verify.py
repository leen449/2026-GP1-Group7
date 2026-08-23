"""
CrashLens · report verification routes.

Endpoints:
  POST /verify/issue        (internal) create+sign a report, store it, return QR
  GET  /verify/{id}         (public)   the human-readable verification page
  GET  /verify/{id}/qr.png  (public)   the QR image, e.g. to embed in the PDF

Wire into main.py exactly like the other routers:
    from routes.verify import router as verify_router
    app.include_router(verify_router, tags=["Verification"])
"""
from __future__ import annotations
import os, uuid, base64
from fastapi import APIRouter, HTTPException, Response
from fastapi.responses import HTMLResponse

from models.report import ReportInput
from services import report_verification_service as svc
from services.report_store import get_store

# One setting to change for deployment: local IP now, real domain later.
BASE_URL = os.environ.get("CRASHLENS_BASE_URL", "http://172.20.10.2:8000")

router = APIRouter()


@router.post("/verify/issue")
def issue_report(data: ReportInput):
    """Called when the admin finalizes a case. Returns the verify URL + QR."""
    store = get_store()
    report_id = str(uuid.uuid4())                       # unguessable
    report_number = svc.format_report_number(store.next_seq())
    record = svc.build_report_record(data, report_id, report_number)
    store.save(record)

    url = svc.verify_url(BASE_URL, report_id)
    qr_png = svc.make_qr_png(url)
    return {
        "report_id": report_id,
        "report_number": report_number,
        "verify_url": url,
        "qr_png_base64": base64.b64encode(qr_png).decode(),   # for the PDF/app
    }


@router.get("/verify/{report_id}", response_class=HTMLResponse)
def verify_page(report_id: str):
    record = get_store().get(report_id)
    if record is None:
        raise HTTPException(status_code=404, detail="No such report")
    valid = svc.verify_record(record)                   # re-checked on every load
    return HTMLResponse(svc.render_verify_html(record, valid))


@router.get("/verify/{report_id}/qr.png")
def verify_qr(report_id: str):
    if get_store().get(report_id) is None:
        raise HTTPException(status_code=404, detail="No such report")
    png = svc.make_qr_png(svc.verify_url(BASE_URL, report_id))
    return Response(content=png, media_type="image/png")
