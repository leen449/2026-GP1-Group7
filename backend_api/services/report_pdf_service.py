from __future__ import annotations

import html
import pathlib

import fitz

from models.report import ReportRecord


_BASE_DIR = pathlib.Path(__file__).resolve().parent.parent
_LOGO_PATH = _BASE_DIR / "assets" / "report" / "logo.png"

_A4 = fitz.paper_rect("a4")
_PAGE_W = float(_A4.width)
_PAGE_H = float(_A4.height)

_INK = (0.08, 0.08, 0.08)
_LINE = (0.12, 0.12, 0.12)
_BAND_FILL = (0.94, 0.94, 0.94)
_BRAND = "#173d6b"

# Maximum number of damage rows on the first page while keeping
# the same approved row height and enough room for Total + QR/footer.
_FIRST_PAGE_MAX_DAMAGE_ROWS = 5

# Continuation pages keep the existing capacity.
_CONTINUATION_PAGE_DAMAGE_ROWS = 8

# Keep exactly the same approved damage-row height that was used
# when the table had four fixed rows.
_FIRST_PAGE_DAMAGE_ROW_H = (
    568.0 - (390.0 + 29.0)
) / 4


def _e(value: object) -> str:
    return html.escape("" if value is None else str(value))


def _money(value: object) -> str:
    if value is None:
        return "—"

    try:
        return f"{float(value):,.2f}"
    except (TypeError, ValueError):
        return _e(value)


def _draw_box(
    page: fitz.Page,
    rect: fitz.Rect,
    *,
    fill=None,
    width: float = 0.7,
) -> None:
    page.draw_rect(
        rect,
        color=_LINE,
        fill=fill,
        width=width,
        overlay=True,
    )


def _draw_line(
    page: fitz.Page,
    p1: tuple[float, float],
    p2: tuple[float, float],
    width: float = 0.7,
) -> None:
    page.draw_line(
        p1,
        p2,
        color=_LINE,
        width=width,
        overlay=True,
    )


def _html_box(
    page: fitz.Page,
    rect: fitz.Rect,
    body: str,
    *,
    rotate: int = 0,
    font_size: float = 8.1,
    bold: bool = False,
    color: str = "#111111",
    padding: float = 1.5,
    line_height: float = 1.16,
) -> None:
    weight = 700 if bold else 400

    markup = f"""
    <div class="cell">{body}</div>
    """

    css = f"""
      * {{ box-sizing: border-box; }}
      html, body {{ margin: 0; padding: 0; }}

      .cell {{
        width: 100%;
        height: 100%;

        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;

        text-align: center;
        padding: {padding}pt;
        color: {color};

        font-family: sans-serif;
        font-size: {font_size}pt;
        font-weight: {weight};
        line-height: {line_height};

        overflow: hidden;
      }}

      .ar {{
        direction: rtl;
        unicode-bidi: isolate;
        font-weight: 600;
      }}

      .en {{
        direction: ltr;
        unicode-bidi: isolate;
        font-weight: 600;
      }}

      .gap {{
        height: 3.2pt;
        min-height: 3.2pt;
      }}

      .value {{
        font-weight: 400;
      }}

      .strong {{
        font-weight: 700;
      }}
    """

    spare, scale = page.insert_htmlbox(
        rect,
        markup,
        css=css,
        rotate=rotate,
        scale_low=0.72,
        overlay=True,
    )

    if spare < -0.5:
        raise ValueError(
            f"Text does not fit in PDF cell {rect}; scale={scale}"
        )


def _bilingual(
    ar: str,
    en: str,
    *,
    strong: bool = False,
) -> str:
    cls = " strong" if strong else ""

    return (
        f'<div class="ar{cls}">{_e(ar)}</div>'
        '<div class="gap"></div>'
        f'<div class="en{cls}">{_e(en)}</div>'
    )


def _value(
    value: object,
    *,
    strong: bool = False,
) -> str:
    cls = "value strong" if strong else "value"
    return f'<div class="{cls}">{_e(value)}</div>'


