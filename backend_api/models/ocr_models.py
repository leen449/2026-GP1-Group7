from pydantic import BaseModel
from typing import List, Any, Optional


class OCRStructuredData(BaseModel):
    plate_number: Optional[str] = ""
    chassis_number: Optional[str] = ""
    vehicle_brand: Optional[str] = ""
    color: Optional[str] = ""
    manufacturing_year: Optional[str] = ""
    serial_number: Optional[str] = ""
    owner_name: Optional[str] = ""
    user_name: Optional[str] = ""


class OCRResponse(BaseModel):
    raw_text: List[str]
    raw_result: List[Any]
    structured_data: OCRStructuredData

# ─────────────────────────────────────────────────────────────────
# Najm Report Models
# ─────────────────────────────────────────────────────────────────
class NajmStructuredData(BaseModel):
    accident_number:  Optional[str] = ""
    accident_date:    Optional[str] = ""
    damage_location:  Optional[str] = ""

class NajmOCRResponse(BaseModel):
    status:  str                        # "success" or "error"
    data:    Optional[NajmStructuredData] = None
    message: Optional[str] = None      # error message if status == "error"
