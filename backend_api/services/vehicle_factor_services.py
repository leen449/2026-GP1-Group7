"""
Vehicle category factor service (request-path).
CrashLens · supplies F_vehicle for the repair-cost estimate:

    C_base = H(part, type) × R × F_paint × F_vehicle × F_severity

The estimator never gave SUV/luxury labor multipliers, so category is DERIVED from
the vehicle's own market value (value_sar) instead of asked. We read the value the
scrape pipeline produced (used median from Syarah, or a depreciated new price), bucket
it into a tier, and each tier carries a multiplier for repair COMPLEXITY — not part
price, which is handled separately.

THRESHOLDS — validated against the real scraped distribution (844 make/model/year
entries, 3,002 used listings), grounded in recognizable cars:

        value < 80,000        economy    0.90
        80,000 – 200,000      mid-range  1.00   (baseline)
        value > 200,000       luxury     1.20

    • 80,000 anchors the baseline at the Camry (78–122k) / Accord (79–101k) class —
      the standard mid sedan — with Corolla/Sonata straddling and Rio (30–45k) below.
    • 200,000 isolates the premium tier: Land Cruiser (175–354k), Patrol (140–337k),
      higher Lexus ES — the real top ~7–12% of the market.
    • Because the used market skews old/cheap, most real cases fall in economy (0.90);
      that is intended — 1.00 is the mid-sedan reference, not the modal car.

WHY THE MULTIPLIERS ARE MODEST (0.90 / 1.00 / 1.20): the labor-hours table already
carries most of the cost; F_vehicle only nudges for repair complexity (premium
materials, stricter standards, specialized labor), so a wide spread would overstate it.

Same storage as paintFactors: real values live in code as seed + fallback, overridable
at config/vehicleFactors in Firestore — retune the multipliers, or the thresholds,
without a redeploy. Unknown/missing value -> baseline 1.0, so a vehicle with no value
on file never inflates the estimate.
"""
import firebase_admin
from firebase_admin import credentials, firestore

CONFIG_COLLECTION = "config"
VEHICLE_DOC = "vehicleFactors"

# Tier key -> multiplier (data layer; seed + fallback).
DEFAULT_VEHICLE_FACTORS = {
    "economy":   0.90,
    "mid_range": 1.00,
    "luxury":    1.20,
}

# Tier boundaries in SAR, validated against the scraped distribution.
# economy: value < ECONOMY_MAX ; mid_range: ECONOMY_MAX..LUXURY_MIN inclusive ;
# luxury: value > LUXURY_MIN.
ECONOMY_MAX = 80_000
LUXURY_MIN  = 200_000

# Stable key -> Arabic label for the admin dashboard.
VEHICLE_LABELS_AR = {
    "economy":   "اقتصادية",
    "mid_range": "متوسطة",
    "luxury":    "فاخرة",
}

BASELINE_FACTOR = 1.00   # unknown value / unresolved tier -> baseline, never inflates
_cache = None


def _db():
    if not firebase_admin._apps:
        firebase_admin.initialize_app(credentials.Certificate("../serviceAccountKey.json"))
    return firestore.client()


def _valid(factors) -> bool:
    return (isinstance(factors, dict) and len(factors) > 0
            and all(isinstance(v, (int, float)) and v > 0 for v in factors.values()))


def load_vehicle_factors(force_refresh: bool = False) -> dict:
    global _cache
    if _cache is not None and not force_refresh:
        return _cache
    try:
        snap = _db().collection(CONFIG_COLLECTION).document(VEHICLE_DOC).get()
        factors = snap.to_dict() if snap.exists else None
        _cache = factors if _valid(factors) else dict(DEFAULT_VEHICLE_FACTORS)
    except Exception:
        _cache = dict(DEFAULT_VEHICLE_FACTORS)
    return _cache


def tier_for_value(value_sar) -> str:
    """Bucket a market value into a tier key. None/invalid -> '' (baseline)."""
    if value_sar is None:
        return ""
    try:
        v = float(value_sar)
    except (TypeError, ValueError):
        return ""
    if v < ECONOMY_MAX:
        return "economy"
    if v > LUXURY_MIN:
        return "luxury"
    return "mid_range"


def get_vehicle_factor(value_sar) -> float:
    """F_vehicle from the vehicle's market value. Unknown -> 1.0."""
    tier = tier_for_value(value_sar)
    return float(load_vehicle_factors().get(tier, BASELINE_FACTOR))


def categories_for_ui():
    """[(key, arabic_label, factor)] — build the admin dashboard row from this."""
    f = load_vehicle_factors()
    return [(k, VEHICLE_LABELS_AR.get(k, k), f[k]) for k in DEFAULT_VEHICLE_FACTORS if k in f]


def seed_defaults():
    """Create/overwrite config/vehicleFactors from DEFAULT_VEHICLE_FACTORS. Run once."""
    _db().collection(CONFIG_COLLECTION).document(VEHICLE_DOC).set(DEFAULT_VEHICLE_FACTORS)
    print(f"Seeded {CONFIG_COLLECTION}/{VEHICLE_DOC}: {DEFAULT_VEHICLE_FACTORS}")


if __name__ == "__main__":
    seed_defaults()
