#!/usr/bin/env python3
"""cmpir.py — cheap codegen-divergence diagnosis.

Dump + diff the LLVM IR (and optionally CHIR) of the SAME input from the reference cjc and our selfhost
cjc, WITHOUT building a binary, running it, or invoking difftest. Uses `--save-temps` to capture each
compiler's pre-opt LLVM bitcode, then `llvm-dis` to text, then diffs. Both compilers use the same
mangling, so user functions are directly comparable.

Usage:
    python3 scripts/cmpir.py <file.cj> [-g NAME] [--opt] [--chir] [--ll]
    python3 scripts/cmpir.py --package DIR [-g NAME] [--opt] [--chir] [--ll]

      -g NAME   restrict the diff to functions whose (mangled) name contains NAME (e.g. a func name)
      --opt     diff the POST-optimization IR (.opt.bc) instead of pre-opt (default: pre-opt)
      --chir    also show the selfhost CHIR dump (own funcs) for hand inspection
      --ll      write each side's normalized IR to /tmp/cmpir.{ref,self}.ll instead of diffing

Env overrides: CANGJIE_HOME, REF_CJC, SELF_CJC.

NOTE on noise: SSA value names (%0, %x) and basic-block labels differ cosmetically between the two
backends and are NOT semantic — skim past them. Real divergences look like: a different instruction
(extractvalue vs getelementptr+load), a missing intrinsic (llvm.expect), an extra addrspacecast, a
different call target, a wrong type. Those are what to act on.
"""
import argparse
import difflib
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CANGJIE_HOME = os.environ.get(
    "CANGJIE_HOME", "/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029"
)
REF = os.environ.get("REF_CJC", f"{CANGJIE_HOME}/bin/cjc")
SELF = os.environ.get(
    "SELF_CJC", str(REPO / "target/release/bin/cangjie_compiler::cjc")
)
DIS = f"{CANGJIE_HOME}/third_party/llvm/bin/llvm-dis"


def build_env():
    env = dict(os.environ)
    env["CANGJIE_HOME"] = CANGJIE_HOME
    libs = [
        f"{CANGJIE_HOME}/third_party/llvm/lib",
        f"{CANGJIE_HOME}/runtime/lib/linux_x86_64_cjnative",
        f"{CANGJIE_HOME}/tools/lib",
        env.get("LD_LIBRARY_PATH", ""),
    ]
    env["LD_LIBRARY_PATH"] = ":".join(p for p in libs if p)
    env["cjHeapSize"] = "8GB"
    return env


# normalization rules mirroring the original sed pipeline
_DROP_LINE = re.compile(r"^(;|![0-9]|source_filename|target |attributes #)")
_SUBS = [
    (re.compile(r",? ?!dbg ![0-9]+"), ""),
    (re.compile(r", ![a-zA-Z.]+ ![0-9]+"), ""),
    (re.compile(r" #[0-9]+ "), " "),
    (re.compile(r"[ \t]*,?[ \t]*$"), ""),
]


def normalize(text):
    out = []
    for line in text.splitlines():
        if _DROP_LINE.match(line):
            continue
        for pat, rep in _SUBS:
            line = pat.sub(rep, line)
        out.append(line)
    return out


# Per-function canonicalization of NON-semantic names so the two backends become comparable:
# local SSA values (%x, %0, %val.ov), basic-block labels, and the hash suffix of compiler-generated
# globals ($const_cjstring.<hash>, lambda/wrapper temp symbols). Mangled user/global symbols (@_CN...)
# are LEFT INTACT — they must match. After this, any remaining diff is a real instruction/operand/type
# divergence, which is exactly the bit-parity gap to close.
_LOCAL = re.compile(r"%[A-Za-z0-9_.$]+|%\"[^\"]+\"")
_LABEL = re.compile(r"^([A-Za-z0-9_.$]+):")
_HASHGLOBAL = re.compile(r"(@\"?\$?(?:const_cjstring|const|lambda|Cl|env)[A-Za-z0-9_.$]*?)[.+][A-Za-z0-9_+/-]{6,}(\"?)")


