"""
backend_api/services/cost_v2/tests/test_golden.py — golden tests for cost rule v2.

Verifies engine.py matches spec/golden_cost_v2.json to the riyal. Per
spec/DECISION_cost_rule_v2.md section 5.1: "The production engine must match to the
riyal (cost_rule_v2_reference.py is the spec-by-code)." Fixtures are read-only here --
if a fixture disagrees with the spec/engine, that is reported, never edited.

Run: pytest backend_api/services/cost_v2/tests/test_golden.py -v
"""
import json
import os
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
COST_V2_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, COST_V2_DIR)

import pytest  # noqa: E402

from engine import estimate, CostV2Error  # noqa: E402
from tables import TABLES as PROD_TABLES  # noqa: E402

GOLDEN_PATH = os.path.join(COST_V2_DIR, "spec", "golden_cost_v2.json")
TOL = 0.01

with open(GOLDEN_PATH, encoding="utf-8") as f:
    GOLDEN = json.load(f)

CASES = GOLDEN["cases"]
BEHAVIOUR_TESTS = GOLDEN["behaviour_tests"]
FIXTURE_TABLES = GOLDEN["tables"]


def _severity_default(case, sev_tag):
    if sev_tag == "none":
        return None
    if sev_tag == "expert":
        return case["severity_expert"]
    if sev_tag == "model":
        return case["severity_model"]
    raise ValueError(f"Unknown severity tag in expected key: {sev_tag!r}")


def _expected_keys():
    """Flatten every (case, expected_key) pair into one parametrize id."""
    keys = []
    for case in CASES:
        for expected_key in case["expected"]:
            keys.append((case["case_id"], expected_key))
    return keys


CASE_BY_ID = {c["case_id"]: c for c in CASES}
EXPECTED_KEY_PAIRS = _expected_keys()


@pytest.mark.parametrize(
    "case_id,expected_key",
    EXPECTED_KEY_PAIRS,
    ids=[f"{cid}:{k}" for cid, k in EXPECTED_KEY_PAIRS],
)
def test_golden_case(case_id, expected_key):
    case = CASE_BY_ID[case_id]
    expected = case["expected"][expected_key]

    table, aggregation, sev_part = expected_key.split("|")
    assert sev_part.startswith("sev=")
    severity_default = _severity_default(case, sev_part[len("sev="):])

    result = estimate(
        case["detections"], table=table, aggregation=aggregation,
        severity_default=severity_default,
    )

    assert result["cost_sar"] == pytest.approx(expected["cost_sar"], abs=TOL), (
        f"{case_id} {expected_key}: cost_sar {result['cost_sar']} != {expected['cost_sar']}"
    )
    assert result["hours"] == pytest.approx(expected["hours"], abs=TOL), (
        f"{case_id} {expected_key}: hours {result['hours']} != {expected['hours']}"
    )
    assert result["weighted_hours"] == pytest.approx(expected["weighted_hours"], abs=TOL), (
        f"{case_id} {expected_key}: weighted_hours {result['weighted_hours']} != "
        f"{expected['weighted_hours']}"
    )
    assert len(result["lines"]) == expected["n_lines"], (
        f"{case_id} {expected_key}: n_lines {len(result['lines'])} != {expected['n_lines']}"
    )


@pytest.mark.parametrize(
    "behaviour_test",
    BEHAVIOUR_TESTS,
    ids=[bt["name"] for bt in BEHAVIOUR_TESTS],
)
def test_behaviour(behaviour_test):
    result = estimate(
        behaviour_test["detections"],
        table=behaviour_test["table"],
        aggregation=behaviour_test["aggregation"],
    )
    assert result["cost_sar"] == pytest.approx(
        behaviour_test["expected_cost_sar"], abs=TOL,
    ), (
        f"{behaviour_test['name']}: cost_sar {result['cost_sar']} != "
        f"{behaviour_test['expected_cost_sar']}"
    )


@pytest.mark.parametrize("table_name", list(FIXTURE_TABLES.keys()))
def test_tables_match_fixture(table_name):
    """Guards against typos: every table_key/damage/hours value in the fixture's own
    "tables" block must equal the production tables.py value exactly. Production tables
    may carry EXTRA keys (e.g. the provisional `rear_quarter`) not present in the
    fixture -- those are intentionally not checked here, see tables.py's docstring."""
    fixture_table = FIXTURE_TABLES[table_name]
    prod_table = PROD_TABLES[table_name]

    assert prod_table["rate"] == fixture_table["rate"], (
        f"{table_name}: rate {prod_table['rate']} != fixture {fixture_table['rate']}"
    )

    for table_key, damages in fixture_table["hours"].items():
        assert table_key in prod_table["hours"], (
            f"{table_name}: table_key {table_key!r} missing from production tables.py"
        )
        for damage, hours in damages.items():
            assert prod_table["hours"][table_key].get(damage) == hours, (
                f"{table_name}.{table_key}.{damage}: production "
                f"{prod_table['hours'][table_key].get(damage)} != fixture {hours}"
            )


def test_unknown_table_key_raises():
    with pytest.raises(CostV2Error):
        estimate([{"panel_id": "p", "table_key": "nope", "damage": "dent"}])


def test_unknown_damage_raises():
    with pytest.raises(CostV2Error):
        estimate([{"panel_id": "p", "table_key": "door", "damage": "nope"}])


def test_unknown_table_raises():
    with pytest.raises(CostV2Error):
        estimate(
            [{"panel_id": "p", "table_key": "door", "damage": "dent"}],
            table="nope",
        )


def test_unknown_aggregation_raises():
    with pytest.raises(CostV2Error):
        estimate(
            [{"panel_id": "p", "table_key": "door", "damage": "dent"}],
            aggregation="nope",
        )


# ---- "wheel" table_key (approved 2026-11-07, not in the golden fixture -- same status
# as "rear_quarter": a new production-only key, value-checked directly here) ----

@pytest.mark.parametrize("table,expected", [
    ("A_100", {"dent": 1, "scratch": 1, "crack": 1, "tire": 1}),
    ("B_130", {"dent": 1, "scratch": 1, "crack": 1, "tire": 1}),
    ("O_165", {"dent": 4.25, "scratch": 0.5, "crack": 1.5, "tire": 0.5}),
])
def test_wheel_table_key_values(table, expected):
    assert PROD_TABLES[table]["hours"]["wheel"] == expected


def test_wheel_table_key_does_not_modify_tire_key():
    """The wheel-panel row must be additive -- "tire" (tyre-flat) stays exactly as the
    fixture defines it."""
    for table in ("A_100", "B_130", "O_165"):
        fixture_tire = FIXTURE_TABLES[table]["hours"]["tire"]
        assert PROD_TABLES[table]["hours"]["tire"] == fixture_tire


def test_wheel_dent_prices_correctly_via_engine():
    result = estimate(
        [{"panel_id": "p", "table_key": "wheel", "damage": "dent"}], table="O_165",
    )
    assert result["cost_sar"] == pytest.approx(4.25 * 165, abs=0.01)
