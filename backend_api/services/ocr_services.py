import re
import cv2
import numpy as np
import easyocr
from deep_translator import GoogleTranslator
from difflib import SequenceMatcher
from datetime import datetime

# Initialize the reader once (Global) to speed up processing
print("Loading OCR Model...")
reader = easyocr.Reader(['ar', 'en'], gpu=False)


def _translate_to_english(text: str) -> str:
    """
    Translates Arabic text to English automatically using deep-translator.
    """
    if not text:
        return ""
    try:
        print(f"   [Network] Translating '{text}' via Google...")
        translator = GoogleTranslator(source='ar', target='en')
        translated = translator.translate(text)
        return translated.strip().title()
    except Exception as e:
        print(f"   [Error] Translation failed for '{text}': {e}")
        return text


# Arabic detection lists (used ONLY to find data in text; translation is automatic)
ARABIC_COLORS = [
    "أبيض", "ابيض", "أسود", "اسود", "فضي", "رمادي", "أحمر", "احمر",
    "أزرق", "ازرق", "أخضر", "اخضر", "بيج", "بني", "ذهبي", "برتقالي"
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
    # Standard aliases
    "هونداي":    "هيونداي",
    "هيونداي":   "هيونداي",
    "شفروليه":   "شيفروليه",
    "شيفروليه":  "شيفروليه",
    "دودج":      "دوج",
    "دوج":       "دوج",
    "جي ام سي":  "GMC",
    "جمس":       "GMC",
    "gmc":       "GMC",
    "بي ام دبليو": "BMW",
    "bmw":       "BMW",
    "ام جي":     "MG",
    "mg":        "MG",
    # Real-world OCR variants
    "شيفورلية":  "شيفروليه",
    "شيفوليه":   "شيفروليه",
    "شيفرولية":  "شيفروليه",
    "تيوتا":     "تويوتا",
    "تيوتو":     "تويوتا",
    "هيونداى":   "هيونداي",
    "هونداى":    "هيونداي",
    "نيسسان":    "نيسان",
    "مرسيدز":    "مرسيدس",
    "لكسس":      "لكزس",
}

MODEL_ALIAS_MAP = {
    "جي اكس ار": "GXR",
    "في اكس ار": "VXR",
    "gxr":       "GXR",
    "vxr":       "VXR",
}

ARABIC_PLATE_LETTER_MAP = {
    "ا": "A",
    "ب": "B",
    "ح": "J",
    "د": "D",
    "ر": "R",
    "س": "S",
    "ص": "X",
    "ط": "T",
    "ع": "E",
    "ق": "G",
    "ك": "K",
    "ل": "L",
    "م": "Z",
    "ن": "N",
    "ه": "H",
    "و": "U",
    "ى": "Y",
    "ي": "Y",
}

def _normalize_text(text: str) -> str:
    """
    Convert Arabic/Hindi digits to English digits and normalize spaces.
    Also fixes common Arabic letter misreads (like ى to ي) for better translation.
    """
    mapping = str.maketrans("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹", "01234567890123456789")
    text = text.translate(mapping)
    text = text.replace("ى", "ي")
    return " ".join(text.split())


def _normalize_match_text(text: str) -> str:
    """
    Normalize text for matching only, not for display.
    """
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
    """
    Validate a 4-digit manufacturing year dynamically.
    """
    if not re.fullmatch(r"\d{4}", year_text):
        return False

    year = int(year_text)
    current_year = datetime.now().year

    # Adjust lower bound if your real data needs older cars
    return 1970 <= year <= current_year + 1


def _extract_valid_year_candidates(text: str) -> list[str]:
    """
    Extract all 4-digit year-like candidates from text and keep only valid ones.
    """
    if not text:
        return []

    candidates = re.findall(r"\d{4}", text)
    return [c for c in candidates if _is_valid_year(c)]

def _resolve_brand_alias(text: str) -> str:
    """
    Return canonical brand if alias is known, otherwise return original text.
    """
    norm = _normalize_match_text(text)
    for alias, canonical in BRAND_ALIAS_MAP.items():
        alias_norm = _normalize_match_text(alias)
        if norm == alias_norm or alias_norm in norm:
            return canonical
    return text


