import re
import base64
import fitz
import firebase_admin
from firebase_admin import firestore, credentials, storage
import cv2
import numpy as np
import easyocr
import unicodedata

reader = easyocr.Reader(['ar', 'en'], gpu=False)


def _ensure_firebase_initialized():
    if not firebase_admin._apps:
        try:
            cred = credentials.Certificate("serviceAccountKey.json")
            firebase_admin.initialize_app(cred, {
                'storageBucket': 'crashlens-233bf.firebasestorage.app'
            })
            print("✅ Firebase Admin initialized in najm_services")
        except Exception as e:
            print(f"❌ Firebase Admin initialization failed: {e}")
            raise



def _normalize(text: str) -> str:
    if not text:
        return ""

    # Convert Arabic presentation forms to normal Unicode letters
    text = unicodedata.normalize("NFKC", text)

    # Arabic/Hindi digits -> English digits
    text = text.translate(str.maketrans(
        "٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹",
        "01234567890123456789"
    ))

    replacements = {
        "أ": "ا",
        "إ": "ا",
        "آ": "ا",
        "ى": "ي",
        "ة": "ه",
        "ؤ": "و",
        "ئ": "ي",
        "ـ": "",
    }
    for old, new in replacements.items():
        text = text.replace(old, new)

    text = text.replace("：", ":")
    text = text.replace("،", ",")
    text = re.sub(r"\s+", " ", text).strip()
    return text


def _extract_text_from_base64_pdf(pdf_base64: str) -> list[str]:
    pdf_bytes = base64.b64decode(pdf_base64)
    pdf_doc = fitz.open(stream=pdf_bytes, filetype="pdf")

    all_lines = []

    for page_index, page in enumerate(pdf_doc):
        text = page.get_text("text")
        lines = [line.strip() for line in text.split("\n") if line.strip()]

        print(f"\n--- PAGE {page_index + 1} RAW LINES ---")
        for line in lines:
            print(line)

        all_lines.extend(lines)

    print(f"\n   [Najm OCR] Extracted {len(all_lines)} lines from PDF")
    return all_lines

    
def _extract_text_from_pdf_bytes(pdf_bytes: bytes) -> list[str]:
        pdf_doc = fitz.open(stream=pdf_bytes, filetype="pdf")

        all_lines = []

        for page_index, page in enumerate(pdf_doc):
         text = page.get_text("text")
         lines = [line.strip() for line in text.split("\n") if line.strip()]
         print(f"\n--- PAGE {page_index + 1} RAW LINES ---")
         
         for line in lines:
            print(line)
            all_lines.extend(lines)

        print(f"\n   [Najm OCR] Extracted {len(all_lines)} lines from PDF")
        return all_lines


def _download_pdf_bytes_from_storage(pdf_path: str) -> bytes:
    bucket = storage.bucket('crashlens-233bf.firebasestorage.app')
    blob = bucket.blob(pdf_path)

    if not blob.exists():
        raise FileNotFoundError(f"Storage file not found: {pdf_path}")

    return blob.download_as_bytes()


def _joined_text(lines: list[str]) -> str:
    return "\n".join(_normalize(line) for line in lines if line.strip())

def _pdf_page_to_image(pdf_bytes: bytes, page_index: int) -> np.ndarray:
    doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    if page_index >= len(doc):
        return None

    page = doc[page_index]
    pix = page.get_pixmap(matrix=fitz.Matrix(2, 2))

    img = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.height, pix.width, pix.n)

    if pix.n == 4:
        img = cv2.cvtColor(img, cv2.COLOR_RGBA2BGR)
    else:
        img = cv2.cvtColor(img, cv2.COLOR_RGB2BGR)

    return img


def _extract_accident_number_from_barcode_area(pdf_bytes: bytes) -> str:
    try:
        # Usually the barcode is on page 2 in your Najm reports
        img = _pdf_page_to_image(pdf_bytes, 1)
        if img is None:
            return ""

        h, w = img.shape[:2]

        # Crop top-center area where barcode usually appears
        crop = img[0:int(h * 0.28), int(w * 0.15):int(w * 0.85)]

        gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
        gray = cv2.GaussianBlur(gray, (3, 3), 0)
        _, thresh = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)

        results = reader.readtext(thresh, detail=0)
        print(f"[BARCODE OCR RAW] {results}")

        for text in results:
            normalized = _normalize(text).replace(" ", "")
            # Added \d{7,10} to catch raw digits if the prefix is mangled
            match = re.search(r"\b([A-Z]{1,3}\d{6,}[A-Z]{0,3}|\d{6,}[A-Z]{1,3}|\d{7,10})\b", normalized, re.IGNORECASE)
            if match:
                candidate = match.group(1).strip()

                # Reject obvious Najm hotline false positive
                if candidate != "920000560":
                    return candidate

        return ""

    except Exception as e:
        print(f"[BARCODE OCR ERROR] {e}")
        return ""
    
