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