def _resolve_model_alias(text: str) -> str:
    """
    Return canonical model if alias is known, otherwise return original text.
    """
    norm = _normalize_match_text(text)
    for alias, canonical in MODEL_ALIAS_MAP.items():
        alias_norm = _normalize_match_text(alias)
        if norm == alias_norm or alias_norm in norm:
            return canonical
    return text


def _build_ocr_items(result: list) -> list:
    """
    Convert EasyOCR detail=1 output into simple structured OCR items.
    """
    items = []
    for bbox, text, conf in result:
        normalized = _normalize_text(text)
        xs = [p[0] for p in bbox]
        ys = [p[1] for p in bbox]
        items.append({
            "text":       text,
            "normalized": normalized,
            "confidence": float(conf),
            "x_min": min(xs),
            "x_max": max(xs),
            "y_min": min(ys),
            "y_max": max(ys),
            "cx":  (min(xs) + max(xs)) / 2,
            "cy":  (min(ys) + max(ys)) / 2,
            "w":   max(xs) - min(xs),
            "h":   max(ys) - min(ys),
        })
    return items


def _find_anchor_item(ocr_items: list, keywords: list) -> dict | None:
    """
    Find the best matching anchor OCR item with fuzzy keyword matching.
    Handles OCR label mistakes like 'طراذ' vs 'طراز'.
    """
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
    """
    Safely crop an image region.
    """
    h, w = image.shape[:2]
    x1 = max(0, int(x1))
    y1 = max(0, int(y1))
    x2 = min(w, int(x2))
    y2 = min(h, int(y2))
    if x2 <= x1 or y2 <= y1:
        return None
    return image[y1:y2, x1:x2]


def _best_color_match(text: str) -> str:
    """
    Return the best matching Arabic color from ARABIC_COLORS using fuzzy similarity.
    """
    text = text.strip()
    if not text:
        return ""
    best_color = ""
    best_score = 0.0
    for color in ARABIC_COLORS:
        score = SequenceMatcher(None, text, color).ratio()
        if score > best_score:
            best_score = score
            best_color = color
    if best_score >= 0.6:
        return best_color
    return ""


def _extract_chassis_number_by_anchor(ocr_items: list) -> str:
    """
    Extract VIN using the anchor 'رقم الهيكل' and nearby OCR items only.
    """
    anchor = _find_anchor_item(ocr_items, ["رقم الهيكل", "الهيكل"])
    if not anchor:
        return ""

    candidates = []

    for item in ocr_items:
        if item is anchor:
            continue

        text = item["normalized"].replace(" ", "").upper()
        text = re.sub(r"[^A-Z0-9]", "", text)

        if len(text) < 14 or len(text) > 18:
            continue
        if not any(ch.isdigit() for ch in text):
            continue
        if not any(ch.isalpha() for ch in text):
            continue

        vertical_diff   = abs(item["cy"] - anchor["cy"])
        horizontal_diff = anchor["cx"] - item["cx"]

        if vertical_diff > max(anchor["h"], item["h"]) * 2.0:
            continue

        score = 0
        if horizontal_diff > 0:
            score += 3
        else:
            score -= 1

        score += max(0, 120 - vertical_diff)

        if len(text) == 17:
            score += 10
        elif len(text) == 16:
            score += 7
        elif len(text) == 15:
            score += 5
        elif len(text) == 18:
            score += 4
        else:
            score += 1

        score += min(item["w"] / 20, 10)
        score += item["confidence"] * 5

        candidates.append((score, text))

    if not candidates:
        return ""

    candidates.sort(reverse=True)
    _, best_text = candidates[0]
    return best_text

def _normalize_plate_text(text: str) -> str:
    """
    Normalize plate OCR text while preserving Arabic and English letters.
    """
    if not text:
        return ""

    text = _normalize_text(text).strip().upper()
    text = " ".join(text.split())
    return text


