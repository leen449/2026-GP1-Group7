import re
import cv2
import numpy as np
import easyocr
from difflib import SequenceMatcher
from datetime import datetime

# Initialize the reader once (Global) to speed up processing
print("Loading OCR Model...")
reader = easyocr.Reader(['ar', 'en'], gpu=False)

# Arabic detection lists
ARABIC_COLORS = [
    "أبيض", "ابيض", "أسود", "اسود", "فضي", "رمادي", "أحمر", "احمر",
    "رصاصي","أزرق", "ازرق", "أخضر", "اخضر", "بيج", "بني", "ذهبي", "برتقالي"
]

ARABIC_BRANDS = [
    "تويوتا", "نيسان", "هيونداي", "هونداي", "كيا", "فورد", "شيفروليه", "شفروليه",
    "مرسيدس", "لكزس", "هوندا", "مازدا", "ميتسوبيشي", "سوزوكي", "جيب",
    "شانجان", "جيلي", "هافال", "ام جي", "بي ام دبليو", "دوج", "دودج", "كرايسلر",
    "جمس", "جي ام سي", "GMC"
]

COMMON_ARABIC_MODELS = [
    "كامري", "كورولا", "يارس", "لاندكروزر", "هايلوكس", "اف جي", "انوفا", "فورتشنر",
    "سوناتا", "النترا", "اكسنت", "توسان", "سانتافي", "ازيرا", "كادينزا", "اوبتيما",
    "سبورتاج", "سيراتو", "ريو", "تاهو", "يوكن", "سوبربان", "سييرا", "سيلفرادو",
    "كابرس", "لومينا", "تشارجر", "تشالنجر", "توروس", "اكسبلورر", "موستنج", "ايدج",
    "باترول", "صني", "التيما", "ماكسيما", "اكس تريل", "باثفندر", "جي اكس ار",
    "في اكس ار", "فاغن"
]

BRAND_ALIAS_MAP = {

    "هيونداي":     "هونداي",
    "شفروليه":     "شيفروليه",
    "شيفروليه":    "شيفروليه",
    "دودج":        "دوج",
    "دوج":         "دوج",
    "جي ام سي":    "جي ام سي",
    "جمس":         "جي ام سي",
    "gmc":         "جي ام سي",
    "بي ام دبليو": "بي ام دبليو",
    "bmw":         "بي ام دبليو",
    "ام جي":       "ام جي",
    "mg":          "ام جي",
    "شيفورلية":    "شيفروليه",
    "شيفوليه":     "شيفروليه",
    "شيفرولية":    "شيفروليه",
    "تيوتا":       "تويوتا",
    "تيوتو":       "تويوتا",
    "هيونداى":     "هيونداي",
    "هونداى":      "هونداي",
    "نيسسان":      "نيسان",
    "مرسيدز":      "مرسيدس",
    "لكسس":        "لكزس",
}
MODEL_ALIAS_MAP = {
    # تويوتا
    "كمري":           "كامري",
    "كمره":           "كامري",
    "كورلا":          "كورولا",
    "كرولا":          "كورولا",
    "يارز":           "يارس",
    "لاند كروزر":     "لاندكروزر",
    "لاندكروز":       "لاندكروزر",
    "هايلكس":         "هايلوكس",
    "هايلكز":         "هايلوكس",
    "افجي":           "اف جي",
    "اف جى":          "اف جي",
    "انوفا":          "انوفا",
    "فورتشنر":        "فورتشنر",

    # هيونداي
    "الينترا":        "النترا",
    "انترا":          "النترا",
    "سوناتة":         "سوناتا",
    "توسن":           "توسان",
    "سانتا في":       "سانتافي",
    "ازيره":          "ازيرا",
    "كادنزا":         "كادينزا",

    # كيا
    "سبورتاج":        "سبورتاج",
    "سيراتو":         "سيراتو",
    "اوبتما":         "اوبتيما",
    "ريو":            "ريو",

    # نيسان
    "باترول":         "باترول",
    "صاني":           "صني",
    "التيما":         "التيما",
    "ماكزيما":        "ماكسيما",
    "اكستريل":        "اكس تريل",
    "باثفايندر":      "باثفندر",
    "جي اكس ار":      "جي اكس ار",

    # شيفروليه / جي ام سي
    "تاهوي":          "تاهو",
    "يوكون":          "يوكن",
    "سبربان":         "سوبربان",
    "سيلفرادو":       "سيلفرادو",
    "سييره":          "سيرا",
    "كابريس":         "كابرس",
    "لومينه":         "لومينا",

    # دوج / كرايسلر
    "تشارجير":        "تشارجر",
    "تشالنجير":       "تشالنجر",

    # فورد
    "تورس":           "توروس",
    "اكسبلورار":      "اكسبلورر",
    "موستانج":        "موستنج",
    "ايدغ":           "ايدج",
}


