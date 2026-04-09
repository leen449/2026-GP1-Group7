import re
import cv2
import numpy as np
import easyocr
from deep_translator import GoogleTranslator
from difflib import SequenceMatcher

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
        # Initialize locally per request to avoid session hanging/timeouts
        translator = GoogleTranslator(source='ar', target='en')
        translated = translator.translate(text)
        return translated.strip().title()
    except Exception as e:
        print(f"   [Error] Translation failed for '{text}': {e}")
        return text # Fallback to original text if translation fails

# Arabic detection lists (Used ONLY to find the data in the text, translation is automatic)
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


def _normalize_text(text: str) -> str:
    """
    Convert Arabic/Hindi digits to English digits and normalize spaces.
    Also fixes common Arabic letter misreads (like ى to ي) for better translation.
    """
    # 1. Convert digits
    mapping = str.maketrans("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹", "01234567890123456789")
    text = text.translate(mapping)
    
    # 2. Fix common OCR mistakes (Alif Maksura to Ya)
    text = text.replace("ى", "ي")
    
    return " ".join(text.split())

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
            "text": text,
            "normalized": normalized,
            "confidence": float(conf),
            "x_min": min(xs),
            "x_max": max(xs),
            "y_min": min(ys),
            "y_max": max(ys),
            "cx": (min(xs) + max(xs)) / 2,
            "cy": (min(ys) + max(ys)) / 2,
            "w": max(xs) - min(xs),
            "h": max(ys) - min(ys),
        })

    return items


def _find_anchor_item(ocr_items: list, keywords: list) -> dict | None:
    """
    Find the best matching anchor OCR item.
    """
    matches = []

    for item in ocr_items:
        text = item["normalized"]
        if any(kw in text for kw in keywords):
            matches.append(item)

    if not matches:
        return None

    # choose the longest / most complete matching label
    matches.sort(key=lambda x: (len(x["normalized"]), x["confidence"]), reverse=True)
    return matches[0]

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

def _extract_year_from_roi(image, ocr_items: list) -> str:
    """
    Extract manufacturing year by:
    1) locating the anchor 'سنة الصنع'
    2) cropping the nearby expected year region
    3) running OCR again only on that small crop
    """
    anchor = _find_anchor_item(ocr_items, ["سنة الصنع", "سنة", "صنع"])
    if not anchor:
        return ""

    # On Arabic cards, the value is usually to the left of the label,
    # and roughly on the same row or slightly below.
    roi_x1 = anchor["x_min"] - max(anchor["w"] * 7.0, 320)
    roi_x2 = anchor["x_max"] + max(anchor["w"] * 1.5, 80)
    roi_y1 = anchor["y_min"] - max(anchor["h"] * 1.0, 30)
    roi_y2 = anchor["y_max"] + max(anchor["h"] * 3.0, 80) 

    roi = _crop_region(image, roi_x1, roi_y1, roi_x2, roi_y2)
    if roi is None or roi.size == 0:
        return ""

    try:
        roi_result = reader.readtext(
            roi,
            detail=0,
            text_threshold=0.4,
            low_text=0.2
        )
    except Exception:
        return ""

    roi_texts = [_normalize_text(t) for t in roi_result]

    # Search clean 4-digit year first
    for text in roi_texts:
        compact = re.sub(r"\s+", "", text)
        match = re.search(r'(19[8-9]\d|20[0-3]\d)', compact)
        if match:
            return match.group(1)
        print("Year ROI OCR:", roi_texts)
        
        
    return ""

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

    # Accept reasonably close OCR misspellings like "ابض" -> "ابيض"
    if best_score >= 0.6:
        return best_color

    return ""