def _extract_arabic_plate_letters(text: str) -> str:
    """
    Extract Arabic plate letters from text and map them to English equivalents.

    Arabic plate letters are often read in visual RTL order, while the final
    English plate output should be LTR, so we reverse the Arabic sequence first.
    """
    if not text:
        return ""

    arabic_letters = re.findall(r"[ابتثجحخدذرزسشصضطظعغفقكلمنهوىي]", text)
    if not arabic_letters:
        return ""

    # Reverse Arabic plate letters so the final mapped English letters
    # come out in left-to-right order
    arabic_letters = arabic_letters[::-1]

    mapped = []
    for ch in arabic_letters:
        mapped_letter = ARABIC_PLATE_LETTER_MAP.get(ch)
        if mapped_letter:
            mapped.append(mapped_letter)

    if len(mapped) >= 3:
        return "".join(mapped[:3])

    return ""


def _looks_like_arabic_plate_letter(text: str) -> bool:
    """
    True if text is a single Arabic plate letter candidate.
    """
    if not text:
        return False
    compact = re.sub(r"\s+", "", text)
    return bool(re.fullmatch(r"[ابتثجحخدذرزسشصضطظعغفقكلمنهوىي]", compact))

def _extract_plate_by_anchor(ocr_items: list) -> str:
    """
    Extract plate number using anchor 'رقم اللوحة'.

    Improvements:
    1. relative horizontal threshold instead of fixed 650
    2. smarter single-letter grouping
    3. Arabic plate-letter support
    4. final sanity check before returning a full plate
    """
    anchor = _find_anchor_item(ocr_items, ["رقم اللوحة", "اللوحة"])
    if not anchor or not ocr_items:
        return ""

    image_width = max(item["x_max"] for item in ocr_items)

    nearby_items = []

    for item in ocr_items:
        if item is anchor:
            continue

        text = _normalize_plate_text(item["normalized"])
        if not text:
            continue

        vertical_diff = abs(item["cy"] - anchor["cy"])
        horizontal_diff = anchor["cx"] - item["cx"]

        if vertical_diff > max(anchor["h"], item["h"]) * 2.2:
            continue

        horizontal_limit = max(image_width * 0.28, anchor["w"] * 6.0)
        if abs(horizontal_diff) > horizontal_limit:
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

    number_candidates = []
    letter_candidates = []
    single_letter_items = []
    single_arabic_letter_items = []

    for item in nearby_items:
        text = item["text"]
        compact = re.sub(r"\s+", "", text)

        # Case 1: number only
        if re.fullmatch(r"\d{1,4}", compact):
            number_candidates.append({
                "score": item["score"] + 4,
                "value": compact,
                "cx": item["cx"],
                "cy": item["cy"],
            })

        # Case 2: English letters only
        elif re.fullmatch(r"[A-Z]{3}", compact):
            letter_candidates.append({
                "score": item["score"] + 4,
                "value": compact,
                "cx": item["cx"],
                "cy": item["cy"],
            })

        # Case 3: single English letter
        elif re.fullmatch(r"[A-Z]", compact):
            single_letter_items.append(item)

        # Case 4: single Arabic plate letter
        elif _looks_like_arabic_plate_letter(compact):
            single_arabic_letter_items.append(item)

        else:
            # Case 5: merged full plate like 6987GTJ
            match = re.fullmatch(r"(\d{1,4})([A-Z]{3})", compact)
            if match:
                digits, letters = match.groups()
                number_candidates.append({
                    "score": item["score"] + 6,
                    "value": digits,
                    "cx": item["cx"],
                    "cy": item["cy"],
                })
                letter_candidates.append({
                    "score": item["score"] + 6,
                    "value": letters,
                    "cx": item["cx"],
                    "cy": item["cy"],
                })
                continue

            # Case 6: digits and English letters separated by spaces/noise
            match = re.search(r"(\d{1,4}).*?([A-Z]\s*[A-Z]\s*[A-Z])", text)
            if match:
                digits = match.group(1)
                letters = re.sub(r"\s+", "", match.group(2))
                number_candidates.append({
                    "score": item["score"] + 5,
                    "value": digits,
                    "cx": item["cx"],
                    "cy": item["cy"],
                })
                letter_candidates.append({
                    "score": item["score"] + 5,
                    "value": letters,
                    "cx": item["cx"],
                    "cy": item["cy"],
                })

            # Case 7: Arabic letters inside a multi-character text block
            arabic_letters = _extract_arabic_plate_letters(text)
            if arabic_letters and re.fullmatch(r"[A-Z]{3}", arabic_letters):
                letter_candidates.append({
                    "score": item["score"] + 4,
                    "value": arabic_letters,
                    "cx": item["cx"],
                    "cy": item["cy"],
                })

    # Smarter English single-letter grouping
    if len(single_letter_items) >= 3:
        single_letter_items.sort(key=lambda x: x["cx"])

        best_group = None
        best_group_score = -1.0

        for i in range(len(single_letter_items) - 2):
            group = single_letter_items[i:i + 3]

            cy_values = [g["cy"] for g in group]
            cx_values = [g["cx"] for g in group]

            max_vertical_spread = max(cy_values) - min(cy_values)
            max_horizontal_gap = max(
                abs(cx_values[1] - cx_values[0]),
                abs(cx_values[2] - cx_values[1])
            )

            avg_h = sum(g["h"] for g in group) / 3.0

            if max_vertical_spread > avg_h * 0.8:
                continue
            if max_horizontal_gap > max(anchor["w"] * 1.8, 90):
                continue

            letters = "".join(re.sub(r"\s+", "", g["text"]) for g in group)
            if not re.fullmatch(r"[A-Z]{3}", letters):
                continue

            group_score = sum(g["score"] for g in group) / 3.0

            if group_score > best_group_score:
                best_group_score = group_score
                best_group = {
                    "score": group_score + 3,
                    "value": letters,
                    "cx": sum(g["cx"] for g in group) / 3.0,
                    "cy": sum(g["cy"] for g in group) / 3.0,
                }

        if best_group:
            letter_candidates.append(best_group)

    # Smarter Arabic single-letter grouping
    if len(single_arabic_letter_items) >= 3:
        single_arabic_letter_items.sort(key=lambda x: x["cx"])

        best_group = None
        best_group_score = -1.0

        for i in range(len(single_arabic_letter_items) - 2):
            group = single_arabic_letter_items[i:i + 3]

            cy_values = [g["cy"] for g in group]
            cx_values = [g["cx"] for g in group]

            max_vertical_spread = max(cy_values) - min(cy_values)
            max_horizontal_gap = max(
                abs(cx_values[1] - cx_values[0]),
                abs(cx_values[2] - cx_values[1])
            )

            avg_h = sum(g["h"] for g in group) / 3.0

            if max_vertical_spread > avg_h * 0.8:
                continue
            if max_horizontal_gap > max(anchor["w"] * 1.8, 90):
                continue

            arabic_text = "".join(re.sub(r"\s+", "", g["text"]) for g in group)
            mapped_letters = _extract_arabic_plate_letters(arabic_text)

            if not re.fullmatch(r"[A-Z]{3}", mapped_letters):
                continue

            group_score = sum(g["score"] for g in group) / 3.0

            if group_score > best_group_score:
                best_group_score = group_score
                best_group = {
                    "score": group_score + 3,
                    "value": mapped_letters,
                    "cx": sum(g["cx"] for g in group) / 3.0,
                    "cy": sum(g["cy"] for g in group) / 3.0,
                }

        if best_group:
            letter_candidates.append(best_group)

    number_candidates.sort(key=lambda x: x["score"], reverse=True)
    letter_candidates.sort(key=lambda x: x["score"], reverse=True)

    best_number = number_candidates[0] if number_candidates else None
    best_letters = letter_candidates[0] if letter_candidates else None

    # Final sanity check for full plate
    if best_number and best_letters:
        digits = best_number["value"]
        letters = best_letters["value"]

        same_row = abs(best_number["cy"] - best_letters["cy"]) <= max(anchor["h"] * 1.2, 35)
        close_enough = abs(best_number["cx"] - best_letters["cx"]) <= max(image_width * 0.20, 180)

        if (
            re.fullmatch(r"\d{1,4}", digits)
            and re.fullmatch(r"[A-Z]{3}", letters)
            and same_row
            and close_enough
        ):
            return f"{digits} {' '.join(letters)}"

    if best_number and re.fullmatch(r"\d{1,4}", best_number["value"]):
        return best_number["value"]

    if best_letters and re.fullmatch(r"[A-Z]{3}", best_letters["value"]):
        return " ".join(best_letters["value"])

    return ""