# English plate letter → Arabic plate letter (for fallback conversion)
ENGLISH_TO_ARABIC_PLATE = {
    "A": "ا",
    "B": "ب",
    "J": "ح",
    "D": "د",
    "R": "ر",
    "S": "س",
    "X": "ص",
    "T": "ط",
    "E": "ع",
    "G": "ق",
    "K": "ك",
    "L": "ل",
    "Z": "م",
    "N": "ن",
    "H": "ه",
    "U": "و",
    "Y": "ى",
}



# Arabic digits for converting English digits to Arabic
ARABIC_DIGITS = "٠١٢٣٤٥٦٧٨٩"

def _to_arabic_digits(text: str) -> str:
    """Convert English digits to Arabic digits."""
    result = ""
    for ch in text:
        if ch.isdigit():
            result += ARABIC_DIGITS[int(ch)]
        else:
            result += ch
    return result


def _normalize_text(text: str) -> str:
    """Convert Arabic digits to English digits and normalize spaces."""
    mapping = str.maketrans("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹", "01234567890123456789")
    text = text.translate(mapping)
    text = text.replace("ى", "ي")
    return " ".join(text.split())


def _normalize_match_text(text: str) -> str:
    """Normalize text for matching only, not for display."""
    if not text:
        return ""
    text = _normalize_text(text).strip().lower()
    text = (
        text.replace("أ", "ا")
            .replace("إ", "ا")
            .replace("آ", "ا")
            .replace("ؤ", "و")
            .replace("ئ", "ي")
            .replace("ة", "ه")
    )
    text = re.sub(r"[^a-z0-9\u0600-\u06ff\s]+", " ", text)
    return " ".join(text.split())


def _is_valid_year(year_text: str) -> bool:
    """Validate a 4-digit manufacturing year dynamically."""
    if not re.fullmatch(r"\d{4}", year_text):
        return False
    year = int(year_text)
    current_year = datetime.now().year
    return 1970 <= year <= current_year + 1


def _extract_valid_year_candidates(text: str) -> list:
    """Extract all valid 4-digit year candidates from text."""
    if not text:
        return []
    candidates = re.findall(r"\d{4}", text)
    return [c for c in candidates if _is_valid_year(c)]

def _resolve_model_alias(text: str) -> str:
    """Return canonical model if alias is known."""
    norm = _normalize_match_text(text)
    for alias, canonical in MODEL_ALIAS_MAP.items():
        alias_norm = _normalize_match_text(alias)
        if norm == alias_norm or alias_norm in norm:
            return canonical
    return text

def _build_ocr_items(result: list) -> list:
    """Convert EasyOCR detail=1 output into structured OCR items."""
    items = []
    for bbox, text, conf in result:
        normalized = _normalize_text(text)
        xs = [p[0] for p in bbox]
        ys = [p[1] for p in bbox]
        items.append({
            "text":       text,
            "normalized": normalized,
            "confidence": float(conf),
            "x_min": min(xs), "x_max": max(xs),
            "y_min": min(ys), "y_max": max(ys),
            "cx": (min(xs) + max(xs)) / 2,
            "cy": (min(ys) + max(ys)) / 2,
            "w":  max(xs) - min(xs),
            "h":  max(ys) - min(ys),
        })
    return items