def _insert_logo(page: fitz.Page) -> None:
    if not _LOGO_PATH.is_file():
        raise FileNotFoundError(
            f"CrashLens logo not found at {_LOGO_PATH}. "
            "Expected backend_api/assets/report/logo.png"
        )

    logo = fitz.Pixmap(str(_LOGO_PATH))

    max_w = 86.0
    max_h = 48.0

    ratio = min(
        max_w / logo.width,
        max_h / logo.height,
    )

    width = logo.width * ratio
    height = logo.height * ratio
    x1 = (_PAGE_W - width) / 2

    page.insert_image(
        fitz.Rect(
            x1,
            10,
            x1 + width,
            10 + height,
        ),
        filename=str(_LOGO_PATH),
        keep_proportion=True,
    )

    _html_box(
        page,
        fitz.Rect(210, 57, 385, 75),
        '<div class="strong">CrashLens</div>',
        font_size=14.5,
        bold=True,
        color=_BRAND,
        padding=0,
    )


def _draw_notices_and_qr(
    page: fitz.Page,
    qr_png: bytes,
    *,
    footer_line_y: float = 690.0,
    qr_y1: float = 714.0,
) -> None:
    left = 24.0
    right = _PAGE_W - 24.0

    _draw_line(
        page,
        (left, footer_line_y),
        (right, footer_line_y),
        width=0.8,
    )

    qr_size = 78.0
    qr_x1 = (_PAGE_W - qr_size) / 2

    # Dynamic bottom so the notices move together with the QR/footer
    # while remaining inside the A4 page.
    notice_bottom = min(
        qr_y1 + 92.0,
        _PAGE_H - 12.0,
    )

    page.insert_image(
        fitz.Rect(
            qr_x1,
            qr_y1,
            qr_x1 + qr_size,
            qr_y1 + qr_size,
        ),
        stream=bytes(qr_png),
        keep_proportion=True,
    )

    english_notice = (
        "The objection request shall be submitted within a period not exceeding "
        "(ten) working days from the date of receiving the final report, and the "
        "period shall start from the day following the date of receiving the final report."
    )

    arabic_notice = (
        "يقدم طلب الاعتراض خلال مدة لا تتجاوز (عشرة) أيام عمل من تاريخ استلام التقرير، "
        "وتبدأ المدة من اليوم التالي لتاريخ استلام التقرير."
    )

    _html_box(
        page,
        fitz.Rect(
            left,
            qr_y1 - 6,
            qr_x1 - 15,
            notice_bottom,
        ),
        (
            '<div class="value" '
            'style="text-align:left;align-self:stretch;line-height:1.55">'
            f"{_e(english_notice)}"
            "</div>"
        ),
        font_size=6.8,
        padding=2,
        line_height=1.48,
    )

    _html_box(
        page,
        fitz.Rect(
            qr_x1 + qr_size + 15,
            qr_y1 - 6,
            right,
            notice_bottom,
        ),
        (
            '<div class="ar value" '
            'style="text-align:right;align-self:stretch;line-height:1.75">'
            f"{_e(arabic_notice)}"
            "</div>"
        ),
        font_size=7.2,
        padding=2,
        line_height=1.55,
    )


