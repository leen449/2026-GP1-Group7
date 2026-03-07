from fastapi import APIRouter, UploadFile, File
from services.ocr_services import process_ocr

router = APIRouter()


@router.post("/")
async def run_ocr(file: UploadFile = File(...)):
    return await process_ocr(file)