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


ARABIC_TO_ENGLISH_PLATE = {
    "ا": "A",
    "ب": "B",
    "ح": "H",
    "د": "D",
    "ر": "R",
    "س": "S",
    "ص": "S",
    "ط": "T",
    "ع": "A",
    "ق": "Q",
    "ك": "K",
    "ل": "L",
    "م": "M",
    "ن": "N",
    "ه": "H",
    "و": "W",
    "ى": "Y",
    "ي": "Y",
}

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

def _normalize_spaces(text: str) -> str:
    return re.sub(r"\s+", " ", _normalize(text)).strip()


def _normalize_plate(text: str) -> str:
    text = _normalize(text)

    # keep only Arabic letters, English letters, digits, and spaces
    text = re.sub(r"[^0-9A-Za-z\u0621-\u064A\s]", " ", text)
    text = re.sub(r"\s+", " ", text).strip()

    # collect digits
    digits = "".join(re.findall(r"\d", text))

    # collect english letters directly
    english_letters = re.findall(r"[A-Za-z]", text)

    # collect arabic letters
    arabic_letters = re.findall(r"[\u0621-\u064A]", text)

    letters = []

    if arabic_letters:
        # reverse Arabic plate letters because OCR/PDF extraction
        # often returns them in visual order
        arabic_letters = list(reversed(arabic_letters))

        for ch in arabic_letters:
            if ch in ARABIC_TO_ENGLISH_PLATE:
                letters.append(ARABIC_TO_ENGLISH_PLATE[ch])

    elif english_letters:
        letters.extend([ch.upper() for ch in english_letters])

    return f"{digits}{''.join(letters)}"

def _normalize_ascii(text: str) -> str:
    return re.sub(r"[^a-z0-9]", "", _normalize(text).lower())


def _normalize_digits(text: str) -> str:
    return re.sub(r"\D", "", _normalize(text))



def _clean_plate_candidate(value: str) -> str:
    value = _normalize(value)

    # remove common label fragments
    value = re.sub(r"(?:رقم\s*اللوحه|رقم\s*اللوحة|اللوحه\s*رقم|اللوحة\s*رقم|رقم)", "", value)
    value = value.strip(" :.-")

    return value

def _extract_plate_number(lines: list[str]) -> str:
    normalized_lines = [_normalize(line) for line in lines]

    labels = [
        "رقم اللوحه",
        "رقم اللوحة",
        "اللوحه رقم",
        "اللوحة رقم",
    ]

    for i, line in enumerate(normalized_lines):
        if any(label in line for label in labels):
            # same line: label + value
            m = re.search(
                r"(?:رقم\s*اللوحه|رقم\s*اللوحة|اللوحه\s*رقم|اللوحة\s*رقم)\s*:?\s*(.+)$",
                line
            )
            if m:
                value = _clean_plate_candidate(m.group(1))
                if re.search(r"\d", value):
                    return value

            # nearby lines fallback
            for j in range(i + 1, min(i + 3, len(normalized_lines))):
                candidate = _clean_plate_candidate(normalized_lines[j])
                if re.search(r"\d", candidate):
                    return candidate

    return ""


def _extract_national_id(lines: list[str]) -> str:
    normalized_lines = [_normalize(line) for line in lines]
    labels = [
        "السجل المدني / الاقامه",
        "السجل المدني / الاقامة",
        "السجل المدني",
        "الاقامه",
        "الاقامة",
        "رقم الهويه",
        "رقم الهويه",
        "رقم الهوية",
    ]

    for i, line in enumerate(normalized_lines):
        if any(label in line for label in labels):
            # same line
            m = re.search(r"(\d{10})", line)
            if m:
                return m.group(1)

            # nearby lines
            for j in range(max(0, i - 1), min(i + 3, len(normalized_lines))):
                nearby = normalized_lines[j]
                m = re.search(r"\b(\d{10})\b", nearby)
                if m:
                    return m.group(1)

    # fallback: any 10-digit number, excluding hotline
    for line in normalized_lines:
        for m in re.finditer(r"\b(\d{10})\b", line):
            candidate = m.group(1)
            if candidate != "920000560":
                return candidate

    return ""





def _safe_str(value) -> str:
    return "" if value is None else str(value).strip()


def _match_plate(extracted: str, expected: str) -> bool:
    if not extracted or not expected:
        return False
    return _normalize_plate(extracted) == _normalize_plate(expected)


def _match_national_id(extracted: str, expected: str) -> bool:
    if not extracted or not expected:
        return False
    return _normalize_digits(extracted) == _normalize_digits(expected)


