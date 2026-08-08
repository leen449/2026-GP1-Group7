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
import os, json, base64, datetime, pathlib, hashlib, uuid
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
_LOGO_PATH = pathlib.Path(__file__).resolve().parent.parent / "assets" / "report" / "logo.png"


@lru_cache(maxsize=1)
def _logo_data_uri() -> str:
    """Same logo asset used on the PDF report, inlined so the page needs no
    extra request/static route."""
    if not _LOGO_PATH.is_file():
        return ""
    return "data:image/png;base64," + base64.b64encode(_LOGO_PATH.read_bytes()).decode()


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

def create_report(data: ReportInput, base_url: str, store):
    """
    Create, sign, and store a new report record, then generate its
    public verification URL and QR image.

    Returns:
        tuple:
            record     -> the signed and stored ReportRecord
            report_url -> public verification URL
            qr_png     -> QR image as PNG bytes
    """
    report_id = str(uuid.uuid4())

    seq = store.next_seq()
    report_number = format_report_number(seq)

    record = build_report_record(
        data=data,
        report_id=report_id,
        report_number=report_number,
    )

    store.save(record)

    report_url = verify_url(base_url, report_id)
    qr_png = make_qr_png(report_url)

    return record, report_url, qr_png


def attach_pdf_hash(report_id: str, pdf_bytes: bytes, store) -> ReportRecord:
    """
    Calculate the SHA-256 fingerprint of the finalized PDF and attach it
    to the stored report record.

    The report is signed again because pdf_sha256 is one of the immutable
    issued facts protected by the digital signature.
    """
    record = store.get(report_id)

    if record is None:
        raise ValueError(f"Report not found: {report_id}")

    pdf_hash = hashlib.sha256(pdf_bytes).hexdigest()

    record.pdf_sha256 = pdf_hash

    # pdf_sha256 is included in _canonical_facts, so the signature must
    # be recreated after attaching the final PDF fingerprint.
    record.signature = sign_record(record)

    store.save(record)

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
# Status is a LIVE field on the report (see models/report.py) — separate from
# the case workflow status ("تم المراجعة") that gates report generation in
# routes/reports.py. Only the Arabic labels shown here changed; the underlying
# values (valid / superseded / claim_pending) are untouched.
_STATUS_LABEL = {
    "valid": ("صالح", "#1a7f37"),
    "superseded": ("تم استبداله بتقييم أحدث", "#9a6700"),
    "claim_pending": ("قيد مراجعة الاعتراض", "#9a6700"),
}