def _extract_accident_number(lines: list[str], pdf_bytes: bytes | None = None) -> str:
    normalized_lines = [_normalize(line) for line in lines]

    labels = [
        "رقم الحاله",
        "الحاله رقم",
        "رقم الحادث",
        "الحادث رقم",
    ]

    for i, line in enumerate(normalized_lines):
        if any(label in line for label in labels):
            print(f"[ACCIDENT NUMBER LABEL LINE] {line}")

            # 1) merged label + value
            m = re.search(r"(?:رقم الحاله|الحاله رقم|رقم الحادث|الحادث رقم)([A-Z]{1,3}\d{6,}[A-Z]{0,3}|\d{6,}[A-Z]{1,3})", line, re.IGNORECASE)
            if m:
                candidate = m.group(1).strip()
                if candidate != "920000560": return candidate

            # 2) same line with colon
            m = re.search(r"(?:رقم الحاله|الحاله رقم|رقم الحادث|الحادث رقم)\s*:\s*([A-Z]{1,3}\d{6,}[A-Z]{0,3}|\d{6,}[A-Z]{1,3}|[A-Z]*\d+[A-Z]*)", line, re.IGNORECASE)
            if m:
                candidate = m.group(1).strip()
                if candidate != "920000560": return candidate

            # 3) same line with space but no colon
            m = re.search(r"(?:رقم الحاله|الحاله رقم|رقم الحادث|الحادث رقم)\s+([A-Z]{1,3}\d{6,}[A-Z]{0,3}|\d{6,}[A-Z]{1,3}|[A-Z]*\d+[A-Z]*)", line, re.IGNORECASE)
            if m:
                candidate = m.group(1).strip()
                if candidate != "920000560": return candidate

            # 4) look in nearby lines only
            for j in range(max(0, i - 1), min(i + 3, len(normalized_lines))):
                nearby = normalized_lines[j]
                m = re.search(r"\b([A-Z]{1,3}\d{6,}[A-Z]{0,3}|\d{6,}[A-Z]{1,3})\b", nearby, re.IGNORECASE)
                if m:
                    candidate = m.group(1).strip()
                    if candidate != "920000560": return candidate

    # 5) fallback: OCR barcode area
    # DEDENTED: This is now outside the loop so it only runs once!
    if pdf_bytes:
        barcode_candidate = _extract_accident_number_from_barcode_area(pdf_bytes)
        if barcode_candidate and barcode_candidate != "920000560":
            print(f"[ACCIDENT NUMBER MATCH - BARCODE OCR] {barcode_candidate}")
            return barcode_candidate

    return ""


def _extract_accident_date(lines: list[str]) -> str:
    normalized_lines = [_normalize(line) for line in lines]

    label_patterns = [
        "تاريخ الحادث",
        "الحادث تاريخ",
    ]

    date_patterns = [
        # 09/07/2023 06:32:47 AM
        r"(\d{1,2}/\d{1,2}/\d{4}\s+\d{1,2}:\d{2}:\d{2}\s*(?:AM|PM))",
        # AM 06:32:47 09/07/2023
        r"((?:AM|PM)\s+\d{1,2}:\d{2}:\d{2}\s+\d{1,2}/\d{1,2}/\d{4})",
        # just date
        r"(\d{1,2}/\d{1,2}/\d{4})",
    ]

    for i, line in enumerate(normalized_lines):
        if any(label in line for label in label_patterns):
            # same line
            for pattern in date_patterns:
                m = re.search(pattern, line, re.IGNORECASE)
                if m:
                    return m.group(1).strip()

            # nearby lines
            for j in range(max(0, i - 2), min(len(normalized_lines), i + 3)):
                nearby = normalized_lines[j]
                for pattern in date_patterns:
                    m = re.search(pattern, nearby, re.IGNORECASE)
                    if m:
                        return m.group(1).strip()

    return ""