def _find_anchor_item(ocr_items: list, keywords: list):
    """Find the best matching anchor OCR item with fuzzy keyword matching."""
    best_match = None
    best_score = -1.0
    for item in ocr_items:
        text_norm = _normalize_match_text(item["normalized"])
        if not text_norm:
            continue
        for kw in keywords:
            kw_norm = _normalize_match_text(kw)
            if not kw_norm:
                continue
            score = SequenceMatcher(None, text_norm, kw_norm).ratio()
            if score > 0.80 and score > best_score:
                best_score = score
                best_match = item
    return best_match


def _crop_region(image, x1, y1, x2, y2):
    """Safely crop an image region."""
    h, w = image.shape[:2]
    x1, y1 = max(0, int(x1)), max(0, int(y1))
    x2, y2 = min(w, int(x2)), min(h, int(y2))
    if x2 <= x1 or y2 <= y1:
        return None
    return image[y1:y2, x1:x2]


def _best_color_match(text: str) -> str:
    """Return the best matching Arabic color using fuzzy similarity."""
    text = text.strip()
    if not text:
        return ""
    best_color, best_score = "", 0.0
    for color in ARABIC_COLORS:
        score = SequenceMatcher(None, text, color).ratio()
        if score > best_score:
            best_score = score
            best_color = color
    return best_color if best_score >= 0.6 else ""


def _looks_like_arabic_plate_letter(text: str) -> bool:
    """True if text is a single Arabic plate letter candidate."""
    if not text:
        return False
    compact = re.sub(r"\s+", "", text)
    return bool(re.fullmatch(r"[ابتثجحخدذرزسشصضطظعغفقكلمنهوىي]", compact))