def _extract_chassis_number_by_anchor(ocr_items: list) -> str:
    """
    Extract VIN using the anchor 'رقم الهيكل' and nearby OCR items only.
    More tolerant than before: if the best nearby candidate is VIN-like,
    return it even if OCR made a small mistake.
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

        # allow near-VIN lengths, not only perfect ones
        if len(text) < 14 or len(text) > 18:
            continue

        # must contain both letters and digits
        if not any(ch.isdigit() for ch in text):
            continue
        if not any(ch.isalpha() for ch in text):
            continue

        vertical_diff = abs(item["cy"] - anchor["cy"])
        horizontal_diff = anchor["cx"] - item["cx"]  # positive means left of anchor

        # keep only nearby candidates
        if vertical_diff > max(anchor["h"], item["h"]) * 2.0:
            continue

        score = 0

        # prefer candidates left of the Arabic label
        if horizontal_diff > 0:
            score += 3
        else:
            score -= 1

        # prefer same row
        score += max(0, 120 - vertical_diff)

        # prefer longer candidates closer to VIN length
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

        # prefer wider text boxes (VINs are usually visually long)
        score += min(item["w"] / 20, 10)

        # tiny boost for confidence
        score += item["confidence"] * 5

        candidates.append((score, text))

    if not candidates:
        return ""

    candidates.sort(reverse=True)
    best_score, best_text = candidates[0]

    # Return the best nearby VIN-like candidate, even if slightly imperfect
    return best_text

def _extract_plate_by_anchor(ocr_items: list) -> str:
    """
    Extract plate number using anchor 'رقم اللوحة'.
    More flexible than before:
    - handles merged strings like 6987GTJ
    - handles spaced letters like X K J
    - combines separate letter boxes
    - returns partial result if only number is found
    """
    anchor = _find_anchor_item(ocr_items, ["رقم اللوحة", "اللوحة"])
    if not anchor:
        return ""

    nearby_items = []

    for item in ocr_items:
        if item is anchor:
            continue

        text = item["normalized"].strip().upper()
        if not text:
            continue

        vertical_diff = abs(item["cy"] - anchor["cy"])
        horizontal_diff = anchor["cx"] - item["cx"]  # positive => left of anchor

        # Keep nearby items only
        if vertical_diff > max(anchor["h"], item["h"]) * 2.2:
            continue

        if abs(horizontal_diff) > 650:
            continue

        # Prefer nearby items left of Arabic label, but do not force it
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

    for item in nearby_items:
        text = item["text"]
        compact = re.sub(r"\s+", "", text)

        # Case 1: number only
        if re.fullmatch(r"\d{1,4}", compact):
            number_candidates.append((item["score"] + 4, compact))

        # Case 2: letters only, maybe spaced
        elif re.fullmatch(r"[A-Z]{3}", compact):
            letter_candidates.append((item["score"] + 4, compact))

        # Case 3: single letter box
        elif re.fullmatch(r"[A-Z]", compact):
            single_letter_items.append(item)

        # Case 4: merged full plate like 6987GTJ
        else:
            match = re.fullmatch(r"(\d{1,4})([A-Z]{3})", compact)
            if match:
                digits, letters = match.groups()
                number_candidates.append((item["score"] + 6, digits))
                letter_candidates.append((item["score"] + 6, letters))
                continue

            # Case 5: maybe digits and letters separated by spaces/noise
            match = re.search(r"(\d{1,4}).*?([A-Z]\s*[A-Z]\s*[A-Z])", text)
            if match:
                digits = match.group(1)
                letters = re.sub(r"\s+", "", match.group(2))
                number_candidates.append((item["score"] + 5, digits))
                letter_candidates.append((item["score"] + 5, letters))

    # Combine separate single-letter OCR boxes if needed
    if len(single_letter_items) >= 3:
        # sort visually from left to right
        single_letter_items.sort(key=lambda x: x["cx"])
        letters = "".join(re.sub(r"\s+", "", item["text"]) for item in single_letter_items[:3])
        if re.fullmatch(r"[A-Z]{3}", letters):
            combined_score = sum(item["score"] for item in single_letter_items[:3]) / 3.0
            letter_candidates.append((combined_score + 3, letters))

    number_candidates.sort(reverse=True)
    letter_candidates.sort(reverse=True)

    best_number = number_candidates[0][1] if number_candidates else ""
    best_letters = letter_candidates[0][1] if letter_candidates else ""

    # Best case: full plate
    if best_number and best_letters:
        return f"{best_number} {' '.join(best_letters)}"

    # Partial fallback: still return number if that's all we confidently have
    if best_number:
        return best_number

    # Or letters only if that is all we have
    if best_letters:
        return " ".join(best_letters)

    return ""

def _extract_year_from_roi(image, ocr_items: list) -> str:
    """
    Extract manufacturing year by locating 'سنة الصنع',
    cropping a tight region near it, enlarging it,
    then OCRing only that area.
    """
    anchor = _find_anchor_item(ocr_items, ["سنة الصنع", "سنة", "صنع"])
    if not anchor:
        print("YEAR: no anchor found")
        return ""

    print("YEAR ANCHOR:", anchor["normalized"], anchor["x_min"], anchor["y_min"], anchor["x_max"], anchor["y_max"])

    # Tighter ROI: mainly left of the label, slightly below it
    roi_x1 = anchor["x_min"] - max(anchor["w"] * 2.2, 140)
    roi_x2 = anchor["x_min"] + max(anchor["w"] * 0.3, 25)
    roi_y1 = anchor["y_min"] - max(anchor["h"] * 0.4, 10)
    roi_y2 = anchor["y_max"] + max(anchor["h"] * 1.2, 35)

    print("YEAR ROI:", roi_x1, roi_y1, roi_x2, roi_y2)

    roi = _crop_region(image, roi_x1, roi_y1, roi_x2, roi_y2)
    if roi is None or roi.size == 0:
        print("YEAR ROI is empty")
        return ""

    # Enlarge ROI because year digits are small
    roi = cv2.resize(roi, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)

    print("YEAR ROI shape:", roi.shape)

    try:
        roi_result = reader.readtext(
            roi,
            detail=0,
            text_threshold=0.35,
            low_text=0.2
        )
    except Exception as e:
        print("YEAR ROI OCR ERROR:", e)
        return ""

    roi_texts = [_normalize_text(t) for t in roi_result]
    print("YEAR ROI OCR:", roi_texts)

    # Prefer a clean 4-digit year
    for text in roi_texts:
     compact = re.sub(r"\s+", "", text)

      # 1) Normal case (e.g., 2023)
     match = re.search(r'(19[8-9]\d|20[0-3]\d)', compact)
     if match:
        return match.group(1)

      # 2) Handle reversed OCR like "2320" (from "23 20")
     if re.fullmatch(r'\d{4}', compact):
        # try reversing
        reversed_text = compact[::-1]

        match = re.search(r'(19[8-9]\d|20[0-3]\d)', reversed_text)
        if match:
            return match.group(1)

    # 3) Handle spaced/reordered like "23 20"
    parts = re.findall(r'\d{2}', text)
    if len(parts) == 2:
        candidate1 = parts[0] + parts[1]
        candidate2 = parts[1] + parts[0]

        for candidate in (candidate1, candidate2):
            if re.fullmatch(r'(19[8-9]\d|20[0-3]\d)', candidate):
                return candidate

    return ""

def _extract_make_by_anchor(ocr_items: list) -> str:
    """
    Extract vehicle make using anchor 'ماركة المركبة'.
    Prefer known brand names and ignore label words / nearby model phrases.
    """
    anchor = _find_anchor_item(ocr_items, ["ماركة المركبة", "ماركة"])
    if not anchor:
        return ""

    candidates = []

    for item in ocr_items:
        if item is anchor:
            continue

        text = item["normalized"].strip()
        if not text:
            continue

        vertical_diff = abs(item["cy"] - anchor["cy"])
        horizontal_diff = anchor["cx"] - item["cx"]  # positive => left of anchor

        # Keep only nearby candidates
        if vertical_diff > max(anchor["h"], item["h"]) * 2.0:
            continue

        if abs(horizontal_diff) > 500:
            continue

        # Clean obvious label words
        cleaned = text
        cleaned = cleaned.replace("ماركة المركبة", "")
        cleaned = cleaned.replace("ماركة", "")
        cleaned = cleaned.replace("المركبة", "")
        cleaned = cleaned.strip()

        if not cleaned:
            continue

        # Reject obvious non-make phrases
        invalid_keywords = [
    "طراز", "نوع", "التسجيل", "حمولة", "وزن", "سنة", "الصنع",
    "اللون", "رقم", "اللوحة", "الهيكل", "المستخدم", "المالك",
    "خاص", "خصوصي", "نقل", "عمومي"
]
        if any(kw in cleaned for kw in invalid_keywords):
            continue

        score = 0.0

        # Prefer left of Arabic anchor
        if horizontal_diff > 0:
            score += 3.0
        else:
            score -= 0.5

        # Prefer same row
        score += max(0.0, 100.0 - vertical_diff)

        # Confidence helps
        score += item["confidence"] * 5.0

        # Strong bonus if candidate contains a known brand
        matched_brand = None
        for brand in ARABIC_BRANDS:
            if brand in cleaned:
                matched_brand = brand
                score += 20.0
                break

        candidates.append((score, cleaned, matched_brand))

    if not candidates:
        return ""

    candidates.sort(key=lambda x: x[0], reverse=True)

    best_score, best_text, matched_brand = candidates[0]

    # If a known brand was found, return the brand only
    if matched_brand:
        return matched_brand

    # Otherwise return cleaned nearby text
    return ""


def _extract_model_by_anchor(ocr_items: list) -> str:
    """
    Extract vehicle model using anchor 'طراز المركبة'.
    Prefer known model names and reject nearby label/junk text.
    """
    anchor = _find_anchor_item(ocr_items, ["طراز المركبة", "طراز", "طراذ"])
    if not anchor:
        return ""

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
        horizontal_diff = anchor["cx"] - item["cx"]  # positive => left of anchor

        # nearby only
        if vertical_diff > max(anchor["h"], item["h"]) * 2.0:
            continue

        if abs(horizontal_diff) > 550:
            continue

        # clean label words from the candidate itself
        cleaned = text
        cleaned = cleaned.replace("طراز المركبة", "")
        cleaned = cleaned.replace("طراذ المركبة", "")
        cleaned = cleaned.replace("طراز", "")
        cleaned = cleaned.replace("طراذ", "")
        cleaned = cleaned.replace("المركبة", "")
        cleaned = " ".join(cleaned.split()).strip()

        if not cleaned:
            continue

        # reject obvious junk
        if any(kw in cleaned for kw in invalid_keywords):
            continue

        # reject pure numbers
        if cleaned.replace(" ", "").isdigit():
            continue
    # ❌ Reject plate-like patterns (e.g., "L E R", "B Z A")
        tokens = cleaned.split()
        if len(tokens) <= 3 and all(t.isalpha() and len(t) == 1 for t in tokens):
         continue
        score = 0.0

        # prefer left of Arabic anchor
        if horizontal_diff > 0:
            score += 3.0
        else:
            score -= 0.5

        # prefer same row
        score += max(0.0, 100.0 - vertical_diff)

        # confidence helps
        score += item["confidence"] * 5.0

        # prefer moderate-length text
        if 2 <= len(cleaned) <= 20:
            score += 2.0

        matched_model = None
        for model in COMMON_ARABIC_MODELS:
            if model in cleaned:
                matched_model = model
                score += 20.0
                break

        candidates.append((score, cleaned, matched_model))

    if not candidates:
        return ""

    candidates.sort(key=lambda x: x[0], reverse=True)
    best_score, best_text, matched_model = candidates[0]

    # If a known model was found, return the model only
    if matched_model:
        # keep your special abbreviations consistent
        if matched_model == "جي اكس ار":
            return "GXR"
        if matched_model == "في اكس ار":
            return "VXR"
        return _translate_to_english(matched_model)

    # Otherwise return cleaned nearby text
    return ""

def _extract_color_by_anchor(ocr_items: list) -> str:
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

        vertical_diff = abs(item["cy"] - anchor["cy"])
        horizontal_diff = anchor["cx"] - item["cx"]  # positive => left of anchor

        # nearby only
        if vertical_diff > max(anchor["h"], item["h"]) * 2.0:
            continue

        if abs(horizontal_diff) > 350:
            continue

        cleaned = text.replace("اللون", "").strip()
        cleaned = " ".join(cleaned.split())

        if not cleaned:
            continue

        matched_color = _best_color_match(cleaned)
        if not matched_color:
            continue

        score = 0.0

        # prefer left of Arabic anchor
        if horizontal_diff > 0:
            score += 3.0
        else:
            score -= 0.5

        # prefer same row
        score += max(0.0, 100.0 - vertical_diff)

        # confidence helps
        score += item["confidence"] * 5.0

        # exact known color gets a bonus
        if cleaned in ARABIC_COLORS:
            score += 10.0

        candidates.append((score, matched_color))

    if not candidates:
        return ""

    candidates.sort(key=lambda x: x[0], reverse=True)
    best_color = candidates[0][1]

    return _translate_to_english(best_color)

# this function is not currently used, but we keep it for potential future use or fallback logic
def _get_vin_confidence(vin: str) -> str:
    """
    Return a simple confidence level for the extracted VIN.
    """
    if not vin:
        return "low"

    vin = vin.strip().upper()
    vin = re.sub(r"[^A-Z0-9]", "", vin)

    has_digit = any(ch.isdigit() for ch in vin)
    has_alpha = any(ch.isalpha() for ch in vin)

    if len(vin) == 17 and has_digit and has_alpha:
        return "high"

    if len(vin) in (15, 16, 18) and has_digit and has_alpha:
        return "medium"

    return "low"

def _extract_plate_english(texts: list) -> str:
    """
    Extract the English plate number, format it, and fix common OCR errors.
    """
    # Broadened the pattern to include 8 and 4 since OCR sometimes misreads B and A
    pattern = r'\b(\d{1,4})\s*([A-Za-z\*84])\s*([A-Za-z\*84])\s*([A-Za-z1084])\b'
    
    for text in texts:
        match = re.search(pattern, text)
        if match:
            n, l1, l2, l3 = match.groups()
            
            # Correct common noise/misreads in Saudi license plates
            def fix_letter(l):
                return l.replace('*', 'X').replace('1', 'J').replace('0', 'O').replace('8', 'B').replace('4', 'A').upper()
            
            return f"{n} {fix_letter(l1)} {fix_letter(l2)} {fix_letter(l3)}"
    return ""

def _extract_chassis_number(texts: list) -> str:
    """
    The chassis number (VIN) always consists of 17 English letters and numbers.
    """
    for text in texts:
        # Remove spaces to search for a continuous string
        clean_text = text.replace(" ", "").upper()
        # Made the search flexible (15 to 17) to catch errors at the edges of the number
        match = re.search(r'[A-Z0-9]{15,17}', clean_text)
        
        if match:
            vin = match.group()
            # The actual VIN must contain numbers (to exclude random English sentences)
            if any(char.isdigit() for char in vin):
                return vin
    return ""

def _extract_year(texts: list) -> str:
    """
    Extract manufacturing year.
    """
    pattern = r'(19[8-9]\d|20[0-3]\d)'
    
    # Search for the year next to the word "سنة" (Year) or "صنع" (Made) as a priority
    for i, text in enumerate(texts):
        if "سنة" in text or "صنع" in text:
            match = re.search(pattern, text)
            if match: return match.group()
            # The year might be in the following line
            if i + 1 < len(texts):
                match = re.search(pattern, texts[i+1])
                if match: return match.group()
                
    # Fallback: search for any year in the text
    for text in texts:
        match = re.search(pattern, text)
        if match:
            return match.group()
    return ""

def _extract_color(texts: list) -> str:
    """
    Search for common colors in the registration card and return the automatic English translation.
    """
    for text in texts:
        for color in ARABIC_COLORS:
            if color in text:
                return _translate_to_english(color)
    return ""

def _extract_brand(texts: list) -> str:
    """
    Search for the vehicle brand and return the automatic English translation.
    """
    for text in texts:
        for brand in ARABIC_BRANDS:
            if brand in text:
                # Custom overrides for brands that might translate poorly literally
                if brand in ["جمس", "جي ام سي"]: return "GMC"
                if brand == "بي ام دبليو": return "BMW"
                return _translate_to_english(brand)
    return ""

def _extract_model(texts: list) -> str:
    """
    Search for the vehicle model (e.g., Innova Wagon, GXR) and return automatically in English.
    """
    # Random words resulting from read errors that we prevent from being taken as a model
    invalid_keywords = [
        "المركبة", "سنة", "الصنع", "نوع", "التسجيل", "حمولة", "خاص", "ماركة", 
        "المالك", "المستخدم", "رقم", "هوية", "تاريخ", "اللون", "ابيض", "اسود", 
        "احمر", "فضي", "رمادي", "ازرق", "اخضر", "وزن", "ص", "ح ك"
    ]
    
    # Helper function to ensure the candidate text is valid as a "model"
    def is_valid_candidate(c: str) -> bool:
        c_strip = c.strip()
        if len(c_strip) <= 1 or c_strip == "اا":
            return False
        # Prevent selecting the brand name as a model (like Toyota)
        if c_strip in ARABIC_BRANDS: 
            return False
        # Prevent selecting random numbers
        if c_strip.replace(" ", "").isdigit(): 
            return False
        for kw in invalid_keywords:
            if kw in c_strip:
                return False
        return True

    # Method 1: Search near the word 'Model' (طراز)
    for i, text in enumerate(texts):
        if "طراز" in text or "طراذ" in text:
            clean_text = re.sub(r'طرا[زذ]\s*(المركبة)?', '', text).strip()
            if is_valid_candidate(clean_text):
                return _translate_to_english(clean_text)
            
            # Search in adjacent lines (before and after)
            search_indices = [i-1, i+1, i-2, i+2]
            for j in search_indices:
                if 0 <= j < len(texts):
                    candidate = texts[j].strip()
                    if is_valid_candidate(candidate):
                        return _translate_to_english(candidate)

    # Method 2 (Smart Fallback): Search for famous models directly
    for text in texts:
        for model in COMMON_ARABIC_MODELS:
            if model in text:
                # Custom overrides for specific abbreviations
                if model == "جي اكس ار": return "GXR"
                if model == "في اكس ار": return "VXR"
                return _translate_to_english(model)
                
    return ""


async def process_ocr(file):
    """
    Main function called by FastAPI.
    Receives an image, extracts text, translates automatically, and returns structured data in English.
    """
    try:
        print("--- NEW OCR REQUEST STARTED ---")
        contents = await file.read()
        nparr = np.frombuffer(contents, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        if image is None:
            raise Exception("Invalid image file. Please upload a valid image.")

        print("1. Starting EasyOCR processing... (Waiting for CPU)")
        # Pass the original image without modifications as the AI prefers it
        result = reader.readtext(image, detail=0, text_threshold=0.5, low_text=0.3)
        result_detailed = reader.readtext(image, detail=1, text_threshold=0.5, low_text=0.3)
        print("   -> OCR Finished successfully!")

        normalized_texts = [_normalize_text(text) for text in result]
        ocr_items = _build_ocr_items(result_detailed)
        
        print("2. Extracting and Translating Data...")
        chassis_number = _extract_chassis_number_by_anchor(ocr_items) or _extract_chassis_number(normalized_texts)
        plate_number = _extract_plate_by_anchor(ocr_items) or _extract_plate_english(normalized_texts)
        manufacturing_year = ( _extract_year_from_roi(image, ocr_items) or _extract_year(normalized_texts))
        make = _extract_make_by_anchor(ocr_items) or _extract_brand(normalized_texts)
        model = _extract_model_by_anchor(ocr_items) or _extract_model(normalized_texts)
        color = _extract_color_by_anchor(ocr_items) or _extract_color(normalized_texts)
        structured_data = {
    "plate number": plate_number,
    "make": make,
    "model": model,
    "manufacturing year": manufacturing_year,
    "color": color,
    "chassis number": chassis_number,
     }
        
        print("3. Data Processed Successfully!")
        print(f"   -> Result: {structured_data}")

        return {
            "status": "success",
            "raw_text": normalized_texts,
            "data": structured_data
        }

    except Exception as e:
        print(f"!!! SERVER ERROR: {str(e)}")
        return {"status": "error", "message": f"OCR Error: {str(e)}"}