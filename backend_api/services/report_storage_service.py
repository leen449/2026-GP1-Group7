from __future__ import annotations

from firebase_admin import storage


_BUCKET_NAME = "crashlens-233bf.firebasestorage.app"


def upload_report_pdf(
    case_id: str,
    report_id: str,
    pdf_bytes: bytes,
) -> tuple[str, str]:
    """
    Upload the finalized report PDF to Firebase Storage.

    Returns:
        pdf_path: path inside Firebase Storage
        pdf_url: public URL used to open the same PDF later
    """
    if not case_id or not case_id.strip():
        raise ValueError("case_id is required")

    if not report_id or not report_id.strip():
        raise ValueError("report_id is required")

    if not isinstance(pdf_bytes, (bytes, bytearray)) or not pdf_bytes:
        raise ValueError("pdf_bytes must contain a valid PDF")

    bucket = storage.bucket(_BUCKET_NAME)

    pdf_path = f"reports/{case_id}/{report_id}.pdf"
    blob = bucket.blob(pdf_path)

    blob.upload_from_string(
        bytes(pdf_bytes),
        content_type="application/pdf",
    )

    # Same approach already used by damage_detection.py.
    blob.make_public()

    return pdf_path, blob.public_url