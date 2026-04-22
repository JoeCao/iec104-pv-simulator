#!/usr/bin/env python3
"""
Generate thing model JSON from sim_rules.csv.

Output format:
{
  "actions": [],
  "events": [],
  "properties": [...]
}
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path
from typing import Any


def _parse_number(value: str) -> float | None:
    if value is None:
        return None
    text = value.strip()
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def _infer_unit(name: str, identifier: str) -> str:
    key = f"{name} {identifier}".lower()
    mapping = [
        (("电压", "_voltage", "volt"), "V"),
        (("电流", "_current", "amp"), "A"),
        (("功率因数", "power_factor"), ""),
        (("功率", "_power"), "kW"),
        (("频率", "frequency"), "Hz"),
        (("温度", "_temp", "_temperature"), "℃"),
        (("湿度", "humidity", "moisture"), "%"),
        (("辐照", "irradiance"), "W/m²"),
        (("风速", "wind_speed"), "m/s"),
        (("风向", "wind_direction"), "°"),
        (("电量", "energy"), "kWh"),
    ]
    for keywords, unit in mapping:
        if any(word in key for word in keywords):
            return unit
    return ""


def _data_type_from_row(row: dict[str, str]) -> dict[str, Any]:
    value_type = (row.get("type") or "").strip().upper()
    if value_type == "BIT":
        return {"type": "bool", "specs": {}}

    specs: dict[str, Any] = {}
    min_value = _parse_number(row.get("min", ""))
    max_value = _parse_number(row.get("max", ""))
    if min_value is not None:
        specs["min"] = min_value
    if max_value is not None:
        specs["max"] = max_value

    unit = _infer_unit(row.get("name", ""), row.get("identity", ""))
    if unit:
        specs["unit"] = unit

    return {"type": "float", "specs": specs}


def _access_mode_from_attribute(attribute: str) -> str:
    attr = (attribute or "").strip().lower()
    if attr == "write":
        return "READ_WRITE"
    return "READ"


def _address_sort_key(address: str) -> tuple[int, int, str]:
    parts = (address or "").split("!")
    if len(parts) != 3:
        return (10**9, 10**9, "")
    ca_text, type_id, ioa_text = parts
    try:
        ca = int(ca_text)
    except ValueError:
        ca = 10**9
    try:
        ioa = int(ioa_text)
    except ValueError:
        ioa = 10**9
    return (ca, ioa, type_id)


INV_PREFIX_RE = re.compile(r"^INV(\d{3,})_")


def _is_inverter_identity_in_scope(identity: str, max_inverters: int | None) -> bool:
    if max_inverters is None:
        return True

    match = INV_PREFIX_RE.match(identity)
    if not match:
        # Keep non-inverter points as common points.
        return True

    inverter_no = int(match.group(1))
    return inverter_no <= max_inverters


def generate_thing_model(input_csv: Path, max_inverters: int | None = None) -> dict[str, Any]:
    if not input_csv.exists():
        raise FileNotFoundError(f"input csv not found: {input_csv}")

    properties: list[dict[str, Any]] = []
    identity_seen: set[str] = set()

    with input_csv.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    rows.sort(key=lambda row: _address_sort_key(row.get("address", "")))

    for row in rows:
        enabled = (row.get("enabled") or "1").strip()
        if enabled == "0":
            continue

        identity = (row.get("identity") or "").strip()
        if not identity or identity in identity_seen:
            continue
        if not _is_inverter_identity_in_scope(identity, max_inverters):
            continue
        identity_seen.add(identity)

        prop = {
            "access_mode": _access_mode_from_attribute(row.get("attribute", "")),
            "data_type": _data_type_from_row(row),
            "desc": (row.get("description") or "").strip(),
            "identifier": identity,
            "name": (row.get("name") or identity).strip(),
        }
        properties.append(prop)

    return {
        "actions": [],
        "events": [],
        "properties": properties,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate thing model JSON from sim_rules.csv")
    parser.add_argument("--input", default="config/sim_rules.csv", help="Input CSV path")
    parser.add_argument(
        "--output",
        default="scripts/sim_rules_thing_model.json",
        help="Output JSON path",
    )
    parser.add_argument(
        "--max-inverters",
        type=int,
        default=None,
        help="Keep inverter points up to INVxxx (e.g. 3 keeps INV001~INV003). Non-INV points are kept.",
    )
    args = parser.parse_args()

    input_csv = Path(args.input)
    output_json = Path(args.output)
    thing_model = generate_thing_model(input_csv, max_inverters=args.max_inverters)

    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(
        json.dumps(thing_model, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print(f"generated: {output_json}")
    print(f"properties: {len(thing_model['properties'])}")


if __name__ == "__main__":
    main()
