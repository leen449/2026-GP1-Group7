"""
cost_calibration.py — post-hoc linear calibration of the case-level repair cost
(production).

The rule-engine total (hours x rate x severity x vehicle x paint factors, summed per
case) under-prices real cases on average. This is a linear correction fit against the
31 expert-priced real cases:

    calibrated = max(0, CALIBRATION_INTERCEPT + CALIBRATION_SLOPE * raw_total)

Fit result on the 31 cases: MAE ~284 SAR (vs ~450 SAR uncalibrated), ~65% of cases within
±30% of the expert figure (vs ~26% uncalibrated).

PILOT-CALIBRATED on 31 labor-only cases -- PROVISIONAL, like the severity thresholds in
severity_fusion_mask.py. Re-fit when more reference cases exist.

KNOWN LIMITATION (do not "fix" silently -- it is inherent to a linear fit with a positive
intercept): the intercept overshoots very-cheap cases. A case whose raw total is ~50 SAR
calibrates to ~610 SAR. This is why verification uses MAE and within-±% rather than MAPE,
which would be dominated by these small-denominator cases.

Applied at the CASE TOTAL only, never per line item -- see cost_estimation_services.py's
process_cost_estimation and _recalculate_admin_totals, the only two call sites.
"""

CALIBRATION_INTERCEPT = 575.3
CALIBRATION_SLOPE = 0.5037


def calibrate_total(raw_total: float) -> float:
    """raw_total: the rule engine's case-level total (sum of line items, severity
    factor already applied). Returns the calibrated case total, floored at 0."""
    return max(0.0, CALIBRATION_INTERCEPT + CALIBRATION_SLOPE * float(raw_total))
