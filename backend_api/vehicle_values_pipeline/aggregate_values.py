"""
Aggregate raw vehicle listings into a (make, model, year) -> value lookup.
CrashLens · step 2 of 3 (scrape -> AGGREGATE -> upload)

CHANGE FROM v1
    v1 read ONE Saleh JSON and keyed by (model, year). This version merges TWO
    sources with different shapes and keys by (MAKE, model, year):
      • Syarah  (CSV)  -> USED cars, clean make/model/year/price. PRIMARY.
      • Saleh   (JSON) -> NEW cars, one blob title.               FALLBACK.

DESIGN DECISIONS (documented on purpose)
    1. KEY = make|model|year (shared normalize.make_key). Model alone collides
       ("6", "C5", "7 SERIES"), and the same key must be reproducible by the
       gate/OCR — so keying lives in the shared normalize module, not here.
    2. USED AND NEW ARE NOT BLENDED. Each group keeps a used median (Syarah) and
       a new median (Saleh) separately. The gate wants USED value; a new price is
       only a depreciated fallback when no used data exists for that vehicle.
       Blending them would inflate value and under-refer total losses.
    3. value_sar is chosen: used median if any used listings, else the new median
       depreciated for the car's age. value_source records which, so the gate can
       treat a depreciated-new estimate with less confidence.

WHY MEDIAN / WHY MIN SAMPLE COUNT — unchanged rationale from v1 (outlier-robust;
    sparse groups flagged low_confidence rather than trusted blindly).
"""
import csv
import json
import statistics
from collections import defaultdict
from datetime import datetime

import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))  # backend_api/ on path -> import normalize
HERE = pathlib.Path(__file__).resolve().parent
from services import normalize   # shared source of truth for keys

# --- Inputs / output -------------------------------------------------
SALEH_JSON  = str(HERE / "data" / "vehicle_listings_raw.json")   # NEW cars
SYARAH_CSV  = str(HERE / "data" / "syarah_cleaned_data.csv")     # USED cars
OUTPUT_FILE = str(HERE / "data" / "vehicle_values_lookup.json")

MIN_LISTINGS_FOR_CONFIDENCE = 3
PRICE_MIN, PRICE_MAX = 5000, 5_000_000        # sanity band (drops noise)
CURRENT_YEAR = datetime.now().year

# Generic depreciation used ONLY to turn a new price into a used estimate when
# no used listings exist. Retention = value kept vs new, by age in years.
# ⚠️ Brand-agnostic placeholder. Chinese brands (much of Saleh's stock)
#    depreciate faster than Toyota/Lexus — tier this once you have evidence.
def retained_fraction(age: int) -> float:
    if age <= 0:
        return 1.0
    return round(0.80 * (0.88 ** (age - 1)), 4)   # ~20% yr1, ~12%/yr after


# ─────────────────────────────────────────────────────────────────────
# Source loaders — each yields common records: (make, model, year, price)
# ─────────────────────────────────────────────────────────────────────
def _valid_price(p):
    return p is not None and PRICE_MIN <= p <= PRICE_MAX

def load_syarah(path):
    out = []
    with open(path, encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            try:
                price = int(float(row["price"]))
                year = int(row["year"])
            except (ValueError, KeyError, TypeError):
                continue
            if not _valid_price(price):
                continue
            out.append((row.get("make", ""), row.get("model", ""), year, price))
    return out

def load_saleh(path):
    out = []
    with open(path, encoding="utf-8") as f:
        for item in json.load(f):
            price = item.get("price_sar")
            year = item.get("year")
            if not _valid_price(price) or year is None:
                continue
            make, model = normalize.parse_blob(item.get("raw_model_text", ""))
            out.append((make, model, year, price))
    return out


# ─────────────────────────────────────────────────────────────────────
def aggregate(saleh_json=SALEH_JSON, syarah_csv=SYARAH_CSV, output=OUTPUT_FILE):
    used = load_syarah(syarah_csv)     # Syarah = used
    new = load_saleh(saleh_json)       # Saleh  = new
    print(f"Loaded {len(used)} used (Syarah) + {len(new)} new (Saleh) records")

    # group[key] = {"make","model","year","used":[...],"new":[...]}
    groups = {}
    def bucket(records, bucket_name):
        for make, model, year, price in records:
            m2, mo2 = normalize.canonical_make(make), normalize.canonical_model(model)
            if not m2 or not mo2:   # skip records we couldn't parse into a real key
                continue
            key = normalize.make_key(make, model, year)
            g = groups.setdefault(key, {
                "make": normalize.canonical_make(make),
                "model": normalize.canonical_model(model),
                "year": year, "used": [], "new": [],
            })
            g[bucket_name].append(price)
    bucket(used, "used")
    bucket(new, "new")

    lookup, low_conf = {}, 0
    for key, g in groups.items():
        used_prices, new_prices = g["used"], g["new"]
        used_median = int(statistics.median(used_prices)) if used_prices else None
        new_median = int(statistics.median(new_prices)) if new_prices else None

        if used_median is not None:
            value, source = used_median, "used"
            confident = len(used_prices) >= MIN_LISTINGS_FOR_CONFIDENCE
        elif new_median is not None:
            age = max(CURRENT_YEAR - g["year"], 0)
            value = int(new_median * retained_fraction(age))
            source = "new_depreciated"
            confident = False   # a modelled estimate, never "confident"
        else:
            continue
        if not confident:
            low_conf += 1

        lookup[key] = {
            "make": g["make"], "model": g["model"], "year": g["year"],
            "value_sar": value,
            "value_source": source,
            "used_median_sar": used_median,
            "used_count": len(used_prices),
            "new_median_sar": new_median,
            "new_count": len(new_prices),
            "low_confidence": not confident,
        }

    metadata = {"_metadata": {
        "generated_at": datetime.utcnow().isoformat(),
        "sources": {"used": "syarah", "new": "salehcars"},
        "used_records": len(used), "new_records": len(new),
        "unique_make_model_years": len(lookup),
        "low_confidence_entries": low_conf,
        "note": ("value_sar prefers the used (Syarah) median; where no used data "
                 "exists it is the new (Saleh) median depreciated by age and "
                 "flagged value_source=new_depreciated / low_confidence."),
    }}

    with open(output, "w", encoding="utf-8") as f:
        json.dump({**metadata, **lookup}, f, ensure_ascii=False, indent=2)

    print(f"✅ {len(lookup)} make/model/year entries → {output}")
    print(f"   {low_conf} low_confidence")
    return lookup


if __name__ == "__main__":
    aggregate()
