"""
Confidence assessment service (request-path).
CrashLens · flags cases where the rule-based cost estimate should not be
trusted without a human looking at it first. This never changes the cost
itself — it only decides whether admin review is required and lists WHY, in
plain, explained Arabic, so a first-time admin understands the reason
without needing to know how the estimator works internally.

HOW IT WORKS
    Each condition below is checked independently. If ANY condition applies,
    review is required and its (Arabic, explained) reason is included in the
    result. There is no numeric score or confidence level — a case either
    needs a second look or it doesn't, and the reasons say exactly why:

        vehicle older than 10 years
        previous accident on the SAME visual part/type
        safety-related (airbag deployed)
        estimate >= 50% of vehicle value

WHERE EACH SIGNAL COMES FROM (passed IN — this service does not fetch them):
    age                          <- vehicle year (registered vehicle)
    prior_accident_same_location <- OUR OWN Firestore case history: an older eligible
                                    case on this vehicle with the same segmentation-
                                    derived canonical part and damage type. It does
                                    not come from a Najm-zone comparison.
    airbag_deployed              <- the Najm report when the accident involved one.
                                    Safety is AIRBAG ONLY — the report does not name
                                    engine/chassis, so we do not pretend to catch them.
    ratio                        <- estimated_cost / value_sar, so this runs AFTER
                                    the cost is computed.

    A signal left as None is simply not evaluated (unknown -> condition does
    not fire), so a missing airbag field or an unavailable value never
    fabricates a reason to review.

Each condition can be turned off without a redeploy via config/confidenceRules
in Firestore — set its value to 0 to disable it, any positive value keeps it
enabled. There is nothing left to weight, since there is no score to weigh
conditions against; the config only toggles conditions on or off.
"""
import firebase_admin
from firebase_admin import credentials, firestore

CONFIG_COLLECTION = "config"
CONFIDENCE_DOC = "confidenceRules"

# Condition key -> enabled flag (>0 enabled, 0 disabled); data layer, seed + fallback.
DEFAULT_CONFIDENCE_DEDUCTIONS = {
    "age_over_10":         1,
    "prior_same_location": 1,
    "safety_airbag":       1,
    "ratio_over_50":       1,
}

AGE_THRESHOLD_YEARS = 10
RATIO_THRESHOLD = 0.50

# Condition key -> explained Arabic reason shown to the admin. Written so a
# first-time reviewer understands WHY it matters, not just what was detected.
REASON_LABELS_AR = {
    "age_over_10": (
        "عمر المركبة يتجاوز 10 سنوات"
    ),
    "prior_same_location": (
        "تم رصد حادث سابق لنفس المركبة في نفس موقع الضرر تقريبًا"),
    "safety_airbag": (
        "انفتحت الوسادة الهوائية في هذا الحادث"
    ),
    "ratio_over_50": (
        "التكلفة التقديرية تعادل أو تتجاوز نصف القيمة السوقية للمركبة"),
}

_cache = None


def _db():
    if not firebase_admin._apps:
        firebase_admin.initialize_app(credentials.Certificate("../serviceAccountKey.json"))
    return firestore.client()


def _valid(d) -> bool:
    return (isinstance(d, dict) and len(d) > 0
            and all(isinstance(v, (int, float)) and v >= 0 for v in d.values()))


def load_deductions(force_refresh: bool = False) -> dict:
    global _cache
    if _cache is not None and not force_refresh:
        return _cache
    try:
        snap = _db().collection(CONFIG_COLLECTION).document(CONFIDENCE_DOC).get()
        d = snap.to_dict() if snap.exists else None
        _cache = d if _valid(d) else dict(DEFAULT_CONFIDENCE_DEDUCTIONS)
    except Exception:
        _cache = dict(DEFAULT_CONFIDENCE_DEDUCTIONS)
    return _cache


def assess_confidence(
    *,
    vehicle_year=None,
    current_year=None,
    estimated_cost=None,
    vehicle_value_sar=None,
    airbag_deployed=None,
    prior_accident_same_location=None,
) -> dict:
    """
    Returns:
        {
          "requires_admin_review": bool,
          "reasons_ar": [str, ...],   # already explained, ready to show as-is
        }
    Signals left as None are not evaluated (unknown -> condition does not fire).
    NOTE: ratio needs estimated_cost, so call this AFTER the cost is computed.
    """
    enabled = load_deductions()
    applied = []

    if (
        enabled.get("age_over_10", 0)
        and vehicle_year
        and current_year
        and (current_year - vehicle_year) > AGE_THRESHOLD_YEARS
    ):
        applied.append("age_over_10")

    if enabled.get("prior_same_location", 0) and prior_accident_same_location is True:
        applied.append("prior_same_location")

    if enabled.get("safety_airbag", 0) and airbag_deployed is True:
        applied.append("safety_airbag")

    if enabled.get("ratio_over_50", 0) and estimated_cost is not None and vehicle_value_sar:
        try:
            if float(estimated_cost) / float(vehicle_value_sar) >= RATIO_THRESHOLD:
                applied.append("ratio_over_50")
        except (TypeError, ValueError, ZeroDivisionError):
            pass

    reasons_ar = [REASON_LABELS_AR.get(k, k) for k in applied]

    return {
        "requires_admin_review": bool(applied),
        "reasons_ar": reasons_ar,
    }


def seed_defaults():
    """Create/overwrite config/confidenceRules from DEFAULT_CONFIDENCE_DEDUCTIONS."""
    _db().collection(CONFIG_COLLECTION).document(CONFIDENCE_DOC).set(DEFAULT_CONFIDENCE_DEDUCTIONS)
    print(f"Seeded {CONFIG_COLLECTION}/{CONFIDENCE_DOC}: {DEFAULT_CONFIDENCE_DEDUCTIONS}")


if __name__ == "__main__":
    seed_defaults()