# ── Plate extraction ──────────────────────────────────────────────────
def _extract_plate_by_anchor(ocr_items: list) -> str:
    """
    Extract plate number using anchor 'رقم اللوحة'.
    Rule:
      - If OCR reads Arabic letters directly, keep the same order.
      - If OCR reads English letters, reverse them before converting to Arabic.
    """
    anchor = _find_anchor_item(ocr_items, ["رقم اللوحة", "اللوحة"])
    if not anchor or not ocr_items:
        return ""

    image_width = max(item["x_max"] for item in ocr_items)

    nearby_items = []
    for item in ocr_items:
        if item is anchor:
            continue

        text = _normalize_text(item["normalized"]).strip().upper()
        if not text:
            continue

        vertical_diff = abs(item["cy"] - anchor["cy"])
        horizontal_diff = anchor["cx"] - item["cx"]

        if vertical_diff > max(anchor["h"], item["h"]) * 2.2:
            continue
        if abs(horizontal_diff) > max(image_width * 0.28, anchor["w"] * 6.0):
            continue

        score = 0.0
        if horizontal_diff > 0:
            score += 3.0
        else:
            score -= 0.5

        score += max(0.0, 120.0 - vertical_diff)
        score += item["confidence"] * 5.0

        nearby_items.append({
            "score": score,
            "text": text,
            "raw": item["normalized"],
            "cx": item["cx"],
            "cy": item["cy"],
            "w": item["w"],
            "h": item["h"],
        })

    if not nearby_items:
        return ""

    nearby_items.sort(key=lambda x: x["score"], reverse=True)

    # Priority 1: English/Arabic digits + Arabic letters
    plate_digits = None
    arabic_letters_combined = []

    for item in nearby_items:
        raw = item["raw"]
        normalized = _normalize_text(raw)

        digits_match = re.search(r"(?<!\d)\d{3,4}(?!\d)", normalized)
        arabic_letters = re.findall(r"[ابتثجحخدذرزسشصضطظعغفقكلمنهوىي]", raw)

        # Get plate digits
        if digits_match:
            plate_digits = digits_match.group()

        # Get Arabic plate letters directly without reversing
        if arabic_letters:
            arabic_letters_combined.extend(arabic_letters)

        # Best case: digits and Arabic letters in the same OCR item
        if digits_match and len(arabic_letters) >= 3:
            arabic_digits = _to_arabic_digits(digits_match.group())
            letters = " ".join(arabic_letters[:3]) # Keep Arabic OCR order
            return f"{arabic_digits} {letters}"

    # Digits and Arabic letters found in separate OCR items
    if plate_digits and len(arabic_letters_combined) >= 3:
        arabic_digits = _to_arabic_digits(plate_digits)
        letters = " ".join(arabic_letters_combined[:3])  # Keep Arabic OCR order
        return f"{arabic_digits} {letters}"

    # Priority 2: English plate letters
    number_candidates = []
    letter_candidates = []
    single_letter_items = []

    for item in nearby_items:
        text = item["text"]
        compact = re.sub(r"\s+", "", text).upper()

        if re.fullmatch(r"\d{1,4}", compact):
            number_candidates.append({
                "score": item["score"] + 4,
                "value": compact,
                "cx": item["cx"],
                "cy": item["cy"]
            })

        elif re.fullmatch(r"[A-Z]{3}", compact):
            letter_candidates.append({
                "score": item["score"] + 4,
                "value": compact,
                "cx": item["cx"],
                "cy": item["cy"]
            })

        elif re.fullmatch(r"[A-Z]", compact):
            single_letter_items.append(item)

        else:
            # Example: 2640LGD
            match = re.fullmatch(r"(\d{1,4})([A-Z]{3})", compact)
            if match:
                digits, letters = match.groups()
                arabic_digits = _to_arabic_digits(digits)

                # converting to Arabic
                arabic_letters = " ".join(
                ENGLISH_TO_ARABIC_PLATE.get(l, l)
                for l in letters
                )
                return f"{arabic_digits} {arabic_letters}"

    # Group single English letters, example: L G D
    if len(single_letter_items) >= 3:
        single_letter_items.sort(key=lambda x: x["cx"])

        for i in range(len(single_letter_items) - 2):
            group = single_letter_items[i:i + 3]

            cy_vals = [g["cy"] for g in group]
            cx_vals = [g["cx"] for g in group]
            avg_h = sum(g["h"] for g in group) / 3.0

            if max(cy_vals) - min(cy_vals) > avg_h * 0.8:
                continue

            if max(abs(cx_vals[1] - cx_vals[0]), abs(cx_vals[2] - cx_vals[1])) > max(anchor["w"] * 1.8, 90):
                continue

            letters = "".join(re.sub(r"\s+", "", g["text"]).upper() for g in group)

            if re.fullmatch(r"[A-Z]{3}", letters):
                letter_candidates.append({
                    "score": sum(g["score"] for g in group) / 3.0 + 3,
                    "value": letters,
                    "cx": sum(g["cx"] for g in group) / 3.0,
                    "cy": sum(g["cy"] for g in group) / 3.0
                })

    number_candidates.sort(key=lambda x: x["score"], reverse=True)
    letter_candidates.sort(key=lambda x: x["score"], reverse=True)

    best_number = number_candidates[0] if number_candidates else None
    best_letters = letter_candidates[0] if letter_candidates else None

    if best_number and best_letters:
        digits = best_number["value"]
        letters = best_letters["value"]

        same_row = abs(best_number["cy"] - best_letters["cy"]) <= max(anchor["h"] * 1.2, 35)
        close_enough = abs(best_number["cx"] - best_letters["cx"]) <= max(image_width * 0.20, 180)

        if re.fullmatch(r"\d{1,4}", digits) and re.fullmatch(r"[A-Z]{3}", letters) and same_row and close_enough:
            arabic_digits = _to_arabic_digits(digits)

            #converting to Arabic
            arabic_letters = " ".join(
            ENGLISH_TO_ARABIC_PLATE.get(l, l)
            for l in letters
            )

            return f"{arabic_digits} {arabic_letters}"

    return ""
