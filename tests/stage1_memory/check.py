#!/usr/bin/env python3
"""Check GC-completed leaf observations from a real stage1 compilation."""
import argparse
import json
import re
from pathlib import Path


def check(result, kind):
    if result["rc"] != 0:
        raise ValueError(f"compiler did not complete: rc={result['rc']}")
    phases = {}
    for line in result["sentinels"]:
        phase = re.search(r"phase=(\w+)", line)
        gc = re.search(r"gcRan=(\d+)", line)
        if phase is None or gc is None or int(gc[1]) < 2:
            raise ValueError(f"missing completed GC observation: {line}")
        phases[phase[1]] = {
            tag: tuple(map(int, counts.split("/")))
            for tag, counts in re.findall(
                r"\b(pkg|file|topdecl|chir_context)=(\d+/\d+)", line
            )
        }
    if kind in ("ast", "ast-multi"):
        tags = ("pkg", "file", "topdecl")
        positive = "sema_end"
        targets = ("chir_optimized", "chir_end") if kind == "ast" else ("chir_end",)
    else:
        tags = ("chir_context",)
        positive = "chir_optimized"
        targets = ("process_end",)
    if kind == "ast-multi" and phases[positive]["pkg"][1] <= 1:
        raise ValueError("multi-package route was not entered")
    totals = {}
    for tag in tags:
        live, total = phases[positive][tag]
        if total <= 0 or live != total:
            raise ValueError(f"positive control failed: {positive} {tag}={live}/{total}")
        totals[tag] = total
    # Validate every observation before evaluating any target assertion.
    for phase in targets:
        for tag in tags:
            if phases[phase][tag][1] != totals[tag]:
                raise ValueError(f"sentinel population changed: {phase} {tag}")
    failures = 0
    for phase in targets:
        for tag in tags:
            live, total = phases[phase][tag]
            passed = live == 0
            failures += int(not passed)
            print(f"TARGET_RELEASE phase={phase} tag={tag} observed={live}/{total} "
                  f"status={'PASS' if passed else 'FAIL'}")
    print(f"TARGET_ASSERTIONS_EXECUTED={len(targets) * len(tags)} FAILURES={failures}")
    return int(failures != 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result", type=Path)
    parser.add_argument("--kind", choices=("ast", "ast-multi", "chir"), required=True)
    args = parser.parse_args()
    try:
        return check(json.loads(args.result.read_text()), args.kind)
    except (KeyError, ValueError) as error:
        print(f"PRECONDITION_FAILED: {error}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
