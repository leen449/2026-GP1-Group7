"""
CrashLens · where report records are stored.

Two interchangeable stores behind one tiny interface:
  * FirestoreReportStore  -> production (collection "reports", same Admin SDK
                             pattern as upload_to_firebase.py / vehicleValues).
  * InMemoryReportStore   -> local testing, no Firebase needed.

`get_store()` picks Firestore when Firebase Admin is initialized, otherwise
falls back to in-memory. This is what lets the exact same route code run on
your laptop today and on Cloud Run later.
"""
from __future__ import annotations
from typing import Optional
from models.report import ReportRecord

_COLLECTION = "reports"
_COUNTER_DOC = ("_meta", "report_counter")   # collection, doc


class InMemoryReportStore:
    def __init__(self):
        self._data: dict[str, dict] = {}
        self._seq = 0

    def next_seq(self) -> int:
        self._seq += 1
        return self._seq

    def save(self, record: ReportRecord) -> None:
        self._data[record.report_id] = record.model_dump()

    def get(self, report_id: str) -> Optional[ReportRecord]:
        doc = self._data.get(report_id)
        return ReportRecord(**doc) if doc else None


class FirestoreReportStore:
    def __init__(self):
        from firebase_admin import firestore
        self._db = firestore.client()

    def next_seq(self) -> int:
        """Atomic incrementing counter so report numbers never collide."""
        from firebase_admin import firestore
        ref = self._db.collection(_COUNTER_DOC[0]).document(_COUNTER_DOC[1])

        @firestore.transactional
        def _txn(txn):
            snap = ref.get(transaction=txn)
            current = (snap.to_dict() or {}).get("seq", 0) if snap.exists else 0
            nxt = current + 1
            txn.set(ref, {"seq": nxt})
            return nxt

        return _txn(self._db.transaction())

    def save(self, record: ReportRecord) -> None:
        self._db.collection(_COLLECTION).document(record.report_id).set(record.model_dump())

    def get(self, report_id: str) -> Optional[ReportRecord]:
        snap = self._db.collection(_COLLECTION).document(report_id).get()
        return ReportRecord(**snap.to_dict()) if snap.exists else None


_singleton = None


def get_store():
    """Return a process-wide store; Firestore if Firebase is up, else in-memory."""
    global _singleton
    if _singleton is not None:
        return _singleton
    try:
        import firebase_admin
        if firebase_admin._apps:                 # main.py already initialized it
            _singleton = FirestoreReportStore()
            return _singleton
    except Exception:
        pass
    _singleton = InMemoryReportStore()
    return _singleton