# ── Chassis ───────────────────────────────────────────────────────────
def _extract_chassis_number_by_anchor(ocr_items: list) -> str:
    """Extract VIN using the anchor 'رقم الهيكل'."""
    anchor = _find_anchor_item(ocr_items, ["رقم الهيكل", "الهيكل"])
    if not anchor:
        return ""

    candidates = []
    for item in ocr_items:
        if item is anchor:
            continue
        text = re.sub(r"[^A-Z0-9]", "", item["normalized"].replace(" ", "").upper())
        if len(text) < 14 or len(text) > 18:
            continue
        if not any(c.isdigit() for c in text) or not any(c.isalpha() for c in text):
            continue

        vd = abs(item["cy"] - anchor["cy"])
        hd = anchor["cx"] - item["cx"]
        if vd > max(anchor["h"], item["h"]) * 2.0:
            continue

        score = (3 if hd > 0 else -1) + max(0, 120 - vd)
        score += {17: 10, 16: 7, 15: 5, 18: 4}.get(len(text), 1)
        score += min(item["w"] / 20, 10) + item["confidence"] * 5
        candidates.append((score, text))

    if not candidates:
        return ""
    candidates.sort(reverse=True)
    return candidates[0][1]


def _extract_chassis_number(texts: list) -> str:
    """Fallback chassis extraction from text lines."""
    for text in texts:
        clean = text.replace(" ", "").upper()
        match = re.search(r'[A-Z0-9]{15,17}', clean)
        if match:
            vin = match.group()
            if any(c.isdigit() for c in vin):
                return vin
    return ""


# ── Year ──────────────────────────────────────────────────────────────
def _extract_year_from_roi(image, ocr_items: list) -> str:
    """Extract manufacturing year by cropping near 'سنة الصنع' anchor."""
    anchor = _find_anchor_item(ocr_items, ["سنة الصنع", "سنة", "صنع"])
    if not anchor:
        return ""

    roi = _crop_region(image,
        anchor["x_min"] - max(anchor["w"] * 2.2, 140),
        anchor["y_min"] - max(anchor["h"] * 0.4, 10),
        anchor["x_min"] + max(anchor["w"] * 0.3, 25),
        anchor["y_max"] + max(anchor["h"] * 1.2, 35))

    if roi is None or roi.size == 0:
        return ""

    roi = cv2.resize(roi, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)
    try:
        roi_result = reader.readtext(roi, detail=0, text_threshold=0.35, low_text=0.2)
    except Exception:
        return ""

    for text in [_normalize_text(t) for t in roi_result]:
        compact = re.sub(r"\s+", "", text)
        cands = _extract_valid_year_candidates(compact)
        if cands:
            return cands[0]
        if re.fullmatch(r"\d{4}", compact):
            rev = _extract_valid_year_candidates(compact[::-1])
            if rev:
                return rev[0]
        parts = re.findall(r"\d{2}", text)
        if len(parts) == 2:
            for c in (parts[0]+parts[1], parts[1]+parts[0]):
                if _is_valid_year(c):
                    return c
    return ""


def _extract_year(texts: list) -> str:
    """Fallback year extraction from text lines."""
    for i, text in enumerate(texts):
        if "سنة" in text or "صنع" in text:
            c = _extract_valid_year_candidates(text)
            if c:
                return c[0]
            if i + 1 < len(texts):
                c = _extract_valid_year_candidates(texts[i + 1])
                if c:
                    return c[0]
    for text in texts:
        c = _extract_valid_year_candidates(text)
        if c:
            return c[0]
    return ""


