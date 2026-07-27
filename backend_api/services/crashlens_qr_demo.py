"""
CrashLens - QR report-verification PROTOTYPE
=============================================

Goal of this demo:
  Prove, entirely on one machine with NO server deployed and NO PDF report yet,
  that we can:
    1. Generate our own signing keys (free, local, no external service).
    2. Take a finalized report's data and produce a QR code for it.
    3. Have a "workshop" scan that QR and confirm the report is:
         - genuinely issued by CrashLens (nobody can forge it), and
         - not tampered with (not a single number changed).

  This is the "signed / offline-verifiable" pattern (like the EU COVID pass).
  It needs no internet at scan time, which is why we can test it right now.

Only two building blocks are used:
  - cryptography  -> Ed25519 digital signatures (private key signs, public verifies)
  - opencv (cv2)  -> turn text into a QR image, and read a QR image back
"""

import json, base64, hashlib, uuid, datetime
import cv2
import numpy as np
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey, Ed25519PublicKey,
)
from cryptography.exceptions import InvalidSignature

def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode().rstrip("=")

def b64url_decode(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))

# ---------------------------------------------------------------------------
# STEP 1 - Generate CrashLens's signing keys.  This happens ONCE, ever.
#          No certificate authority, no paid service. One local call.
#          In production: private key lives as a secret on the backend,
#          public key is baked into whatever does the verifying.
# ---------------------------------------------------------------------------
private_key = Ed25519PrivateKey.generate()
public_key  = private_key.public_key()
print("STEP 1  Generated CrashLens key pair (local, free, no external service).")

# ---------------------------------------------------------------------------
# STEP 2 - A finalized report record.  NOTE: no PDF needs to exist. This is
#          just the data the admin approved. The 'pdf_sha256' is where the
#          hash of the real PDF would go once it's generated later.
# ---------------------------------------------------------------------------
report = {
    "id": str(uuid.uuid4()),                 # unguessable report id
    "plate": "RST 4821",
    "vehicle": "Toyota Camry 2019",
    "damages": [
        {"part": "front bumper", "severity": "moderate"},
        {"part": "left headlight", "severity": "severe"},
    ],
    "final_cost_sar": 4350,
    "issued": datetime.date.today().isoformat(),
    "pdf_sha256": "PENDING",                 # filled in once the PDF exists
}
print("STEP 2  Built a mock finalized report (no PDF/deployment needed).")

# ---------------------------------------------------------------------------
# STEP 3 - Sign the report and pack it into a compact token.
#          token = payload.signature  (both base64url)
# ---------------------------------------------------------------------------
payload_bytes = json.dumps(report, separators=(",", ":"), sort_keys=True).encode()
signature     = private_key.sign(payload_bytes)
token         = "CRASHLENS1." + b64url(payload_bytes) + "." + b64url(signature)
print(f"STEP 3  Signed the report. QR will carry {len(token)} characters.")

# ---------------------------------------------------------------------------
# STEP 4 - Turn the token into a QR image.  THIS is what gets printed on the
#          report later. We also show the 'lookup URL' the same id could use.
# ---------------------------------------------------------------------------
encoder = cv2.QRCodeEncoder_create()
qr_img  = encoder.encode(token)
qr_img  = cv2.resize(qr_img, (600, 600), interpolation=cv2.INTER_NEAREST)
cv2.imwrite("crashlens_report_qr.png", qr_img)
print("STEP 4  Wrote crashlens_report_qr.png")
print(f"        (Server-lookup equivalent would be: https://verify.crashlens.app/r/{report['id']})")

# ===========================================================================
#            ---- everything below is the WORKSHOP side ----
#   The workshop only has: the QR image + CrashLens's PUBLIC key. No internet.
# ===========================================================================
public_raw = public_key.public_bytes_raw()   # the public key the verifier ships with

def verify_qr(image_path: str):
    """Scan a QR image and check it was issued by CrashLens and untampered."""
    img = cv2.imread(image_path)
    detector = cv2.QRCodeDetector()
    scanned, _, _ = detector.detectAndDecode(img)
    if not scanned:
        return False, "Could not read any QR code.", None
    try:
        tag, p_b64, s_b64 = scanned.split(".")
        assert tag == "CRASHLENS1"
    except Exception:
        return False, "Not a CrashLens code.", None
    payload = b64url_decode(p_b64)
    sig     = b64url_decode(s_b64)
    try:
        Ed25519PublicKey.from_public_bytes(public_raw).verify(sig, payload)
    except InvalidSignature:
        return False, "INVALID - signature does not match. Forged or altered.", None
    return True, "AUTHENTIC - genuinely issued by CrashLens, unaltered.", json.loads(payload)

# ---------------------------------------------------------------------------
# STEP 5 - The normal, honest case: workshop scans the real QR.
# ---------------------------------------------------------------------------
print("\nSTEP 5  Workshop scans the genuine QR:")
ok, msg, data = verify_qr("crashlens_report_qr.png")
print("        Result:", msg)
if ok:
    print(f"        -> {data['vehicle']}  |  {data['final_cost_sar']} SAR  |  issued {data['issued']}")

# ---------------------------------------------------------------------------
# STEP 6 - TAMPER TEST: a dishonest user changes the cost inside the QR
#          (4350 -> 999) and re-generates a QR, WITHOUT the private key.
# ---------------------------------------------------------------------------
print("\nSTEP 6  Someone edits the cost to 999 SAR and makes a fake QR:")
forged = dict(report); forged["final_cost_sar"] = 999
forged_payload = json.dumps(forged, separators=(",", ":"), sort_keys=True).encode()
# they reuse the OLD signature because they can't create a valid new one:
forged_token = "CRASHLENS1." + b64url(forged_payload) + "." + b64url(signature)
cv2.imwrite("forged_qr.png",
            cv2.resize(encoder.encode(forged_token), (600, 600), interpolation=cv2.INTER_NEAREST))
ok, msg, data = verify_qr("forged_qr.png")
print("        Result:", msg)

print("\nDONE. The genuine QR verifies; the tampered one is rejected. No server, no PDF.")
