"""
CrashLens · report verification service (the ONLY place cryptography lives).

Responsibilities, all as plain functions so they are easy to test:
  * load the Ed25519 keys ONCE (from Secret Manager env vars in prod,
    or from backend_api/keys/*.pem in local dev),
  * sign a finalized report record (the "issued facts"),
  * verify a stored record against the public key,
  * build the QR image (encodes only the verify URL),
  * render the public verification HTML page.

The signature covers the *immutable issued facts* only — NOT the `status`
field, because status is a live value (valid / superseded / claim_pending)
that the admin or a claim can change after issuance without re-signing.
"""
from __future__ import annotations
import os, json, base64, datetime, pathlib
from functools import lru_cache
from typing import Optional

import cv2
import numpy as np
from jinja2 import Template
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey, Ed25519PublicKey,
)
from cryptography.exceptions import InvalidSignature

from models.report import ReportRecord, ReportInput

_KEYS_DIR = pathlib.Path(__file__).resolve().parent.parent / "keys"


# ── keys ────────────────────────────────────────────────────────────────────
@lru_cache(maxsize=1)
def _private_key() -> Ed25519PrivateKey:
    pem = os.environ.get("CRASHLENS_PRIVATE_KEY_PEM")
    data = pem.encode() if pem else (_KEYS_DIR / "crashlens_private.pem").read_bytes()
    return serialization.load_pem_private_key(data, password=None)


@lru_cache(maxsize=1)
def _public_key() -> Ed25519PublicKey:
    pem = os.environ.get("CRASHLENS_PUBLIC_KEY_PEM")
    data = pem.encode() if pem else (_KEYS_DIR / "crashlens_public.pem").read_bytes()
    return serialization.load_pem_public_key(data)


# ── canonical payload + signing ──────────────────────────────────────────────
def _canonical_facts(record: ReportRecord) -> bytes:
    """Deterministic bytes of the issued facts (everything except live status
    and the signature itself). Any change to these bytes breaks the signature."""
    facts = record.model_dump()
    facts.pop("status", None)
    facts.pop("signature", None)
    return json.dumps(facts, separators=(",", ":"), sort_keys=True).encode()


def sign_record(record: ReportRecord) -> str:
    sig = _private_key().sign(_canonical_facts(record))
    return base64.b64encode(sig).decode()


def verify_record(record: ReportRecord) -> bool:
    if not record.signature:
        return False
    try:
        _public_key().verify(base64.b64decode(record.signature), _canonical_facts(record))
        return True
    except (InvalidSignature, ValueError):
        return False


# ── record assembly ──────────────────────────────────────────────────────────
def format_report_number(seq: int, when: Optional[datetime.date] = None) -> str:
    when = when or datetime.date.today()
    return f"CL-{when.year}-{seq:06d}"


def build_report_record(data: ReportInput, report_id: str, report_number: str) -> ReportRecord:
    """Assemble + sign a record. `report_id` (unguessable UUID) and
    `report_number` (human-friendly) are allocated by the caller."""
    total = round(sum(d.cost_sar for d in data.damages), 2)
    record = ReportRecord(
        report_id=report_id,
        report_number=report_number,
        issued_at=datetime.date.today().isoformat(),
        accident_number=data.accident_number,
        user=data.user,
        vehicle=data.vehicle,
        damages=data.damages,
        total_cost_sar=total,
        pdf_sha256=data.pdf_sha256,
        status="valid",
    )
    record.signature = sign_record(record)
    return record


# ── QR ───────────────────────────────────────────────────────────────────────
def verify_url(base_url: str, report_id: str) -> str:
    return f"{base_url.rstrip('/')}/verify/{report_id}"


def make_qr_png(url: str, box_size: int = 600) -> bytes:
    """QR encodes ONLY the URL, so any phone camera can open it."""
    img = cv2.QRCodeEncoder_create().encode(url)
    img = cv2.resize(img, (box_size, box_size), interpolation=cv2.INTER_NEAREST)
    ok, buf = cv2.imencode(".png", img)
    if not ok:
        raise RuntimeError("QR PNG encode failed")
    return buf.tobytes()


# ── public verification page ─────────────────────────────────────────────────
_STATUS_LABEL = {
    "valid": ("Valid", "#1a7f37"),
    "superseded": ("Superseded by a newer assessment", "#9a6700"),
    "claim_pending": ("Under claim review", "#9a6700"),
}

