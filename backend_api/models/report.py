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
    part: Optional[str] = None  # canonical damaged part, when identified
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
    # Single case-level severity (MAX over images — see damage_detection.py's
    # overallSeverity). Shown once on the report instead of repeating severity
    # on every damage row. Optional so existing callers/tests keep working.
    overall_severity: Optional[str] = None
    pdf_sha256: Optional[str] = None   # set once the final PDF exists
    # A case referred to the human specialist (شيخ المعارض) instead of being
    # admin-reviewed. Its report is preliminary and carries no repair-cost
    # figures — see ReportRecord.report_kind. Defaults keep every existing
    # caller/test unaffected.
    is_referral_report: bool = False
    referral_reasons: Optional[List[str]] = None
    # Cost rule v2 display switch (2026-11-07, see
    # backend_api/services/cost_v2/spec/DECISION_cost_rule_v2.md section 7-8).
    # When the case's authoritative total (displayCostSar) was computed by cost_v2,
    # routes/reports.py passes it here explicitly rather than letting the record
    # re-derive total_cost_sar by summing `damages` -- v2's per-LINE sar (line_sar)
    # can round differently than the engine's own single hours*rate-then-round total
    # (see cost_v2/engine.py's docstring), so summing the lines could be a cent or
    # two off from the real displayCostSar. Default None preserves every existing
    # caller's behavior exactly (sum(damages), as before).
    total_cost_sar_override: Optional[float] = None
    # "v1" (default, unchanged) | "v2". Only changes whether the PDF/verify page
    # show the cost_v2 footer below -- never changes how total_cost_sar itself
    # was computed (that's total_cost_sar_override above).
    cost_source: str = "v1"
    cost_rule_version: Optional[str] = None
    cost_table: Optional[str] = None
    cost_rate_sar: Optional[float] = None


class ReportRecord(BaseModel):
    """The full record we store in Firestore and render on the verify page."""
    report_id: str            # unguessable UUID — used inside the verify URL
    report_number: str        # human-friendly, e.g. "CL-2026-000123"
    issued_at: str            # ISO date the report was issued
    accident_number: str
    user: UserInfo
    vehicle: VehicleInfo
    damages: List[DamageItem]
    overall_severity: Optional[str] = None
    total_cost_sar: float
    pdf_sha256: Optional[str] = None
    status: str = "valid"     # valid | superseded | claim_pending  (LIVE, not signed)
    # An ISSUED, permanent fact (unlike `status` above) — fixed at generation
    # time and included in the signature. final | referral_preliminary.
    report_kind: str = "final"
    referral_reasons: Optional[List[str]] = None
    # Cost rule v2 display switch -- see ReportInput's fields of the same name.
    # Carried onto the signed record (not just the PDF) so the public verify page
    # shows the same footer the PDF does, and so it's part of the immutable
    # issued facts like everything else here.
    cost_source: str = "v1"
    cost_rule_version: Optional[str] = None
    cost_table: Optional[str] = None
    cost_rate_sar: Optional[float] = None
    signature: Optional[str] = None   # base64 Ed25519 signature over the issued facts