# ── Make ──────────────────────────────────────────────────────────────
def _extract_make_by_anchor(ocr_items: list) -> str:
    """Extract vehicle make using anchor 'ماركة المركبة'."""
    anchor = _find_anchor_item(ocr_items, ["ماركة المركبة", "ماركة"])
    if not anchor or not ocr_items:
        return ""

    image_width = max(item["x_max"] for item in ocr_items)
    invalid = ["طراز","نوع","التسجيل","حمولة","وزن","سنة","الصنع",
               "اللون","رقم","اللوحة","الهيكل","المستخدم","المالك","خاص","خصوصي","نقل","عمومي"]
    candidates = []

    for item in ocr_items:
        if item is anchor:
            continue
        text = item["normalized"].strip()
        if not text:
            continue
        vd = abs(item["cy"] - anchor["cy"])
        hd = anchor["cx"] - item["cx"]
        if vd > max(anchor["h"], item["h"]) * 2.0:
            continue
        if abs(hd) > max(image_width * 0.22, anchor["w"] * 4.5):
            continue

        cleaned = text
        for noise in ("ماركة المركبة", "ماركة", "المركبة"):
            cleaned = cleaned.replace(noise, "")
        cleaned = " ".join(cleaned.split()).strip()
        if not cleaned or any(kw in cleaned for kw in invalid):
            continue

        score = (3.0 if hd > 0 else -0.5) + max(0.0, 100.0 - vd) + item["confidence"] * 5.0
        candidates.append((score, cleaned))

    if not candidates:
        return ""
    candidates.sort(reverse=True)

    for _, cleaned in candidates:
        norm = _normalize_match_text(cleaned)
        for alias, canonical in BRAND_ALIAS_MAP.items():
            if _normalize_match_text(alias) in norm:
                return canonical
        for brand in ARABIC_BRANDS:
            if SequenceMatcher(None, norm, _normalize_match_text(brand)).ratio() >= 0.75:
                return brand
    return ""


def _extract_brand(texts: list) -> str:
    """Fallback brand extraction from text lines."""
    for text in texts:
        for brand in ARABIC_BRANDS:
            if brand in text:
                return brand
    return ""


# ── Model ─────────────────────────────────────────────────────────────
def _extract_model_by_anchor(ocr_items: list) -> str:
    """Extract vehicle model using anchor 'طراز المركبة'."""
    anchor = _find_anchor_item(ocr_items, ["طراز المركبة", "طراز", "طراذ"])
    if not anchor or not ocr_items:
        return ""

    image_width = max(item["x_max"] for item in ocr_items)
    invalid = ["ماركة","الماركة","نوع","التسجيل","حمولة","وزن","سنة","الصنع",
               "اللون","رقم","اللوحة","الهيكل","المالك","المستخدم","خاص","خصوصي","نقل","طراز","المركبة"]
    candidates = []

    for item in ocr_items:
        if item is anchor:
            continue
        text = item["normalized"].strip()
        if not text:
            continue
        vd = abs(item["cy"] - anchor["cy"])
        hd = anchor["cx"] - item["cx"]
        if vd > max(anchor["h"], item["h"]) * 2.0:
            continue
        if abs(hd) > max(image_width * 0.24, anchor["w"] * 5.0):
            continue

        cleaned = text
        for noise in ("طراز المركبة","طراذ المركبة","طراز","طراذ","المركبة"):
            cleaned = cleaned.replace(noise, "")
        cleaned = " ".join(cleaned.split()).strip()
        if not cleaned or any(kw in cleaned for kw in invalid):
            continue
        if cleaned.replace(" ", "").isdigit():
            continue
        tokens = cleaned.split()
        if len(tokens) <= 3 and all(t.isalpha() and len(t) == 1 for t in tokens):
            continue

        score = (3.0 if hd > 0 else -0.5) + max(0.0, 100.0 - vd) + item["confidence"] * 5.0
        if 2 <= len(cleaned) <= 20:
            score += 2.0
        candidates.append((score, cleaned))

    if not candidates:
        return ""
    candidates.sort(reverse=True)

    for _, cleaned in candidates:
        resolved = _resolve_model_alias(cleaned)
        if resolved in MODEL_ALIAS_MAP.values():
            return resolved
        norm = _normalize_match_text(cleaned)
        for model in COMMON_ARABIC_MODELS:
            if SequenceMatcher(None, norm, _normalize_match_text(model)).ratio() >= 0.80:
                return _resolve_model_alias(model)
    return ""


