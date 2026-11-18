"""
Labor-hours lookup (request-path).
CrashLens · supplies H(part, damage_type) — the base labor hours that anchor the
repair-cost estimate:

    C_base = H(part, type) × R × F_paint × F_vehicle

(Severity factor removed from the formula per 2026-11 supervisor decision — severity
is still classified and shown to the admin/in the report, it just no longer scales
the price. See cost_estimation_services.py.)

REQUEST KEYS come from the vision association layer:
    • part        = a canonical model part such as door, windshield, lamp, or wheel
    • damage_type = the YOLO damage class, normalized to:
                    dent | scratch | crack | lamp | glass | tire

VALUES are the estimator's (Tagdeer) second reference form (the 25-row sheet, 2026-11),
transcribed as exact part rows in LOOKUP. Logical model keys collapse multiple rows
only while the configured values agree. The values are real expert numbers — do not
edit them here; retune through an approved Firestore `config/laborHours` update if the
estimator revises them.

SPECIAL HANDLING
    trunk + tailgate  -> both use the estimator's "Trunk" row.
    windshield       -> front/rear glass rows have the same hours (3h); resolve only
                         while their configured values agree.
    door / door_glass -> side-specific door rows now DIFFER by side for glass (right
                         door glass 3h, left door glass 2h) while dent/scratch/crack
                         stay equal across all four door rows. A side-blind "door"/
                         "window" match can't pick between the two glass values, so
                         -- same approved-average-fallback precedent as wheel dent
                         below -- it resolves to the 2.5h average rather than being
                         left unpriced.
    lamp              -> all applicable lamp-break cells are 1h; resolve from the
                         configured rows rather than choosing a location.
    wheel             -> all four expert rows are stored in LOOKUP/Firestore and are
                         now EQUAL (1h) at every position for dent/scratch/crack/tire,
                         per the 25-row sheet's rim rows. The front/rear wheel-dent
                         hint logic in get_hours() is left in place (harmless no-op
                         now that front/rear agree) rather than removed, so a future
                         table revision reintroducing a front/rear split would not
                         need the mechanism rebuilt.
    left/right mirror -> not costed (no estimator row) -> returns None.

GENERIC fender/sill/roof: the part-seg model (exp04+) emits these as SIDELESS classes
(no front/back or left/right). "fender"'s canonical row uses the sheet's FRONT fender
values (5/5/7h, lamp 1h) — the sheet's rear quarter-panel values genuinely differ
(7-8/5-6/25h) and the current model has no way to tell front from rear fender damage
apart, so this is a known, separately-tracked gap (see the planned rear-quarter
context-rule work), not an oversight. "sill" is symmetric in the sheet (right/left
both 8/5/25h) so no such gap applies there. The original side-specific rows stay in
UNMAPPED_PARTS, preserved for a future side-aware model (now also updated to the
25-row sheet's values); get_unmapped_hours() remains available as a fallback for any
part still unmapped.

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
    "front_bumper":      {"najm_zone": "المقدمة",       "hours": {"dent": 7, "scratch": 5, "crack": 7}},
    "hood":              {"najm_zone": "المقدمة",       "hours": {"dent": 5,   "scratch": 5}},
    "front_glass":       {"najm_zone": "المقدمة",       "hours": {"glass": 3}},
    "front_left_light":  {"najm_zone": "المقدمة",       "hours": {"lamp": 1}},
    "front_right_light": {"najm_zone": "المقدمة",       "hours": {"lamp": 1}},

    "front_left_door":   {"najm_zone": "الجانب الأيسر", "hours": {"dent": 7, "scratch": 5, "crack": 7, "glass": 2}},
    "front_right_door":  {"najm_zone": "الجانب الأيمن", "hours": {"dent": 7, "scratch": 5, "crack": 7, "glass": 3}},
    "back_left_door":    {"najm_zone": "الجانب الأيسر", "hours": {"dent": 7, "scratch": 5, "crack": 7, "glass": 2}},
    "back_right_door":   {"najm_zone": "الجانب الأيمن", "hours": {"dent": 7, "scratch": 5, "crack": 7, "glass": 3}},

    "back_bumper":       {"najm_zone": "المؤخرة",       "hours": {"dent": 5, "scratch": 4, "crack": 7}},
    "back_glass":        {"najm_zone": "المؤخرة",       "hours": {"glass": 3}},
    "back_left_light":   {"najm_zone": "المؤخرة",       "hours": {"lamp": 1}},
    "back_right_light":  {"najm_zone": "المؤخرة",       "hours": {"lamp": 1}},

    # trunk row; tailgate is aliased to it below.
    "trunk":             {"najm_zone": "المؤخرة",       "hours": {"dent": 7, "scratch": 5, "glass": 1}},

    # generic (sideless) panels the part-seg model now emits directly — see module
    # docstring. najm_zone is None: side isn't derivable from the class alone.
    # "fender" uses the sheet's FRONT fender row (rear quarter-panel genuinely
    # differs -- see module docstring, known tracked gap, not an oversight).
    "fender":            {"najm_zone": None,            "hours": {"dent": 5, "scratch": 5, "crack": 7, "lamp": 1}},
    "sill":              {"najm_zone": None,            "hours": {"dent": 8, "scratch": 5, "crack": 25}},
    "roof":              {"najm_zone": "الأعلى",        "hours": {"dent": 10, "scratch": 7, "crack": 25}},

    # Exact expert wheel rows. All four rim positions now carry identical values
    # per the 25-row sheet (dent/scratch/crack/tire all 1h everywhere). Keeping all
    # four rows makes the Firestore document match the source form.
    "back_right_wheel":  {"najm_zone": "المؤخرة",       "hours": {"dent": 1, "scratch": 1, "crack": 1, "tire": 1}},
    "back_left_wheel":   {"najm_zone": "المؤخرة",       "hours": {"dent": 1, "scratch": 1, "crack": 1, "tire": 1}},
    "front_right_wheel": {"najm_zone": "المقدمة",       "hours": {"dent": 1, "scratch": 1, "crack": 1, "tire": 1}},
    "front_left_wheel":  {"najm_zone": "المقدمة",       "hours": {"dent": 1, "scratch": 1, "crack": 1, "tire": 1}},
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
    "left_door": ("front_left_door", "back_left_door"),
    "right_door": ("front_right_door", "back_right_door"),
}

# Expert hours for parts the current model can't emit. Preserved, not on request path.
# front fender L/R agree (5/5/7, lamp 1) in the 25-row sheet; rear quarter-panel
# genuinely differs by side (back_right 8/6/25 vs back_left 7/5/25, lamp 1 both).
UNMAPPED_PARTS = {
    "front_left_fender":  {"najm_zone": "الجانب الأيسر", "hours": {"dent": 5, "scratch": 5, "crack": 7, "lamp": 1}},
    "front_right_fender": {"najm_zone": "الجانب الأيمن", "hours": {"dent": 5, "scratch": 5, "crack": 7, "lamp": 1}},
    "back_left_fender":   {"najm_zone": "الجانب الأيسر", "hours": {"dent": 7, "scratch": 5, "crack": 25, "lamp": 1}},
    "back_right_fender":  {"najm_zone": "الجانب الأيمن", "hours": {"dent": 8, "scratch": 6, "crack": 25, "lamp": 1}},
    "roof":               {"najm_zone": "الأعلى",        "hours": {"dent": 10, "scratch": 7, "crack": 25}},
    "right_sill":         {"najm_zone": "الجانب الأيمن", "hours": {"dent": 8, "scratch": 5, "crack": 25}},
    "left_sill":          {"najm_zone": "الجانب الأيسر", "hours": {"dent": 8, "scratch": 5, "crack": 25}},
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

    if c in ("door", "door_glass") and d == "glass":
        # Door glass now genuinely differs by side (right 3h / left 2h, 2026-11
        # sheet). A side-blind "door"/generic "window" match can't pick between
        # them, so -- same approved-average-fallback precedent as wheel dent
        # above -- use the average (2.5h) rather than leaving it unpriced.
        direct = _common_hours(table, _DOOR_ROWS, d)
        if direct is not None:
            return direct
        left = _common_hours(table, _COMMON_VALUE_ROWS["left_door"], d)
        right = _common_hours(table, _COMMON_VALUE_ROWS["right_door"], d)
        if left is None or right is None:
            return None
        return (left + right) / 2.0

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
