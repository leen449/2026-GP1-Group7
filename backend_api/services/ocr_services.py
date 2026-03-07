import os
import re
import shutil
import easyocr

reader = easyocr.Reader(['ar', 'en'], gpu=False)


def _normalize_digits(text: str) -> str:
    mapping = str.maketrans("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹", "01234567890123456789")
    return text.translate(mapping)


def _extract_plate_number(texts):
    joined = " ".join([_normalize_digits(t) for t in texts])
    patterns = [
        r'\d{4}\s+[\u0600-\u06FF]\s+[\u0600-\u06FF]\s+[\u0600-\u06FF]',
        r'\d{4}\s+[A-Z]\s+[A-Z]\s+[A-Z]',
        r'\d{3,4}\s*[A-Z]{1,3}',
    ]
    for pattern in patterns:
        match = re.search(pattern, joined)
        if match:
            return match.group().strip()
    return ""


def _extract_chassis_number(texts):
    for text in texts:
        cleaned = _normalize_digits(text).strip().replace(" ", "").upper()
        if re.fullmatch(r'[A-HJ-NPR-Z0-9]{15,20}', cleaned):
            return cleaned
    return ""


def _extract_year(texts):
    for text in texts:
        normalized = _normalize_digits(text)
        match = re.search(r'\b(19[8-9]\d|20[0-3]\d)\b', normalized)
        if match:
            return match.group()
        match_h = re.search(r'\b(14[0-9]{2})\b', normalized)
        if match_h:
            return str(int(match_h.group()) - 579)
    return ""


def _extract_color(texts):
    color_map = {
        "أبيض": "أبيض", "ابيض": "أبيض", "white": "أبيض",
        "أسود": "أسود", "اسود": "أسود", "black": "أسود",
        "فضي": "فضي",   "فضة": "فضي",   "silver": "فضي",
        "رمادي": "رمادي", "gray": "رمادي", "grey": "رمادي",
        "أحمر": "أحمر", "احمر": "أحمر", "red": "أحمر",
        "أزرق": "أزرق", "ازرق": "أزرق", "blue": "أزرق",
        "أخضر": "أخضر", "اخضر": "أخضر", "green": "أخضر",
        "بيج": "بيج",   "beige": "بيج",
        "بني": "بني",   "brown": "بني",
        "ذهبي": "ذهبي", "gold": "ذهبي",
    }
    for text in texts:
        for key, value in color_map.items():
            if key in text.strip().lower():
                return value
    return ""


def _extract_brand(texts):
    brands = {
        "تويوتا": "تويوتا", "toyota": "Toyota",
        "كامري": "تويوتا",  "لاندكروزر": "تويوتا",
        "اكمن": "تويوتا",   "هايلكس": "تويوتا",
        "نيسان": "نيسان",   "nissan": "Nissan",
        "باترول": "نيسان",  "التيما": "نيسان",
        "هيونداي": "هيونداي", "hyundai": "Hyundai",
        "كيا": "كيا",       "kia": "Kia",
        "فورد": "فورد",     "ford": "Ford",
        "شيفروليه": "شيفروليه", "chevrolet": "Chevrolet",
        "مرسيدس": "مرسيدس", "mercedes": "Mercedes",
        "bmw": "BMW",        "بي ام دبليو": "BMW",
        "لكزس": "لكزس",     "lexus": "Lexus",
        "هوندا": "هوندا",   "honda": "Honda",
        "مازدا": "مازدا",   "mazda": "Mazda",
        "ميتسوبيشي": "ميتسوبيشي", "mitsubishi": "Mitsubishi",
        "سوزوكي": "سوزوكي", "suzuki": "Suzuki",
        "جيب": "جيب",       "jeep": "Jeep",
    }
    for text in texts:
        text_lower = text.strip().lower()
        for key, value in brands.items():
            if key in text_lower:
                return value
    return ""


def _extract_structured_data(texts: list[str]) -> dict:
    return {
        "plate_number":       _extract_plate_number(texts),
        "vehicle_brand":      _extract_brand(texts),
        "color":              _extract_color(texts),
        "manufacturing_year": _extract_year(texts),
        "chassis_number":     _extract_chassis_number(texts),
    }


async def process_ocr(file):
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
        if os.path.exists(temp_path):
            os.remove(temp_path)