def _extract_year_from_roi(image, ocr_items: list) -> str:
    """
    Extract manufacturing year by locating 'سنة الصنع', cropping a tight
    region near it, enlarging it, then OCRing only that area.
    """
    anchor = _find_anchor_item(ocr_items, ["سنة الصنع", "سنة", "صنع"])
    if not anchor:
        print("YEAR: no anchor found")
        return ""

    print(
        "YEAR ANCHOR:",
        anchor["normalized"],
        anchor["x_min"], anchor["y_min"],
        anchor["x_max"], anchor["y_max"]
    )

    roi_x1 = anchor["x_min"] - max(anchor["w"] * 2.2, 140)
    roi_x2 = anchor["x_min"] + max(anchor["w"] * 0.3, 25)
    roi_y1 = anchor["y_min"] - max(anchor["h"] * 0.4, 10)
    roi_y2 = anchor["y_max"] + max(anchor["h"] * 1.2, 35)

    print("YEAR ROI:", roi_x1, roi_y1, roi_x2, roi_y2)

    roi = _crop_region(image, roi_x1, roi_y1, roi_x2, roi_y2)
    if roi is None or roi.size == 0:
        print("YEAR ROI is empty")
        return ""

    roi = cv2.resize(roi, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)
    print("YEAR ROI shape:", roi.shape)

    try:
        roi_result = reader.readtext(roi, detail=0, text_threshold=0.35, low_text=0.2)
    except Exception as e:
        print("YEAR ROI OCR ERROR:", e)
        return ""

    roi_texts = [_normalize_text(t) for t in roi_result]
    print("YEAR ROI OCR:", roi_texts)

    for text in roi_texts:
        compact = re.sub(r"\s+", "", text)

        # 1) Normal case: direct 4-digit year
        direct_candidates = _extract_valid_year_candidates(compact)
        if direct_candidates:
            return direct_candidates[0]

        # 2) Reversed OCR case, e.g. "5201" for "1025" or similar mistakes
        if re.fullmatch(r"\d{4}", compact):
            reversed_text = compact[::-1]
            reversed_candidates = _extract_valid_year_candidates(reversed_text)
            if reversed_candidates:
                return reversed_candidates[0]

        # 3) Spaced/reordered case like "20 15" or "15 20"
        parts = re.findall(r"\d{2}", text)
        if len(parts) == 2:
            candidate1 = parts[0] + parts[1]
            candidate2 = parts[1] + parts[0]

            for candidate in (candidate1, candidate2):
                if _is_valid_year(candidate):
                    return candidate

    return ""


