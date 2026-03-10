import re
import cv2
import numpy as np
import easyocr
from deep_translator import GoogleTranslator

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
        print("   -> OCR Finished successfully!")
        
        # Normalize texts (Arabic numerals to English numerals, fix letters)
        normalized_texts = [_normalize_text(text) for text in result]
        
        print("2. Extracting and Translating Data...")
        structured_data = {
            "plate number": _extract_plate_english(normalized_texts),
            "make": _extract_brand(normalized_texts),
            "model": _extract_model(normalized_texts),
            "manufacturing year": _extract_year(normalized_texts),
            "color": _extract_color(normalized_texts),
            "chassis number": _extract_chassis_number(normalized_texts),
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