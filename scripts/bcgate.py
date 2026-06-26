#!/usr/bin/env python3
"""bcgate.py — bitcode-level regression gate (cheap alternative to compile+run difftest).

For each corpus sample, emit LLVM bitcode with a CANDIDATE compiler and a BASELINE compiler (default:
the reference cjc) via --save-temps, normalize (llvm-dis, strip names/metadata), and compare.

  - bitcode IDENTICAL  -> behavior is provably unchanged, NO run needed.
  - bitcode DIFFERENT  -> only THEN compile+run BOTH and diff stdout to see if the change is benign.

Rationale: the committed selfhost baseline already matches the reference on the whole corpus
(difftest 113/113), so "candidate bitcode == baseline bitcode" transitively proves the candidate still
matches the reference on that sample — without linking or executing it. A typical cut changes the
bitcode of only a handful of samples, so the expensive run path is taken for just those.

Usage:
  python3 scripts/bcgate.py --self <candidate_cjc> [--base <baseline_cjc>] [--corpus DIR] [--run] [-v]
    --self  PATH   candidate compiler (e.g. a worktree's target/release/bin/cangjie_compiler::cjc)
    --base  PATH   baseline compiler (default: $CANGJIE_HOME/bin/cjc, the reference)
    --corpus DIR   corpus of .cj programs (default: scripts/difftest_corpus)
    --run          for CHANGED samples, compile+run both and compare stdout (else just list them)
    -v             also print the per-function IR diff for each changed sample
"""
import argparse
import hashlib
import os
import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

CANGJIE_HOME = os.environ.get("CANGJIE_HOME", "/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029")
REPO = Path(__file__).resolve().parent.parent
DIS = f"{CANGJIE_HOME}/third_party/llvm/bin/llvm-dis"

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cmpir import normalize as _normalize, canonicalize as _canonicalize  # noqa: E402


def env():
    e = dict(os.environ)
    e["CANGJIE_HOME"] = CANGJIE_HOME
    libs = [f"{CANGJIE_HOME}/third_party/llvm/lib",
            f"{CANGJIE_HOME}/runtime/lib/linux_x86_64_cjnative",
            f"{CANGJIE_HOME}/tools/lib", e.get("LD_LIBRARY_PATH", "")]
    e["LD_LIBRARY_PATH"] = ":".join(p for p in libs if p)
    e["cjHeapSize"] = "8GB"
    return e


def norm_ir(text):
    return _canonicalize(_normalize(text))


_DEFNAME = re.compile(r'define[^@]*@("[^"]+"|[^ (]+)')


def emit_funcs(compiler, src, workdir, e):
    """Compile src to bitcode; return {functionMangledName: canonicalized body} (robust to how the two
    backends split a package into modules — we match function-by-function, not by module layout)."""
    d = workdir / hashlib.md5(compiler.encode()).hexdigest()[:8]
    d.mkdir(parents=True, exist_ok=True)
    r = subprocess.run([compiler, str(src), "--save-temps", str(d), "-o", str(d / "a")],
                       cwd=workdir, env=e, capture_output=True, text=True)
    bcs = sorted(b for b in d.glob("*.bc") if not b.name.endswith(".opt.bc"))
    if not bcs:
        return None, (r.stderr or r.stdout or "no bitcode emitted").strip().splitlines()[-1:]
    chunks = []
    for bc in bcs:
        dr = subprocess.run([DIS, str(bc), "-o", "-"], capture_output=True, text=True)
        if dr.returncode == 0:
            chunks.append(dr.stdout)
    lines = norm_ir("\n".join(chunks))
    funcs, cur, name = {}, None, None
    for ln in lines:
        if ln.startswith("define "):
            m = _DEFNAME.match(ln)
            name = m.group(1) if m else ln
            cur = [ln]
        elif cur is not None:
            cur.append(ln)
            if ln == "}":
                funcs[name] = "\n".join(cur)
                cur = None
    return funcs, None


