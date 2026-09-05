#!/usr/bin/env python3
"""Require aggregate whole-copy verifier keys to clear without collateral deltas."""

from __future__ import annotations

import argparse
import collections
import csv
import json
import pathlib
import sys


FIELDS = (
    "module", "function", "rule", "instruction", "dest_as", "src_as",
    "length", "dest_root", "src_root", "source_type",
)


def read_rows(path: pathlib.Path) -> list[tuple[str, ...]]:
    with path.open(newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        if tuple(reader.fieldnames or ()) != FIELDS:
            raise ValueError(f"{path}: expected the ten verifier fields {FIELDS}")
        return [tuple(row[field] for field in FIELDS) for row in reader]


def is_whole_aggregate_copy(row: tuple[str, ...]) -> bool:
    value = dict(zip(FIELDS, row))
    source = value["source_type"].lstrip()
    return (
        "StructureString" in (value["function"] + source)
        and value["instruction"] in {"memcpy", "memmove"}
        and value["dest_as"] == "0"
        and value["src_as"] == "0"
        and source.startswith(("%", "[", "{", "<{"))
    )


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
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    try:
        baseline_rows = read_rows(args.baseline)
        candidate_rows = read_rows(args.candidate)
    except (OSError, ValueError) as error:
        print(f"FAIL input: {error}")
        return 2

    baseline = collections.Counter(baseline_rows)
    candidate = collections.Counter(candidate_rows)
    target = collections.Counter(row for row in baseline_rows if is_whole_aggregate_copy(row))
    expected = baseline - target
    remaining = collections.Counter(row for row in candidate_rows if is_whole_aggregate_copy(row))
    missing_other = expected - candidate
    new = candidate - expected
    write_rows(args.out / "baseline-whole-copy.tsv", sorted(target.elements()))
    write_rows(args.out / "candidate-whole-copy.tsv", sorted(remaining.elements()))
    write_rows(args.out / "missing-other.tsv", sorted(missing_other.elements()))
    write_rows(args.out / "new.tsv", sorted(new.elements()))
    summary = {
        "baseline_whole_copy": sum(target.values()),
        "candidate_whole_copy": sum(remaining.values()),
        "missing_other": sum(missing_other.values()),
        "new": sum(new.values()),
    }
    (args.out / "summary.json").write_text(json.dumps(summary, sort_keys=True, indent=2) + "\n")
    checks = {
        "baselinePositiveControl": bool(target),
        "candidateWholeCopyEmpty": not remaining,
        "otherKeysStable": not missing_other,
        "newKeysEmpty": not new,
    }
    for name, passed in checks.items():
        print(f"{'PASS' if passed else 'FAIL'} {name}")
    print(json.dumps(summary, sort_keys=True))
    return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
