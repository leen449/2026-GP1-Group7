"""
confidence_signals.py — derives the two currently-unwired confidence_service inputs
(airbag_deployed, prior_accident_same_location) from data already on the case.

CrashLens · imported ONLY by cost_estimation_services.py. Pure text/parsing helpers —
no Firestore access here (the prior-accident QUERY itself stays in
cost_estimation_services.py, since it needs the live db client and case shape). Does
not touch confidence_service.py's scoring, the damage/severity/OCR pipeline, or the
labor table.

Both signals are best-effort heuristics over free-text Najm OCR output. Returning
None/False on anything unrecognized is always the safe outcome — never guess a
positive.
"""
import re
import unicodedata
from typing import Optional

# harakat + tatweel — same set normalize.py already strips for vehicle-key matching.
_AR_DIACRITICS = re.compile(r"[ً-ْٰـ]")


def normalize_arabic(text: Optional[str]) -> str:
    """
    NFKC (folds Arabic presentation-form glyphs — the isolated/positional forms in
    U+FB50-FDFF and U+FE70-FEFF — back to their base letters) + diacritics/tatweel
    strip + whitespace collapse.

    Deliberately does NOT fold hamza/alef spelling variants (أ/إ/ا) — callers list
    each spelling they care about explicitly, same style as the airbag keyword list.
    """
    if not text:
        return ""
    t = unicodedata.normalize("NFKC", text)
    t = _AR_DIACRITICS.sub("", t)
    return re.sub(r"\s+", " ", t).strip()


# ---------------------------------------------------------------- FIX A: airbag
_AIRBAG_KEYWORDS = ["أكياس", "اكياس", "هوائية", "هوائيه", "ايرباق", "اير باق", "airbag"]


def detect_airbag(damage_location: Optional[str]) -> bool:
    """True if any airbag keyword appears (substring) in the normalized text."""
    norm = normalize_arabic(damage_location).lower()
    return any(kw.lower() in norm for kw in _AIRBAG_KEYWORDS)


# ---------------------------------------------------------------- FIX B: zone parsing
# Vocabulary grounded in zones already used elsewhere in this codebase: the
# najm_zone values in labor_hours_lookup.LOOKUP ("المقدمة", "المؤخرة", "الجانب
# الأيمن/الأيسر") plus the front/rear literals already in cost_estimation_services._najm_zone,
# extended with adjective ("الأمامي"/"الخلفي") and corner ("الركن ...") phrasing.
_FRONT_KW = ["المقدمة", "مقدمة", "مقدم", "الأمامي", "الامامي", "أمامي", "امامي", "أمام", "امام"]
_REAR_KW = ["المؤخرة", "مؤخرة", "مؤخر", "الخلفي", "خلفي", "خلف"]
_LEFT_KW = ["الأيسر", "الايسر", "أيسر", "ايسر", "يسار"]
_RIGHT_KW = ["الأيمن", "الايمن", "أيمن", "ايمن", "يمين"]
_TOP_KW = ["الأعلى", "الاعلى", "أعلى", "اعلى", "السقف", "سقف"]


def parse_zone(damage_location: Optional[str]) -> Optional[str]:
    """
    Best-effort side/zone from Najm's free-text damageLocation. One of:
    "front", "rear", "left", "right", "front_left", "front_right", "rear_left",
    "rear_right", "top" — or None when absent, self-contradictory (e.g. mentions
    both front and rear), or too vague to place on a side.

    "الركن الأمامي الأيسر" (front-left corner) resolves via its front+left words to
    "front_left" — a corner IS a front/rear + left/right combination, no separate
    corner keyword list is needed.
    """
    norm = normalize_arabic(damage_location)
    if not norm:
        return None

    has_front = any(kw in norm for kw in _FRONT_KW)
    has_rear = any(kw in norm for kw in _REAR_KW)
    has_left = any(kw in norm for kw in _LEFT_KW)
    has_right = any(kw in norm for kw in _RIGHT_KW)
    has_top = any(kw in norm for kw in _TOP_KW)

    if has_front and has_rear:   # contradictory text -> can't place it
        return None
    if has_left and has_right:
        return None
    if has_top:
        return "top"
    if has_front:
        return "front_left" if has_left else "front_right" if has_right else "front"
    if has_rear:
        return "rear_left" if has_left else "rear_right" if has_right else "rear"
    if has_left:
        return "left"
    if has_right:
        return "right"
    return None


def zones_compatible(zone_a: Optional[str], zone_b: Optional[str]) -> bool:
    """Exact-match only. Either side missing/vague (None) -> not compatible."""
    return zone_a is not None and zone_a == zone_b
