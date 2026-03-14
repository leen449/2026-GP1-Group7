import re
import base64
import fitz  # PyMuPDF — pip install pymupdf
import firebase_admin
from firebase_admin import firestore

# ─────────────────────────────────────────────────────────────────────
# Helper: extract text from PDF base64 string
# ─────────────────────────────────────────────────────────────────────
def _extract_text_from_base64_pdf(pdf_base64: str) -> list[str]:
    """
    Decodes a base64 PDF string and extracts all text lines from it.
    Returns a list of non-empty text lines.
    """
    # Decode base64 → bytes
    pdf_bytes = base64.b64decode(pdf_base64)

    # Open PDF from bytes using PyMuPDF
    pdf_doc = fitz.open(stream=pdf_bytes, filetype="pdf")

    all_lines = []
    for page in pdf_doc:
        text = page.get_text()
        lines = [line.strip() for line in text.split('\n') if line.strip()]
        all_lines.extend(lines)

    print(f"   [Najm OCR] Extracted {len(all_lines)} lines from PDF")
    return all_lines


# ─────────────────────────────────────────────────────────────────────
# Helper: normalize Arabic/Hindi digits to English
# ─────────────────────────────────────────────────────────────────────
def _normalize(text: str) -> str:
    mapping = str.maketrans("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹", "01234567890123456789")
    return text.translate(mapping).strip()


# ─────────────────────────────────────────────────────────────────────
# Extract: Accident Number (رقم الحادث)
# ─────────────────────────────────────────────────────────────────────
def _extract_accident_number(lines: list[str]) -> str:
    """
    Looks for the line containing 'رقم الحادث' and extracts the number
    from the same line or the next line.
    Example: 'رقم الحادث : 15343' → '15343'
    """
    for i, line in enumerate(lines):
        if 'رقم الحادث' in line or 'رقم الحادث' in line:
            # Try to extract number from same line
            normalized = _normalize(line)
            match = re.search(r':\s*(\d+)', normalized)
            if match:
                return match.group(1)

            # Try next line
            if i + 1 < len(lines):
                next_line = _normalize(lines[i + 1])
                match = re.search(r'\d+', next_line)
                if match:
                    return match.group()

    return ''


# ─────────────────────────────────────────────────────────────────────
# Extract: Accident Date (تاريخ الحادث)
# ─────────────────────────────────────────────────────────────────────
def _extract_accident_date(lines: list[str]) -> str:
    """
    Looks for the line containing 'تاريخ الحادث' and extracts the date.
    Example: 'تاريخ الحادث : 12/08/2025 07:55:04 AM' → '12/08/2025'
    """
    for i, line in enumerate(lines):
        if 'تاريخ الحادث' in line:
            normalized = _normalize(line)

            # Look for date pattern DD/MM/YYYY
            match = re.search(r'\d{1,2}/\d{1,2}/\d{4}', normalized)
            if match:
                return match.group()

            # Try next line
            if i + 1 < len(lines):
                next_normalized = _normalize(lines[i + 1])
                match = re.search(r'\d{1,2}/\d{1,2}/\d{4}', next_normalized)
                if match:
                    return match.group()

    return ''


# ─────────────────────────────────────────────────────────────────────
# Extract: Damage Location (مكان الضرر بالمركبة)
# ─────────────────────────────────────────────────────────────────────
def _extract_damage_location(lines: list[str]) -> str:
    """
    Looks for 'مكان الضرر' and returns the Arabic description.
    Example: 'مكان الضرر بالمركبة : الركن الأمامي الأيسر'
    → 'الركن الأمامي الأيسر'
    """
    damage_keywords = ['مكان الضرر', 'الضرر بالمركبة', 'مكان الضرر بالمركبة']

    for i, line in enumerate(lines):
        for keyword in damage_keywords:
            if keyword in line:
                # Try to extract after colon on same line
                if ':' in line:
                    parts = line.split(':')
                    if len(parts) > 1:
                        value = parts[-1].strip()
                        if value and len(value) > 2:
                            return value

                # Try next line
                if i + 1 < len(lines):
                    next_line = lines[i + 1].strip()
                    if next_line and len(next_line) > 2:
                        return next_line

    return ''


# ─────────────────────────────────────────────────────────────────────
# Main function — called by the FastAPI route
# ─────────────────────────────────────────────────────────────────────
async def process_najm_ocr(case_id: str) -> dict:
    """
    Main function called by POST /ocr/najm
    1. Reads pdfBase64 from Firestore using case_id
    2. Extracts accident info from the PDF
    3. Updates the Firestore document with extracted fields
    4. Returns the extracted data
    """
    try:
        print(f"--- NAJM OCR REQUEST: {case_id} ---")

        # ── 1. Get Firestore document ─────────────────────────────────
        db = firestore.client()
        case_ref = db.collection('accidentCase').document(case_id)
        case_doc = case_ref.get()

        if not case_doc.exists:
            return {
                'status': 'error',
                'message': f'Case {case_id} not found in Firestore'
            }

        case_data = case_doc.to_dict()
        pdf_base64 = case_data.get('pdfBase64', '')

        if not pdf_base64:
            return {
                'status': 'error',
                'message': 'No PDF found for this case'
            }

        print(f"   [Najm OCR] PDF found, size: {len(pdf_base64)} chars")

        # ── 2. Extract text from PDF ──────────────────────────────────
        lines = _extract_text_from_base64_pdf(pdf_base64)

        # ── 3. Extract the 3 fields ───────────────────────────────────
        accident_number  = _extract_accident_number(lines)
        accident_date    = _extract_accident_date(lines)
        damage_location  = _extract_damage_location(lines)

        print(f"   [Najm OCR] accidentNumber:  {accident_number}")
        print(f"   [Najm OCR] accidentDate:    {accident_date}")
        print(f"   [Najm OCR] damageLocation:  {damage_location}")

        # ── 4. Update Firestore ───────────────────────────────────────
        case_ref.update({
            'najimReport.accidentNumber':  accident_number,
            'najimReport.accidentDate':    accident_date,
            'najimReport.damageLocation':  damage_location,
        })

        print(f"   [Najm OCR] Firestore updated successfully")

        return {
            'status': 'success',
            'data': {
                'accidentNumber':  accident_number,
                'accidentDate':    accident_date,
                'damageLocation':  damage_location,
            }
        }

    except Exception as e:
        print(f"!!! NAJM OCR ERROR: {str(e)}")
        return {
            'status': 'error',
            'message': f'Najm OCR Error: {str(e)}'
        }