#!/usr/bin/env python3
"""whydiff.py — classify WHY each bcgate function diverges, to build a root-cluster map fast.

Reuses bcgate's per-function IR emission (emit_funcs). For every shared function that differs between
candidate (selfhost) and baseline (reference), it classifies the divergence so a handful of structural
roots can be read off directly instead of hand-diffing IR per cut:

  CALL-ORDER  : same set of call/invoke targets, different ORDER  (e.g. _CGP file-init ordering)
  CALL-SET    : different set of call/invoke targets              (missing/extra calls)
  SIZE±N      : body line-count differs by N                      (extra/fewer instructions/blocks)
  CONTENT     : same size, token-level differences                (operand/typing divergence)

Single-side functions (present on only one side) are bucketed by mangled-name prefix.

Usage:
  python3 scripts/whydiff.py --self <cjc> [--base <cjc>] [--corpus DIR] [-j N]
  python3 scripts/whydiff.py --self <cjc> --func _CGP7defaultiiHv   # show per-sample diff of one function
  python3 scripts/whydiff.py --self <cjc> --strict                  # do NOT canonicalize hash names (true parity)
"""
import argparse
import os
import re
import sys
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bcgate  # reuse emit_funcs/env
from cmpir import normalize as _normalize, canonicalize as _canonicalize

REPO = Path(__file__).resolve().parent.parent
_CALL = re.compile(r'\b(?:call|invoke)\b[^@]*@("[^"]+"|[\w.$]+)')


def call_seq(body):
    return _CALL.findall(body)


def classify(cand_body, base_body):
    cs, bs = call_seq(cand_body), call_seq(base_body)
    if cs != bs:
        if set(cs) == set(bs) and len(cs) == len(bs):
            return "CALL-ORDER", f"{len(cs)} calls reordered"
        miss = [x for x in bs if x not in cs]
        extra = [x for x in cs if x not in bs]
        return "CALL-SET", f"-{len(miss)} +{len(extra)}: " + ",".join((miss + extra)[:3])
    cl, bl = cand_body.count("\n"), base_body.count("\n")
    if cl != bl:
        return "SIZE", f"{cl - bl:+d} lines (self {cl} vs ref {bl})"
    return "CONTENT", "same size, token diff"


def prefix_of(name):
    n = name.strip('"')
    m = re.match(r'(_C[A-Z]{1,3})', n)
    if m:
        tag = m.group(1)
        if "<main>" in n:
            return tag + "..<main>"
        return tag
    return n[:12]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--self", dest="cand", required=True)
    ap.add_argument("--base", default=f"{bcgate.CANGJIE_HOME}/bin/cjc")
    ap.add_argument("--corpus", default=str(REPO / "scripts/difftest_corpus"))
    ap.add_argument("--func", default=None, help="show per-sample canonicalized diff for one function")
    ap.add_argument("--strict", action="store_true", help="normalize only (keep hash-suffixed names)")
    ap.add_argument("-j", "--jobs", type=int, default=min(16, os.cpu_count() or 4))
    args = ap.parse_args()
    e = bcgate.env()

    # optionally strict: monkeypatch norm_ir to skip canonicalize
    if args.strict:
        bcgate.norm_ir = lambda text: _normalize(text)

    samples = sorted(Path(args.corpus).resolve().glob("*.cj"))
    import tempfile

    def emit(src, work):
        cand, _ = bcgate.emit_funcs(args.cand, src, work / "c" / src.stem, e)
        base, _ = bcgate.emit_funcs(args.base, src, work / "b" / src.stem, e)
        return src.name, cand, base

    with tempfile.TemporaryDirectory() as work:
        work = Path(work)
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            results = list(pool.map(lambda s: emit(s, work), samples))

    if args.func:
        target = args.func
        shown = 0
        for name, cand, base in sorted(results):
            if cand is None or base is None:
                continue
            cb, bb = cand.get(target), base.get(target)
            if cb is None and bb is None:
                continue
            if cb == bb:
                continue
            kind = "single-side" if (cb is None or bb is None) else classify(cb, bb)[0]
            print(f"\n===== {name}: {target}  [{kind}] =====")
            import difflib
            diff = difflib.unified_diff((bb or "").splitlines(), (cb or "").splitlines(),
                                        "reference", "selfhost", lineterm="")
            print("\n".join(list(diff)[:80]))
            shown += 1
            if shown >= 6:
                print("\n... (more samples omitted)")
                break
        return 0

    # cluster mode
    differ_kind = defaultdict(Counter)   # func -> Counter(kind)
    differ_detail = {}                   # func -> a representative detail string
    differ_count = Counter()             # func -> #samples differing
    single_side = Counter()              # func -> #samples single-side
    single_prefix = Counter()
    for name, cand, base in results:
        if cand is None or base is None:
            continue
        shared = set(cand) & set(base)
        for fn in shared:
            if cand[fn] != base[fn]:
                k, d = classify(cand[fn], base[fn])
                differ_kind[fn][k] += 1
                differ_detail[fn] = d
                differ_count[fn] += 1
        for fn in set(cand) ^ set(base):
            single_side[fn] += 1
            single_prefix[prefix_of(fn)] += 1

    print(f"\n=== whydiff cluster map {'(STRICT)' if args.strict else ''} over {len(samples)} samples ===")
    print(f"\n-- DIFFERING shared functions (ranked by #samples), with divergence class --")
    for fn, c in differ_count.most_common(25):
        kinds = ",".join(f"{k}×{n}" for k, n in differ_kind[fn].most_common())
        print(f"  {c:3d}  {fn:42s} [{kinds}] {differ_detail.get(fn,'')[:48]}")

    print(f"\n-- divergence-class TOTALS (sum over differing funcs×samples) --")
    klass = Counter()
    for fn, ctr in differ_kind.items():
        for k, n in ctr.items():
            klass[k] += n
    for k, n in klass.most_common():
        print(f"  {n:5d}  {k}")

    print(f"\n-- SINGLE-SIDE functions bucketed by mangled prefix --")
    for p, n in single_prefix.most_common(15):
        print(f"  {n:5d}  {p}")
    print(f"  total single-side occurrences: {sum(single_side.values())}, distinct funcs: {len(single_side)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
