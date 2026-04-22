#!/usr/bin/env python3
"""
Generate sim-rules CSV based on docs/SIM_RULES_SPEC.md.

Default output:
- 300 inverters
- 30 points per inverter
- fill to 10,000 total points with plant-level metrics
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path
from typing import Dict, List


HEADERS = [
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
    "sim_class",
    "min",
    "max",
    "noise",
    "deadband",
    "update_ms",
    "formula",
    "depends_on",
    "init_value",
    "control_ref",
    "enabled",
]


def base_row() -> Dict[str, str]:
    return {
        "group": "IEC104",
        "interval": "1000",
        "name": "",
        "address": "",
        "attribute": "Read",
        "type": "FLOAT",
        "description": "",
        "decimal": "0",
        "precision": "2",
        "bias": "0",
        "identity": "",
        "sim_class": "random_walk",
        "min": "",
        "max": "",
        "noise": "0",
        "deadband": "1.0",
        "update_ms": "1000",
        "formula": "",
        "depends_on": "",
        "init_value": "0",
        "control_ref": "",
        "enabled": "1",
    }


def inverter_templates() -> List[Dict[str, str]]:
    return [
        {"suffix": "DC_Voltage", "name": "直流电压", "iec_type": "M_ME_NC", "sim_class": "solar_scaled", "min": "600", "max": "850", "noise": "10"},
        {"suffix": "DC_Current", "name": "直流电流", "iec_type": "M_ME_NC", "sim_class": "solar_scaled", "min": "0", "max": "60", "noise": "2"},
        {"suffix": "DC_Power", "name": "直流功率", "iec_type": "M_ME_NC", "sim_class": "derived_formula", "formula": "{prefix}_DC_Voltage*{prefix}_DC_Current/1000", "depends_on": "{prefix}_DC_Voltage;{prefix}_DC_Current"},
        {"suffix": "AC_Voltage_A", "name": "A相电压", "iec_type": "M_ME_NC", "sim_class": "random_walk", "min": "380", "max": "420", "noise": "3"},
        {"suffix": "AC_Voltage_B", "name": "B相电压", "iec_type": "M_ME_NC", "sim_class": "random_walk", "min": "380", "max": "420", "noise": "3"},
        {"suffix": "AC_Voltage_C", "name": "C相电压", "iec_type": "M_ME_NC", "sim_class": "random_walk", "min": "380", "max": "420", "noise": "3"},
        {"suffix": "AC_Current_A", "name": "A相电流", "iec_type": "M_ME_NC", "sim_class": "solar_scaled", "min": "0", "max": "50", "noise": "2"},
        {"suffix": "AC_Current_B", "name": "B相电流", "iec_type": "M_ME_NC", "sim_class": "solar_scaled", "min": "0", "max": "50", "noise": "2"},
        {"suffix": "AC_Current_C", "name": "C相电流", "iec_type": "M_ME_NC", "sim_class": "solar_scaled", "min": "0", "max": "50", "noise": "2"},
        {"suffix": "AC_Power", "name": "交流有功功率", "iec_type": "M_ME_NC", "sim_class": "derived_formula", "formula": "{prefix}_DC_Power*0.97", "depends_on": "{prefix}_DC_Power"},
        {"suffix": "Reactive_Power", "name": "无功功率", "iec_type": "M_ME_NC", "sim_class": "random_walk", "min": "-10", "max": "10", "noise": "1"},
        {"suffix": "Power_Factor", "name": "功率因数", "iec_type": "M_ME_NC", "sim_class": "random_walk", "min": "0.9", "max": "1.0", "noise": "0.01"},
        {"suffix": "Frequency", "name": "频率", "iec_type": "M_ME_NC", "sim_class": "random_walk", "min": "49.8", "max": "50.2", "noise": "0.03"},
        {"suffix": "Heatsink_Temp", "name": "散热器温度", "iec_type": "M_ME_NC", "sim_class": "solar_scaled", "min": "20", "max": "95", "noise": "2"},
        {"suffix": "Cabinet_Temp", "name": "机柜温度", "iec_type": "M_ME_NC", "sim_class": "random_walk", "min": "10", "max": "70", "noise": "1"},
        {"suffix": "Module_Temp", "name": "组件温度", "iec_type": "M_ME_NC", "sim_class": "solar_scaled", "min": "15", "max": "85", "noise": "3"},
        {"suffix": "Insulation_Resistance", "name": "绝缘电阻", "iec_type": "M_ME_NC", "sim_class": "random_walk", "min": "0.5", "max": "5.0", "noise": "0.1"},
        {"suffix": "Efficiency", "name": "转换效率", "iec_type": "M_ME_NC", "sim_class": "random_walk", "min": "92.0", "max": "99.5", "noise": "0.2"},
        {"suffix": "Daily_Energy", "name": "日发电量", "iec_type": "M_ME_NC", "sim_class": "counter", "init_value": "0", "noise": "0.2"},
        {"suffix": "Total_Energy", "name": "总发电量", "iec_type": "M_ME_NC", "sim_class": "counter", "init_value": "10000", "noise": "0.2"},
        {"suffix": "String_01_Current", "name": "组串01电流", "iec_type": "M_ME_NC", "sim_class": "solar_scaled", "min": "0", "max": "12", "noise": "0.5"},
        {"suffix": "String_02_Current", "name": "组串02电流", "iec_type": "M_ME_NC", "sim_class": "solar_scaled", "min": "0", "max": "12", "noise": "0.5"},
        {"suffix": "String_03_Current", "name": "组串03电流", "iec_type": "M_ME_NC", "sim_class": "solar_scaled", "min": "0", "max": "12", "noise": "0.5"},
        {"suffix": "String_04_Current", "name": "组串04电流", "iec_type": "M_ME_NC", "sim_class": "solar_scaled", "min": "0", "max": "12", "noise": "0.5"},
        {"suffix": "String_05_Current", "name": "组串05电流", "iec_type": "M_ME_NC", "sim_class": "solar_scaled", "min": "0", "max": "12", "noise": "0.5"},
        {"suffix": "String_06_Current", "name": "组串06电流", "iec_type": "M_ME_NC", "sim_class": "solar_scaled", "min": "0", "max": "12", "noise": "0.5"},
        {"suffix": "String_07_Current", "name": "组串07电流", "iec_type": "M_ME_NC", "sim_class": "solar_scaled", "min": "0", "max": "12", "noise": "0.5"},
        {"suffix": "String_08_Current", "name": "组串08电流", "iec_type": "M_ME_NC", "sim_class": "solar_scaled", "min": "0", "max": "12", "noise": "0.5"},
        {"suffix": "Status", "name": "运行状态", "iec_type": "M_SP_NA", "type": "BIT", "sim_class": "status_from_control", "deadband": "0", "precision": "0", "control_ref": "{prefix}_Control", "init_value": "1"},
        {"suffix": "Control", "name": "启停控制", "iec_type": "C_SC_NA", "attribute": "Write", "type": "BIT", "sim_class": "fixed", "deadband": "0", "precision": "0", "init_value": "1"},
    ]


def build_inverter_rows(inverter_count: int, ca: int, ioa_start: int) -> List[Dict[str, str]]:
    rows: List[Dict[str, str]] = []
    ioa = ioa_start
    templates = inverter_templates()

    for inv in range(1, inverter_count + 1):
        prefix = f"INV{inv:03d}"
        for tpl in templates:
            row = base_row()
            row["name"] = f"逆变器{inv}{tpl['name']}"
            row["description"] = row["name"]
            row["identity"] = f"{prefix}_{tpl['suffix']}"
            row["address"] = f"{ca}!{tpl['iec_type']}!{ioa}"
            ioa += 1

            row["sim_class"] = tpl.get("sim_class", row["sim_class"])
            row["attribute"] = tpl.get("attribute", row["attribute"])
            row["type"] = tpl.get("type", row["type"])
            row["min"] = tpl.get("min", "")
            row["max"] = tpl.get("max", "")
            row["noise"] = tpl.get("noise", row["noise"])
            row["deadband"] = tpl.get("deadband", row["deadband"])
            row["precision"] = tpl.get("precision", row["precision"])
            row["init_value"] = tpl.get("init_value", row["init_value"])

            formula = tpl.get("formula", "")
            depends_on = tpl.get("depends_on", "")
            control_ref = tpl.get("control_ref", "")
            if formula:
                row["formula"] = formula.format(prefix=prefix)
            if depends_on:
                row["depends_on"] = depends_on.format(prefix=prefix)
            if control_ref:
                row["control_ref"] = control_ref.format(prefix=prefix)

            rows.append(row)

    return rows


def build_plant_rows(target_count: int, existing_count: int, ca: int, ioa_start: int) -> List[Dict[str, str]]:
    rows: List[Dict[str, str]] = []
    ioa = ioa_start
    idx = 1

    while existing_count + len(rows) < target_count:
        row = base_row()
        row["name"] = f"电站辅助测点{idx:04d}"
        row["description"] = row["name"]
        row["identity"] = f"PLANT_AUX_{idx:04d}"
        row["address"] = f"{ca}!M_ME_NC!{ioa}"
        row["sim_class"] = "random_walk"
        row["min"] = "0"
        row["max"] = "10000"
        row["noise"] = "20"
        row["deadband"] = "5.0"
        row["update_ms"] = "1000"
        rows.append(row)
        ioa += 1
        idx += 1

    return rows


def write_csv(path: Path, rows: List[Dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=HEADERS)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate sim-rules CSV")
    parser.add_argument("--output", default="config/sim_rules.csv", help="Output CSV path")
    parser.add_argument("--target-points", type=int, default=10000, help="Target total points")
    parser.add_argument("--inverters", type=int, default=300, help="Inverter count")
    parser.add_argument("--ca", type=int, default=1, help="Common address in IEC104 address field")
    args = parser.parse_args()

    if args.target_points <= 0:
        raise ValueError("target-points must be > 0")
    if args.inverters <= 0:
        raise ValueError("inverters must be > 0")

    inverter_rows = build_inverter_rows(args.inverters, args.ca, ioa_start=1)

    if len(inverter_rows) > args.target_points:
        raise ValueError(
            f"inverter rows ({len(inverter_rows)}) exceed target points ({args.target_points}); "
            "please increase target-points or reduce inverters"
        )

    plant_rows = build_plant_rows(
        target_count=args.target_points,
        existing_count=len(inverter_rows),
        ca=args.ca,
        ioa_start=len(inverter_rows) + 1,
    )

    all_rows = inverter_rows + plant_rows
    write_csv(Path(args.output), all_rows)

    print(f"generated: {args.output}")
    print(f"total rows: {len(all_rows)}")
    print(f"inverter rows: {len(inverter_rows)}")
    print(f"plant rows: {len(plant_rows)}")


if __name__ == "__main__":
    main()