def _extract_make_by_anchor(ocr_items: list) -> str:
    """
    Extract vehicle make using anchor 'ماركة المركبة'.

    Safer strategy:
    1. Alias map.
    2. Fuzzy match against ARABIC_BRANDS.
    3. If no confident match, return empty.
    """
    anchor = _find_anchor_item(ocr_items, ["ماركة المركبة", "ماركة"])
    if not anchor or not ocr_items:
        return ""

    image_width = max(item["x_max"] for item in ocr_items)

    invalid_keywords = [
        "طراز", "نوع", "التسجيل", "حمولة", "وزن", "سنة", "الصنع",
        "اللون", "رقم", "اللوحة", "الهيكل", "المستخدم", "المالك",
        "خاص", "خصوصي", "نقل", "عمومي"
    ]

    candidates = []

    for item in ocr_items:
        if item is anchor:
            continue

        text = item["normalized"].strip()
        if not text:
            continue

        vertical_diff = abs(item["cy"] - anchor["cy"])
        horizontal_diff = anchor["cx"] - item["cx"]

        if vertical_diff > max(anchor["h"], item["h"]) * 2.0:
            continue

        horizontal_limit = max(image_width * 0.22, anchor["w"] * 4.5)
        if abs(horizontal_diff) > horizontal_limit:
            continue

        cleaned = text
        for noise in ("ماركة المركبة", "ماركة", "المركبة"):
            cleaned = cleaned.replace(noise, "")
        cleaned = " ".join(cleaned.split()).strip()

        if not cleaned:
            continue
        if any(kw in cleaned for kw in invalid_keywords):
            continue

        score = 0.0
        if horizontal_diff > 0:
            score += 3.0
        else:
            score -= 0.5
        score += max(0.0, 100.0 - vertical_diff)
        score += item["confidence"] * 5.0

        candidates.append((score, cleaned))

    if not candidates:
        return ""

    candidates.sort(key=lambda x: x[0], reverse=True)

    for _, cleaned in candidates:
        cleaned_norm = _normalize_match_text(cleaned)

        # 1) Alias map
        for alias, canonical in BRAND_ALIAS_MAP.items():
            alias_norm = _normalize_match_text(alias)
            if cleaned_norm == alias_norm or alias_norm in cleaned_norm:
                return canonical

        # 2) Fuzzy match against known Arabic brands
        for brand in ARABIC_BRANDS:
            brand_norm = _normalize_match_text(brand)
            if SequenceMatcher(None, cleaned_norm, brand_norm).ratio() >= 0.75:
                return _resolve_brand_alias(brand)

    # 3) No raw fallback
    return ""