_PAGE = Template(r"""<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>تقرير CrashLens · {{ r.report_number }}</title>
<style>
 :root{--ink:#12233b;--muted:#5b6b7f;--line:#e6ebf1;--bg:#f4f6f9}
 *{box-sizing:border-box} body{margin:0;font-family:"Segoe UI",Tahoma,Arial,sans-serif;
   background:var(--bg);color:var(--ink);padding:clamp(10px,4vw,24px)}
 .card{max-width:720px;margin:0 auto;background:#fff;border:1px solid var(--line);
   border-radius:16px;overflow:hidden;box-shadow:0 6px 24px rgba(18,35,59,.06)}
 .top{display:flex;align-items:center;gap:12px;padding:18px clamp(14px,4vw,24px);border-bottom:1px solid var(--line)}
 .logo{width:40px;height:40px;border-radius:10px;object-fit:contain;flex-shrink:0}
 .brand{font-weight:800;font-size:clamp(16px,4vw,19px);letter-spacing:.2px}
 .sub{color:var(--muted);font-size:13px}
 .status{padding:10px clamp(14px,4vw,24px);font-size:13px;font-weight:700}
 .grid{padding:8px clamp(14px,4vw,24px) 4px} .sec{padding:14px 0;border-bottom:1px solid var(--line)}
 .sec:last-child{border-bottom:0} .h{font-size:12px;
   letter-spacing:.6px;color:var(--muted);margin-bottom:8px;font-weight:700}
 .row{display:flex;justify-content:space-between;gap:12px;padding:4px 0;font-size:14px;flex-wrap:wrap}
 .row .k{color:var(--muted)} .row .v{font-weight:600;text-align:left;word-break:break-word}
 .twrap{overflow-x:auto}
 table{width:100%;border-collapse:collapse;font-size:13.5px;min-width:340px}
 th,td{padding:7px 8px;text-align:right}
 th{color:var(--muted);font-weight:700;border-bottom:1px solid var(--line);font-size:12px}
 td{border-bottom:1px solid var(--line)} .sev{font-weight:700}
 .total{display:flex;justify-content:space-between;padding:14px clamp(14px,4vw,24px);font-size:16px;font-weight:800;
   background:#fafbfc;border-top:1px solid var(--line)}
 .foot{padding:14px clamp(14px,4vw,24px);color:var(--muted);font-size:12.5px;line-height:1.6}
 .foot.bad{color:#c0362c;font-weight:600}
 @media (max-width:420px){
   .row{flex-direction:column;gap:2px} .row .v{text-align:right}
   .total{flex-direction:column;gap:4px}
 }
</style></head><body><div class="card">
 <div class="top">
   {% if logo %}<img class="logo" src="{{ logo }}" alt="CrashLens">{% endif %}
   <div><div class="brand">CrashLens</div><div class="sub">التحقق من التقرير</div></div>
 </div>
 <div class="status" style="background:{{ scolor }}12;color:{{ scolor }}">الحالة: {{ slabel }}</div>
 <div class="grid">
   <div class="sec">
     <div class="row"><span class="k">رقم التقرير</span><span class="v">{{ r.report_number }}</span></div>
     <div class="row"><span class="k">تاريخ التقرير</span><span class="v">{{ r.issued_at }}</span></div>
     <div class="row"><span class="k">رقم الحادث (نجم)</span><span class="v">{{ r.accident_number }}</span></div>
   </div>
   <div class="sec"><div class="h">المالك</div>
     <div class="row"><span class="k">الاسم</span><span class="v">{{ r.user.name }}</span></div>
     <div class="row"><span class="k">رقم الهوية</span><span class="v">{{ r.user.national_id }}</span></div>
     <div class="row"><span class="k">رقم الجوال</span><span class="v">{{ r.user.phone }}</span></div>
   </div>
   <div class="sec"><div class="h">بيانات المركبة</div>
     <div class="row"><span class="k">المصنع والموديل</span><span class="v">{{ r.vehicle.make }} {{ r.vehicle.model }}</span></div>
     <div class="row"><span class="k">السنة</span><span class="v">{{ r.vehicle.year }}</span></div>
     <div class="row"><span class="k">اللون</span><span class="v">{{ r.vehicle.color }}</span></div>
     <div class="row"><span class="k">رقم الهيكل</span><span class="v">{{ r.vehicle.vin }}</span></div>
   </div>
   <div class="sec"><div class="h">تقييم الأضرار</div>
     <div class="twrap"><table><thead><tr><th>نوع الضرر</th><th>شدة الضرر</th><th>التكلفة (ريال)</th></tr></thead>
     <tbody>{% for d in r.damages %}<tr><td>{{ d.type }}</td>
       <td class="sev">{{ d.severity }}</td>
       <td>{{ "%.0f"|format(d.cost_sar) }}</td></tr>{% endfor %}</tbody></table></div>
   </div>
 </div>
 <div class="total"><span>إجمالي التكلفة التقديرية</span><span>{{ "%.0f"|format(r.total_cost_sar) }} ريال</span></div>
 <div class="foot{% if not valid %} bad{% endif %}">
   {% if valid %}تم التحقق من هذا التقرير إلكترونيًا، ولم تُعدَّل بياناته منذ إصداره من قِبل CrashLens.
   {% else %}تنبيه: تعذّر التحقق من هذا التقرير. قد تكون بياناته معدَّلة أو أنه لم يصدر عن CrashLens.{% endif %}
 </div>
</div></body></html>""")


def render_verify_html(record: ReportRecord, valid: bool) -> str:
    slabel, scolor = _STATUS_LABEL.get(record.status, (record.status, "#5b6b7f"))
    return _PAGE.render(
        r=record, valid=valid, slabel=slabel, scolor=scolor, logo=_logo_data_uri()
    )
