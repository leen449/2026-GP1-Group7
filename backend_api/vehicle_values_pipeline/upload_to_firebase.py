"""
Upload the aggregated vehicle-value lookup into Firestore.
CrashLens · step 3 of 3 (scrape -> aggregate -> UPLOAD)

Reads vehicle_values_lookup.json and writes it to a Firestore collection the
backend can query per case.

FIRESTORE STRUCTURE
    Collection: vehicleValues
    Document ID: "make|model|year"  (same key as the lookup JSON / normalize.make_key)
    Fields:      make, model, year, value_sar, value_source,
                 used_median_sar, used_count, new_median_sar, new_count,
                 low_confidence

    Document-per-vehicle (not one giant doc) means the gate fetches exactly the
    one vehicle it needs with a direct .get(doc_id) — no scanning. The gate MUST
    build doc_id via the SAME normalize.make_key(), or lookups silently miss.

RUN THIS ONCE (or whenever you re-aggregate). Not part of the request path.
Uses the same serviceAccountKey.json / Admin SDK as the backend, so it bypasses
security rules — no client can write this collection.

    pip install firebase-admin
"""
import json, pathlib
import firebase_admin
from firebase_admin import credentials, firestore

HERE = pathlib.Path(__file__).resolve().parent
LOOKUP_FILE = str(HERE / "data" / "vehicle_values_lookup.json")
COLLECTION = "vehicleValues"
BATCH_LIMIT = 400   # Firestore hard limit is 500 writes/batch; stay under.


def upload():
    if not firebase_admin._apps:
        cred = credentials.Certificate(str(HERE.parent / "serviceAccountKey.json"))
        firebase_admin.initialize_app(cred)
    db = firestore.client()

    with open(LOOKUP_FILE, encoding="utf-8") as f:
        data = json.load(f)

    # Drop the metadata block; upload only real entries.
    entries = {k: v for k, v in data.items() if not k.startswith("_")}
    print(f"Uploading {len(entries)} entries to '{COLLECTION}'...")

    batch = db.batch()
    count = 0
    for key, value in entries.items():
        # Firestore doc IDs cannot contain '/'. Keys are make|model|year
        # (lowercase); guard against a stray slash or empty id just in case.
        doc_id = key.replace("/", "-").strip()
        if not doc_id or doc_id.count("|") != 2:
            print(f"   ⚠️  skipped malformed key: {key!r}")
            continue
        ref = db.collection(COLLECTION).document(doc_id)
        batch.set(ref, value)
        count += 1

        if count % BATCH_LIMIT == 0:
            batch.commit()
            batch = db.batch()
            print(f"   committed {count}")

    batch.commit()
    print(f"✅ Uploaded {count} vehicle value entries")


if __name__ == "__main__":
    upload()
