#!/usr/bin/env python3
"""Generate reproducible synthetic datasets for the pharma analytics warehouse."""

from __future__ import annotations

import csv
import math
import random
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Iterable, Mapping

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"

SEED = 2026
PRESCRIBER_COUNT = 3_000
CALL_COUNT = 40_000
WEEK_COUNT = 52
FIRST_WEEK_ENDING = date(2025, 1, 3)

REGION_NAMES = [
    "North", "South", "East", "West", "Central"
]
SPECIALTIES = [
    "Cardiology", "Endocrinology", "Internal Medicine",
    "Neurology", "Oncology", "Primary Care"
]
CHANNELS = ["In-person", "Video", "Phone"]
OUTCOMES = ["Discussed product", "Follow-up required", "No response", "Sample requested"]

PRODUCTS = [
    {"product_id": 1, "product_name": "Product Alpha", "molecule": "Molecule A", "launch_date": "2020-01-01"},
    {"product_id": 2, "product_name": "Product Beta", "molecule": "Molecule B", "launch_date": "2020-01-01"},
    {"product_id": 3, "product_name": "Product Gamma", "molecule": "Molecule C", "launch_date": "2025-07-01"},
]


def write_csv(filename: str, fieldnames: list[str], rows: Iterable[Mapping[str, object]]) -> None:
    """Write dictionaries as UTF-8 CSV with a stable column order."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    destination = DATA_DIR / filename
    with destination.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {destination.relative_to(ROOT)}")


def as_iso(value: date | datetime) -> str:
    return value.isoformat(sep=" ") if isinstance(value, datetime) else value.isoformat()


def main() -> None:
    rng = random.Random(SEED)

    regions = [
        {"region_id": idx, "region_name": name}
        for idx, name in enumerate(REGION_NAMES, start=1)
    ]

    reps = []
    for rep_id in range(1, 61):
        region_id = (rep_id - 1) // 12 + 1
        hire_date = date(2019, 1, 1) + timedelta(days=rng.randrange(0, 2_190))
        reps.append({
            "rep_id": rep_id,
            "rep_name": f"Representative {rep_id:03d}",
            "region_id": region_id,
            "hire_date": hire_date.isoformat(),
        })

    territories = []
    for territory_id in range(1, 181):
        rep_id = (territory_id - 1) // 3 + 1
        region_id = (rep_id - 1) // 12 + 1
        territories.append({
            "territory_id": territory_id,
            "territory_name": f"Territory {territory_id:03d}",
            "region_id": region_id,
            "rep_id": rep_id,
        })

    territory_ids = [row["territory_id"] for row in territories]
    prescribers = []
    prescriber_territory: dict[str, int] = {}
    prescriber_base: dict[str, float] = {}
    for idx in range(1, PRESCRIBER_COUNT + 1):
        npi = f"{1000000000 + idx:010d}"
        territory_id = rng.choice(territory_ids)
        first_seen = date(2024, 1, 1) + timedelta(days=rng.randrange(0, 730))
        prescribers.append({
            "npi": npi,
            "specialty": rng.choice(SPECIALTIES),
            "territory_id": territory_id,
            "first_seen_date": first_seen.isoformat(),
        })
        prescriber_territory[npi] = territory_id
        # A log-normal distribution produces a realistic long-tail volume shape.
        prescriber_base[npi] = max(2.0, rng.lognormvariate(3.1, 0.65))

    weeks = [
        FIRST_WEEK_ENDING + timedelta(days=7 * offset)
        for offset in range(WEEK_COUNT)
    ]

    prescriptions = []
    for prescriber in prescribers:
        npi = str(prescriber["npi"])
        base = prescriber_base[npi]
        for product in PRODUCTS:
            product_id = int(product["product_id"])
            launch_date = date.fromisoformat(str(product["launch_date"]))
            product_factor = {1: 1.0, 2: 0.72, 3: 0.58}[product_id]
            for week_index, week_ending in enumerate(weeks):
                if week_ending < launch_date:
                    nrx = 0
                    trx = 0
                else:
                    seasonal = 1.0 + 0.12 * math.sin(2 * math.pi * week_index / WEEK_COUNT)
                    gradual_trend = 0.96 + 0.10 * week_index / WEEK_COUNT
                    expected = max(0.5, base * product_factor * seasonal * gradual_trend / 4.0)
                    nrx = max(0, int(rng.gauss(expected, max(0.8, math.sqrt(expected)))))
                    trx = max(nrx, int(nrx * rng.uniform(1.15, 1.75)))
                prescriptions.append({
                    "npi": npi,
                    "product_id": product_id,
                    "week_ending": week_ending.isoformat(),
                    "trx": trx,
                    "nrx": nrx,
                })

    rep_by_territory = {
        int(row["territory_id"]): int(row["rep_id"])
        for row in territories
    }
    calls = []
    first_day = date(2025, 1, 1)
    for call_id in range(1, CALL_COUNT + 1):
        prescriber = rng.choice(prescribers)
        npi = str(prescriber["npi"])
        territory_id = prescriber_territory[npi]
        rep_id = rep_by_territory[territory_id]
        call_day = first_day + timedelta(days=rng.randrange(365))
        call_time = datetime(
            call_day.year, call_day.month, call_day.day,
            rng.randrange(8, 18), rng.choice([0, 15, 30, 45])
        )
        calls.append({
            "call_id": call_id,
            "npi": npi,
            "rep_id": rep_id,
            "call_datetime": as_iso(call_time),
            "channel": rng.choice(CHANNELS),
            "outcome": rng.choice(OUTCOMES),
        })

    quarterly_targets = []
    quarter_starts = [
        date(2025, 1, 1), date(2025, 4, 1),
        date(2025, 7, 1), date(2025, 10, 1),
    ]
    for prescriber in prescribers:
        npi = str(prescriber["npi"])
        base = prescriber_base[npi]
        for product in PRODUCTS:
            product_id = int(product["product_id"])
            product_factor = {1: 1.0, 2: 0.72, 3: 0.58}[product_id]
            for quarter_start in quarter_starts:
                target_trx = max(1, int(base * product_factor * 13 * rng.uniform(0.8, 1.25)))
                quarterly_targets.append({
                    "npi": npi,
                    "product_id": product_id,
                    "quarter_start": quarter_start.isoformat(),
                    "target_trx": target_trx,
                    "target_nrx": int(target_trx * 0.18),
                })

    write_csv("regions.csv", ["region_id", "region_name"], regions)
    write_csv("reps.csv", ["rep_id", "rep_name", "region_id", "hire_date"], reps)
    write_csv("territories.csv", ["territory_id", "territory_name", "region_id", "rep_id"], territories)
    write_csv("products.csv", ["product_id", "product_name", "molecule", "launch_date"], PRODUCTS)
    write_csv("prescribers.csv", ["npi", "specialty", "territory_id", "first_seen_date"], prescribers)
    write_csv("prescriptions.csv", ["npi", "product_id", "week_ending", "trx", "nrx"], prescriptions)
    write_csv("calls.csv", ["call_id", "npi", "rep_id", "call_datetime", "channel", "outcome"], calls)
    write_csv(
        "quarterly_targets.csv",
        ["npi", "product_id", "quarter_start", "target_trx", "target_nrx"],
        quarterly_targets,
    )

    print(f"Generated {len(prescriptions):,} prescription rows, {len(calls):,} calls, "
          f"and {len(quarterly_targets):,} quarterly targets.")
    print("All records are synthetic; do not interpret call associations as causal effects.")


if __name__ == "__main__":
    main()