def _extract_model_by_anchor(ocr_items: list) -> str:
    """
    Extract vehicle model using anchor 'طراز المركبة'.

    Safer strategy:
    1. Alias map.
    2. Fuzzy match against COMMON_ARABIC_MODELS.
    3. If no confident match, return empty.
    """
    anchor = _find_anchor_item(ocr_items, ["طراز المركبة", "طراز", "طراذ"])
    if not anchor or not ocr_items:
        return ""

    image_width = max(item["x_max"] for item in ocr_items)

    invalid_keywords = [
        "ماركة", "الماركة", "نوع", "التسجيل", "حمولة", "وزن",
        "سنة", "الصنع", "اللون", "رقم", "اللوحة", "الهيكل",
        "المالك", "المستخدم", "خاص", "خصوصي", "نقل",
        "طراز", "المركبة"
    ]

    candidates = []

    for item in ocr_items:
        if item is anchor:
            continue

        text = item["normalized"].strip()
        if not text:
            continue

        vertical_diff = abs(item["cy"] - anchor["cy"])
        horizontal_diff = anchor["cx"] - item["cx"]

        if vertical_diff > max(anchor["h"], item["h"]) * 2.0:
            continue

        horizontal_limit = max(image_width * 0.24, anchor["w"] * 5.0)
        if abs(horizontal_diff) > horizontal_limit:
            continue

        cleaned = text
        for noise in ("طراز المركبة", "طراذ المركبة", "طراز", "طراذ", "المركبة"):
            cleaned = cleaned.replace(noise, "")
        cleaned = " ".join(cleaned.split()).strip()

        if not cleaned:
            continue
        if any(kw in cleaned for kw in invalid_keywords):
            continue
        if cleaned.replace(" ", "").isdigit():
            continue

        tokens = cleaned.split()
        if len(tokens) <= 3 and all(t.isalpha() and len(t) == 1 for t in tokens):
            continue

        score = 0.0
        if horizontal_diff > 0:
            score += 3.0
        else:
            score -= 0.5
        score += max(0.0, 100.0 - vertical_diff)
        score += item["confidence"] * 5.0
        if 2 <= len(cleaned) <= 20:
            score += 2.0

        candidates.append((score, cleaned))

    if not candidates:
        return ""

    candidates.sort(key=lambda x: x[0], reverse=True)

    for _, cleaned in candidates:
        # 1) Alias map
        resolved = _resolve_model_alias(cleaned)
        if resolved in MODEL_ALIAS_MAP.values():
            return resolved

        # 2) Fuzzy match against known models
        cleaned_norm = _normalize_match_text(cleaned)
        for model in COMMON_ARABIC_MODELS:
            model_norm = _normalize_match_text(model)
            if SequenceMatcher(None, cleaned_norm, model_norm).ratio() >= 0.80:
                return _resolve_model_alias(model)

    # 3) No raw fallback
    return ""


