"""
pytest for the verification feature. Runs with NO Firebase (in-memory store)
and NO deployment. From backend_api/:  pytest -q

Requires your existing deps plus: cryptography, jinja2  (pytest to run).
Make sure keys/ exists first (see VERIFICATION_SETUP.md step 1).
"""
from fastapi import FastAPI
from fastapi.testclient import TestClient
from routes.verify import router

app = FastAPI()
app.include_router(router)
client = TestClient(app)

SAMPLE = {
    "accident_number": "NAJM-2026-778812",
    "user": {"name": "Faisal Al-Otaibi", "national_id": "1093xxxxxx", "phone": "+9665xxxxxxx"},
    "vehicle": {"make": "Toyota", "model": "Camry", "color": "White",
                "year": 2019, "vin": "4T1BF1FK5CU511111"},
    "damages": [
        {"type": "flat tire", "severity": "moderate", "cost_sar": 1800},
        {"type": "dent", "severity": "severe", "cost_sar": 2200},
    ],
}


def test_issue_then_verify_ok():
    r = client.post("/verify/issue", json=SAMPLE).json()
    assert r["report_number"].startswith("CL-")
    page = client.get(f"/verify/{r['report_id']}")
    assert page.status_code == 200
    assert "Cryptographically verified" in page.text
    assert "NAJM-2026-778812" in page.text
    assert "4000 SAR" in page.text          # 1800 + 2200


def test_unknown_report_404():
    assert client.get("/verify/does-not-exist").status_code == 404


def test_tampered_record_fails_verification():
    from services.report_store import get_store
    r = client.post("/verify/issue", json=SAMPLE).json()
    rec = get_store().get(r["report_id"])
    rec.damages[0].cost_sar = 1              # tamper
    get_store().save(rec)
    page = client.get(f"/verify/{r['report_id']}")
    assert "Verification failed" in page.text
