"""
Labor-hours lookup (request-path).
CrashLens · supplies H(part, damage_type) — the base labor hours (at MODERATE
severity) that anchor the repair-cost estimate:

    C_base = H(part, type) × R × F_paint × F_vehicle × F_severity

KEYS come straight from the two vision models:
    • part        = carparts-seg class name (front_bumper, back_left_door, wheel, …)
    • damage_type = the YOLO damage class, normalized to:
                    dent | scratch | crack | lamp | glass | tire

VALUES are the estimator's (Tagdeer) form, transcribed and verified against the
original by the team. They are real expert numbers — do not edit them here; retune
via Firestore if the estimator ever revises them.

SPECIAL HANDLING
    trunk + tailgate  -> both use the estimator's "Trunk" row.
    wheel             -> position-dependent. Only the DENT value differs front/rear
                         (front 4.5 / rear 4.0); scratch/crack/tire are identical.
                         Najm's front/rear zone selects the value; if position is
                         unknown, use the averaged ("ambiguous") row (dent 4.25).
    left/right mirror -> not costed (no estimator row) -> returns None.

GENERIC fender/sill/roof: the part-seg model (exp04+) emits these as SIDELESS classes
(no front/back or left/right). Their moderate-hours values are identical across sides
(verified against the Tagdeer form), so a single canonical "fender"/"sill" row lives in
LOOKUP below with najm_zone left as None (side can't be inferred from the class alone —
verification against Najm's left/right zone is skipped for these, not guessed). "roof"
already had no side. The original side-specific rows stay in UNMAPPED_PARTS, preserved
for a future side-aware model; get_unmapped_hours() remains available as a fallback for
any part still unmapped.

Storage mirrors the other factor services: real values in code as seed + fallback,
overridable at config/laborHours in Firestore (no redeploy).
"""
from typing import Optional
import firebase_admin
from firebase_admin import credentials, firestore

CONFIG_COLLECTION = "config"
LABOR_DOC = "laborHours"

DAMAGE_TYPES = ["dent", "scratch", "crack", "lamp", "glass", "tire"]

# carparts-seg class -> { najm_zone (verification), hours: {damage_type: hours} }
# Only the damage types the part actually takes are listed.
LOOKUP = {
    "front_bumper":      {"najm_zone": "المقدمة",       "hours": {"dent": 2.5, "scratch": 1.5, "crack": 2}},
    "hood":              {"najm_zone": "المقدمة",       "hours": {"dent": 3,   "scratch": 1.5}},
    "front_glass":       {"najm_zone": "المقدمة",       "hours": {"glass": 2}},
    "front_left_light":  {"najm_zone": "المقدمة",       "hours": {"lamp": 0.5}},
    "front_right_light": {"najm_zone": "المقدمة",       "hours": {"lamp": 0.5}},

    "front_left_door":   {"najm_zone": "الجانب الأيسر", "hours": {"dent": 3, "scratch": 1.5, "crack": 2.5, "glass": 0.8}},
    "front_right_door":  {"najm_zone": "الجانب الأيمن", "hours": {"dent": 3, "scratch": 1.5, "crack": 2.5, "glass": 0.8}},
    "back_left_door":    {"najm_zone": "الجانب الأيسر", "hours": {"dent": 3, "scratch": 1.5, "crack": 2.5, "glass": 0.8}},
    "back_right_door":   {"najm_zone": "الجانب الأيمن", "hours": {"dent": 3, "scratch": 1.5, "crack": 2.5, "glass": 0.8}},

    "back_bumper":       {"najm_zone": "المؤخرة",       "hours": {"dent": 2.5, "scratch": 1.5, "crack": 1}},
    "back_glass":        {"najm_zone": "المؤخرة",       "hours": {"glass": 2}},
    "back_left_light":   {"najm_zone": "المؤخرة",       "hours": {"lamp": 0.5}},
    "back_right_light":  {"najm_zone": "المؤخرة",       "hours": {"lamp": 0.5}},

    # trunk row; tailgate is aliased to it below.
    "trunk":             {"najm_zone": "المؤخرة",       "hours": {"dent": 2.5, "scratch": 1.5, "glass": 1}},

    # generic (sideless) panels the part-seg model now emits directly — see module
    # docstring. najm_zone is None: side isn't derivable from the class alone.
    "fender":            {"najm_zone": None,            "hours": {"dent": 2, "scratch": 1.2, "crack": 2.2, "lamp": 0.5}},
    "sill":              {"najm_zone": None,            "hours": {"dent": 1.5, "scratch": 1}},
    "roof":              {"najm_zone": "الأعلى",        "hours": {"dent": 4, "scratch": 2}},
}

# Model classes that alias onto an existing row.
ALIASES = {"tailgate": "trunk"}