def _draw_total_section(
    page: fitz.Page,
    record: ReportRecord,
    *,
    top: float,
    bottom: float,
    left: float,
    right: float,
    inner_x: float,
    outer_x: float,
    label_col_x: float,
) -> None:
    _draw_box(
        page,
        fitz.Rect(left, top, right, bottom),
    )

    _draw_line(
        page,
        (label_col_x, top),
        (label_col_x, bottom),
    )

    _draw_line(
        page,
        (inner_x, top),
        (inner_x, bottom),
    )

    _draw_line(
        page,
        (outer_x, top),
        (outer_x, bottom),
    )

    _draw_box(
        page,
        fitz.Rect(
            outer_x,
            top,
            right,
            bottom,
        ),
        fill=_BAND_FILL,
    )

    _html_box(
        page,
        fitz.Rect(
            outer_x,
            top,
            right,
            bottom,
        ),
        _bilingual(
            "معلومات التقدير",
            "Assessment Information",
            strong=True,
        ),
        rotate=90,
        font_size=7.4,
        bold=True,
        padding=2,
    )

    _html_box(
        page,
        fitz.Rect(
            label_col_x,
            top,
            inner_x,
            bottom,
        ),
        (
            '<div style="padding-top: 28pt;">'
            f'{_bilingual("إجمالي التكلفة التقديرية", "Total Estimated Cost (SAR)", strong=True)}'
            "</div>"
        ),
        font_size=8.0,
        bold=True,
        padding=4,
    )

    _html_box(
        page,
        fitz.Rect(
            left,
            top,
            label_col_x,
            bottom,
        ),
        (
            '<div style="padding-top: 35pt;">'
            f'{_value(_money(record.total_cost_sar), strong=True)}'
            "</div>"
        ),
        font_size=9.0,
        bold=True,
    )