_PAGE = Template(r"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>CrashLens · Report {{ r.report_number }}</title>
<style>
 :root{--ink:#12233b;--muted:#5b6b7f;--line:#e6ebf1;--bg:#f4f6f9}
 *{box-sizing:border-box} body{margin:0;font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;
   background:var(--bg);color:var(--ink);padding:24px}
 .card{max-width:720px;margin:0 auto;background:#fff;border:1px solid var(--line);
   border-radius:16px;overflow:hidden;box-shadow:0 6px 24px rgba(18,35,59,.06)}
 .top{display:flex;align-items:center;gap:12px;padding:20px 24px;border-bottom:1px solid var(--line)}
 .logo{width:40px;height:40px;border-radius:10px;background:#12233b;display:flex;
   align-items:center;justify-content:center;color:#fff;font-weight:800}
 .brand{font-weight:800;font-size:19px;letter-spacing:.2px}
 .sub{color:var(--muted);font-size:13px}
 .badge{margin-left:auto;display:flex;align-items:center;gap:8px;font-weight:700;
   font-size:14px;padding:8px 14px;border-radius:999px}
 .ok{background:#eaf6ee;color:#1a7f37} .bad{background:#fdecec;color:#c0362c}
 .status{padding:10px 24px;font-size:13px;font-weight:600}
 .grid{padding:8px 24px 4px} .sec{padding:14px 0;border-bottom:1px solid var(--line)}
 .sec:last-child{border-bottom:0} .h{font-size:12px;text-transform:uppercase;
   letter-spacing:.6px;color:var(--muted);margin-bottom:8px}
 .row{display:flex;justify-content:space-between;gap:16px;padding:3px 0;font-size:14px}
 .row .k{color:var(--muted)} .row .v{font-weight:600;text-align:right}
 table{width:100%;border-collapse:collapse;font-size:14px} th,td{padding:7px 8px;text-align:left}
 th{color:var(--muted);font-weight:600;border-bottom:1px solid var(--line);font-size:12px}
 td{border-bottom:1px solid var(--line)} .sev{font-weight:700;text-transform:capitalize}
 .total{display:flex;justify-content:space-between;padding:14px 24px;font-size:16px;font-weight:800;
   background:#fafbfc;border-top:1px solid var(--line)}
 .foot{padding:14px 24px;color:var(--muted);font-size:12px;line-height:1.5}
 .hash{font-family:ui-monospace,Menlo,monospace;word-break:break-all}
</style></head><body><div class="card">
 <div class="top">
   <div class="logo">CL</div>
   <div><div class="brand">CrashLens</div><div class="sub">Report verification</div></div>
   {% if valid %}<div class="badge ok">&#10003; Cryptographically verified</div>
   {% else %}<div class="badge bad">&#10007; Verification failed</div>{% endif %}
 </div>
 <div class="status" style="background:{{ scolor }}12;color:{{ scolor }}">Status: {{ slabel }}</div>
 <div class="grid">
   <div class="sec">
     <div class="row"><span class="k">Report number</span><span class="v">{{ r.report_number }}</span></div>
     <div class="row"><span class="k">Report date</span><span class="v">{{ r.issued_at }}</span></div>
     <div class="row"><span class="k">Najm accident number</span><span class="v">{{ r.accident_number }}</span></div>
   </div>
   <div class="sec"><div class="h">Owner</div>
     <div class="row"><span class="k">Name</span><span class="v">{{ r.user.name }}</span></div>
     <div class="row"><span class="k">National ID</span><span class="v">{{ r.user.national_id }}</span></div>
     <div class="row"><span class="k">Phone</span><span class="v">{{ r.user.phone }}</span></div>
   </div>
   <div class="sec"><div class="h">Vehicle</div>
     <div class="row"><span class="k">Make &amp; model</span><span class="v">{{ r.vehicle.make }} {{ r.vehicle.model }}</span></div>
     <div class="row"><span class="k">Year</span><span class="v">{{ r.vehicle.year }}</span></div>
     <div class="row"><span class="k">Color</span><span class="v">{{ r.vehicle.color }}</span></div>
     <div class="row"><span class="k">VIN</span><span class="v hash">{{ r.vehicle.vin }}</span></div>
   </div>
   <div class="sec"><div class="h">Damage assessment</div>
     <table><thead><tr><th>Type</th><th>Severity</th><th style="text-align:right">Est. cost (SAR)</th></tr></thead>
     <tbody>{% for d in r.damages %}<tr><td>{{ d.type }}</td>
       <td class="sev">{{ d.severity }}</td>
       <td style="text-align:right">{{ "%.0f"|format(d.cost_sar) }}</td></tr>{% endfor %}</tbody></table>
   </div>
 </div>
 <div class="total"><span>Total estimated repair cost</span><span>{{ "%.0f"|format(r.total_cost_sar) }} SAR</span></div>
 <div class="foot">
   {% if valid %}This report was issued by CrashLens and its contents have not been altered
   since issuance (verified with CrashLens's Ed25519 public key).{% else %}
   <b>Warning:</b> the signature does not match. This report may have been altered or was not issued by CrashLens.{% endif %}
   {% if r.pdf_sha256 %}<br>Issued PDF fingerprint (SHA-256): <span class="hash">{{ r.pdf_sha256 }}</span>{% endif %}
 </div>
</div></body></html>""")


def render_verify_html(record: ReportRecord, valid: bool) -> str:
    slabel, scolor = _STATUS_LABEL.get(record.status, (record.status, "#5b6b7f"))
    return _PAGE.render(r=record, valid=valid, slabel=slabel, scolor=scolor)
