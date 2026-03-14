from fastapi import APIRouter
from services.najm_services import process_najm_ocr

router = APIRouter()


@router.post("/{case_id}")
async def run_najm_ocr(case_id: str):
    """
    POST /ocr/najm/{case_id}

    Reads the pdfBase64 from Firestore for the given case,
    extracts accidentNumber, accidentDate, damageLocation,
    updates Firestore, and returns the extracted data.

    Called by Flutter after a successful case submission.
    """
    return await process_najm_ocr(case_id)