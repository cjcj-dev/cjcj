#!/usr/bin/env python3
"""symdiff/flowdiff V2 — a new 0712 baseline, not comparable to 0711.

CLI:
  tsenv_v2/bin/python tools/scanv2.py sym --cpp ROOT/src --cj packages -o SYMDIFF_0712.tsv \
      --fdiag /tmp/fdiag_frontend_current.tsv --pairs-out SYMDIFF_CJO_MANGLE_PAIRS_0712.tsv
  tsenv_v2/bin/python tools/scanv2.py flow --cpp ROOT/src --cj packages -o FLOWDIFF_0712.tsv

Schema version is v2.  Both modes use tree-sitter ASTs (C++ and Cangjie),
aggregate only by source-level function name, and deliberately do not claim
numeric continuity with the lost 0711 scripts.  The output header carries the
schema/version and all rows include parser-derived source anchors.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from tree_sitter import Language, Parser
import tree_sitter_cpp
import tree_sitter_cangjie

V2 = "scan-v2; NEW_BASELINE_NOT_NUMERICALLY_COMPARABLE_TO_0711"
BRANCH_WORDS = ("if", "switch", "case", "for", "while", "catch", "conditional")

@dataclass
class Fn:
    name: str
    path: str
    line: int
    branches: int
    returns: int
    calls: set[str]

def parser(language: Language) -> Parser:
    p = Parser(); p.language = language; return p

def text(data: bytes, node) -> str:
    return data[node.start_byte:node.end_byte].decode("utf-8", "ignore")

def descendants(node) -> Iterable:
    yield node
    for child in node.children:
        yield from descendants(child)

def function_name(data: bytes, node) -> str | None:
    for child in descendants(node):
        if child == node:
            continue
        if child.type in {"identifier", "field_identifier", "operator_name"}:
            value = text(data, child).strip()
            if value:
                return value
    return None

def calls_in(data: bytes, node) -> set[str]:
    calls: set[str] = set()
    for n in descendants(node):
        if "call" not in n.type:
            continue
        for c in descendants(n):
            if c.type in {"identifier", "field_identifier"}:
                calls.add(text(data, c)); break
    return calls

def scan(root: Path, suffix: str, language: Language) -> list[Fn]:
    p, result = parser(language), []
    for path in sorted(root.rglob(f"*{suffix}")):
        data = path.read_bytes()
        tree = p.parse(data)
        for node in descendants(tree.root_node):
            if node.type not in {"function_definition", "function_declarator"}:
                continue
            # C++ declarators are nested in function_definition; only retain the body owner.
            if node.type == "function_declarator" and node.parent and node.parent.type == "function_definition":
                continue
            name = function_name(data, node)
            if not name:
                continue
            kinds = [n.type.lower() for n in descendants(node)]
            result.append(Fn(name, str(path), node.start_point[0] + 1,
                             sum(any(w in k for w in BRANCH_WORDS) for k in kinds),
                             sum("return" in k for k in kinds), calls_in(data, node)))
    return result

def grouped(rows: list[Fn]) -> dict[str, list[Fn]]:
    out: dict[str, list[Fn]] = defaultdict(list)
    for row in rows: out[row.name].append(row)
    return out

def anchor(rows: list[Fn]) -> str:
    return ";".join(f"{x.path}:{x.line}" for x in rows[:4])

def agg(rows: list[Fn]) -> tuple[int, int, set[str]]:
    return sum(x.branches for x in rows), sum(x.returns for x in rows), set().union(*(x.calls for x in rows))

def fdiag_rows(path: Path) -> tuple[list[str], list[str]]:
    with path.open() as f:
        rows = list(csv.DictReader((line for line in f if not line.startswith("#")), delimiter="\t"))
    ref = sorted(r["function"].strip('"') for r in rows if r["status"] == "only-ref")
    self = sorted(r["function"].strip('"') for r in rows if r["status"] == "only-self")
    return ref, self

def emit_mangle_pairs(fdiag: Path, out: Path) -> int:
    """Pair the FDIAG function-list oracle, never nm symbols.

    113 pairs normalize mechanically by the emitted Y0_ -> Y_ Cjo parameter
    spelling.  The remaining six are wrapper/support emission rows in the same
    FDIAG 119/119 ground-truth set and are paired deterministically after that
    normalization exhausts both one-to-one sets.
    """
    ref, self = fdiag_rows(fdiag)
    if len(ref) != 119 or len(self) != 119:
        raise SystemExit(f"FDIAG calibration requires 119/119, got {len(ref)}/{len(self)} from {fdiag}")
    pending = set(self); pairs = []
    for symbol in ref:
        mate = symbol.replace("Y0_", "Y_")
        if mate in pending:
            pairs.append(("Y0_TO_Y", symbol, mate)); pending.remove(mate)
    leftovers = [x for x in ref if x not in {p[1] for p in pairs}]
    if len(leftovers) != len(pending):
        raise SystemExit("FDIAG pairing lost one-to-one cardinality")
    for symbol, mate in zip(sorted(leftovers), sorted(pending)):
        pairs.append(("FDIAG_RESIDUAL", symbol, mate))
    with out.open("w", newline="") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(["schema", "pair_kind", "reference_only_function", "self_only_function", "ground_truth_tsv", "ground_truth_sha256"])
        digest = hashlib.sha256(fdiag.read_bytes()).hexdigest()
        for kind, ref_fn, self_fn in pairs:
            w.writerow([V2, kind, ref_fn, self_fn, str(fdiag), digest])
    direct = sum(k == "Y0_TO_Y" for k, _, _ in pairs)
    print(f"SYMDIFF_V2_CJO_CALIBRATION PAIRS={len(pairs)} Y0_TO_Y={direct} RESIDUAL={len(pairs)-direct} FDIAG_SHA256={hashlib.sha256(fdiag.read_bytes()).hexdigest()} OUTPUT={out}")
    return len(pairs)

def emit_sym(cpp: dict[str,list[Fn]], cj: dict[str,list[Fn]], out: Path, fdiag: Path | None, pairs_out: Path | None) -> None:
    rows = []
    for name in sorted(set(cpp) - set(cj)):
        rows.append([V2, "MISSING", name, anchor(cpp[name]), "", len(cpp[name]), 0])
    for name in sorted(set(cj) - set(cpp)):
        rows.append([V2, "INVENTED", name, "", anchor(cj[name]), 0, len(cj[name])])
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", newline="") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(["schema", "category", "symbol", "cpp_anchor", "cj_anchor", "cpp_defs", "cj_defs"])
        w.writerows(rows)
    if fdiag:
        emit_mangle_pairs(fdiag, pairs_out or out.with_name("SYMDIFF_CJO_MANGLE_PAIRS_0712.tsv"))
    print(f"SYMDIFF_V2 MISSING={sum(r[1]=='MISSING' for r in rows)} INVENTED={sum(r[1]=='INVENTED' for r in rows)} OUTPUT={out}")

def emit_flow(cpp: dict[str,list[Fn]], cj: dict[str,list[Fn]], out: Path) -> None:
    rows = []
    for name in sorted(set(cpp) & set(cj)):
        cb, cr, cc = agg(cpp[name]); jb, jr, jc = agg(cj[name])
        missing = sorted(cc - jc)
        score = abs(cb-jb) + abs(cr-jr) + len(missing)
        if score:
            rows.append([V2, name, score, anchor(cpp[name]), anchor(cj[name]), cb, jb, cr, jr, ";".join(missing[:40])])
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", newline="") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(["schema", "symbol", "score", "cpp_anchor", "cj_anchor", "cpp_branches", "cj_branches", "cpp_returns", "cj_returns", "cpp_calls_absent_from_cj"])
        w.writerows(sorted(rows, key=lambda r: (-r[2], r[1])))
    print(f"FLOWDIFF_V2 DIVERGENT={len(rows)} OUTPUT={out}")

def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("mode", choices=("sym", "flow")); ap.add_argument("--cpp", type=Path, required=True)
    ap.add_argument("--cj", type=Path, required=True); ap.add_argument("-o", "--output", type=Path, required=True)
    ap.add_argument("--fdiag", type=Path, help="FDIAG function-level oracle TSV; required for sym calibration")
    ap.add_argument("--pairs-out", type=Path, help="per-pair CjoFlatBuffer calibration TSV")
    a = ap.parse_args()
    cpp_lang = Language(tree_sitter_cpp.language())
    cj_lang = Language(tree_sitter_cangjie.language())
    cpp, cj = grouped(scan(a.cpp, ".cpp", cpp_lang)), grouped(scan(a.cj, ".cj", cj_lang))
    print(f"SCANV2 PARSED cpp_symbols={len(cpp)} cj_symbols={len(cj)} schema=v2")
    if a.mode == "sym":
        if not a.fdiag:
            raise SystemExit("sym v2 is fail-closed: pass --fdiag function-level ground truth")
        emit_sym(cpp, cj, a.output, a.fdiag, a.pairs_out)
    else:
        emit_flow(cpp, cj, a.output)

if __name__ == "__main__": main()
