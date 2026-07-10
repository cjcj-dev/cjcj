#!/usr/bin/env python3
"""sc_bcgate.py — self-compile bcgate: compile a COMPILER PACKAGE with the candidate (selfhost) and the
baseline (reference C++) cjc, compare emitted bitcode function-by-function. A FAR broader faithfulness
signal than the 113 single-file difftest corpus (packages exercise generics/casts/closures/imports/...).

Usage: python3 scripts/sc_bcgate.py <pkg> [<pkg2> ...] [--self PATH] [--timeout N]
  default --self = ./target/release/bin/<module>::cjc (auto-detected) ; baseline = $CANGJIE_HOME/bin/cjc
Reuses bcgate.py's IR normalization (function-by-function, module-layout independent).
"""
import os, sys, subprocess, hashlib, tempfile, pathlib, importlib.util

ROOT = pathlib.Path(__file__).resolve().parent.parent
CANGJIE_HOME = os.environ.get("CANGJIE_HOME", "/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029")
DIS = f"{CANGJIE_HOME}/third_party/llvm/bin/llvm-dis"

# reuse bcgate.py's normalization + function extraction
spec = importlib.util.spec_from_file_location("bcgate", str(ROOT / "scripts" / "bcgate.py"))
bg = importlib.util.module_from_spec(spec); spec.loader.exec_module(bg)

def env():
    e = dict(os.environ)
    e["LD_LIBRARY_PATH"] = f"{CANGJIE_HOME}/third_party/llvm/lib:{CANGJIE_HOME}/runtime/lib/linux_x86_64_cjnative:{CANGJIE_HOME}/tools/lib:" + e.get("LD_LIBRARY_PATH", "")
    e["cjHeapSize"] = os.environ.get("cjHeapSize", "24GB"); e["CANGJIE_HOME"] = CANGJIE_HOME
    return e

def emit_pkg_funcs(compiler, pkg, workdir, e, timeout):
    d = workdir / hashlib.md5(compiler.encode()).hexdigest()[:8]
    d.mkdir(parents=True, exist_ok=True)
    module_name = "cjcj" if "cjcj" in str(ROOT.name) else "cangjie_compiler"
    cmd = [compiler, "--package", f"packages/{pkg}/src", "--module-name", module_name,
           "--import-path", "target/release", "--output-type=staticlib", "--save-temps", str(d),
           "-o", str(d / f"lib{pkg}.a")]
    try:
        r = subprocess.run(cmd, cwd=str(ROOT), env=e, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, f"<compile-timeout-{timeout}s>"
    bcs = sorted(b for b in d.glob("*.bc") if not b.name.endswith(".opt.bc"))
    if not bcs:
        return None, (r.stderr or r.stdout or "no bitcode").strip().splitlines()[-1:]
    chunks = []
    for bc in bcs:
        dr = subprocess.run([DIS, str(bc), "-o", "-"], capture_output=True, text=True)
        if dr.returncode == 0:
            chunks.append(dr.stdout)
    lines = bg.norm_ir("\n".join(chunks))
    funcs, cur, name = {}, None, None
    for ln in lines:
        if ln.startswith("define "):
            m = bg._DEFNAME.match(ln); name = m.group(1) if m else ln; cur = [ln]
        elif cur is not None:
            cur.append(ln)
            if ln == "}":
                funcs[name] = "\n".join(cur); cur = None
    return funcs, None

def main():
    args = sys.argv[1:]
    self_cc_candidates = sorted((ROOT / "target/release/bin").glob("*::cjc")) if (ROOT / "target/release/bin").exists() else []
    self_cc = str(self_cc_candidates[0]) if self_cc_candidates else str(ROOT / "target/release/bin/cjcj::cjc")
    base_cc = f"{CANGJIE_HOME}/bin/cjc"; timeout = 600; pkgs = []
    i = 0
    while i < len(args):
        if args[i] == "--self": self_cc = args[i+1]; i += 2
        elif args[i] == "--timeout": timeout = int(args[i+1]); i += 2
        else: pkgs.append(args[i]); i += 1
    if not pkgs:
        print("usage: sc_bcgate.py <pkg> [...]"); return 2
    e = env(); wd = pathlib.Path(tempfile.mkdtemp(prefix="sc_bcgate_"))
    tot_id = tot_diff = tot_shared = 0
    for pkg in pkgs:
        rf, rerr = emit_pkg_funcs(base_cc, pkg, wd / f"ref_{pkg}", e, timeout)
        sf, serr = emit_pkg_funcs(self_cc, pkg, wd / f"self_{pkg}", e, timeout)
        if rf is None: print(f"{pkg}: REF compile failed: {rerr}"); continue
        if sf is None: print(f"{pkg}: SELF compile failed: {serr}"); continue
        shared = set(rf) & set(sf)
        ident = sum(1 for f in shared if rf[f] == sf[f])
        diff = len(shared) - ident
        only_ref = len(set(rf) - set(sf)); only_self = len(set(sf) - set(rf))
        tot_id += ident; tot_diff += diff; tot_shared += len(shared)
        pct = 100.0*ident/len(shared) if shared else 0
        print(f"{pkg}: shared={len(shared)} byte-identical={ident} ({pct:.1f}%) differing={diff} | only-ref={only_ref} only-self={only_self}")
        for f in sorted(shared)[:0]: pass
        difflist = [f for f in shared if rf[f] != sf[f]][:8]
        if difflist: print("   differing funcs:", ", ".join(d[:40] for d in difflist))
    if len(pkgs) > 1:
        pct = 100.0*tot_id/tot_shared if tot_shared else 0
        print(f"TOTAL: shared={tot_shared} byte-identical={tot_id} ({pct:.1f}%) differing={tot_diff}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