def _draw_first_page(
    doc: fitz.Document,
    record: ReportRecord,
    qr_png: bytes,
    first_page_damages: list,
    has_continuation: bool,
) -> None:
    page = doc.new_page(
        width=_PAGE_W,
        height=_PAGE_H,
    )

    _insert_logo(page)

    left = 24.0
    right = _PAGE_W - 24.0

    # ── Top report information ──────────────────────────────────────────────
    top_y1 = 82.0
    top_y2 = 184.0

    title_x = 370.0
    label_x = 234.0
    top_row_h = (top_y2 - top_y1) / 3

    _draw_box(
        page,
        fitz.Rect(
            left,
            top_y1,
            right,
            top_y2,
        ),
    )

    _draw_line(
        page,
        (title_x, top_y1),
        (title_x, top_y2),
    )

    _draw_line(
        page,
        (label_x, top_y1),
        (label_x, top_y2),
    )

    for i in (1, 2):
        y = top_y1 + top_row_h * i

        _draw_line(
            page,
            (left, y),
            (title_x, y),
        )

    title = _bilingual(
        "تقرير تقييم الأضرار",
        "Damage Assessment Report",
        strong=True,
    )

    _html_box(
        page,
        fitz.Rect(
            title_x,
            top_y1 + 30,
            right,
            top_y2 - 30,
        ),
        title,
        font_size=12.0,
        bold=True,
        padding=5,
    )

    top_rows = [
        (
            "رقم التقرير",
            "Report No.",
            record.report_number,
        ),
        (
            "تاريخ التقرير",
            "Report Date",
            record.issued_at,
        ),
        (
            "رقم الحادث",
            "Accident No.",
            record.accident_number,
        ),
    ]

    for i, (ar, en, value) in enumerate(top_rows):
        y1 = top_y1 + top_row_h * i
        y2 = y1 + top_row_h

        _html_box(
            page,
            fitz.Rect(
                label_x,
                y1,
                title_x,
                y2,
            ),
            _bilingual(ar, en),
            font_size=7.6,
        )

        _html_box(
            page,
            fitz.Rect(
                left,
                y1,
                label_x,
                y2,
            ),
            f'<div style="padding-top: 9pt;">{_value(value)}</div>',
            font_size=8.1,
        )

    # ── Main integrated table ───────────────────────────────────────────────
    main_y1 = 196.0

    outer_x = right - 37.0
    inner_x = outer_x - 58.0
    label_col_x = 286.0

    owner_y2 = 274.0
    vehicle_y2 = 390.0

    # ── Dynamic damage section ──────────────────────────────────────────────
    # Keep the approved damage-table header height.
    header_h = 29.0

    visible_damage_rows = len(first_page_damages)

    # Defensive fallback only. Reports normally cannot be generated
    # without at least one damage.
    if visible_damage_rows < 1:
        visible_damage_rows = 1

    damage_y2 = (
        vehicle_y2
        + header_h
        + (_FIRST_PAGE_DAMAGE_ROW_H * visible_damage_rows)
    )

    # Keep exactly the same total-section height as the approved design:
    # 674 - 568 = 106 pt.
    total_section_h = 106.0
    full_main_y2 = damage_y2 + total_section_h

    main_y2 = (
        damage_y2
        if has_continuation
        else full_main_y2
    )

    _draw_box(
        page,
        fitz.Rect(
            left,
            main_y1,
            right,
            main_y2,
        ),
    )

    _draw_line(
        page,
        (outer_x, main_y1),
        (outer_x, main_y2),
    )

    _draw_line(
        page,
        (inner_x, main_y1),
        (inner_x, main_y2),
    )

    for y in (
        owner_y2,
        vehicle_y2,
        damage_y2,
    ):
        if y <= main_y2:
            _draw_line(
                page,
                (left, y),
                (right, y),
            )

    # Outer Vehicle Details band.
    _draw_box(
        page,
        fitz.Rect(
            outer_x,
            main_y1,
            right,
            damage_y2,
        ),
        fill=_BAND_FILL,
    )

    _html_box(
        page,
        fitz.Rect(
            outer_x,
            main_y1,
            right,
            damage_y2,
        ),
        _bilingual(
            "بيانات المركبة",
            "Vehicle Details",
            strong=True,
        ),
        rotate=90,
        font_size=8.0,
        bold=True,
        padding=3,
    )

    # Inner vertical bands.
    for y1, y2, ar, en in (
        (
            main_y1,
            owner_y2,
            "المالك",
            "Owner",
        ),
        (
            owner_y2,
            vehicle_y2,
            "بيانات المركبة",
            "Vehicle Info",
        ),
        (
            vehicle_y2,
            damage_y2,
            "معلومات الضرر",
            "Damage Info",
        ),
    ):
        _draw_box(
            page,
            fitz.Rect(
                inner_x,
                y1,
                outer_x,
                y2,
            ),
            fill=_BAND_FILL,
        )

        _html_box(
            page,
            fitz.Rect(
                inner_x,
                y1,
                outer_x,
                y2,
            ),
            (
                '<div style="padding-top: 9pt;">'
                f"{_bilingual(ar, en, strong=True)}"
                "</div>"
            ),
            rotate=90,
            font_size=7.8,
            bold=True,
            padding=2.5,
        )

    # Owner rows.
    owner_rows = [
        (
            "اسم مالك المركبة",
            "Vehicle Owner Name",
            record.user.name,
        ),
        (
            "رقم الهوية",
            "ID",
            record.user.national_id,
        ),
        (
            "رقم الجوال",
            "Mobile No.",
            record.user.phone,
        ),
    ]

    owner_h = (
        owner_y2 - main_y1
    ) / len(owner_rows)

    for i, (ar, en, value) in enumerate(owner_rows):
        y1 = main_y1 + owner_h * i
        y2 = y1 + owner_h

        if i:
            _draw_line(
                page,
                (left, y1),
                (inner_x, y1),
            )

        _draw_line(
            page,
            (label_col_x, y1),
            (label_col_x, y2),
        )

        _html_box(
            page,
            fitz.Rect(
                label_col_x,
                y1,
                inner_x,
                y2,
            ),
            _bilingual(ar, en),
            font_size=7.15,
        )

        _html_box(
            page,
            fitz.Rect(
                left,
                y1,
                label_col_x,
                y2,
            ),
            f'<div style="padding-top: 6pt;">{_value(value)}</div>',
            font_size=7.9,
        )

    # Vehicle rows. "الشاصي" is intentionally not used.
    vehicle_rows = [
        (
            "مصنع المركبة",
            "Vehicle Manufacturer",
            record.vehicle.make,
        ),
        (
            "الموديل",
            "Model",
            record.vehicle.model,
        ),
        (
            "اللون / السنة",
            "Color / Year",
            f"{record.vehicle.color} / {record.vehicle.year}",
        ),
        (
            "رقم الهيكل",
            "Chassis No. / VIN",
            record.vehicle.vin,
        ),
    ]

    vehicle_h = (
        vehicle_y2 - owner_y2
    ) / len(vehicle_rows)

    for i, (ar, en, value) in enumerate(vehicle_rows):
        y1 = owner_y2 + vehicle_h * i
        y2 = y1 + vehicle_h

        if i:
            _draw_line(
                page,
                (left, y1),
                (inner_x, y1),
            )

        _draw_line(
            page,
            (label_col_x, y1),
            (label_col_x, y2),
        )

        _html_box(
            page,
            fitz.Rect(
                label_col_x,
                y1,
                inner_x,
                y2,
            ),
            _bilingual(ar, en),
            font_size=7.05,
        )

        _html_box(
            page,
            fitz.Rect(
                left,
                y1,
                label_col_x,
                y2,
            ),
            f'<div style="padding-top: 6pt;">{_value(value)}</div>',
            font_size=7.8,
        )

    # ── Damage table ────────────────────────────────────────────────────────
    # The number of visible rows now matches the actual number of damages.
    damage_left = left
    damage_right = inner_x

    no_x = damage_left + 31.0
    type_x = damage_left + 144.0
    severity_x = label_col_x

    for x in (
        no_x,
        type_x,
        severity_x,
    ):
        _draw_line(
            page,
            (x, vehicle_y2),
            (x, damage_y2),
        )

    _draw_line(
        page,
        (
            damage_left,
            vehicle_y2 + header_h,
        ),
        (
            damage_right,
            vehicle_y2 + header_h,
        ),
    )

    _html_box(
        page,
        fitz.Rect(
            damage_left,
            vehicle_y2,
            no_x,
            vehicle_y2 + header_h,
        ),
        _value("#", strong=True),
        font_size=7.8,
        bold=True,
    )

    _html_box(
        page,
        fitz.Rect(
            no_x,
            vehicle_y2,
            type_x,
            vehicle_y2 + header_h,
        ),
        _bilingual(
            "نوع الضرر",
            "Damage Type",
            strong=True,
        ),
        font_size=7.0,
        bold=True,
    )

    _html_box(
        page,
        fitz.Rect(
            type_x,
            vehicle_y2,
            severity_x,
            vehicle_y2 + header_h,
        ),
        _bilingual(
            "شدة الضرر",
            "Severity",
            strong=True,
        ),
        font_size=7.0,
        bold=True,
    )

    _html_box(
        page,
        fitz.Rect(
            severity_x,
            vehicle_y2,
            damage_right,
            vehicle_y2 + header_h,
        ),
        _bilingual(
            "التكلفة (ريال)",
            "Cost (SAR)",
            strong=True,
        ),
        font_size=6.9,
        bold=True,
    )

    damage_row_h = _FIRST_PAGE_DAMAGE_ROW_H

    for i, damage in enumerate(first_page_damages):
        y1 = (
            vehicle_y2
            + header_h
            + damage_row_h * i
        )

        y2 = y1 + damage_row_h

        if i:
            _draw_line(
                page,
                (damage_left, y1),
                (damage_right, y1),
            )

        _html_box(
            page,
            fitz.Rect(
                damage_left,
                y1,
                no_x,
                y2,
            ),
            _value(i + 1),
            font_size=7.5,
        )

        type_value = damage.type
        severity_value = damage.severity
        cost_value = _money(
            damage.cost_sar
        )

        _html_box(
            page,
            fitz.Rect(
                no_x,
                y1,
                type_x,
                y2,
            ),
            (
                '<div style="padding-top: 10pt;">'
                f"{_value(type_value)}"
                "</div>"
            ),
            font_size=7.15,
        )

        _html_box(
            page,
            fitz.Rect(
                type_x,
                y1,
                severity_x,
                y2,
            ),
            (
                '<div style="padding-top: 10pt;">'
                f"{_value(severity_value)}"
                "</div>"
            ),
            font_size=7.15,
        )

        _html_box(
            page,
            fitz.Rect(
                severity_x,
                y1,
                damage_right,
                y2,
            ),
            (
                '<div style="padding-top: 10pt;">'
                f"{_value(cost_value)}"
                "</div>"
            ),
            font_size=7.15,
        )

    # If all damages fit on the first page, place the Total + QR/footer
    # immediately after the actual last damage row.
    if not has_continuation:
        _draw_total_section(
            page,
            record,
            top=damage_y2,
            bottom=full_main_y2,
            left=left,
            right=right,
            inner_x=inner_x,
            outer_x=outer_x,
            label_col_x=label_col_x,
        )

        footer_line_y = full_main_y2 + 16.0
        qr_y1 = footer_line_y + 24.0

        _draw_notices_and_qr(
            page,
            qr_png,
            footer_line_y=footer_line_y,
            qr_y1=qr_y1,
        )


