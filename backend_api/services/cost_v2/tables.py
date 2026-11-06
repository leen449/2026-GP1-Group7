"""
backend_api/services/cost_v2/tables.py — versioned hours/rate config for cost rule v2.

STANDALONE / OFFLINE ONLY (see spec/DECISION_cost_rule_v2.md). Not imported by
cost_estimation_services.py, not wired into Firestore, the admin view, or the app.

Three assessor tables (D2/D9 of the decision record):
  A_100 (rate 100, DEFAULT/deployed) -- matches the Tagdeer workbook labels best (MAE 125).
  B_130 (rate 130) -- kept for sensitivity runs.
  O_165 (rate 165) -- the original/current in-app table -- kept for sensitivity runs.

Every table carries the fixture's own `_R`/`_L` rear-quarter and door keys unchanged (the
golden tests check production tables equal the fixture tables key-for-key) PLUS one extra
production-only key, `rear_quarter`, used because the current part-segmentation model has
no left/right signal (see DECISION doc, open item O1/O2). `rear_quarter` is NOT in the
fixture and is therefore not covered by golden-test parity -- it is new, documented here.
"""

VERSION = "cost_rule_v2-draft-2026-11-06"

SEV_F = {"minor": 0.85, "moderate": 1.0, "severe": 1.25}
SEV_ORDER = {"minor": 0, "moderate": 1, "severe": 2}

TABLES = {
    "A_100": {
        "rate": 100,
        "hours": {
            "front_bumper": {"dent": 7, "scratch": 5, "crack": 7},
            "back_bumper": {"dent": 5, "scratch": 4, "crack": 7},
            "hood": {"dent": 5, "scratch": 5},
            "front_fender": {"dent": 5, "scratch": 5, "crack": 7, "lamp": 1},
            "door": {"dent": 7, "scratch": 5, "crack": 7, "glass": 3},
            "door_L": {"dent": 7, "scratch": 5, "crack": 7, "glass": 2},
            "door_R": {"dent": 7, "scratch": 5, "crack": 7, "glass": 3},
            "rear_quarter_R": {"dent": 8, "scratch": 6, "crack": 25, "lamp": 1},
            "rear_quarter_L": {"dent": 7, "scratch": 5, "crack": 25, "lamp": 1},
            # PROVISIONAL -- team to confirm (R 8/6, L 7/5, or average). Average of R and L
            # used here so production has *a* value until O1/O2 (part-model side split) land.
            "rear_quarter": {"dent": 7.5, "scratch": 5.5, "crack": 25, "lamp": 1},
            "trunk": {"dent": 7, "scratch": 5, "glass": 1},
            "roof": {"dent": 10, "scratch": 7, "crack": 25},
            "sill": {"dent": 8, "scratch": 5, "crack": 25},
            "lamp": {"lamp": 1},
            "glass": {"glass": 3},
            "tire": {"tire": 1},
            # Wheel-panel dent/scratch/crack (distinct from tyre-flat, which stays on
            # "tire" above) -- new production-only key, approved 2026-11-07. Does not
            # modify "tire" (the golden fixture parity test checks that key verbatim).
            "wheel": {"dent": 1, "scratch": 1, "crack": 1, "tire": 1},
        },
    },
    "B_130": {
        "rate": 130,
        "hours": {
            "front_bumper": {"dent": 5, "scratch": 3, "crack": 5},
            "back_bumper": {"dent": 5, "scratch": 3, "crack": 5},
            "hood": {"dent": 5, "scratch": 3},
            "front_fender": {"dent": 4, "scratch": 3, "crack": 5, "lamp": 1},
            "door": {"dent": 3, "scratch": 2, "crack": 5, "glass": 2},
            "door_L": {"dent": 3, "scratch": 2, "crack": 5, "glass": 2},
            "door_R": {"dent": 3, "scratch": 2, "crack": 5, "glass": 2},
            "rear_quarter_R": {"dent": 5, "scratch": 4, "crack": 25, "lamp": 1},
            "rear_quarter_L": {"dent": 5, "scratch": 4, "crack": 25, "lamp": 1},
            # Both sides already equal in B -- no averaging needed, not provisional.
            "rear_quarter": {"dent": 5, "scratch": 4, "crack": 25, "lamp": 1},
            "trunk": {"dent": 4, "scratch": 3, "glass": 3},
            "roof": {"dent": 6, "scratch": 5, "crack": 30},
            "sill": {"dent": 5, "scratch": 3, "crack": 8},
            "lamp": {"lamp": 1},
            "glass": {"glass": 3},
            "tire": {"tire": 1},
            "wheel": {"dent": 1, "scratch": 1, "crack": 1, "tire": 1},
        },
    },
    "O_165": {
        "rate": 165,
        "hours": {
            "front_bumper": {"dent": 2.5, "scratch": 1.5, "crack": 2},
            "back_bumper": {"dent": 2.5, "scratch": 1.5, "crack": 1},
            "hood": {"dent": 3, "scratch": 1.5},
            "front_fender": {"dent": 2, "scratch": 1.2, "crack": 2.2, "lamp": 0.5},
            "door": {"dent": 3, "scratch": 1.5, "crack": 2.5, "glass": 0.8},
            "door_L": {"dent": 3, "scratch": 1.5, "crack": 2.5, "glass": 0.8},
            "door_R": {"dent": 3, "scratch": 1.5, "crack": 2.5, "glass": 0.8},
            "rear_quarter_R": {"dent": 2, "scratch": 1.2, "crack": 2.2, "lamp": 0.5},
            "rear_quarter_L": {"dent": 2, "scratch": 1.2, "crack": 2.2, "lamp": 0.5},
            # Both sides already equal in O -- no averaging needed, not provisional.
            "rear_quarter": {"dent": 2, "scratch": 1.2, "crack": 2.2, "lamp": 0.5},
            "trunk": {"dent": 2.5, "scratch": 1.5, "glass": 1},
            "roof": {"dent": 4, "scratch": 2},
            "sill": {"dent": 1.5, "scratch": 1},
            "lamp": {"lamp": 0.5},
            "glass": {"glass": 2},
            "tire": {"tire": 0.5},
            # dent value PROVISIONAL -- average of front (4.5h) / rear (4.0h), since the
            # current part model has no front/back wheel signal. scratch/crack/tire are
            # the agreed flat values (not averaged -- they don't vary by position today).
            "wheel": {"dent": 4.25, "scratch": 0.5, "crack": 1.5, "tire": 0.5},
        },
    },
}
