#!/usr/bin/env python3
"""sc_bcgate.py — self-compile bcgate: compile a COMPILER PACKAGE with the candidate (selfhost) and the
baseline (reference C++) cjc, compare emitted bitcode function-by-function. A FAR broader faithfulness
signal than the 113 single-file difftest corpus (packages exercise generics/casts/closures/imports/...).

Usage: python3 scripts/sc_bcgate.py <pkg> [<pkg2> ...] [--self PATH] [--timeout N] [--jobs K] [--no-cache]
  default --self = ./target/release/bin/<module>::cjc (auto-detected) ; baseline = $CANGJIE_HOME/bin/cjc
Reuses bcgate.py's IR normalization (function-by-function, module-layout independent).
"""
import os, sys, subprocess, hashlib, tempfile, pathlib, importlib.util, json, re, shutil
from concurrent.futures import ThreadPoolExecutor

ROOT = pathlib.Path(__file__).resolve().parent.parent
CANGJIE_HOME = os.environ.get("CANGJIE_HOME", "/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029")
DIS = f"{CANGJIE_HOME}/third_party/llvm/bin/llvm-dis"
CACHE_DIR = pathlib.Path("/root/cj_build/audit_persist/scb_cache")

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

def hash_files(paths, relative_to):
    digest = hashlib.sha256()
    for path in sorted(paths):
        digest.update(str(path.relative_to(relative_to)).encode())
        digest.update(b"\0")
        with path.open("rb") as src:
            for chunk in iter(lambda: src.read(1024 * 1024), b""):
                digest.update(chunk)
    return digest.hexdigest()

def reference_cache_context(base_cc, e):
    version = subprocess.run(
        [base_cc, "--version"], env=e, capture_output=True, check=True
    ).stdout
    # 0713: 缓存的是【归一化之后】的函数体，所以缓存键必须包含归一化代码的指纹。
    # 此前只认编译器版本 —— 改了 cmpir.py 的归一化规则后，缓存里的 ref 仍是旧口径，
    # 与新口径现算的 self 对撞，量出鬼数字（差异从 994 虚增到 1251，方向完全相反）。
    norm_src = b""
    for f in ("cmpir.py", "bcgate.py"):
        try:
            norm_src += (pathlib.Path(__file__).resolve().parent / f).read_bytes()
        except OSError:
            pass
    return {
        "cangjie_home": str(pathlib.Path(CANGJIE_HOME).resolve()),
        "compiler_version_sha256": hashlib.sha256(version).hexdigest(),
        "normalizer_sha256": hashlib.sha256(norm_src).hexdigest(),
    }

def reference_cache_path(pkg, cache_context):
    source_root = ROOT / "packages" / pkg / "src"
    source_hash = hash_files((p for p in source_root.rglob("*") if p.is_file()), source_root)
    manifest = (ROOT / "packages" / pkg / "cjpm.toml").read_text(encoding="utf-8")
    dependency_section = manifest.partition("[dependencies]")[2].partition("\n[")[0]
    dependencies = re.findall(r'^\s*"([^"]+)"\s*=', dependency_section, re.MULTILINE)
    cjo_paths = []
    for name in dependencies:
        organization, package = name.split("::", 1)
        dependency_dir = ROOT / "target/release" / f"{package}@{organization}"
        cjo_paths.extend(dependency_dir.glob("*.cjo"))
    import_hash = hash_files(cjo_paths, ROOT / "target/release")
    key_data = dict(
        cache_context, package=pkg, source_hash=source_hash, import_cjo_hash=import_hash
    )
    key = hashlib.sha256(json.dumps(key_data, sort_keys=True).encode()).hexdigest()
    return CACHE_DIR / f"{key}.json"

def emit_reference_funcs(base_cc, pkg, workdir, e, timeout, cache_context):
    if cache_context is None:
        return emit_pkg_funcs(base_cc, pkg, workdir, e, timeout)
    try:
        cache_path = reference_cache_path(pkg, cache_context)
        with cache_path.open(encoding="utf-8") as src:
            return json.load(src), None
    except FileNotFoundError:
        pass
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        return emit_pkg_funcs(base_cc, pkg, workdir, e, timeout)
    funcs, error = emit_pkg_funcs(base_cc, pkg, workdir, e, timeout)
    if funcs is not None:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        temporary = cache_path.with_suffix(f".{os.getpid()}.tmp")
        with temporary.open("w", encoding="utf-8") as dst:
            json.dump(funcs, dst, sort_keys=True, separators=(",", ":"))
        os.replace(temporary, cache_path)
    return funcs, error

def compile_pkg(base_cc, self_cc, pkg, workdir, e, timeout, cache_context):
    with ThreadPoolExecutor(max_workers=2) as pool:
        ref = pool.submit(emit_reference_funcs, base_cc, pkg, workdir / f"ref_{pkg}", e, timeout, cache_context)
        selfhost = pool.submit(emit_pkg_funcs, self_cc, pkg, workdir / f"self_{pkg}", e, timeout)
        return ref.result(), selfhost.result()

def main():
    args = sys.argv[1:]
    self_cc_candidates = sorted((ROOT / "target/release/bin").glob("*::cjc")) if (ROOT / "target/release/bin").exists() else []
    self_cc = str(self_cc_candidates[0]) if self_cc_candidates else str(ROOT / "target/release/bin/cjcj::cjc")
    base_cc = f"{CANGJIE_HOME}/bin/cjc"; timeout = 600; jobs = 1; use_cache = True; pkgs = []
    i = 0
    while i < len(args):
        if args[i] == "--self": self_cc = args[i+1]; i += 2
        elif args[i] == "--timeout": timeout = int(args[i+1]); i += 2
        elif args[i] == "--jobs": jobs = int(args[i+1]); i += 2
        elif args[i] == "--no-cache": use_cache = False; i += 1
        else: pkgs.append(args[i]); i += 1
    if not pkgs:
        print("usage: sc_bcgate.py <pkg> [...]"); return 2
    if jobs < 1:
        print("--jobs must be at least 1", file=sys.stderr); return 2
    e = env(); wd = pathlib.Path(tempfile.mkdtemp(prefix="sc_bcgate_"))
    try:
        return _run(base_cc, self_cc, pkgs, wd, e, timeout, jobs, use_cache)
    finally:
        # 0713: 此前从不清理，169 个残留目录堆积 47G 撑爆根分区（lane 门跑到一半报 No space left on device）。
        # 需要保留失败现场时设 SC_BCGATE_KEEP_TMP=1。
        if os.environ.get("SC_BCGATE_KEEP_TMP") == "1":
            print(f"[sc_bcgate] kept temp dir: {wd}", file=sys.stderr)
        else:
            shutil.rmtree(wd, ignore_errors=True)


def _run(base_cc, self_cc, pkgs, wd, e, timeout, jobs, use_cache):
    cache_context = reference_cache_context(base_cc, e) if use_cache else None
    tot_id = tot_diff = tot_shared = 0
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        results = list(pool.map(
            lambda pkg: compile_pkg(base_cc, self_cc, pkg, wd, e, timeout, cache_context), pkgs
        ))
    for pkg, ((rf, rerr), (sf, serr)) in zip(pkgs, results):
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