def _extract_model(texts: list) -> str:
    """Fallback model extraction from text lines."""
    invalid = ["المركبة","المرعبة","سنة","الصنع","نوع","التسجيل","حمولة","خاص","ماركة",
               "المالك","المستخدم","رقم","هوية","تاريخ","اللون","ابيض","اسود",
               "احمر","فضي","رمادي","ازرق","اخضر","وزن","ص","ح ك"]

    def is_valid(c):
        c = c.strip()
        if len(c) <= 1 or c == "اا" or c in ARABIC_BRANDS or c.replace(" ","").isdigit():
            return False
        return not any(kw in c for kw in invalid)

    for i, text in enumerate(texts):
        if "طراز" in text or "طراذ" in text:
            clean = re.sub(r'طرا[زذ]\s*(المركبة)?', '', text).strip()
            if is_valid(clean):
                return clean
            for j in [i-1, i+1, i-2, i+2]:
                if 0 <= j < len(texts) and is_valid(texts[j].strip()):
                    return texts[j].strip()

    for text in texts:
        for model in COMMON_ARABIC_MODELS:
            if model in text:
                return model
    return ""


# ── Color ─────────────────────────────────────────────────────────────
def _extract_color_by_anchor(ocr_items: list, image_width: int) -> str:
    """Extract vehicle color using anchor 'اللون'."""
    anchor = _find_anchor_item(ocr_items, ["اللون"])
    if not anchor:
        return ""

    candidates = []
    for item in ocr_items:
        if item is anchor:
            continue
        text = item["normalized"].strip()
        if not text:
            continue
        vd = abs(item["cy"] - anchor["cy"])
        hd = anchor["cx"] - item["cx"]
        if vd > max(anchor["h"], item["h"]) * 2.0:
            continue
        if abs(hd) > max(image_width * 0.20, anchor["w"] * 4.0):
            continue

        cleaned = " ".join(text.replace("اللون", "").split())
        if not cleaned:
            continue
        matched = _best_color_match(cleaned)
        if not matched:
            continue

        score = (3.0 if hd > 0 else -0.5) + max(0.0, 100.0 - vd) + item["confidence"] * 5.0
        if cleaned in ARABIC_COLORS:
            score += 10.0
        candidates.append((score, matched))

    if not candidates:
        return ""
    candidates.sort(reverse=True)
    return candidates[0][1]


def _extract_color(texts: list) -> str:
    """Fallback color extraction from text lines."""
    for text in texts:
        for color in ARABIC_COLORS:
            if color in text:
                return color
    return ""


# ── Main ──────────────────────────────────────────────────────────────
async def process_ocr_registration(file):
    """
    Main function called by FastAPI.
    Extracts vehicle data from registration card image in Arabic.
    """
    try:
        print("--- NEW OCR REQUEST STARTED ---")
        contents = await file.read()
        nparr    = np.frombuffer(contents, np.uint8)
        image    = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        if image is None:
            raise Exception("Invalid image file.")

        print("1. Running EasyOCR...")
        result          = reader.readtext(image, detail=0, text_threshold=0.5, low_text=0.3)
        result_detailed = reader.readtext(image, detail=1, text_threshold=0.5, low_text=0.3)
        print("   -> Done!")

        normalized_texts = [_normalize_text(t) for t in result]
        ocr_items        = _build_ocr_items(result_detailed)

        print("2. Extracting fields...")
        chassis_number     = _extract_chassis_number_by_anchor(ocr_items) or _extract_chassis_number(normalized_texts)
        plate_number       = _extract_plate_by_anchor(ocr_items)
        manufacturing_year = _extract_year_from_roi(image, ocr_items) or _extract_year(normalized_texts)
        make               = _extract_make_by_anchor(ocr_items) or _extract_brand(normalized_texts)
        model              = _extract_model_by_anchor(ocr_items) or _extract_model(normalized_texts)
        image_width        = image.shape[1]
        color              = _extract_color_by_anchor(ocr_items, image_width) or _extract_color(normalized_texts)

        structured_data = {
            "plateNumber":   plate_number,
            "make":          make,
            "model":         model,
            "year":          manufacturing_year,
            "color":         color,
            "chassisNumber": chassis_number,
        }

        print(f"3. Done! -> {structured_data}")

        return {
            "status":   "success",
            "raw_text": normalized_texts,
            "data":     structured_data,
        }

    except Exception as e:
        print(f"!!! SERVER ERROR: {str(e)}")
        return {"status": "error", "message": f"OCR Error: {str(e)}"}