# Model classes detected but intentionally NOT costed.
NON_COSTED = {"left_mirror", "right_mirror"}

# wheel: position-dependent. Only DENT differs front/rear.
WHEEL_HOURS = {
    "front":     {"dent": 4.5,  "scratch": 0.5, "crack": 1.5, "tire": 0.5},
    "rear":      {"dent": 4.0,  "scratch": 0.5, "crack": 1.5, "tire": 0.5},
    "ambiguous": {"dent": 4.25, "scratch": 0.5, "crack": 1.5, "tire": 0.5},  # front/rear avg
}

# Expert hours for parts the current model can't emit. Preserved, not on request path.
UNMAPPED_PARTS = {
    "front_left_fender":  {"najm_zone": "الجانب الأيسر", "hours": {"dent": 2, "scratch": 1.2, "crack": 2.2, "lamp": 0.5}},
    "front_right_fender": {"najm_zone": "الجانب الأيمن", "hours": {"dent": 2, "scratch": 1.2, "crack": 2.2, "lamp": 0.5}},
    "back_left_fender":   {"najm_zone": "الجانب الأيسر", "hours": {"dent": 2, "scratch": 1.2, "crack": 2.2, "lamp": 0.5}},
    "back_right_fender":  {"najm_zone": "الجانب الأيمن", "hours": {"dent": 2, "scratch": 1.2, "crack": 2.2, "lamp": 0.5}},
    "roof":               {"najm_zone": "الأعلى",        "hours": {"dent": 4, "scratch": 2}},
    "right_sill":         {"najm_zone": "الجانب الأيمن", "hours": {"dent": 1.5, "scratch": 1}},
    "left_sill":          {"najm_zone": "الجانب الأيسر", "hours": {"dent": 1.5, "scratch": 1}},
}

_cache = None


def _db():
    if not firebase_admin._apps:
        firebase_admin.initialize_app(credentials.Certificate("../serviceAccountKey.json"))
    return firestore.client()


def _valid(tbl) -> bool:
    return isinstance(tbl, dict) and "front_bumper" in tbl and isinstance(tbl["front_bumper"], dict)


def load_lookup(force_refresh: bool = False) -> dict:
    global _cache
    if _cache is not None and not force_refresh:
        return _cache
    try:
        snap = _db().collection(CONFIG_COLLECTION).document(LABOR_DOC).get()
        tbl = snap.to_dict() if snap.exists else None
        _cache = tbl if _valid(tbl) else dict(LOOKUP)
    except Exception:
        _cache = dict(LOOKUP)
    return _cache


def _norm(s) -> str:
    return (s or "").strip().lower().replace(" ", "_")


def najm_zone_for(model_class: str) -> Optional[str]:
    """The Najm zone a detected part rolls up to (for verification). None for wheel/mirror."""
    c = _norm(model_class)
    c = ALIASES.get(c, c)
    if c in NON_COSTED or c == "wheel":
        return None
    return load_lookup().get(c, {}).get("najm_zone")


def get_hours(model_class: str, damage_type: str, *, wheel_position: Optional[str] = None) -> Optional[float]:
    """
    Base (moderate) labor hours for a detected (part, damage_type).
      wheel_position: 'front' | 'rear' | None. Used only when model_class == 'wheel';
                      None -> the averaged 'ambiguous' row.
    Returns hours, or None when the part isn't costed (mirror) or the part has no
    entry for that damage type (caller decides how to handle a no-match).
    """
    c = _norm(model_class)
    d = _norm(damage_type)

    if c in NON_COSTED:
        return None

    if c == "wheel":
        pos = _norm(wheel_position) if wheel_position else "ambiguous"
        if pos not in WHEEL_HOURS:
            pos = "ambiguous"
        v = WHEEL_HOURS[pos].get(d)
        return float(v) if v is not None else None

    c = ALIASES.get(c, c)
    entry = load_lookup().get(c)
    if not entry:
        return None
    v = entry.get("hours", {}).get(d)
    return float(v) if v is not None else None


def get_unmapped_hours(part: str, damage_type: str) -> Optional[float]:
    """Hours for a preserved non-model part (fender/sill/roof) — for routing/future use."""
    v = UNMAPPED_PARTS.get(_norm(part), {}).get("hours", {}).get(_norm(damage_type))
    return float(v) if v is not None else None


def seed_defaults():
    """Create/overwrite config/laborHours from the in-code LOOKUP. Run once."""
    _db().collection(CONFIG_COLLECTION).document(LABOR_DOC).set(LOOKUP)
    print(f"Seeded {CONFIG_COLLECTION}/{LABOR_DOC}: {len(LOOKUP)} classes")


if __name__ == "__main__":
    seed_defaults()
