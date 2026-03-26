import firebase_admin
from firebase_admin import credentials
from fastapi import FastAPI

# Import routers
from routes.ocr import router as ocr_router
from routes.najm import router as najm_router


# ─────────────────────────────────────────────────────────────────────
# Firebase Admin — initialize once at startup
# All services (najm_services, ocr_services) will reuse this instance
# ─────────────────────────────────────────────────────────────────────
if not firebase_admin._apps:
    cred = credentials.Certificate('serviceAccountKey.json')
    firebase_admin.initialize_app(cred)
    print("✅ Firebase Admin initialized in main.py")


# ─────────────────────────────────────────────────────────────────────
# FastAPI app
# ─────────────────────────────────────────────────────────────────────
app = FastAPI(
    title="CrashLens Backend",
    description="Vehicle damage OCR and case management API",
    version="1.0.0",
)

# Include routers
app.include_router(ocr_router,  prefix="/ocr",       tags=["OCR"])
app.include_router(najm_router, prefix="/ocr/najm",  tags=["Najm OCR"])


@app.get("/")
def root():
    return {"message": "Backend is running"}