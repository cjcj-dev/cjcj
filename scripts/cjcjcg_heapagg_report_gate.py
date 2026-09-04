#!/usr/bin/env python3
"""Compare verifier report rows before and after typed heap-aggregate lowering.

Package names select the requested corpus only.  Classification of the rows
under repair is structural: a managed destination, native source, raw copy and
an LLVM aggregate pointee type.  In particular, it does not depend on byte
length, module name, or an SSA-root allowlist.
"""

from __future__ import annotations

import argparse
import collections
import csv
import json
import pathlib
import sys


FIELDS = (
    "module",
    "function",
    "rule",
    "instruction",
    "dest_as",
    "src_as",
    "length",
    "dest_root",
    "src_root",
    "source_type",
)


def read_rows(
    path: pathlib.Path, modules: tuple[str, ...], *, require_presence: bool
) -> list[tuple[str, ...]]:
    with path.open(newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        if tuple(reader.fieldnames or ()) != FIELDS:
            raise ValueError(f"{path}: expected the ten verifier fields {FIELDS}, got {reader.fieldnames}")
        rows = [tuple(row[field] for field in FIELDS) for row in reader]
    selected = [row for row in rows if any(row[0].endswith(module) for module in modules)]
    if require_presence:
        present = {module for module in modules if any(row[0].endswith(module) for row in selected)}
        missing = set(modules) - present
        if missing:
            raise ValueError(f"{path}: selected corpus has no rows for {sorted(missing)}")
    return selected


def is_concrete_aggregate_copy(row: tuple[str, ...]) -> bool:
    values = dict(zip(FIELDS, row))
    source_type = values["source_type"].lstrip()
    aggregate_pointee = source_type.startswith(("%", "[", "{", "<{"))
    return (
        values["instruction"] in {"memcpy", "memmove"}
        and values["dest_as"] == "1"
        and values["src_as"] == "0"
        and aggregate_pointee
    )


def untouched_family(row: tuple[str, ...]) -> str:
    values = dict(zip(FIELDS, row))
    source_type = values["source_type"].strip()
    if (
        values["instruction"] == "memmove"
        and values["dest_as"] == "1"
        and values["src_as"] == "1"
        and source_type == "i8 addrspace(1)*"
        and values["length"].isdigit()
    ):
        return "constarray"
    if source_type.startswith("i8") or values["length"].startswith("%"):
        return "dynamic"
    return "other"


def expanded(counter: collections.Counter[tuple[str, ...]]) -> list[tuple[str, ...]]:
    return sorted(counter.elements())


def write_rows(path: pathlib.Path, rows: list[tuple[str, ...]]) -> None:
    with path.open("w", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(FIELDS)
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", required=True, type=pathlib.Path)
    parser.add_argument("--candidate", required=True, type=pathlib.Path)
    parser.add_argument("--out", required=True, type=pathlib.Path)
    parser.add_argument(
        "--module",
        action="append",
        default=[],
        help="module suffix to include; repeat for each corpus package",
    )
    args = parser.parse_args()
    modules = tuple(args.module or ("std.ast", "std.collection.concurrent", "std.net", "std.regex"))
    args.out.mkdir(parents=True, exist_ok=True)

    try:
        baseline_rows = read_rows(args.baseline, modules, require_presence=True)
        candidate_rows = read_rows(args.candidate, modules, require_presence=False)
    except (OSError, ValueError) as error:
        print(f"FAIL input: {error}")
        return 2

    baseline = collections.Counter(baseline_rows)
    candidate = collections.Counter(candidate_rows)
    repaired = collections.Counter(row for row in baseline_rows if is_concrete_aggregate_copy(row))
    expected = baseline - repaired
    remaining_repaired = collections.Counter(
        row for row in candidate_rows if is_concrete_aggregate_copy(row)
    )
    missing_untouched = expected - candidate
    new_rows = candidate - expected

    family_deltas: dict[str, dict[str, int]] = {}
    for family in ("constarray", "dynamic", "other"):
        before = collections.Counter(row for row in expected.elements() if untouched_family(row) == family)
        after = collections.Counter(
            row for row in candidate.elements()
            if not is_concrete_aggregate_copy(row) and untouched_family(row) == family
        )
        family_deltas[family] = {
            "baseline": sum(before.values()),
            "candidate": sum(after.values()),
            "missing": sum((before - after).values()),
            "new": sum((after - before).values()),
        }

    write_rows(args.out / "baseline-repaired.tsv", expanded(repaired))
    write_rows(args.out / "candidate-repaired.tsv", expanded(remaining_repaired))
    write_rows(args.out / "missing-untouched.tsv", expanded(missing_untouched))
    write_rows(args.out / "new.tsv", expanded(new_rows))
    summary = {
        "baseline_rows": sum(baseline.values()),
        "baseline_repaired": sum(repaired.values()),
        "candidate_rows": sum(candidate.values()),
        "candidate_repaired": sum(remaining_repaired.values()),
        "missing_untouched": sum(missing_untouched.values()),
        "new": sum(new_rows.values()),
        "modules": list(modules),
        "untouched_families": family_deltas,
    }
    (args.out / "summary.json").write_text(json.dumps(summary, sort_keys=True, indent=2) + "\n")

    checks = {
        "baselinePositiveControl": bool(repaired),
        "candidateHeapAggregateEmpty": not remaining_repaired,
        "untouchedMultisetStable": not missing_untouched,
        "newRowsEmpty": not new_rows,
        "constarrayStable": family_deltas["constarray"]["missing"] == 0
        and family_deltas["constarray"]["new"] == 0,
        "dynamicStable": family_deltas["dynamic"]["missing"] == 0
        and family_deltas["dynamic"]["new"] == 0,
        "otherStable": family_deltas["other"]["missing"] == 0
        and family_deltas["other"]["new"] == 0,
    }
    for name, passed in checks.items():
        print(f"{'PASS' if passed else 'FAIL'} {name}")
    print(json.dumps(summary, sort_keys=True))
    return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