def canonicalize(lines):
    out, names, labels, n, ln = [], {}, {}, [0], [0]

    def local(m):
        k = m.group(0)
        if k not in names:
            n[0] += 1
            names[k] = f"%v{n[0]}"
        return names[k]

    for line in lines:
        if line.startswith("define "):
            names, labels, n, ln = {}, {}, [0], [0]
        # canonicalize a hash-suffixed compiler global to a stable name (drop the volatile hash)
        line = _HASHGLOBAL.sub(lambda m: m.group(1) + ".H" + (m.group(2) or ""), line)
        m = _LABEL.match(line)
        if m:
            lab = m.group(1)
            if lab not in labels:
                ln[0] += 1
                labels[lab] = f"L{ln[0]}"
            line = labels[lab] + ":" + line[m.end():]
        # canonicalize block-label REFERENCES (label %foo) and local SSA names
        line = re.sub(r"label %([A-Za-z0-9_.$]+)",
                      lambda m: "label %" + labels.setdefault(m.group(1), f"L{(ln.__setitem__(0, ln[0]+1) or ln[0])}"),
                      line)
        line = _LOCAL.sub(local, line)
        out.append(line)
    return out


def disnorm(directory, bckind):
    """llvm-dis every matching bitcode module in `directory`, concatenate, normalize, canonicalize."""
    chunks = []
    for bc in sorted(Path(directory).glob(f"*.{bckind}")):
        if bckind == "bc" and bc.name.endswith(".opt.bc"):
            continue
        r = subprocess.run([DIS, str(bc), "-o", "-"], capture_output=True, text=True)
        if r.returncode == 0:
            chunks.append(r.stdout)
    return canonicalize(normalize("\n".join(chunks)))


def select_fns(lines, name):
    """Keep only function bodies (define..}) whose header line contains `name`."""
    if not name:
        return lines
    out, keep = [], False
    for line in lines:
        if "define" in line and name in line:
            keep = True
        if keep:
            out.append(line)
        if keep and line.rstrip() == "}":
            keep = False
    return out


def compile_savetemps(compiler, srcargs, workdir, outdir, env):
    outdir.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [compiler, *srcargs, "--save-temps", str(outdir), "-o", str(outdir / "a")],
        cwd=workdir,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def dump_chir(compiler, srcargs, workdir, env, name):
    r = subprocess.run(
        [compiler, *srcargs, "--dump-chir", "--dump-to-screen", "-o", str(workdir / "c")],
        cwd=workdir,
        env=env,
        capture_output=True,
        text=True,
    )
    lines = [
        ln
        for ln in r.stdout.splitlines()
        if "imported" not in ln and "srcCodeImported" not in ln
    ]
    if name:
        lines = [ln for ln in lines if name in ln]
    return lines[:60]


def main():
    ap = argparse.ArgumentParser(add_help=True, description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", nargs="?", help="path to a .cj file")
    ap.add_argument("--package", help="compile a package directory instead of a single file")
    ap.add_argument("-g", dest="filter", default="", help="only diff functions whose name contains this")
    ap.add_argument("--opt", action="store_true", help="diff post-optimization IR (.opt.bc)")
    ap.add_argument("--chir", action="store_true", help="also show selfhost CHIR (own funcs)")
    ap.add_argument("--ll", action="store_true", help="write normalized IR to /tmp/cmpir.{ref,self}.ll")
    args = ap.parse_args()

    if args.package:
        srcargs = ["--package", args.package]
    elif args.input:
        srcargs = [args.input]
    else:
        ap.error("provide a <file.cj> or --package DIR")

    bckind = "opt.bc" if args.opt else "bc"
    env = build_env()

    with tempfile.TemporaryDirectory() as work:
        work = Path(work)
        compile_savetemps(REF, srcargs, work, work / "r", env)
        compile_savetemps(SELF, srcargs, work, work / "s", env)

        ref = select_fns(disnorm(work / "r", bckind), args.filter)
        slf = select_fns(disnorm(work / "s", bckind), args.filter)

        if args.ll:
            Path("/tmp/cmpir.ref.ll").write_text("\n".join(ref) + "\n")
            Path("/tmp/cmpir.self.ll").write_text("\n".join(slf) + "\n")
            print(f"wrote /tmp/cmpir.ref.ll ({len(ref)} lines) and /tmp/cmpir.self.ll ({len(slf)} lines)")
        else:
            tag = "opt" if args.opt else "pre-opt"
            flt = f"   [funcs matching '{args.filter}']" if args.filter else ""
            print(f"### LLVM IR diff ({tag})  < reference   > selfhost{flt}")
            diff = list(
                difflib.unified_diff(ref, slf, fromfile="reference", tofile="selfhost", lineterm="")
            )
            if diff:
                print("\n".join(diff))
            else:
                print("(identical after normalization)")

        if args.chir:
            print("\n### selfhost CHIR (own funcs only)")
            print("\n".join(dump_chir(SELF, srcargs, work, env, args.filter)))


if __name__ == "__main__":
    sys.exit(main())