def _clean_damage_value(value: str) -> str:
    value = _normalize(value)

    blocked = [
        "الضرر القديم",
        "الضرر الجديد",
        "توقيع الطرف",
        "الرسم التوضيحي",
        "الرسم التقريبي",
    ]

    if not value:
        return ""

    for b in blocked:
        if b in value:
            return ""

    return value.strip(" :.-")


def _extract_damage_location(lines: list[str]) -> str:
    normalized_lines = [_normalize(line) for line in lines]

    keywords = [
        "مكان الضرر",
        "الضرر مكان",
        "مكان الضرر بالمركبه",
        "الضرر بالمركبه",
    ]

    for i, line in enumerate(normalized_lines):
        if any(k in line for k in keywords):
            # same line after colon
            m = re.search(r"(?:مكان الضرر|الضرر مكان)\s*:\s*(.+)", line)
            if m:
                value = _clean_damage_value(m.group(1))
                if value:
                    return value

            # next few lines
            for j in range(i + 1, min(i + 5, len(normalized_lines))):
                candidate = _clean_damage_value(normalized_lines[j])
                if candidate:
                    return candidate

    return ""


async def process_najm_ocr(case_id: str) -> dict:
    try:
        print(f"--- NAJM OCR REQUEST: {case_id} ---")

        _ensure_firebase_initialized()

        db = firestore.client()
        case_ref = db.collection("accidentCase").document(case_id)
        case_doc = case_ref.get()

        if not case_doc.exists:
            return {
                "status": "error",
                "message": f"Case {case_id} not found in Firestore",
                "data": None,
            }

        case_data = case_doc.to_dict()
        najm_report = case_data.get("najimReport", {}) or {}

        pdf_path = najm_report.get("pdfPath", "")
        pdf_base64 = case_data.get("pdfBase64", "")

        pdf_bytes = None

        # 1) Prefer Firebase Storage
        if pdf_path:
            print(f"[Najm OCR] Trying Storage path: {pdf_path}")
            try:
                pdf_bytes = _download_pdf_bytes_from_storage(pdf_path)
              
                print(f"   [Najm OCR] PDF loaded from Storage, size: {len(pdf_bytes)} bytes")
            except Exception as storage_error:
                print(f"   [Najm OCR] Storage load failed: {storage_error}")

        # 2) Fallback to old base64
        if pdf_bytes is None and pdf_base64:
            try:
                pdf_bytes = base64.b64decode(pdf_base64)
                pdf_source = "base64"
                print(f"   [Najm OCR] PDF loaded from base64, size: {len(pdf_bytes)} bytes")
            except Exception as decode_error:
                print(f"   [Najm OCR] Base64 decode failed: {decode_error}")

        if pdf_bytes is None:
            return {
                "status": "error",
                "message": "No PDF found for this case (neither Storage path nor base64)",
                "data": None,
            }

        lines = _extract_text_from_pdf_bytes(pdf_bytes)

        accident_number = _extract_accident_number(lines, pdf_bytes)
        accident_date = _extract_accident_date(lines)
        damage_location = _extract_damage_location(lines)

        print(f"   [Najm OCR] accidentNumber: {accident_number}")
        print(f"   [Najm OCR] accidentDate: {accident_date}")
        print(f"   [Najm OCR] damageLocation: {damage_location}")

        found_count = sum(bool(x) for x in [accident_number, accident_date, damage_location])

        case_ref.update({
            "najimReport.accidentNumber": accident_number,
            "najimReport.accidentDate": accident_date,
            "najimReport.damageLocation": damage_location,
        })

        if found_count == 0:
            return {
                "status": "error",
                "message": "PDF was processed, but no target Najm fields were extracted",
                "data": None,
            }

        status = "success" if found_count == 3 else "partial_success"

        return {
            "status": status,
            "data": {
                "accidentNumber": accident_number,
                "accidentDate": accident_date,
                "damageLocation": damage_location,
            },
            "message": None if status == "success" else "Some Najm fields were extracted, but not all",
        }

    except Exception as e:
        print(f"!!! NAJM OCR ERROR: {str(e)}")
        return {
            "status": "error",
            "message": f"Najm OCR Error: {str(e)}",
            "data": None,
        }