def _match_text_loose(extracted: str, expected: str) -> bool:
    if not extracted or not expected:
        return False
    a = _normalize_ascii(extracted)
    b = _normalize_ascii(expected)
    return bool(a) and bool(b) and (a == b or a in b or b in a)


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

        owner_id = case_data.get("ownerId", "")
        vehicle_id = case_data.get("vehicleId", "")

        pdf_bytes = None

        if pdf_path:
            print(f"[Najm OCR] Trying Storage path: {pdf_path}")
            try:
                pdf_bytes = _download_pdf_bytes_from_storage(pdf_path)
                print(f"   [Najm OCR] PDF loaded from Storage, size: {len(pdf_bytes)} bytes")
            except Exception as storage_error:
                print(f"   [Najm OCR] Storage load failed: {storage_error}")

        if pdf_bytes is None and pdf_base64:
            try:
                pdf_bytes = base64.b64decode(pdf_base64)
                print(f"   [Najm OCR] PDF loaded from base64, size: {len(pdf_bytes)} bytes")
            except Exception as decode_error:
                print(f"   [Najm OCR] Base64 decode failed: {decode_error}")

        if pdf_bytes is None:
            error_message = "No PDF found for this case (neither Storage path nor base64)"
            case_ref.update({
                "status": "ocr_failed",
                "ocrError": error_message,
            })
            return {
                "status": "error",
                "message": error_message,
                "data": None,
            }

        lines = _extract_text_from_pdf_bytes(pdf_bytes)

        # Existing Najm fields
        accident_number = _extract_accident_number(lines, pdf_bytes)
        accident_date = _extract_accident_date(lines)
        damage_location = _extract_damage_location(lines)

        # New verification fields from report
        extracted_plate = _extract_plate_number(lines)
        extracted_national_id = _extract_national_id(lines)
  

        print(f"   [Najm OCR] accidentNumber: {accident_number}")
        print(f"   [Najm OCR] accidentDate: {accident_date}")
        print(f"   [Najm OCR] damageLocation: {damage_location}")
        print(f"   [Najm OCR] extractedPlate: {extracted_plate}")
        print(f"   [Najm OCR] extractedNationalID: {extracted_national_id}")


        # Load expected values from Firestore
        user_data = {}
        vehicle_data = {}

        if owner_id:
            user_doc = db.collection("users").document(owner_id).get()
            if user_doc.exists:
                user_data = user_doc.to_dict() or {}

        if vehicle_id:
            vehicle_doc = db.collection("vehicles").document(vehicle_id).get()
            if vehicle_doc.exists:
                vehicle_data = vehicle_doc.to_dict() or {}

        expected_national_id = _safe_str(user_data.get("nationalID"))

        expected_plate = _safe_str(vehicle_data.get("plateNumber"))


        # Matching
        plate_matched = _match_plate(extracted_plate, expected_plate)
        national_id_matched = _match_national_id(extracted_national_id, expected_national_id)
        print(f"[PLATE RAW] extracted={extracted_plate} expected={expected_plate}")
        print(f"[PLATE NORMALIZED] extracted={_normalize_plate(extracted_plate)} expected={_normalize_plate(expected_plate)}")
        print(f"[PLATE MATCH] {plate_matched}")
        print(f"[NID RAW] extracted={extracted_national_id} expected={expected_national_id}")
        print(f"[NID MATCH] {national_id_matched}")


        # OCR completeness
        required_ocr_ok = all([accident_number, accident_date, damage_location])

        # Verification rule:
        # strong pass = plate + national ID
        # fallback pass = plate + make + model
        identity_verified = national_id_matched 
        vehicle_verified = plate_matched and (national_id_matched )

        verified = required_ocr_ok and vehicle_verified

        update_data = {
            "najimReport.accidentNumber": accident_number,
            "najimReport.accidentDate": accident_date,
            "najimReport.damageLocation": damage_location,
        }

        if verified:
            update_data["status"] = "under_analysis"
            update_data["ocrError"] = firestore.DELETE_FIELD
            case_ref.update(update_data)

            return {
                "status": "success",
                "message": None,
                "data": {
                    "accidentNumber": accident_number,
                    "accidentDate": accident_date,
                    "damageLocation": damage_location,
                    "plateNumber": extracted_plate,
                    "nationalID": extracted_national_id,
                    "verification": {
                        "plateMatched": plate_matched,
                        "nationalIdMatched": national_id_matched,
                    },
                },
            }

        errors = []

        if not required_ocr_ok:
            if not accident_number:
                errors.append("accidentNumber missing")
            if not accident_date:
                errors.append("accidentDate missing")
            if not damage_location:
                errors.append("damageLocation missing")

        if not plate_matched:
            errors.append("plate number does not match selected vehicle")

        if not (national_id_matched ):
            errors.append("report does not sufficiently match selected vehicle / user")

        error_message = "Najm verification failed: " + ", ".join(errors)

        update_data["status"] = "ocr_failed"
        update_data["ocrError"] = error_message
        case_ref.update(update_data)

        return {
            "status": "error",
            "message": error_message,
            "data": {
                "accidentNumber": accident_number,
                "accidentDate": accident_date,
                "damageLocation": damage_location,
                "plateNumber": extracted_plate,
                "nationalID": extracted_national_id,
                "verification": {
                    "plateMatched": plate_matched,
                    "nationalIdMatched": national_id_matched,
                },
            },
        }

    except Exception as e:
        error_message = f"Najm OCR Error: {str(e)}"
        print(f"!!! NAJM OCR ERROR: {error_message}")

        try:
            _ensure_firebase_initialized()
            db = firestore.client()
            case_ref = db.collection("accidentCase").document(case_id)
            case_ref.update({
                "status": "ocr_failed",
                "ocrError": error_message,
            })
        except Exception as update_error:
            print(f"❌ Failed to update case status after OCR exception: {update_error}")

        return {
            "status": "error",
            "message": error_message,
            "data": None,
        }