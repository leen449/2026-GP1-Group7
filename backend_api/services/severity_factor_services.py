"""
Severity factor service (request-path).
CrashLens · supplies F_severity for the repair-cost estimate:

    C_base = H(part, type) × R × F_paint × F_vehicle × F_severity

H is the estimator's labor-hours table, taken as the MODERATE-severity baseline.
F_severity scales that baseline for minor / severe. moderate is 1.00 by definition —
it is the reference the hours are assumed to represent, so if the estimator's numbers
weren't exactly "moderate" in practice, this factor is what absorbs the difference.

WHY THE VALUES ARE DELIBERATELY TIGHT (0.85 / 1.00 / 1.25):
    The hours table already grows with severity — a severe repair already books more
    hours than a minor one. A wide multiplier on top (e.g. 0.5 / 1 / 1.5) would count
    severity a second time and exaggerate the estimate. So this factor is a gentle
    correction, not the main severity driver.

        minor    0.85  — cosmetic damage, less material and finishing work
        moderate 1.00  — baseline repair scenario (the hours table as given)
        severe   1.25  — more extensive effort and repair complexity

These are the agreed working values. They live in code as the seed + fallback and are
overridable at config/severityFactors in Firestore: if the estimator later returns
real per-severity coefficients, the admin swaps them in — no redeploy, no code change,
nothing else in the pipeline affected.

The severity STRING comes from severity_service.classify_severity
(minor | moderate | severe); this service only maps that string to its factor.
"""
import firebase_admin
from firebase_admin import credentials, firestore

CONFIG_COLLECTION = "config"
SEVERITY_DOC = "severityFactors"

# Severity string -> multiplier. moderate is the fixed 1.00 reference.
DEFAULT_SEVERITY_FACTORS = {
    "minor":    0.85,
    "moderate": 1.00,
    "severe":   1.25,
}

# Stable key -> Arabic label for the admin dashboard.
SEVERITY_LABELS_AR = {
    "minor":    "بسيط",
    "moderate": "متوسط",
    "severe":   "شديد",
}

BASELINE_FACTOR = 1.00   # unknown/null severity -> moderate-equivalent, never distorts
_cache = None


def _db():
    if not firebase_admin._apps:
        firebase_admin.initialize_app(credentials.Certificate("../serviceAccountKey.json"))
    return firestore.client()


def _valid(factors) -> bool:
    # moderate must stay the 1.00 reference; every factor a positive number.
    return (isinstance(factors, dict)
            and float(factors.get("moderate", 0)) == 1.00
            and all(isinstance(v, (int, float)) and v > 0 for v in factors.values()))


def load_severity_factors(force_refresh: bool = False) -> dict:
    global _cache
    if _cache is not None and not force_refresh:
        return _cache
    try:
        snap = _db().collection(CONFIG_COLLECTION).document(SEVERITY_DOC).get()
        factors = snap.to_dict() if snap.exists else None
        _cache = factors if _valid(factors) else dict(DEFAULT_SEVERITY_FACTORS)
    except Exception:
        _cache = dict(DEFAULT_SEVERITY_FACTORS)
    return _cache


def get_severity_factor(severity: str) -> float:
    """F_severity for a severity string (minor/moderate/severe). Unknown -> 1.0."""
    key = (severity or "").strip().lower()
    return float(load_severity_factors().get(key, BASELINE_FACTOR))


def categories_for_ui():
    """[(key, arabic_label, factor)] — build the admin dashboard row from this."""
    f = load_severity_factors()
    return [(k, SEVERITY_LABELS_AR.get(k, k), f[k]) for k in DEFAULT_SEVERITY_FACTORS if k in f]


def seed_defaults():
    """Create/overwrite config/severityFactors from DEFAULT_SEVERITY_FACTORS. Run once."""
    _db().collection(CONFIG_COLLECTION).document(SEVERITY_DOC).set(DEFAULT_SEVERITY_FACTORS)
    print(f"Seeded {CONFIG_COLLECTION}/{SEVERITY_DOC}: {DEFAULT_SEVERITY_FACTORS}")


if __name__ == "__main__":
    seed_defaults()
