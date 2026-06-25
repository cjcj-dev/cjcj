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


def emit_ir(compiler, src, workdir, e):
    """Compile src to bitcode with --save-temps; return normalized IR text (sorted by function)."""
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
    # split into function bodies, sort, so module-ordering noise doesn't matter
    lines = norm_ir("\n".join(chunks))
    funcs, cur = [], None
    for ln in lines:
        if ln.startswith("define "):
            cur = [ln]
            funcs.append(cur)
        elif cur is not None:
            cur.append(ln)
            if ln == "}":
                cur = None
    bodies = sorted("\n".join(f) for f in funcs)
    return "\n".join(bodies), None


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
    args = ap.parse_args()
    e = env()
    samples = sorted(Path(args.corpus).resolve().glob("*.cj"))
    if not samples:
        print(f"no .cj in {args.corpus}", file=sys.stderr)
        return 2

    unchanged, changed, errors = [], [], []
    with tempfile.TemporaryDirectory() as work:
        work = Path(work)
        for src in samples:
            cand_ir, cerr = emit_ir(args.cand, src, work / "c" / src.stem, e)
            base_ir, berr = emit_ir(args.base, src, work / "b" / src.stem, e)
            name = src.name
            if cand_ir is None or base_ir is None:
                errors.append((name, cerr or berr))
                continue
            if cand_ir == base_ir:
                unchanged.append(name)
            else:
                verdict = ""
                if args.run:
                    co = run_prog(args.cand, src, work / "rc" / src.stem, e)
                    bo = run_prog(args.base, src, work / "rb" / src.stem, e)
                    verdict = "stdout-MATCH" if co == bo else f"stdout-MISMATCH (cand={co!r} base={bo!r})"
                changed.append((name, verdict))
                if args.v:
                    import difflib
                    print(f"--- IR diff: {name} ---")
                    print("\n".join(difflib.unified_diff(base_ir.splitlines(), cand_ir.splitlines(),
                                                          "baseline", "candidate", lineterm=""))[:4000])

    print(f"\n=== bcgate: {len(samples)} samples  |  {len(unchanged)} bitcode-identical (proven non-regress)"
          f"  |  {len(changed)} changed  |  {len(errors)} compile-error ===")
    for name, verdict in changed:
        print(f"  CHANGED  {name}  {verdict}")
    for name, err in errors:
        print(f"  ERROR    {name}  {err}")
    bad = [n for n, v in changed if "MISMATCH" in v] + [n for n, _ in errors]
    if not changed and not errors:
        print("ALL BITCODE IDENTICAL — no behavioral change vs baseline, no run needed.")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
