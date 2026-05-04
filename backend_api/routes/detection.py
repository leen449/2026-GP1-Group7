from fastapi import APIRouter
from services.damage_detection import process_damage_detection

router = APIRouter()
@router.post("/analyze/{case_id}")
async def analyze_damage(case_id: str):
    # The service handles EVERYTHING now!
    result = await process_damage_detection(case_id)
    
    if result["status"] == "error":
        # You could return a 400 or 500 status code here if desired
        return result
        
    return result