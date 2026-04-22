#!/usr/bin/env python3
"""
Export zdaq IEC104 import xlsx from sim_rules.csv.

Only the first 11 compatible columns are exported:
group, interval, name, address, attribute, type, description, decimal, precision, bias, identity
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

from openpyxl import Workbook


ZDAQ_COLUMNS = [
    "group",
    "interval",
    "name",
    "address",
    "attribute",
    "type",
    "description",
    "decimal",
    "precision",
    "bias",
    "identity",
]


def export_xlsx(input_csv: Path, output_xlsx: Path, sheet_name: str = "IEC104-tags") -> int:
    if not input_csv.exists():
        raise FileNotFoundError(f"input csv not found: {input_csv}")

    wb = Workbook()
    ws = wb.active
    ws.title = sheet_name
    ws.append(ZDAQ_COLUMNS)

    row_count = 0
    with input_csv.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            ws.append([row.get(col, "") for col in ZDAQ_COLUMNS])
            row_count += 1

    output_xlsx.parent.mkdir(parents=True, exist_ok=True)
    wb.save(output_xlsx)
    return row_count


def main() -> None:
    parser = argparse.ArgumentParser(description="Export zdaq import xlsx from sim_rules.csv")
    parser.add_argument("--input", default="config/sim_rules.csv", help="input sim rules csv path")
    parser.add_argument("--output", default="scripts/IEC104-tags.generated.xlsx", help="output xlsx path")
    args = parser.parse_args()

    count = export_xlsx(Path(args.input), Path(args.output))
    print(f"generated: {args.output}")
    print(f"rows: {count}")


if __name__ == "__main__":
    main()
