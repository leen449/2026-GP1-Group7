"""
damage_mask_service.py — damage-segmentation MASKS for severity (production).

Mirrors part_segmentation_service.py: the model is loaded once at import and reused. For
one image it returns damage instances (class label, confidence, bbox, binary mask).

Weights: the PREVIOUS / best CarDD segmentation run (yolov8s-seg) — NOT the tuned v2
weights, which scored worse on the 31 real expert-priced photos (see
services/severity_fusion_mask.py's docstring). conf/iou match that run's selected
validation threshold.

This is an ADDITIVE model: the existing bbox damage detector (damage_detection.py) and
its stored Firestore detections are completely unchanged and still drive detection/
association/cost. This model's masks are consumed ONLY by severity_fusion_mask's extent
ratio — see cost_estimation_services._stage_image.
"""
import numpy as np

try:
    import cv2
except Exception:
    cv2 = None

from ultralytics import YOLO

MODEL_PATH = "weight/best-seg-detection.pt"
DAMAGE_SEG_CONF = 0.15
DAMAGE_SEG_IOU = 0.50
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


def segment_damages(image, conf: float = DAMAGE_SEG_CONF, iou: float = DAMAGE_SEG_IOU):
    """
    Returns a list of dicts, one per detected damage instance:
        {label: str, confidence: float, bbox: (x1,y1,x2,y2), mask: bool ndarray HxW}
    Masks are rasterized in ORIGINAL image coordinates, same convention as
    part_segmentation_service.segment_parts, so they align with part masks for the
    severity extent ratio.
    """
    r = _load()(image, conf=conf, iou=iou, verbose=False)[0]
    out = []
    if r.masks is None:
        return out
    h, w = r.orig_shape
    names = r.names
    polys = r.masks.xy
    for i in range(len(r.boxes)):
        box = r.boxes.xyxy[i].cpu().numpy().astype(int)
        out.append({
            "label": names[int(r.boxes.cls[i])],
            "confidence": float(r.boxes.conf[i]),
            "bbox": tuple(int(v) for v in box.tolist()),
            "mask": _mask_to_orig(polys[i] if i < len(polys) else None, h, w),
        })
    return out
