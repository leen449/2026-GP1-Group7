from fastapi import FastAPI
# Import routers from different route files
from routes.ocr import router as ocr_router

# Create FastAPI
app = FastAPI()

# Include routers
app.include_router(ocr_router, prefix="/ocr", tags=["OCR"])

@app.get("/")
def root():
    return {"message": "Backend is running"}