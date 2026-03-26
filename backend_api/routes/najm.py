from fastapi import APIRouter
from services.najm_services import process_najm_ocr
from models.ocr_models import NajmOCRResponse, NajmStructuredData

router = APIRouter()


@router.post("/{case_id}", response_model=NajmOCRResponse)
async def run_najm_ocr(case_id: str):
    """
    POST /ocr/najm/{case_id}

    Reads the pdfBase64 from Firestore for the given case,
    extracts accidentNumber, accidentDate, damageLocation,
    updates Firestore, and returns the extracted data.

    Called by Flutter after a successful case submission.
    """
    result = await process_najm_ocr(case_id)

    if result['status'] == 'success':
        return NajmOCRResponse(
            status='success',
            data=NajmStructuredData(
                accident_number=result['data']['accidentNumber'],
                accident_date=result['data']['accidentDate'],
                damage_location=result['data']['damageLocation'],
            ),
            message=None,
        )
    else:
        return NajmOCRResponse(
            status='error',
            data=None,
            message=result.get('message', 'Unknown error'),
        )