def run_prog(compiler, src, workdir, e):
    d = workdir / ("run_" + hashlib.md5(compiler.encode()).hexdigest()[:6])
    d.mkdir(parents=True, exist_ok=True)
    exe = d / "a.out"
    c = subprocess.run([compiler, str(src), "-o", str(exe)], cwd=workdir, env=e,
                       capture_output=True, text=True)
    if c.returncode != 0:
        return f"<compile-fail: {(c.stderr or c.stdout).strip().splitlines()[-1:]}>"
    run = subprocess.run([str(exe)], cwd=workdir, env=e, capture_output=True, text=True)
    return run.stdout


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--self", dest="cand", required=True, help="candidate compiler path")
    ap.add_argument("--base", default=f"{CANGJIE_HOME}/bin/cjc", help="baseline compiler (default: reference cjc)")
    ap.add_argument("--corpus", default=str(REPO / "scripts/difftest_corpus"))
    ap.add_argument("--run", action="store_true", help="run+diff stdout for changed samples")
    ap.add_argument("-v", action="store_true", help="print per-sample IR diff for changed samples")
    ap.add_argument("-j", "--jobs", type=int, default=min(16, os.cpu_count() or 4),
                    help="parallel samples to process at once (default: min(16, nproc))")
    args = ap.parse_args()
    e = env()
    samples = sorted(Path(args.corpus).resolve().glob("*.cj"))
    if not samples:
        print(f"no .cj in {args.corpus}", file=sys.stderr)
        return 2

    samples_identical, errors = [], []
    tot_fn = tot_same = 0
    from collections import Counter
    differ = Counter()           # function-name -> how many samples it differs in
    only_one_side = Counter()

    def process(src, work):
        """Per-sample work (independent, isolated workdirs) -> partial result. No shared state."""
        cand, cerr = emit_funcs(args.cand, src, work / "c" / src.stem, e)
        base, berr = emit_funcs(args.base, src, work / "b" / src.stem, e)
        if cand is None or base is None:
            return {"name": src.name, "error": cerr or berr}
        shared = set(cand) & set(base)
        return {
            "name": src.name,
            "error": None,
            "shared": len(shared),
            "same": sum(1 for n in shared if cand[n] == base[n]),
            "differ": [n for n in shared if cand[n] != base[n]],
            "one_side": list(set(cand) ^ set(base)),
        }

    with tempfile.TemporaryDirectory() as work:
        work = Path(work)
        with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
            results = list(pool.map(lambda s: process(s, work), samples))
    # Aggregate serially (sorted by name) so output is identical regardless of completion order.
    for res in sorted(results, key=lambda r: r["name"]):
        if res["error"] is not None:
            errors.append((res["name"], res["error"]))
            continue
        tot_fn += res["shared"]
        tot_same += res["same"]
        for n in res["differ"]:
            differ[n] += 1
        for n in res["one_side"]:
            only_one_side[n] += 1
        if res["same"] == res["shared"] and not res["one_side"]:
            samples_identical.append(res["name"])

    pct = (100.0 * tot_same / tot_fn) if tot_fn else 0.0
    print(f"\n=== bcgate PER-FUNCTION parity (candidate vs baseline) over {len(samples)} samples ===")
    print(f"shared functions: {tot_fn}  |  byte-identical: {tot_same} ({pct:.1f}%)  |  differing: {tot_fn - tot_same}")
    print(f"fully-identical samples: {len(samples_identical)}/{len(samples) - len(errors)}  |  compile-errors: {len(errors)}")
    if differ:
        print("top differing functions (name: #samples):")
        for n, c in differ.most_common(15):
            print(f"  {c:3d}  {n}")
    if only_one_side:
        print(f"functions present on only one side (module/emission-set divergence): {sum(only_one_side.values())} occurrences, {len(only_one_side)} distinct")
    for name, err in errors[:10]:
        print(f"  ERROR  {name}  {err}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