def _extract_color_by_anchor(ocr_items: list, image_width: int) -> str:
    """
    Extract vehicle color using anchor 'اللون' and fuzzy matching.
    """
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

        vertical_diff   = abs(item["cy"] - anchor["cy"])
        horizontal_diff = anchor["cx"] - item["cx"]

        if vertical_diff > max(anchor["h"], item["h"]) * 2.0:
            continue

        horizontal_limit = max(image_width * 0.20, anchor["w"] * 4.0)
        if abs(horizontal_diff) > horizontal_limit:
            continue

        cleaned = text.replace("اللون", "").strip()
        cleaned = " ".join(cleaned.split())
        if not cleaned:
            continue

        matched_color = _best_color_match(cleaned)
        if not matched_color:
            continue

        score = 0.0
        if horizontal_diff > 0:
            score += 3.0
        else:
            score -= 0.5
        score += max(0.0, 100.0 - vertical_diff)
        score += item["confidence"] * 5.0
        if cleaned in ARABIC_COLORS:
            score += 10.0

        candidates.append((score, matched_color))

    if not candidates:
        return ""

    candidates.sort(key=lambda x: x[0], reverse=True)
    return _translate_to_english(candidates[0][1])




def _extract_plate_english(texts: list) -> str:
    """
    Extract the English plate number, format it, and fix common OCR errors.
    """
    pattern = r'\b(\d{1,4})\s*([A-Za-z\*84])\s*([A-Za-z\*84])\s*([A-Za-z1084])\b'

    def fix_letter(l):
        return (
            l.replace('*', 'X')
             .replace('1', 'J')
             .replace('0', 'O')
             .replace('8', 'B')
             .replace('4', 'A')
             .upper()
        )

    for text in texts:
        match = re.search(pattern, text)
        if match:
            n, l1, l2, l3 = match.groups()
            return f"{n} {fix_letter(l1)} {fix_letter(l2)} {fix_letter(l3)}"
    return ""


def _extract_chassis_number(texts: list) -> str:
    """
    The chassis number (VIN) always consists of 17 English letters and numbers.
    """
    for text in texts:
        clean_text = text.replace(" ", "").upper()
        match = re.search(r'[A-Z0-9]{15,17}', clean_text)
        if match:
            vin = match.group()
            if any(char.isdigit() for char in vin):
                return vin
    return ""


def _extract_year(texts: list) -> str:
    """
    Extract manufacturing year from OCR text lines.
    """
    for i, text in enumerate(texts):
        if "سنة" in text or "صنع" in text:
            candidates = _extract_valid_year_candidates(text)
            if candidates:
                return candidates[0]

            if i + 1 < len(texts):
                candidates = _extract_valid_year_candidates(texts[i + 1])
                if candidates:
                    return candidates[0]

    for text in texts:
        candidates = _extract_valid_year_candidates(text)
        if candidates:
            return candidates[0]

    return ""


def _extract_color(texts: list) -> str:
    """
    Search for common colors in the registration card and return the English translation.
    """
    for text in texts:
        for color in ARABIC_COLORS:
            if color in text:
                return _translate_to_english(color)
    return ""


def _extract_brand(texts: list) -> str:
    """
    Search for the vehicle brand and return the English translation.
    """
    for text in texts:
        for brand in ARABIC_BRANDS:
            if brand in text:
                if brand in ["جمس", "جي ام سي"]:
                    return "GMC"
                if brand == "بي ام دبليو":
                    return "BMW"
                return _translate_to_english(brand)
    return ""


