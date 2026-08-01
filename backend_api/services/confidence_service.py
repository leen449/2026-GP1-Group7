"""
Confidence assessment service (request-path).
CrashLens · scores how much to TRUST a rule-based estimate. This is a SEPARATE
score shown next to the cost — it never changes the cost itself. It encodes the
cases Tagdeer estimators said they don't auto-value and refer to شيخ المعارض, and
keeps a human in the loop by surfacing the reasons to the admin.

HOW IT WORKS
    Start at 100 and subtract for each condition that applies:

        vehicle older than 10 years .................. −10
        previous accident in the SAME location ....... −10
        safety-related (airbag deployed) ............. −20
        estimate ≥ 50% of vehicle value .............. −20

        confidence = 100 − (sum of deductions)     [clamped to 0..100]

    Level:  90–100 High   |   70–89 Medium   |   below 70 Low
    Action: High = fine · Medium = review before approving · Low = manual inspection

WHERE EACH SIGNAL COMES FROM (passed IN — this service does not fetch them):
    age                          <- vehicle year (registered vehicle)
    prior_accident_same_location <- OUR OWN case database (a prior case on this
                                    vehicle at the same location), NOT the Najm report
    airbag_deployed              <- the Najm report when the accident involved one.
                                    Safety is AIRBAG ONLY — the report does not name
                                    engine/chassis, so we do not pretend to catch them.
    ratio                        <- estimated_cost / value_sar, so this runs AFTER
                                    the cost is computed.

    A signal left as None is simply not evaluated (unknown -> no deduction), so a
    missing airbag field or an unavailable value never fabricates a penalty.

Deduction values live in code as seed + fallback and are overridable at
config/confidenceRules in Firestore (retune without a redeploy). The band cutoffs
are module constants below.
"""
import firebase_admin
from firebase_admin import credentials, firestore

CONFIG_COLLECTION = "config"
CONFIDENCE_DOC = "confidenceRules"

# Condition key -> confidence points deducted (data layer; seed + fallback).
DEFAULT_CONFIDENCE_DEDUCTIONS = {
    "age_over_10":         10,
    "prior_same_location": 10,
    "safety_airbag":       20,
    "ratio_over_50":       20,
}

# Band cutoffs (design constants).
HIGH_MIN = 90     # 90..100 -> high
MEDIUM_MIN = 70   # 70..89  -> medium ; below -> low

AGE_THRESHOLD_YEARS = 10
RATIO_THRESHOLD = 0.50

# Condition key -> Arabic reason shown to the admin.
REASON_LABELS_AR = {
    "age_over_10":         "عمر المركبة يتجاوز 10 سنوات",
    "prior_same_location": "يوجد حادث سابق في نفس الموقع",
    "safety_airbag":       "ضرر متعلق بالسلامة (انفتاح وسادة هوائية)",
    "ratio_over_50":       "التقدير يعادل أو يتجاوز 50% من قيمة المركبة",
}

# Level -> (Arabic label, admin recommendation).
LEVEL_AR = {"high": "عالية", "medium": "متوسطة", "low": "منخفضة"}
LEVEL_RECOMMENDATION_AR = {
    "high":   "",
    "medium": "يرجى المراجعة قبل الاعتماد",
    "low":    "يوصى بالفحص اليدوي",
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


def _level(score: int) -> str:
    if score >= HIGH_MIN:
        return "high"
    if score >= MEDIUM_MIN:
        return "medium"
    return "low"


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
          "confidence_score": int,          # 0..100
          "level": "high|medium|low",
          "level_ar": str,
          "recommendation_ar": str,         # "" for high
          "requires_admin_review": bool,    # True for medium/low
          "deductions": [ {reason, reason_ar, points}, ... ],
          "reasons_ar": [str, ...],
        }
    Signals left as None are not evaluated (unknown -> no deduction).
    NOTE: ratio needs estimated_cost, so call this AFTER the cost is computed.
    """
    d = load_deductions()
    applied = []  # list of condition keys that fired

    if vehicle_year and current_year and (current_year - vehicle_year) > AGE_THRESHOLD_YEARS:
        applied.append("age_over_10")

    if prior_accident_same_location is True:
        applied.append("prior_same_location")

    if airbag_deployed is True:
        applied.append("safety_airbag")

    if estimated_cost is not None and vehicle_value_sar:
        try:
            if float(estimated_cost) / float(vehicle_value_sar) >= RATIO_THRESHOLD:
                applied.append("ratio_over_50")
        except (TypeError, ValueError, ZeroDivisionError):
            pass

    total = sum(float(d.get(k, 0)) for k in applied)
    score = int(max(0, min(100, 100 - total)))
    level = _level(score)

    deductions = [
        {"reason": k, "reason_ar": REASON_LABELS_AR.get(k, k), "points": int(d.get(k, 0))}
        for k in applied
    ]

    return {
        "confidence_score": score,
        "level": level,
        "level_ar": LEVEL_AR[level],
        "recommendation_ar": LEVEL_RECOMMENDATION_AR[level],
        "requires_admin_review": level != "high",
        "deductions": deductions,
        "reasons_ar": [x["reason_ar"] for x in deductions],
    }


def seed_defaults():
    """Create/overwrite config/confidenceRules from DEFAULT_CONFIDENCE_DEDUCTIONS."""
    _db().collection(CONFIG_COLLECTION).document(CONFIDENCE_DOC).set(DEFAULT_CONFIDENCE_DEDUCTIONS)
    print(f"Seeded {CONFIG_COLLECTION}/{CONFIDENCE_DOC}: {DEFAULT_CONFIDENCE_DEDUCTIONS}")


if __name__ == "__main__":
    seed_defaults()
