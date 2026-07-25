"""
Paint factor service (request-path).
CrashLens · supplies F_paint for the repair-cost estimate:

    C_base = H(L,T,S) × R × F_paint × F_vehicle

The user picks a paint category from a fixed Arabic dropdown. The UI shows
ARABIC; the data uses a stable KEY. Keeping them separate means you can reword
the Arabic label any time without touching the Firestore doc, the defaults, or
the formula. get_paint_factor() accepts EITHER the Arabic label or the key, so
it works whichever the client sends.

WHERE THE NUMBERS LIVE
    Factor values live in Firestore (config/paintFactors), keyed by the stable
    keys below, so the admin can retune them without a redeploy. The dashboard
    shows PAINT_LABELS_AR next to each number; the stored key never changes.
    DEFAULT_PAINT_FACTORS is the version-controlled fallback AND the seed: if the
    doc is missing/unreachable/invalid, the estimate runs on these instead of
    breaking.

⚠️ VALUES ARE PLACEHOLDERS — calibrate against a real refinish rate sheet.
   F_paint multiplies the whole C_base; keep the spread small or later scope it
   to the refinish share. ARABIC LABELS are editable — adjust wording freely.
"""
import pathlib
import firebase_admin
from firebase_admin import credentials, firestore

CONFIG_COLLECTION = "config"
PAINT_DOC = "paintFactors"
_KEY = pathlib.Path(__file__).resolve().parent.parent / "serviceAccountKey.json"

# Stable keys -> default multipliers (data layer; also the seed + fallback).
DEFAULT_PAINT_FACTORS = {
    "solid": 1.00,
    "metallic": 1.10,
    "pearl": 1.20,
    "tricoat": 1.35,
}

# Stable key -> Arabic label shown in the dropdown / admin dashboard (UI layer).
PAINT_LABELS_AR = {
    "solid": "سادة",
    "metallic": "ميتاليك",
    "pearl": "لؤلؤي",
    "tricoat": "مطفي",   # tri-coat / matte / special finishes
}

# Accept Arabic labels (and a few common variants) OR the key itself as input.
_ALIAS_TO_KEY = {
    "سادة": "solid", "عادي": "solid",
    "ميتاليك": "metallic", "متاليك": "metallic", "معدني": "metallic",
    "لؤلؤي": "pearl", "لولوي": "pearl", "بيرل": "pearl", "برلي": "pearl",
    "خاص": "tricoat", "مطفي": "tricoat", "ثلاثي الطبقات": "tricoat",
}

BASELINE_FACTOR = 1.00   # unknown/blank -> baseline, never inflates
_cache = None


def _db():
    if not firebase_admin._apps:                       # reuse main.py's init if present
        firebase_admin.initialize_app(credentials.Certificate(str(_KEY)))
    return firestore.client()


def _valid(factors) -> bool:
    return (isinstance(factors, dict) and len(factors) > 0
            and all(isinstance(v, (int, float)) and v > 0 for v in factors.values()))


def _resolve_key(category: str) -> str:
    """Arabic label OR key -> stable key. Empty string if unresolved."""
    c = (category or "").strip()
    if c in DEFAULT_PAINT_FACTORS:      # already a key
        return c
    if c.lower() in DEFAULT_PAINT_FACTORS:
        return c.lower()
    return _ALIAS_TO_KEY.get(c, "")     # Arabic label / variant


def load_paint_factors(force_refresh: bool = False) -> dict:
    global _cache
    if _cache is not None and not force_refresh:
        return _cache
    try:
        snap = _db().collection(CONFIG_COLLECTION).document(PAINT_DOC).get()
        factors = snap.to_dict() if snap.exists else None
        _cache = factors if _valid(factors) else dict(DEFAULT_PAINT_FACTORS)
    except Exception:
        _cache = dict(DEFAULT_PAINT_FACTORS)
    return _cache


def get_paint_factor(category: str) -> float:
    """F_paint for the selected category (Arabic label or key). Unknown -> 1.0."""
    key = _resolve_key(category)
    return float(load_paint_factors().get(key, BASELINE_FACTOR))


def categories_for_ui():
    """[(key, arabic_label, factor)] — build the dropdown / dashboard from this."""
    f = load_paint_factors()
    return [(k, PAINT_LABELS_AR.get(k, k), f[k]) for k in DEFAULT_PAINT_FACTORS if k in f]


def seed_defaults():
    """Create/overwrite config/paintFactors from DEFAULT_PAINT_FACTORS. Run once."""
    _db().collection(CONFIG_COLLECTION).document(PAINT_DOC).set(DEFAULT_PAINT_FACTORS)
    print(f"Seeded {CONFIG_COLLECTION}/{PAINT_DOC}: {DEFAULT_PAINT_FACTORS}")


if __name__ == "__main__":
    seed_defaults()
