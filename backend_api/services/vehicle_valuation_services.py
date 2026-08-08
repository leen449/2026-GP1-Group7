"""
Vehicle valuation service (request-path).
CrashLens · reads ONE vehicle's value from Firestore for the referral gate.

Builds the document id with the SAME normalize.make_key() the pipeline used, so
a vehicle the user registered (make/model/year, typed in Arabic OR Latin)
resolves to the exact document upload_to_firebase.py wrote. One direct .get() —
no scanning, no query cost beyond a single read.

    pip install firebase-admin
"""
import firebase_admin
from firebase_admin import credentials, firestore

from services import normalize   # the shared key logic — must be the same module the pipeline used

COLLECTION = "vehicleValues"
_db = None


def _client():
    global _db
    if _db is None:
        if not firebase_admin._apps:
            firebase_admin.initialize_app(credentials.Certificate("serviceAccountKey.json"))
        _db = firestore.client()
    return _db


def get_vehicle_value(make: str, model: str, year) -> dict | None:
    """
    Return the value record for a vehicle, or None if it's not in the table.
    The gate applies its own repair-to-value ratio and should treat
    low_confidence / value_source == 'new_depreciated' cautiously.
    """
    key = normalize.make_key(make, model, year)
    snap = _client().collection(COLLECTION).document(key).get()
    return snap.to_dict() if snap.exists else None


if __name__ == "__main__":
    import sys
    make, model, year = sys.argv[1], sys.argv[2], int(sys.argv[3])
    key = normalize.make_key(make, model, year)
    rec = get_vehicle_value(make, model, year)
    if rec is None:
        print(f"No value for {make} {model} {year}  (key={key})")
    else:
        print(f"key={key}  value_sar={rec['value_sar']}  source={rec['value_source']}  "
              f"low_confidence={rec['low_confidence']}")
