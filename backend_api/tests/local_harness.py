"""Local proof (no FastAPI/Firebase): issue -> QR round-trip -> verify -> tamper -> render."""
import sys, pathlib, cv2, numpy as np
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from models.report import ReportInput, UserInfo, VehicleInfo, DamageItem
from services import report_verification_service as svc
from services.report_store import InMemoryReportStore

BASE_URL = "http://172.20.10.2:8000"
store = InMemoryReportStore()

# ---- mock finalized case (the fields you listed) ----
data = ReportInput(
    accident_number="NAJM-2026-778812",
    user=UserInfo(name="Faisal Al-Otaibi", national_id="1093xxxxxx", phone="+9665xxxxxxx"),
    vehicle=VehicleInfo(make="Toyota", model="Camry", color="White", year=2019,
                        vin="4T1BF1FK5CU511111"),
    damages=[
        DamageItem(type="Front bumper", severity="moderate", cost_sar=1800),
        DamageItem(type="Left headlight", severity="severe", cost_sar=2200),
        DamageItem(type="Hood", severity="minor", cost_sar=350),
    ],
)

import uuid
report_id = str(uuid.uuid4())
report_number = svc.format_report_number(store.next_seq())
record = svc.build_report_record(data, report_id, report_number)
store.save(record)
print(f"1. Issued {record.report_number}  id={report_id[:8]}...  total={record.total_cost_sar} SAR")

# ---- QR encodes only the URL; prove it round-trips ----
url = svc.verify_url(BASE_URL, report_id)
png = svc.make_qr_png(url)
pathlib.Path("report_qr.png").write_bytes(png)
img = cv2.imdecode(np.frombuffer(png, np.uint8), cv2.IMREAD_COLOR)
decoded, _, _ = cv2.QRCodeDetector().detectAndDecode(img)
print(f"2. QR encodes: {decoded}")
assert decoded == url, "QR round-trip mismatch!"

# ---- verify the genuine record ----
print(f"3. Signature check (genuine):  {'VALID' if svc.verify_record(store.get(report_id)) else 'INVALID'}")

# ---- render the real verify page ----
good = store.get(report_id)
pathlib.Path("verify_page.html").write_text(
    svc.render_verify_html(good, svc.verify_record(good)), encoding="utf-8")
print("4. Wrote verify_page.html (valid)")

# ---- TAMPER: change a stored cost, re-verify ----
tampered = store.get(report_id)
tampered.damages[1].cost_sar = 200          # attacker lowers the headlight cost
tampered.total_cost_sar = 2350
print(f"5. Signature check (tampered): {'VALID' if svc.verify_record(tampered) else 'INVALID'}")
pathlib.Path("verify_page_tampered.html").write_text(
    svc.render_verify_html(tampered, svc.verify_record(tampered)), encoding="utf-8")
print("6. Wrote verify_page_tampered.html (should show failure)")
print("\nDONE — core logic works with no server and no PDF.")
