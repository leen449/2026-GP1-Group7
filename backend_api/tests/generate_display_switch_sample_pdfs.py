"""
backend_api/tests/generate_display_switch_sample_pdfs.py — one-off local proof for
the cost rule v2 DISPLAY SWITCH (integration step 1-2, part 2; see
services/cost_v2/spec/DECISION_cost_rule_v2.md §7-8): generates two real PDFs,
no FastAPI/Firebase, same "local proof" spirit as tests/local_harness.py --

  1. v1_case_sample.pdf  — an OLD case: cost_source="v1" (ReportInput's default),
     exactly what every case issued before this switch already looks like.
  2. v2_case_sample.pdf  — a NEW case: cost_source="v2" with the v2 config/footer
     fields set, exactly what routes/reports.py's _build_report_input produces
     for a case whose displayCostSource == "v2".

Both go through the real build_report_record -> build_report_pdf path (same
functions production uses), so this is a genuine render of what admins/users
will see, not a mockup.

Usage: python tests/generate_display_switch_sample_pdfs.py
"""
import sys
import uuid
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND_DIR))

from models.report import ReportInput, UserInfo, VehicleInfo, DamageItem  # noqa: E402
from services import report_verification_service as svc  # noqa: E402
from services.report_pdf_service import build_report_pdf  # noqa: E402
from services.report_store import InMemoryReportStore  # noqa: E402

OUTPUT_DIR = BACKEND_DIR / "tests" / "output" / "sample_reports"

_USER = UserInfo(name="Faisal Al-Otaibi", national_id="1093456789", phone="+966501234567")
_VEHICLE = VehicleInfo(make="Toyota", model="Camry", color="White", year=2019,
                        vin="4T1BF1FK5CU511111")


def _issue_and_render(data: ReportInput, store, label: str) -> Path:
    report_id = str(uuid.uuid4())
    report_number = svc.format_report_number(store.next_seq())
    record = svc.build_report_record(data, report_id, report_number)
    store.save(record)

    url = svc.verify_url("http://192.168.0.12:8000", report_id)
    qr_png = svc.make_qr_png(url)
    pdf_bytes = build_report_pdf(record, qr_png)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    out_path = OUTPUT_DIR / f"{label}.pdf"
    out_path.write_bytes(pdf_bytes)
    print(f"{label}: {record.report_number}  total={record.total_cost_sar} SAR  "
          f"cost_source={record.cost_source}  -> {out_path}")
    return out_path


def main():
    store = InMemoryReportStore()

    # ---- v1 case: an old case, cost rule v2 never involved -----------------
    v1_data = ReportInput(
        accident_number="NAJM-2026-778812",
        user=_USER,
        vehicle=_VEHICLE,
        damages=[
            DamageItem(type="dent", part="front_bumper", severity="moderate", cost_sar=412.5),
            DamageItem(type="lamp", part="lamp", severity="severe", cost_sar=165.0),
        ],
        overall_severity="severe",
        # cost_source defaults to "v1"; total_cost_sar is sum(damages) as always.
    )
    _issue_and_render(v1_data, store, "v1_case_sample")

    # ---- v2 case: what routes/reports.py builds when displayCostSource=="v2"
    v2_data = ReportInput(
        accident_number="NAJM-2026-778900",
        user=_USER,
        vehicle=_VEHICLE,
        damages=[
            # "window" exercises the 2026-11-07 glass-identity fix's new Arabic
            # label (door_glass bucket's real identity, not "door").
            DamageItem(type="glass", part="window", severity="severe", cost_sar=375.0),
            DamageItem(type="dent", part="fender", severity="moderate", cost_sar=500.0),
        ],
        overall_severity="severe",
        total_cost_sar_override=875.0,  # engine's own hours*factor-then-rate total
        cost_source="v2",
        cost_rule_version="v2.0",
        cost_table="A_100",
        cost_rate_sar=100,
    )
    _issue_and_render(v2_data, store, "v2_case_sample")


if __name__ == "__main__":
    main()