def _draw_continuation_page(
    doc: fitz.Document,
    record: ReportRecord,
    qr_png: bytes,
    damages: list,
    *,
    start_number: int,
    is_last_page: bool,
) -> None:
    page = doc.new_page(
        width=_PAGE_W,
        height=_PAGE_H,
    )

    _insert_logo(page)

    left = 24.0
    right = _PAGE_W - 24.0

    outer_x = right - 37.0
    inner_x = outer_x - 58.0
    label_col_x = 286.0

    title_top = 86.0
    title_bottom = 122.0

    _draw_box(
        page,
        fitz.Rect(
            left,
            title_top,
            right,
            title_bottom,
        ),
        fill=_BAND_FILL,
    )

    _html_box(
        page,
        fitz.Rect(
            left,
            title_top + 4,
            right,
            title_bottom - 4,
        ),
        _bilingual(
            "تكملة معلومات الضرر",
            "Damage Information Continued",
            strong=True,
        ),
        font_size=10.0,
        bold=True,
        padding=2,
    )

    table_top = 138.0
    header_h = 32.0
    row_h = 42.0

    damage_left = left
    damage_right = inner_x

    no_x = damage_left + 31.0
    type_x = damage_left + 144.0
    severity_x = label_col_x

    table_bottom = (
        table_top
        + header_h
        + row_h * len(damages)
    )

    _draw_box(
        page,
        fitz.Rect(
            damage_left,
            table_top,
            damage_right,
            table_bottom,
        ),
    )

    _draw_box(
        page,
        fitz.Rect(
            inner_x,
            table_top,
            right,
            table_bottom,
        ),
        fill=_BAND_FILL,
    )

    _html_box(
        page,
        fitz.Rect(
            inner_x,
            table_top,
            right,
            table_bottom,
        ),
        (
            '<div style="padding-top: 9pt;">'
            f'{_bilingual("معلومات الضرر", "Damage Info", strong=True)}'
            "</div>"
        ),
        rotate=90,
        font_size=7.8,
        bold=True,
        padding=2.5,
    )

    for x in (
        no_x,
        type_x,
        severity_x,
    ):
        _draw_line(
            page,
            (x, table_top),
            (x, table_bottom),
        )

    _draw_line(
        page,
        (
            damage_left,
            table_top + header_h,
        ),
        (
            damage_right,
            table_top + header_h,
        ),
    )

    _html_box(
        page,
        fitz.Rect(
            damage_left,
            table_top,
            no_x,
            table_top + header_h,
        ),
        _value("#", strong=True),
        font_size=7.8,
        bold=True,
    )

    _html_box(
        page,
        fitz.Rect(
            no_x,
            table_top,
            type_x,
            table_top + header_h,
        ),
        _bilingual(
            "نوع الضرر",
            "Damage Type",
            strong=True,
        ),
        font_size=7.0,
        bold=True,
    )

    _html_box(
        page,
        fitz.Rect(
            type_x,
            table_top,
            severity_x,
            table_top + header_h,
        ),
        _bilingual(
            "شدة الضرر",
            "Severity",
            strong=True,
        ),
        font_size=7.0,
        bold=True,
    )

    _html_box(
        page,
        fitz.Rect(
            severity_x,
            table_top,
            damage_right,
            table_top + header_h,
        ),
        _bilingual(
            "التكلفة (ريال)",
            "Cost (SAR)",
            strong=True,
        ),
        font_size=6.9,
        bold=True,
    )

    for index, damage in enumerate(damages):
        y1 = (
            table_top
            + header_h
            + row_h * index
        )

        y2 = y1 + row_h

        if index:
            _draw_line(
                page,
                (damage_left, y1),
                (damage_right, y1),
            )

        _html_box(
            page,
            fitz.Rect(
                damage_left,
                y1,
                no_x,
                y2,
            ),
            _value(start_number + index),
            font_size=7.5,
        )

        _html_box(
            page,
            fitz.Rect(
                no_x,
                y1,
                type_x,
                y2,
            ),
            (
                '<div style="padding-top: 10pt;">'
                f"{_value(damage.type)}"
                "</div>"
            ),
            font_size=7.15,
        )

        _html_box(
            page,
            fitz.Rect(
                type_x,
                y1,
                severity_x,
                y2,
            ),
            (
                '<div style="padding-top: 10pt;">'
                f"{_value(damage.severity)}"
                "</div>"
            ),
            font_size=7.15,
        )

        _html_box(
            page,
            fitz.Rect(
                severity_x,
                y1,
                damage_right,
                y2,
            ),
            (
                '<div style="padding-top: 10pt;">'
                f"{_value(_money(damage.cost_sar))}"
                "</div>"
            ),
            font_size=7.15,
        )

    if is_last_page:
        total_top = table_bottom + 14.0
        total_bottom = total_top + 106.0

        _draw_total_section(
            page,
            record,
            top=total_top,
            bottom=total_bottom,
            left=left,
            right=right,
            inner_x=inner_x,
            outer_x=outer_x,
            label_col_x=label_col_x,
        )

        footer_line_y = total_bottom + 16.0
        qr_y1 = footer_line_y + 24.0

        _draw_notices_and_qr(
            page,
            qr_png,
            footer_line_y=footer_line_y,
            qr_y1=qr_y1,
        )


