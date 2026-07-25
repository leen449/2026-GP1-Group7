"""
Canonical vehicle-key normalization — SHARED SOURCE OF TRUTH.
CrashLens · imported by BOTH the value pipeline (aggregate_values.py) AND the
referral gate's lookup (lookup.py). One copy only, so the table can never be
keyed one way and queried another.

KEY = make | model | year   (lowercased)

LANGUAGE
    The value table is keyed in ENGLISH (that's how Syarah/Saleh label cars).
    But users register vehicles by typing make/model as free text in ARABIC
    ('ماركة المركبة' / 'طراز المركبة'). In practice Saudi users also often type
    Latin ('Toyota', 'Camry'). So canonical_make/canonical_model accept BOTH:
      • Arabic input  -> mapped to the English canonical via the maps below.
      • Latin input   -> uppercased + alias-folded (matches the table directly).
    No UI change, no dropdown, nothing restricted — just a translation layer.

WHAT'S SOLID vs WHAT NEEDS FEEDING
    MAKES are a bounded set (~51) -> ARABIC_MAKE_MAP is reliable and near-complete.
    MODELS are open-ended and users may type them in Arabic OR Latin. Latin model
    input already matches the table; Arabic model input needs MODEL_ALIASES, which
    is SEEDED with common ones and is the surface you extend as you see real
    registrations that miss. A model miss just yields no value (gate treats it as
    unknown) — it never returns a wrong number.
"""
import re

# ─────────────────────────────────────────────────────────────────────
# Arabic spelling folding — so 'هيونداي' / 'هونداي' / 'هيوندأي' all match.
# ─────────────────────────────────────────────────────────────────────
_AR_DIACRITICS = re.compile(r"[\u064B-\u0652\u0670\u0640]")   # harakat + tatweel

def _ar_normalize(text: str) -> str:
    t = (text or "").strip()
    t = _AR_DIACRITICS.sub("", t)
    t = (t.replace("أ", "ا").replace("إ", "ا").replace("آ", "ا").replace("ٱ", "ا")
           .replace("ى", "ي").replace("ة", "ه").replace("ؤ", "و").replace("ئ", "ي"))
    return re.sub(r"\s+", " ", t).strip()


def _clean(text: str) -> str:
    """Latin-facing clean: uppercase + collapse spaces (Arabic passes through)."""
    return re.sub(r"\s+", " ", (text or "").upper().strip())


# ─────────────────────────────────────────────────────────────────────
# Makes
# ─────────────────────────────────────────────────────────────────────
MAKE_VOCAB = {
    "AUDI", "BAIC", "BMW", "BYD", "CADILLAC", "CHANGAN", "CHERY", "CHEVROLET",
    "CHRYSLER", "CMC", "DODGE", "DONGFENG", "FAW", "FIAT", "FORD", "FOTON",
    "GAC", "GEELY", "GENESIS", "GMC", "GREAT WALL", "HAVAL", "HONDA", "HONGQI",
    "HYUNDAI", "INFINITI", "ISUZU", "JAC", "JAECOO", "JEEP", "JETOUR", "JMC",
    "KAIYI", "KIA", "LAND ROVER", "LEXUS", "LINCOLN", "LINK & CO", "LUCID",
    "MASERATI", "MAXUS", "MAZDA", "MERCEDES", "MG", "MINI", "MITSUBISHI",
    "NISSAN", "OMODA", "PEUGEOT", "PORSCHE", "RENAULT", "ROLLS ROYCE", "ROX",
    "SKODA", "SOUEAST", "SUZUKI", "TOYOTA", "VICTORIA AUTO", "VOLKSWAGEN",
}

# Latin spelling variants -> canonical make.
MAKE_ALIASES = {
    "MERCEDES-BENZ": "MERCEDES", "MERCEDES BENZ": "MERCEDES", "BENZ": "MERCEDES",
    "VW": "VOLKSWAGEN", "CHEVY": "CHEVROLET", "LANDROVER": "LAND ROVER",
    "LAND-ROVER": "LAND ROVER", "RANGE ROVER": "LAND ROVER",
    "ROLLS-ROYCE": "ROLLS ROYCE", "LYNK & CO": "LINK & CO", "GREATWALL": "GREAT WALL",
}

