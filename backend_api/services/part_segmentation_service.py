"""
part_segmentation_service.py — vehicle PART segmentation (STAGING).

Mirrors damage_detection.py: the model is loaded once at import and reused. For one
image it returns part instances (canonical class name, confidence, bbox, binary mask).

Weights: the exp04 model (HITL-trained yolov8s-seg). It was trained on all 16 canonical
classes (8 panels + 8 supporting glass/lamp/wheel/etc.), so it emits those too — the
association layer decides which to trust for costing.

⚠️ STAGING ONLY. Real-domain panel accuracy is unmeasured (n≈4 real panel images) and
   the model over-fires / mislabels on extreme close-ups. Use this to run the pipeline
   end-to-end on test images, NOT to cost real user claims.
"""
import numpy as np

try:
    import cv2
except Exception:
    cv2 = None

from ultralytics import YOLO

MODEL_PATH = "weight/part_seg_exp04.pt"   # copy exp04 best.pt here
PART_CONF = 0.25
_model = None


def _load():
    global _model
    if _model is None:
        _model = YOLO(MODEL_PATH)
    return _model


def _mask_to_orig(polygon_xy, h, w):
    """Rasterize an Ultralytics polygon (orig-image coords) to a bool HxW mask."""
    m = np.zeros((h, w), dtype=np.uint8)
    if cv2 is not None and polygon_xy is not None and len(polygon_xy) >= 3:
        cv2.fillPoly(m, [np.asarray(polygon_xy, dtype=np.int32)], 1)
    return m.astype(bool)


def segment_parts(image, conf: float = PART_CONF):
    """
    Returns a list of dicts, one per detected part instance:
        {label: str, confidence: float, bbox: (x1,y1,x2,y2), mask: bool ndarray HxW}
    Masks are rasterized in ORIGINAL image coordinates so they align with the damage
    boxes from damage_detection.py.
    """
    r = _load()(image, conf=conf, verbose=False)[0]
    out = []
    if r.masks is None:
        return out
    h, w = r.orig_shape
    names = r.names
    polys = r.masks.xy  # list of (K,2) arrays in original-image pixel coords
    for i in range(len(r.boxes)):
        box = r.boxes.xyxy[i].cpu().numpy().astype(int)
        out.append({
            "label": names[int(r.boxes.cls[i])],
            "confidence": float(r.boxes.conf[i]),
            "bbox": tuple(int(v) for v in box.tolist()),
            "mask": _mask_to_orig(polys[i] if i < len(polys) else None, h, w),
        })
    return out