def build_report_pdf(
    record: ReportRecord,
    qr_png: bytes,
) -> bytes:
    """Build the finalized CrashLens assessment PDF.

    Behavior:
      * Up to 5 damages:
          one page with exactly the number of actual damage rows.
          No empty damage rows are added.

      * More than 5 damages:
          the first five damages remain on the first page;
          extra damages continue on one or more continuation pages;
          the total, QR, and objection notices appear only after the final
          damage row on the last page.

    The QR bytes must be the exact PNG returned by create_report().
    This function only renders the PDF; it does not create, sign, store,
    or hash report records.
    """
    if not isinstance(
        qr_png,
        (bytes, bytearray),
    ) or not qr_png:
        raise ValueError(
            "qr_png must contain the PNG bytes returned by create_report()"
        )

    damages = list(record.damages)

    first_page_damages = damages[
        :_FIRST_PAGE_MAX_DAMAGE_ROWS
    ]

    remaining_damages = damages[
        _FIRST_PAGE_MAX_DAMAGE_ROWS:
    ]

    doc = fitz.open()

    _draw_first_page(
        doc,
        record,
        qr_png,
        first_page_damages,
        has_continuation=bool(remaining_damages),
    )

    if remaining_damages:
        chunks = [
            remaining_damages[
                index:index + _CONTINUATION_PAGE_DAMAGE_ROWS
            ]
            for index in range(
                0,
                len(remaining_damages),
                _CONTINUATION_PAGE_DAMAGE_ROWS,
            )
        ]

        next_damage_number = (
            len(first_page_damages) + 1
        )

        for chunk_index, chunk in enumerate(chunks):
            is_last_page = (
                chunk_index == len(chunks) - 1
            )

            _draw_continuation_page(
                doc,
                record,
                qr_png,
                chunk,
                start_number=next_damage_number,
                is_last_page=is_last_page,
            )

            next_damage_number += len(chunk)

    pdf_bytes = doc.tobytes(
        garbage=4,
        deflate=True,
        clean=True,
    )

    doc.close()

    return pdf_bytes