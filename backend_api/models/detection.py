from pydantic import BaseModel
from typing import List


class DamageBox(BaseModel):
    label: str
    confidence: float
    x1: float
    y1: float
    x2: float
    y2: float


class ImageAnalysisResult(BaseModel):
    imageUrl: str
    damages: List[DamageBox]


class DamageAnalysisResponse(BaseModel):
    caseId: str
    results: List[ImageAnalysisResult]