"""
Labor-hours lookup (request-path).
CrashLens · supplies H(part, damage_type) — the base labor hours (at MODERATE
severity) that anchor the repair-cost estimate:

    C_base = H(part, type) × R × F_paint × F_vehicle × F_severity

REQUEST KEYS come from the vision association layer:
    • part        = a canonical model part such as door, windshield, lamp, or wheel
    • damage_type = the YOLO damage class, normalized to:
                    dent | scratch | crack | lamp | glass | tire

VALUES are the estimator's (Tagdeer) form, transcribed as exact part rows in LOOKUP.
Logical model keys collapse multiple rows only while the configured values agree. The
values are real expert numbers — do not edit them here; retune through an approved
Firestore `config/laborHours` update if the estimator revises them.

SPECIAL HANDLING
    trunk + tailgate  -> both use the estimator's "Trunk" row.
    windshield       -> front/rear glass rows have the same hours; resolve only while
                         their configured values agree.
    door / door_glass -> side-specific door rows have identical hours; resolve only
                         while the applicable configured values agree.
    lamp              -> all applicable lamp-break cells are 0.5; resolve from the
                         configured rows rather than choosing a location.
    wheel             -> all four expert rows are stored in LOOKUP/Firestore. Tire,
                         scratch, and crack resolve while all rows agree. Wheel dent
                         uses a front/rear hint (4.5/4.0); an unknown position keeps
                         the approved 4.25 average fallback.
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
from copy import deepcopy
from typing import Optional
import math
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

    # Exact expert wheel rows. Left/right values are equal, while front/rear dent
    # differs. Keeping all four rows makes the Firestore document match the source form.
    "back_right_wheel":  {"najm_zone": "المؤخرة",       "hours": {"dent": 4,   "scratch": 0.5, "crack": 1.5, "tire": 0.5}},
    "back_left_wheel":   {"najm_zone": "المؤخرة",       "hours": {"dent": 4,   "scratch": 0.5, "crack": 1.5, "tire": 0.5}},
    "front_right_wheel": {"najm_zone": "المقدمة",       "hours": {"dent": 4.5, "scratch": 0.5, "crack": 1.5, "tire": 0.5}},
    "front_left_wheel":  {"najm_zone": "المقدمة",       "hours": {"dent": 4.5, "scratch": 0.5, "crack": 1.5, "tire": 0.5}},
}

# Model classes that alias onto an existing row.
ALIASES = {"tailgate": "trunk"}

# Model classes detected but intentionally NOT costed.
NON_COSTED = {"left_mirror", "right_mirror"}

# Logical model outputs that safely collapse expert rows only while their values agree.
_DOOR_ROWS = (
    "front_left_door", "front_right_door", "back_left_door", "back_right_door",
)
_WHEEL_ROWS = (
    "front_left_wheel", "front_right_wheel", "back_left_wheel", "back_right_wheel",
)
_LAMP_ROWS = (
    "front_left_light", "front_right_light", "back_left_light", "back_right_light",
)
_COMMON_VALUE_ROWS = {
    "door": _DOOR_ROWS,
    "door_glass": _DOOR_ROWS,
    "windshield": ("front_glass", "back_glass"),
    "lamp": _LAMP_ROWS,
    "front_wheel": ("front_left_wheel", "front_right_wheel"),
    "rear_wheel": ("back_left_wheel", "back_right_wheel"),
    "wheel": _WHEEL_ROWS,
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


def _positive_hours(value) -> bool:
    # bool is a subclass of int — reject it so True/False cannot sneak in as 1/0.
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return False
    return math.isfinite(value) and value > 0


def _valid_row(row, expected) -> bool:
    if not isinstance(row, dict) or set(row.keys()) != {"najm_zone", "hours"}:
        return False
    zone = row.get("najm_zone")
    if zone is not None and not isinstance(zone, str):
        return False
    hours = row.get("hours")
    if not isinstance(hours, dict):
        return False
    if set(hours.keys()) != set(expected["hours"].keys()):
        return False
    return all(_positive_hours(hours[key]) for key in expected["hours"])


def _valid(tbl) -> bool:
    """Accept only a complete sparse LOOKUP-shaped table. Partial/stale docs fall back."""
    if not isinstance(tbl, dict) or set(tbl.keys()) != set(LOOKUP.keys()):
        return False
    return all(_valid_row(tbl[part], expected) for part, expected in LOOKUP.items())


def load_lookup(force_refresh: bool = False) -> dict:
    global _cache
    if _cache is not None and not force_refresh:
        return _cache
    try:
        snap = _db().collection(CONFIG_COLLECTION).document(LABOR_DOC).get()
        tbl = snap.to_dict() if snap.exists else None
        if _valid(tbl):
            _cache = deepcopy(tbl)
        else:
            reason = "missing" if not tbl else "incomplete, stale, or malformed"
            print(
                f"⚠️ config/{LABOR_DOC} is {reason}; "
                "using the built-in LOOKUP table"
            )
            _cache = deepcopy(LOOKUP)
    except Exception as exc:
        print(f"⚠️ config/{LABOR_DOC} could not be read ({exc}); using the built-in LOOKUP table")
        _cache = deepcopy(LOOKUP)
    return _cache


def _norm(s) -> str:
    return (s or "").strip().lower().replace(" ", "_")


def _common_hours(table: dict, rows, damage_type: str) -> Optional[float]:
    """Return a shared configured value, or None when candidate rows disagree/miss it."""
    values = []
    for row_key in rows:
        value = table.get(row_key, {}).get("hours", {}).get(damage_type)
        if value is None:
            return None
        values.append(float(value))
    return values[0] if values and all(v == values[0] for v in values[1:]) else None


def najm_zone_for(model_class: str) -> Optional[str]:
    """The expert-table zone for verification, when one unambiguous zone exists."""
    c = ALIASES.get(_norm(model_class), _norm(model_class))
    if c in NON_COSTED or c in _COMMON_VALUE_ROWS:
        return None
    return load_lookup().get(c, {}).get("najm_zone")


def get_hours(model_class: str, damage_type: str, *, wheel_position: Optional[str] = None) -> Optional[float]:
    """
    Return configured expert hours for a model-level part and damage type.

    Equivalent source rows are collapsed only when their values agree. For generic
    wheel dent, a clear front/rear hint selects that pair; otherwise the approved
    4.25-hour average is retained as an explicit fallback by the association layer.
    """
    c = _norm(model_class)
    d = _norm(damage_type)

    if c in NON_COSTED:
        return None

    table = load_lookup()
    c = ALIASES.get(c, c)

    if c == "wheel":
        pos = _norm(wheel_position) if wheel_position else None
        if pos in ("front", "rear"):
            return _common_hours(table, _COMMON_VALUE_ROWS[f"{pos}_wheel"], d)
        if d == "dent":
            front = _common_hours(table, _COMMON_VALUE_ROWS["front_wheel"], d)
            rear = _common_hours(table, _COMMON_VALUE_ROWS["rear_wheel"], d)
            if front is None or rear is None:
                return None
            return (front + rear) / 2.0

    rows = _COMMON_VALUE_ROWS.get(c)
    if rows:
        return _common_hours(table, rows, d)

    entry = table.get(c)
    if not entry:
        return None
    value = entry.get("hours", {}).get(d)
    return float(value) if value is not None else None


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