# Arabic make -> English canonical. Multiple spellings per brand are welcome;
# keys are folded through _ar_normalize() at load, so variants collapse together.
_ARABIC_MAKE_RAW = {
    "تويوتا": "TOYOTA", "هيونداي": "HYUNDAI", "هونداي": "HYUNDAI", "كيا": "KIA",
    "نيسان": "NISSAN", "مازدا": "MAZDA", "ام جي": "MG", "جي اي سي": "GAC",
    "سوزوكي": "SUZUKI", "جيلي": "GEELY", "شيفروليه": "CHEVROLET", "شفروليه": "CHEVROLET",
    "شانجان": "CHANGAN", "تشانجان": "CHANGAN", "فورد": "FORD", "لكزس": "LEXUS",
    "لكسز": "LEXUS", "هافال": "HAVAL", "شيري": "CHERY", "تشيري": "CHERY",
    "بي ام دبليو": "BMW", "رينو": "RENAULT", "مرسيدس": "MERCEDES", "مرسيدس بنز": "MERCEDES",
    "هوندا": "HONDA", "جيب": "JEEP", "جي ام سي": "GMC", "جمس": "GMC", "فاو": "FAW",
    "لاند روفر": "LAND ROVER", "رنج روفر": "LAND ROVER", "بيجو": "PEUGEOT",
    "ميتسوبيشي": "MITSUBISHI", "متسوبيشي": "MITSUBISHI", "جينيسيس": "GENESIS",
    "جيتور": "JETOUR", "دودج": "DODGE", "ايسوزو": "ISUZU", "فولكس واجن": "VOLKSWAGEN",
    "فولكسفاجن": "VOLKSWAGEN", "اودي": "AUDI", "بايك": "BAIC", "جريت وول": "GREAT WALL",
    "لوسيد": "LUCID", "ميني": "MINI", "كاديلاك": "CADILLAC", "كرايسلر": "CHRYSLER",
    "انفينيتي": "INFINITI", "بورش": "PORSCHE", "هونشي": "HONGQI", "هونغتشي": "HONGQI",
    "دونج فينج": "DONGFENG", "دونغ فنغ": "DONGFENG", "فيات": "FIAT", "اومودا": "OMODA",
    "امودا": "OMODA", "جايكو": "JAECOO", "لينكولن": "LINCOLN", "مازيراتي": "MASERATI",
    "ماكسوس": "MAXUS", "بي واي دي": "BYD", "جاك": "JAC", "سكودا": "SKODA",
}
ARABIC_MAKE_MAP = {_ar_normalize(k): v for k, v in _ARABIC_MAKE_RAW.items()}

# Arabic (or Latin) model -> canonical model. SEED — extend from real misses.
_MODEL_ALIASES_RAW = {
    "كامري": "CAMRY", "كورولا": "COROLLA", "لاندكروزر": "LAND CRUISER",
    "لاند كروزر": "LAND CRUISER", "سوناتا": "SONATA", "النترا": "ELANTRA",
    "اكسنت": "ACCENT", "سنتافي": "SANTA FE", "توسان": "TUCSON", "سيراتو": "CERATO",
    "سبورتاج": "SPORTAGE", "باترول": "PATROL", "سنترا": "SENTRA", "اكورد": "ACCORD",
}
MODEL_ALIASES = {_ar_normalize(k): v for k, v in _MODEL_ALIASES_RAW.items()}

_MAKES_BY_LEN = sorted(MAKE_VOCAB, key=lambda m: -len(m.split()))


def canonical_make(raw_make: str) -> str:
    ar = _ar_normalize(raw_make)
    if ar in ARABIC_MAKE_MAP:            # Arabic input
        return ARABIC_MAKE_MAP[ar]
    s = _clean(raw_make)                 # Latin input
    return MAKE_ALIASES.get(s, s)


def canonical_model(raw_model: str) -> str:
    ar = _ar_normalize(raw_model)
    if ar in MODEL_ALIASES:              # Arabic model
        return MODEL_ALIASES[ar]
    s = _clean(raw_model)
    return MODEL_ALIASES.get(_ar_normalize(s), s)


def parse_blob(blob: str):
    """Best-effort split of a Saleh-style Latin blob into (make, model)."""
    text = _clean(blob)
    text = re.sub(r"\b(19|20)\d{2}\b", "", text).strip()
    make = ""
    for cand in _MAKES_BY_LEN:
        if text == cand or text.startswith(cand + " "):
            make, text = cand, text[len(cand):].strip()
            break
    if not make:
        parts = text.split()
        make = MAKE_ALIASES.get(parts[0], parts[0]) if parts else ""
        text = " ".join(parts[1:])
    model = text.split()[0] if text.split() else ""
    return make, canonical_model(model)


def make_key(make: str, model: str, year) -> str:
    return f"{canonical_make(make)}|{canonical_model(model)}|{year}".lower()