def _extract_model(texts: list) -> str:
    """
    Search for the vehicle model and return it in English.
    """
    invalid_keywords = [
        "المركبة", "سنة", "الصنع", "نوع", "التسجيل", "حمولة", "خاص", "ماركة",
        "المالك", "المستخدم", "رقم", "هوية", "تاريخ", "اللون", "ابيض", "اسود",
        "احمر", "فضي", "رمادي", "ازرق", "اخضر", "وزن", "ص", "ح ك"
    ]

    def is_valid_candidate(c: str) -> bool:
        c_strip = c.strip()
        if len(c_strip) <= 1 or c_strip == "اا":
            return False
        if c_strip in ARABIC_BRANDS:
            return False
        if c_strip.replace(" ", "").isdigit():
            return False
        for kw in invalid_keywords:
            if kw in c_strip:
                return False
        return True

    for i, text in enumerate(texts):
        if "طراز" in text or "طراذ" in text:
            clean_text = re.sub(r'طرا[زذ]\s*(المركبة)?', '', text).strip()
            if is_valid_candidate(clean_text):
                return _translate_to_english(clean_text)

            for j in [i - 1, i + 1, i - 2, i + 2]:
                if 0 <= j < len(texts):
                    candidate = texts[j].strip()
                    if is_valid_candidate(candidate):
                        return _translate_to_english(candidate)

    for text in texts:
        for model in COMMON_ARABIC_MODELS:
            if model in text:
                if model == "جي اكس ار":
                    return "GXR"
                if model == "في اكس ار":
                    return "VXR"
                return _translate_to_english(model)

    return ""


async def process_ocr(file):
    """
    Main function called by FastAPI.
    Receives an image, extracts text, translates automatically,
    and returns structured data in English.
    """
    try:
        print("--- NEW OCR REQUEST STARTED ---")
        contents = await file.read()
        nparr    = np.frombuffer(contents, np.uint8)
        image    = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        if image is None:
            raise Exception("Invalid image file. Please upload a valid image.")

        print("1. Starting EasyOCR processing... (Waiting for CPU)")
        result          = reader.readtext(image, detail=0, text_threshold=0.5, low_text=0.3)
        result_detailed = reader.readtext(image, detail=1, text_threshold=0.5, low_text=0.3)
        print("   -> OCR Finished successfully!")

        normalized_texts = [_normalize_text(text) for text in result]
        ocr_items        = _build_ocr_items(result_detailed)

        print("2. Extracting and Translating Data...")

        chassis_number     = _extract_chassis_number_by_anchor(ocr_items) or _extract_chassis_number(normalized_texts)
        plate_number       = _extract_plate_by_anchor(ocr_items) or _extract_plate_english(normalized_texts)
        manufacturing_year = _extract_year_from_roi(image, ocr_items) or _extract_year(normalized_texts)

        make_raw = _extract_make_by_anchor(ocr_items)
        if make_raw:
            if make_raw in {"GMC", "BMW", "MG"}:
                make = make_raw
            else:
                make = _translate_to_english(make_raw)
        else:
            make = _extract_brand(normalized_texts)

        model_raw = _extract_model_by_anchor(ocr_items)
        if model_raw:
            if model_raw in {"GXR", "VXR"}:
                model = model_raw
            else:
                model = _translate_to_english(model_raw)
        else:
            model = _extract_model(normalized_texts)

        image_width = image.shape[1]
        color       = _extract_color_by_anchor(ocr_items, image_width) or _extract_color(normalized_texts)

        structured_data = {
            "plateNumber":       plate_number,
            "make":               make,
            "model":              model,
            "year": manufacturing_year,
            "color":              color,
            "chassisNumber":     chassis_number,
        }

        print("3. Data Processed Successfully!")
        print(f"   -> Result: {structured_data}")

        return {
            "status":   "success",
            "raw_text": normalized_texts,
            "data":     structured_data,
        }

    except Exception as e:
        print(f"!!! SERVER ERROR: {str(e)}")
        return {"status": "error", "message": f"OCR Error: {str(e)}"}