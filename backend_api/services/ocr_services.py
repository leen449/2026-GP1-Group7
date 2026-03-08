import os
import re
import shutil
import easyocr

reader = easyocr.Reader(['ar', 'en'], gpu=False)


def _normalize_digits(text: str) -> str:
    """Convert Arabic/Hindi digits to English digits"""
    mapping = str.maketrans("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹", "01234567890123456789")
    return text.translate(mapping)


def _get_value_after_label(texts: list[str], labels: list[str]) -> str:
    """
    The Saudi registration card layout is fixed.
    The label always appears directly before its value.
    Example: ['سنة الصنع', '١٤٣٣'] -> returns '1433'
    """
    for i, text in enumerate(texts):
        cleaned = text.strip()
        if any(label in cleaned for label in labels):
            if i + 1 < len(texts):
                return _normalize_digits(texts[i + 1].strip())
    return ""


def _extract_plate_number(texts: list[str]) -> str:
    """
    Plate number — fixed label in the card: 'رقم اللوحة'
    Format: 4 digits + 3 Arabic letters
    Example: 6176 ب ز أ
    """
    # First: search after the fixed label
    value = _get_value_after_label(texts, ["رقم اللوحة"])
    if value:
        return value

    # Fallback: match Saudi plate pattern directly
    joined = " ".join([_normalize_digits(t) for t in texts])
    patterns = [
        r'\d{4}\s+[\u0600-\u06FF]\s+[\u0600-\u06FF]\s+[\u0600-\u06FF]',  # 6176 ب ز أ
        r'\d{4}\s+[A-Z]\s+[A-Z]\s+[A-Z]',                                 # 6176 B Z A
    ]
    for pattern in patterns:
        match = re.search(pattern, joined)
        if match:
            return match.group().strip()
    return ""


def _extract_chassis_number(texts: list[str]) -> str:
    """
    Chassis number — fixed label in the card: 'رقم الهيكل'
    Format: 17-character VIN
    Example: MHKTC31E4CK010657
    """
    # First: search after the fixed label
    value = _get_value_after_label(texts, ["رقم الهيكل"])
    if value and len(value.replace(" ", "")) >= 15:
        return value.replace(" ", "").upper()

    # Fallback: match VIN pattern directly
    for text in texts:
        cleaned = _normalize_digits(text).strip().replace(" ", "").upper()
        if re.fullmatch(r'[A-HJ-NPR-Z0-9]{15,20}', cleaned):
            return cleaned
    return ""


def _extract_year(texts: list[str]) -> str:
    """
    Manufacturing year — fixed label in the card: 'سنة الصنع'
    Value is Gregorian written in Arabic digits
    Example: ٢٠١٥ -> 2015
    """
    # First: search after the fixed label
    value = _get_value_after_label(texts, ["سنة الصنع"])
    if value:
        normalized = _normalize_digits(value)
        match = re.search(r'\b(19[8-9]\d|20[0-3]\d)\b', normalized)
        if match:
            return match.group()

    # Fallback: search across all texts
    for text in texts:
        normalized = _normalize_digits(text)
        match = re.search(r'\b(19[8-9]\d|20[0-3]\d)\b', normalized)
        if match:
            return match.group()
    return ""


def _extract_color(texts: list[str]) -> str:
    """
    Color — fixed label in the card: 'اللون'
    Value is always a single Arabic word
    """
    # First: search after the fixed label
    value = _get_value_after_label(texts, ["اللون"])
    if value:
        return value

    # Fallback: match known color keywords
    color_map = {
        "أبيض": "أبيض", "ابيض": "أبيض",
        "أسود": "أسود", "اسود": "أسود",
        "فضي": "فضي",   "فضة": "فضي",
        "رمادي": "رمادي",
        "أحمر": "أحمر", "احمر": "أحمر",
        "أزرق": "أزرق", "ازرق": "أزرق",
        "أخضر": "أخضر", "اخضر": "أخضر",
        "بيج": "بيج",
        "بني": "بني",
        "ذهبي": "ذهبي",
        "برتقالي": "برتقالي",
    }
    for text in texts:
        for key, val in color_map.items():
            if key in text.strip():
                return val
    return ""


def _extract_brand(texts: list[str]) -> str:
    """
    Vehicle brand — fixed label in the card: 'ماركة المركبة'
    Value is always the manufacturer name in Arabic
    Example: تويوتا
    """
    # First: search after the fixed label
    value = _get_value_after_label(texts, ["ماركة المركبة", "الشركة الصانعة"])
    if value:
        return value

    # Fallback: match known brand keywords
    brands = {
        "تويوتا": "تويوتا", "نيسان": "نيسان",
        "هيونداي": "هيونداي", "كيا": "كيا",
        "فورد": "فورد", "شيفروليه": "شيفروليه",
        "مرسيدس": "مرسيدس", "لكزس": "لكزس",
        "هوندا": "هوندا", "مازدا": "مازدا",
        "ميتسوبيشي": "ميتسوبيشي", "سوزوكي": "سوزوكي",
        "جيب": "جيب", "بي ام دبليو": "BMW",
        "toyota": "Toyota", "nissan": "Nissan",
        "hyundai": "Hyundai", "kia": "Kia",
        "ford": "Ford", "chevrolet": "Chevrolet",
        "mercedes": "Mercedes", "lexus": "Lexus",
        "honda": "Honda", "mazda": "Mazda",
        "bmw": "BMW", "jeep": "Jeep",
    }
    for text in texts:
        for key, val in brands.items():
            if key in text.strip().lower():
                return val
    return ""


def _extract_structured_data(texts: list[str]) -> dict:
    """Extract only the fields needed for the Verify Details screen"""
    return {
        "plate_number":       _extract_plate_number(texts),
        "vehicle_brand":      _extract_brand(texts),
        "color":              _extract_color(texts),
        "manufacturing_year": _extract_year(texts),
        "chassis_number":     _extract_chassis_number(texts),
    }


async def process_ocr(file):
    """
    Receives an uploaded image, runs EasyOCR,
    and returns raw text + structured vehicle data.
    """
    temp_path = f"temp_{file.filename}"

    with open(temp_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    try:
        print("=== OCR STARTED ===")

        result = reader.readtext(
            temp_path,
            detail=1,
            paragraph=False,
            text_threshold=0.5,
            low_text=0.3,
        )

        # Extract text strings only
        raw_text = [item[1].strip() for item in result if item[1].strip()]
        print("Extracted text:", raw_text)

        structured_data = _extract_structured_data(raw_text)
        print("Structured data:", structured_data)

        return {
            "raw_text": raw_text,
            "structured_data": structured_data
        }

    except Exception as e:
        print("ERROR INSIDE OCR:", repr(e))
        raise

    finally:
        # Always delete the temp file after processing
        if os.path.exists(temp_path):
            os.remove(temp_path)