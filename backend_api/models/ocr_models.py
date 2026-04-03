from pydantic import BaseModel
from typing import List, Optional
 
 
class OCRStructuredData(BaseModel):
    """Represents the extracted vehicle fields from the registration card"""
    plate_number:       Optional[str] = ""
    make:               Optional[str] = ""
    model:              Optional[str] = ""
    manufacturing_year: Optional[str] = ""
    color:              Optional[str] = ""
    chassis_number:     Optional[str] = ""
 
 
class OCRResponse(BaseModel):
    """Full response returned by the /ocr/ endpoint"""
    status:   str
    raw_text: List[str]
    data:     OCRStructuredData

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
