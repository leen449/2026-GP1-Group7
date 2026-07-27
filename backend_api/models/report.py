"""
CrashLens · report record data shapes (Pydantic).

These describe the DATA of a finalized report — the same fields that appear on
the PDF and on the public verification page. Nothing here talks to the database
or does any cryptography; it is purely the shape of the information.
"""
from __future__ import annotations
from typing import List, Optional
from pydantic import BaseModel, Field


class UserInfo(BaseModel):
    name: str
    national_id: str          # immutable after first case (per project rules)
    phone: str


class VehicleInfo(BaseModel):
    make: str
    model: str
    color: str
    year: int
    vin: str


class DamageItem(BaseModel):
    type: str                 # e.g. "dent", "scratch"
    severity: str             # minor | moderate | severe
    cost_sar: float           # estimated repair cost for this item


class ReportInput(BaseModel):
    """What the backend passes in when the admin finalizes a case.

    `report_id` / `report_number` / `issued_at` are filled in by the service,
    so they are NOT required here.
    """
    accident_number: str      # Najm accident number, read from the
                              #   users/{uid}/accidentCases subcollection
    user: UserInfo
    vehicle: VehicleInfo
    damages: List[DamageItem]
    pdf_sha256: Optional[str] = None   # set once the final PDF exists


class ReportRecord(BaseModel):
    """The full record we store in Firestore and render on the verify page."""
    report_id: str            # unguessable UUID — used inside the verify URL
    report_number: str        # human-friendly, e.g. "CL-2026-000123"
    issued_at: str            # ISO date the report was issued
    accident_number: str
    user: UserInfo
    vehicle: VehicleInfo
    damages: List[DamageItem]
    total_cost_sar: float
    pdf_sha256: Optional[str] = None
    status: str = "valid"     # valid | superseded | claim_pending  (LIVE, not signed)
    signature: Optional[str] = None   # base64 Ed25519 signature over the issued facts
