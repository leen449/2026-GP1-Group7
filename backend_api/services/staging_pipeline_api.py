"""
staging_pipeline_api.py — end-to-end cost estimation, exposed in Swagger UI (STAGING).

Run:
    pip install fastapi "uvicorn[standard]" python-multipart ultralytics pillow numpy
    uvicorn staging_pipeline_api:app --reload
Then open  http://127.0.0.1:8000/docs  and try POST /estimate with an image.

Pipeline:  image
  -> damage detection (YOLO boxes + damage type)
  -> part segmentation (YOLO-seg masks + part)          [part_segmentation_service]
  -> association (IoA-multi, damage-priority glass/lamp/tire, centroid fallback)
  -> labor hours (labor_hours_lookup) x rate 165
  -> x F_paint x F_vehicle x F_severity
  -> confidence score (separate, never changes the cost)

⚠️ STAGING ONLY. Real-domain panel accuracy is unmeasured and the part model over-fires
   on close-ups. Use this to watch the chain run on your own images, not to cost real
   claims. Every stage degrades gracefully so /docs always loads.
"""
import io, os
from typing import Optional
import numpy as np
from fastapi import FastAPI, UploadFile, File, Form
from fastapi.responses import RedirectResponse
from PIL import Image

from part_association_service import associate, CostLine

RATE_SAR = 165.0
DAMAGE_WEIGHTS = os.environ.get("DAMAGE_WEIGHTS", "weight/best.pt")
PART_WEIGHTS   = os.environ.get("PART_WEIGHTS", "weight/part_seg_exp04.pt")

# ---- defensive imports: real services when present, safe fallbacks otherwise -------
def _one(*_a, **_k):        # neutral factor
    return 1.0
try:
    from labor_hours_lookup import get_hours, get_unmapped_hours
except Exception:
    def get_hours(*a, **k): return None
    def get_unmapped_hours(*a, **k): return None
try:
    from severity_factor_services import get_severity_factor
except Exception:
    get_severity_factor = _one
try:
    from vehicle_factor_services import get_vehicle_factor
except Exception:
    get_vehicle_factor = _one
try:
    from paint_factor_services import get_paint_factor
except Exception:
    def get_paint_factor(*a, **k): return 1.0
try:
    from confidence_service import assess_confidence
except Exception:
    def assess_confidence(**k): return {"confidence_score": None, "level": "unknown",
                                        "requires_admin_review": None, "reasons_ar": []}

# ---- lazy model loaders -----------------------------------------------------------
_damage_model = None
_part_seg = None

def _run_damage(img_np):
    global _damage_model
    from ultralytics import YOLO
    if _damage_model is None:
        _damage_model = YOLO(DAMAGE_WEIGHTS)
    r = _damage_model(img_np, verbose=False)[0]
    out = []
    if r.boxes is not None:
        for i in range(len(r.boxes)):
            b = r.boxes.xyxy[i].cpu().numpy().astype(int)
            out.append({"label": r.names[int(r.boxes.cls[i])],
                        "bbox": tuple(int(v) for v in b.tolist()),
                        "confidence": float(r.boxes.conf[i])})
    return out

def _run_parts(img_np):
    global _part_seg
    if _part_seg is None:
        import part_segmentation_service as pss
        _part_seg = pss
    return _part_seg.segment_parts(img_np)


def _wheel_pos(najm_zone):
    z = (najm_zone or "").lower()
    if "front" in z or "مقدم" in z: return "front"
    if "rear" in z or "back" in z or "خلف" in z or "مؤخر" in z: return "rear"
    return None


def _hours_for(line: CostLine):
    """Look up hours, falling back to UNMAPPED_PARTS for fender/sill/roof."""
    if line.lookup_key is None:
        return None
    wp = None  # wheel position resolved upstream via najm; kept simple here
    h = get_hours(line.lookup_key, line.damage_type)
    if h is None and "promote_lookup" in line.flags:
        h = get_unmapped_hours(line.lookup_key, line.damage_type)
    return h


def build_estimate(damages, parts, image_hw, *, najm_zone=None, severity="moderate",
                   vehicle_value_sar=None, paint_color=None, vehicle_year=None,
                   current_year=None, prior_accident_same_location=None,
                   airbag_deployed=None):
    """Pure assembly step — the testable core of the endpoint."""
    lines = associate(damages, parts, image_hw, najm_zone=najm_zone)

    items, labor_subtotal, review = [], 0.0, False
    for ln in lines:
        h = _hours_for(ln)
        row = {"damage_type": ln.damage_type, "part": ln.part, "lookup_key": ln.lookup_key,
               "source": ln.source, "ioa": round(ln.ioa, 3), "part_conf": round(ln.part_conf, 3),
               "hours": h, "line_cost_sar": None, "flags": list(ln.flags)}
        if h is None:
            row["flags"].append("no_hours" if ln.lookup_key else "unassigned")
            review = True
        else:
            cost = h * RATE_SAR
            row["line_cost_sar"] = round(cost, 2)
            labor_subtotal += cost
        if ln.source in ("centroid_fallback", "unassigned") or ln.flags:
            review = True
        items.append(row)

    f_paint = float(get_paint_factor(paint_color) if paint_color else 1.0)
    f_veh   = float(get_vehicle_factor(vehicle_value_sar))
    f_sev   = float(get_severity_factor(severity))
    base = labor_subtotal * f_paint * f_veh * f_sev

    conf = assess_confidence(vehicle_year=vehicle_year, current_year=current_year,
                             estimated_cost=base, vehicle_value_sar=vehicle_value_sar,
                             airbag_deployed=airbag_deployed,
                             prior_accident_same_location=prior_accident_same_location)

    return {
        "staging": True,
        "line_items": items,
        "labor_subtotal_sar": round(labor_subtotal, 2),
        "rate_sar_per_hour": RATE_SAR,
        "factors": {"paint": f_paint, "vehicle": f_veh, "severity": f_sev},
        "estimated_cost_sar": round(base, 2),
        "confidence": conf,
        "needs_admin_review": bool(review or conf.get("requires_admin_review")),
    }


app = FastAPI(title="CrashLens — Staging Cost Pipeline", version="0.1-staging")

@app.get("/", include_in_schema=False)
def _root():
    return RedirectResponse("/docs")

@app.post("/estimate")
async def estimate(
    image: UploadFile = File(..., description="Damage photo"),
    najm_zone: Optional[str] = Form(None, description="e.g. 'front' / 'rear' — from Najm report"),
    severity: str = Form("moderate", description="minor | moderate | severe"),
    vehicle_value_sar: Optional[float] = Form(None),
    paint_color: Optional[str] = Form(None),
    vehicle_year: Optional[int] = Form(None),
    current_year: Optional[int] = Form(None),
    prior_accident_same_location: Optional[bool] = Form(None),
    airbag_deployed: Optional[bool] = Form(None),
):
    img = Image.open(io.BytesIO(await image.read())).convert("RGB")
    img_np = np.array(img)
    H, W = img_np.shape[:2]
    damages = _run_damage(img_np)
    parts = _run_parts(img_np)
    result = build_estimate(
        damages, parts, (H, W), najm_zone=najm_zone, severity=severity,
        vehicle_value_sar=vehicle_value_sar, paint_color=paint_color,
        vehicle_year=vehicle_year, current_year=current_year,
        prior_accident_same_location=prior_accident_same_location,
        airbag_deployed=airbag_deployed,
    )
    result["detections"] = {"damages": damages,
                            "parts": [{"label": p["label"], "confidence": round(p["confidence"], 3)}
                                      for p in parts]}
    return result
