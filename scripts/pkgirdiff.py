#!/usr/bin/env python3
"""pkgirdiff.py - package-level selfhost/reference LLVM IR comparer.

Compile the same selfhost package with a reference cjc and a candidate selfhost
cjc, rescue emitted package modules even when compilation fails, and compare the
resulting LLVM IR by mangled function name instead of by round-robin module
number.
"""
import argparse
import difflib
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from cmpir import normalize as cmpir_normalize  # noqa: E402

CANGJIE_HOME = os.environ.get(
    "CANGJIE_HOME", "/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029"
)
DEFAULT_BASE = f"{CANGJIE_HOME}/bin/cjc"
DIS = f"{CANGJIE_HOME}/third_party/llvm/bin/llvm-dis"

_DEFNAME = re.compile(r'define[^@]*@("[^"]+"|[^ (]+)')
_TYPEDEF = re.compile(r'^(%("[^"]+"|[-A-Za-z0-9_.$]+)) = type (.+)$')
_LABEL_DEF = re.compile(r"^([A-Za-z0-9_.$-]+):")
_LOCAL_TOKEN = re.compile(r'%"[^"]+"|%[A-Za-z0-9_.$-]+')
_LABEL_REF = re.compile(r"label %([A-Za-z0-9_.$-]+)")
_HASHGLOBAL = re.compile(
    r'(@"?\$?(?:const_cjstring|const|lambda|Cl|env)[A-Za-z0-9_.$]*?)[.+][A-Za-z0-9_+/-]{6,}("?)'
)
_CALL = re.compile(r'\b(?:call|invoke)\b[^@]*@("[^"]+"|[\w.$:]+)')
_TYPE_TOKEN = re.compile(
    r'%"[^"]+"|%[A-Z][A-Za-z0-9_.$-]*|%struct\.[A-Za-z0-9_.$-]+|%enum\.[A-Za-z0-9_.$-]+|'
    r'\b(?:void|half|float|double|fp128|x86_fp80|ppc_fp128|label|metadata|token|i\d+)\b'
)
_ASSIGN = re.compile(r"^\s*(?:%" + r'[A-Za-z0-9_.$-]+' + r'|%"[^"]+")\s*=\s*')
_OPCODE = re.compile(
    r"^\s*(?:(?:tail|musttail|notail|fast|cold|cc|ccc|fastcc|zeroext|signext)\s+)*([a-z][a-z0-9_.]*)\b"
)


@dataclass
class FunctionIR:
    name: str
    module: str
    raw_lines: list[str]
    canon_lines: list[str] = field(default_factory=list)

    @property
    def body(self) -> str:
        return "\n".join(self.canon_lines)


@dataclass
class TypeDef:
    name: str
    definition: str
    module: str


@dataclass
class ModuleIR:
    path: Path
    display: str
    text: str
    lines: list[str]


@dataclass
class SideResult:
    label: str
    compiler: str
    rc: int
    command: list[str]
    stdout: str
    stderr: str
    work_dir: Path
    rescue_dir: Path
    saved_files: list[Path]
    artifact_count: int
    modules: list[ModuleIR] = field(default_factory=list)
    funcs: dict[str, FunctionIR] = field(default_factory=dict)
    type_defs: dict[str, TypeDef] = field(default_factory=dict)
    duplicate_funcs: dict[str, list[str]] = field(default_factory=dict)
    type_conflicts: dict[str, list[str]] = field(default_factory=dict)
    unreadable: list[tuple[str, str]] = field(default_factory=list)


@dataclass
class DiffItem:
    name: str
    kind: str
    detail: str
    score: int
    base: FunctionIR
    selfhost: FunctionIR


def build_env() -> dict[str, str]:
    env = dict(os.environ)
    env["CANGJIE_HOME"] = CANGJIE_HOME
    libs = [
        f"{CANGJIE_HOME}/third_party/llvm/lib",
        f"{CANGJIE_HOME}/runtime/lib/linux_x86_64_cjnative",
        f"{CANGJIE_HOME}/tools/lib",
        env.get("LD_LIBRARY_PATH", ""),
    ]
    env["LD_LIBRARY_PATH"] = ":".join(p for p in libs if p)
    env.setdefault("cjHeapSize", "16GB")
    return env


def resolve_tool(path: str) -> str:
    if "/" not in path:
        return path
    p = Path(path).expanduser()
    if not p.is_absolute():
        p = (Path.cwd() / p).resolve()
    return str(p)


def copy_tree_artifacts(src: Path, dst: Path) -> list[Path]:
    copied = []
    if not src.exists():
        return copied
    for path in src.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix not in (".bc", ".ll") and not path.name.endswith(".opt.bc"):
            continue
        rel = path.relative_to(src)
        out = dst / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        try:
            shutil.copy2(path, out)
            copied.append(out)
        except OSError:
            # A compiler worker may still be writing the file. The next poll,
            # or the final copy after process exit, will retry it.
            pass
    return copied


def rescue_artifacts(work_dir: Path, save_dir: Path, rescue_dir: Path) -> list[Path]:
    copied = []
    copied.extend(copy_tree_artifacts(save_dir, rescue_dir / "save-temps"))
    copied.extend(copy_tree_artifacts(work_dir / ".cached", rescue_dir / "cached"))
    return copied


def package_output_name(pkg: Path) -> str:
    parent = pkg.parent.name if pkg.name == "src" else pkg.name
    return parent or "package"


def run_compile(label: str, compiler: str, pkg: Path, root: Path, env: dict[str, str]) -> SideResult:
    work_dir = root / label / "work"
    save_dir = root / label / "save"
    rescue_dir = root / label / "rescued"
    out_dir = root / label / "out"
    for d in (work_dir, save_dir, rescue_dir, out_dir):
        d.mkdir(parents=True, exist_ok=True)

    out_base = out_dir / f"lib{package_output_name(pkg)}.a"
    command = [
        compiler,
        "--package",
        str(pkg),
        "--module-name",
        "cangjie_compiler",
        "--import-path",
        str(REPO / "target/release"),
        "--output-type=staticlib",
        "--save-temps",
        str(save_dir),
        "-o",
        str(out_base),
    ]

    stdout_path = root / label / "compile.stdout"
    stderr_path = root / label / "compile.stderr"
    with stdout_path.open("w", encoding="utf-8", errors="replace") as stdout_file, stderr_path.open(
        "w", encoding="utf-8", errors="replace"
    ) as stderr_file:
        proc = subprocess.Popen(
            command,
            cwd=work_dir,
            env=env,
            stdout=stdout_file,
            stderr=stderr_file,
            text=True,
        )
        while proc.poll() is None:
            rescue_artifacts(work_dir, save_dir, rescue_dir)
            time.sleep(0.15)
        rc = proc.returncode

    rescued = rescue_artifacts(work_dir, save_dir, rescue_dir)
    stdout = stdout_path.read_text(encoding="utf-8", errors="replace")
    stderr = stderr_path.read_text(encoding="utf-8", errors="replace")
    artifact_count = len([p for p in rescue_dir.rglob("*") if p.is_file() and (p.suffix in (".bc", ".ll") or p.name.endswith(".opt.bc"))])
    return SideResult(
        label=label,
        compiler=compiler,
        rc=rc,
        command=command,
        stdout=stdout,
        stderr=stderr,
        work_dir=work_dir,
        rescue_dir=rescue_dir,
        saved_files=rescued,
        artifact_count=artifact_count,
    )


def select_preopt_inputs(rescue_dir: Path) -> list[Path]:
    for root in (rescue_dir / "save-temps", rescue_dir / "cached"):
        if not root.exists():
            continue
        bcs = sorted(p for p in root.rglob("*.bc") if not p.name.endswith(".opt.bc"))
        if bcs:
            return bcs
    return sorted(p for p in rescue_dir.rglob("*.ll") if ".opt." not in p.name)


def disassemble(path: Path) -> tuple[str | None, str | None]:
    if path.suffix == ".ll":
        try:
            return path.read_text(encoding="utf-8", errors="replace"), None
        except OSError as exc:
            return None, str(exc)
    run = subprocess.run([DIS, str(path), "-o", "-"], capture_output=True, text=True)
    if run.returncode == 0:
        return run.stdout, None
    ll = path.with_suffix(".ll")
    if ll.exists():
        try:
            return ll.read_text(encoding="utf-8", errors="replace"), None
        except OSError:
            pass
    err = (run.stderr or run.stdout or "llvm-dis failed").strip()
    return None, err.splitlines()[-1] if err else "llvm-dis failed"


def extract_functions(module: ModuleIR) -> list[FunctionIR]:
    funcs = []
    cur = None
    name = None
    for line in module.lines:
        if line.startswith("define "):
            m = _DEFNAME.match(line)
            name = m.group(1) if m else line
            cur = [line]
            continue
        if cur is not None:
            cur.append(line)
            if line == "}":
                funcs.append(FunctionIR(name=name or "<unknown>", module=module.display, raw_lines=cur))
                cur = None
                name = None
    return funcs


def extract_type_defs(module: ModuleIR) -> list[TypeDef]:
    out = []
    for line in module.lines:
        m = _TYPEDEF.match(line)
        if not m:
            continue
        out.append(TypeDef(name=m.group(1), definition=line, module=module.display))
    return out


def load_side_ir(side: SideResult) -> None:
    for path in select_preopt_inputs(side.rescue_dir):
        text, err = disassemble(path)
        display = str(path.relative_to(side.rescue_dir))
        if text is None:
            side.unreadable.append((display, err or "unreadable module"))
            continue
        lines = cmpir_normalize(text)
        module = ModuleIR(path=path, display=display, text=text, lines=lines)
        side.modules.append(module)

        for ty in extract_type_defs(module):
            prev = side.type_defs.get(ty.name)
            if prev is None:
                side.type_defs[ty.name] = ty
            elif prev.definition != ty.definition:
                side.type_conflicts.setdefault(ty.name, [prev.module]).append(ty.module)

        for fn in extract_functions(module):
            prev = side.funcs.get(fn.name)
            if prev is None:
                side.funcs[fn.name] = fn
            elif prev.raw_lines != fn.raw_lines:
                side.duplicate_funcs.setdefault(fn.name, [prev.module]).append(fn.module)


def normalize_global_hashes(line: str) -> str:
    # Matches cmpir.py's volatile compiler-generated globals. Package diffs see
    # these frequently because each module owns its own string/global hash.
    return _HASHGLOBAL.sub(lambda m: m.group(1) + ".H" + (m.group(2) or ""), line)


def canonicalize_function(lines: list[str], known_types: set[str]) -> list[str]:
    names: dict[str, str] = {}
    labels: dict[str, str] = {}
    value_i = 0
    label_i = 0

    def local_token(match: re.Match[str]) -> str:
        nonlocal value_i
        token = match.group(0)
        if token in known_types:
            return token
        if token.startswith('%"'):
            # Quoted percent names in this IR are overwhelmingly named LLVM
            # types. Keeping them visible prevents hiding layout divergences.
            return token
        if token not in names:
            value_i += 1
            names[token] = f"%v{value_i}"
        return names[token]

    def label_ref(match: re.Match[str]) -> str:
        nonlocal label_i
        name = match.group(1)
        if name not in labels:
            label_i += 1
            labels[name] = f"L{label_i}"
        return "label %" + labels[name]

    out = []
    for line in lines:
        line = normalize_global_hashes(line)
        m = _LABEL_DEF.match(line)
        if m:
            label = m.group(1)
            if label not in labels:
                label_i += 1
                labels[label] = f"L{label_i}"
            line = labels[label] + ":" + line[m.end():]
        line = _LABEL_REF.sub(label_ref, line)
        line = _LOCAL_TOKEN.sub(local_token, line)
        out.append(line)
    return out


def canonicalize_side(side: SideResult, known_types: set[str]) -> None:
    for fn in side.funcs.values():
        fn.canon_lines = canonicalize_function(fn.raw_lines, known_types)


def opcode_seq(lines: list[str]) -> list[str]:
    ops = []
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped in ("{", "}") or stripped.startswith("define "):
            continue
        if _LABEL_DEF.match(stripped):
            continue
        inst = _ASSIGN.sub("", stripped)
        m = _OPCODE.match(inst)
        if m:
            ops.append(m.group(1))
    return ops


def type_seq(lines: list[str]) -> list[str]:
    out = []
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped == "}" or _LABEL_DEF.match(stripped):
            continue
        out.extend(_TYPE_TOKEN.findall(stripped))
    return out


def call_seq(body: str) -> list[str]:
    return _CALL.findall(body)


def diff_score(a: list[str], b: list[str]) -> int:
    score = abs(len(a) - len(b))
    score += sum(1 for left, right in zip(a, b) if left != right)
    return score


def classify(base: FunctionIR, selfhost: FunctionIR) -> tuple[str, str]:
    base_ops = opcode_seq(base.canon_lines)
    self_ops = opcode_seq(selfhost.canon_lines)
    if len(base_ops) != len(self_ops):
        return "FUNCTIONAL", f"instr-count self-base={len(self_ops) - len(base_ops):+d} (base {len(base_ops)} self {len(self_ops)})"
    if base_ops != self_ops:
        return "FUNCTIONAL", "opcode-sequence differs"
    base_types = type_seq(base.canon_lines)
    self_types = type_seq(selfhost.canon_lines)
    if base_types != self_types:
        return "FUNCTIONAL", "type-sequence differs"
    base_calls = call_seq(base.body)
    self_calls = call_seq(selfhost.body)
    if base_calls != self_calls and set(base_calls) == set(self_calls) and len(base_calls) == len(self_calls):
        return "COSMETIC", "call order/name-only difference after structural match"
    return "COSMETIC", "same instr/opcode/type shape; operand or name difference"


def compare_functions(base: SideResult, selfhost: SideResult, func_filter: str) -> tuple[list[str], list[DiffItem], set[str], set[str]]:
    base_names = set(base.funcs)
    self_names = set(selfhost.funcs)
    if func_filter:
        base_names = {n for n in base_names if func_filter in n}
        self_names = {n for n in self_names if func_filter in n}
    shared = sorted(base_names & self_names)
    diffs: list[DiffItem] = []
    for name in shared:
        left = base.funcs[name]
        right = selfhost.funcs[name]
        if left.body == right.body:
            continue
        kind, detail = classify(left, right)
        diffs.append(DiffItem(name=name, kind=kind, detail=detail, score=diff_score(left.canon_lines, right.canon_lines), base=left, selfhost=right))
    return shared, diffs, base_names - self_names, self_names - base_names


def compare_types(base: SideResult, selfhost: SideResult) -> tuple[list[str], set[str], set[str]]:
    shared = sorted(set(base.type_defs) & set(selfhost.type_defs))
    differing = [name for name in shared if base.type_defs[name].definition != selfhost.type_defs[name].definition]
    return differing, set(base.type_defs) - set(selfhost.type_defs), set(selfhost.type_defs) - set(base.type_defs)


def print_compile_status(side: SideResult) -> None:
    print(
        f"{side.label}: rc={side.rc} rescued_artifacts={side.artifact_count} "
        f"preopt_inputs={len(select_preopt_inputs(side.rescue_dir))} readable_modules={len(side.modules)} "
        f"unreadable_modules={len(side.unreadable)}"
    )
    if side.rc != 0:
        print(f"-- {side.label} compiler stderr --")
        err = side.stderr.strip() or side.stdout.strip() or "<no compiler output>"
        print(err)


def print_type_report(base: SideResult, selfhost: SideResult, top: int) -> tuple[int, int, int]:
    differing, base_only, self_only = compare_types(base, selfhost)
    print(
        f"\n-- named type definitions: shared={len(set(base.type_defs) & set(selfhost.type_defs))} "
        f"differing={len(differing)} base_only={len(base_only)} self_only={len(self_only)}"
    )
    limit = top if top > 0 else len(differing)
    for name in differing[:limit]:
        b = base.type_defs[name]
        s = selfhost.type_defs[name]
        print(f"TYPE-DIFF {name}")
        print(f"  base {b.module}: {b.definition}")
        print(f"  self {s.module}: {s.definition}")
    if len(differing) > limit:
        print(f"  ... {len(differing) - limit} more type diffs omitted by --top")
    return len(differing), len(base_only), len(self_only)


def print_single_side(label: str, names: set[str], funcs: dict[str, FunctionIR], top: int) -> None:
    if not names:
        return
    grouped: dict[str, list[str]] = defaultdict(list)
    for name in sorted(names):
        grouped[funcs[name].module].append(name)
    print(f"\n-- {label} functions by module ({len(names)} total)")
    per_module = top if top > 0 else max(len(v) for v in grouped.values())
    for module in sorted(grouped):
        vals = grouped[module]
        print(f"[{len(vals)}] {module}")
        for name in vals[:per_module]:
            print(f"  {name}")
        if len(vals) > per_module:
            print(f"  ... {len(vals) - per_module} more omitted by --top")


def print_unreadable(side: SideResult, top: int) -> None:
    if not side.unreadable:
        return
    limit = top if top > 0 else len(side.unreadable)
    print(f"\n-- {side.label} unreadable rescued modules ({len(side.unreadable)})")
    for module, err in side.unreadable[:limit]:
        print(f"  {module}: {err}")
    if len(side.unreadable) > limit:
        print(f"  ... {len(side.unreadable) - limit} more omitted by --top")


def print_duplicate_report(side: SideResult, top: int) -> None:
    if not side.duplicate_funcs and not side.type_conflicts:
        return
    print(f"\n-- {side.label} internal duplicate/conflict notes")
    for i, (name, modules) in enumerate(sorted(side.duplicate_funcs.items())):
        if top > 0 and i >= top:
            print(f"  ... {len(side.duplicate_funcs) - top} more duplicate functions omitted by --top")
            break
        shown = ", ".join(modules[:3])
        suffix = f", ... {len(modules) - 3} more" if len(modules) > 3 else ""
        print(f"  DUP-FUNC {name}: {len(modules)} modules ({shown}{suffix})")
    for i, (name, modules) in enumerate(sorted(side.type_conflicts.items())):
        if top > 0 and i >= top:
            print(f"  ... {len(side.type_conflicts) - top} more type conflicts omitted by --top")
            break
        shown = ", ".join(modules[:3])
        suffix = f", ... {len(modules) - 3} more" if len(modules) > 3 else ""
        print(f"  TYPE-CONFLICT {name}: {len(modules)} modules ({shown}{suffix})")


def print_diff_items(diffs: list[DiffItem], top: int) -> None:
    if not diffs:
        return
    ranked = sorted(diffs, key=lambda d: (-d.score, d.kind, d.name))
    limit = top if top > 0 else len(ranked)
    print(f"\n-- top differing shared functions ({min(limit, len(ranked))}/{len(ranked)})")
    for item in ranked[:limit]:
        print(
            f"{item.kind:<10} score={item.score:<5} base={item.base.module} "
            f"self={item.selfhost.module} {item.name}  {item.detail}"
        )


def print_unified_diffs(diffs: list[DiffItem]) -> None:
    if not diffs:
        return
    print("\n-- canonicalized unified diffs")
    for item in sorted(diffs, key=lambda d: d.name):
        print(f"\n===== {item.name} [{item.kind}: {item.detail}] =====")
        diff = difflib.unified_diff(
            item.base.canon_lines,
            item.selfhost.canon_lines,
            fromfile=f"base/{item.base.module}",
            tofile=f"self/{item.selfhost.module}",
            lineterm="",
        )
        print("\n".join(diff))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pkg", required=True, help="package src directory, e.g. packages/basic/src")
    ap.add_argument("--self", dest="self_cjc", required=True, help="selfhost cjc path")
    ap.add_argument("--base", default=DEFAULT_BASE, help="reference cjc path (default: $CANGJIE_HOME/bin/cjc)")
    ap.add_argument("--func", default="", help="mangled-name substring filter")
    ap.add_argument("--diff", action="store_true", help="print canonicalized unified diffs for filtered differing functions")
    ap.add_argument("--top", type=int, default=20, help="number of largest diffs/items to show (0 means all)")
    ap.add_argument("--keep-temps", action="store_true", help="keep rescued bitcode/IR temp directory")
    args = ap.parse_args()

    pkg = Path(args.pkg).expanduser()
    if not pkg.is_absolute():
        pkg = (Path.cwd() / pkg).resolve()
    if not pkg.is_dir():
        print(f"error: package directory does not exist: {pkg}", file=sys.stderr)
        return 2

    base_cjc = resolve_tool(args.base)
    self_cjc = resolve_tool(args.self_cjc)
    env = build_env()

    temp_root = Path(tempfile.mkdtemp(prefix="pkgirdiff-"))
    try:
        base = run_compile("base", base_cjc, pkg, temp_root, env)
        selfhost = run_compile("self", self_cjc, pkg, temp_root, env)

        load_side_ir(base)
        load_side_ir(selfhost)
        known_types = set(base.type_defs) | set(selfhost.type_defs)
        canonicalize_side(base, known_types)
        canonicalize_side(selfhost, known_types)

        print(f"pkgirdiff package={pkg}")
        print(f"base_cjc={base_cjc}")
        print(f"self_cjc={self_cjc}")
        if args.keep_temps:
            print(f"temps={temp_root}")
        print_compile_status(base)
        print_compile_status(selfhost)

        if base.artifact_count == 0 or selfhost.artifact_count == 0:
            print(
                f"PKGIRDIFF base_funcs={len(base.funcs)} self_funcs={len(selfhost.funcs)} "
                "shared=0 byte-identical=0 differing=0 base-only=0 self-only=0"
            )
            print("error: at least one side produced no rescued .bc/.ll artifacts")
            return 2

        shared, diffs, base_only, self_only = compare_functions(base, selfhost, args.func)
        identical = len(shared) - len(diffs)
        functional = sum(1 for d in diffs if d.kind == "FUNCTIONAL")
        cosmetic = sum(1 for d in diffs if d.kind == "COSMETIC")
        print(
            f"PKGIRDIFF base_funcs={len(base.funcs)} self_funcs={len(selfhost.funcs)} "
            f"shared={len(shared)} byte-identical={identical} differing={len(diffs)} "
            f"functional={functional} cosmetic={cosmetic} base-only={len(base_only)} self-only={len(self_only)}"
            + (f" filter={args.func!r}" if args.func else "")
        )

        print_unreadable(base, args.top)
        print_unreadable(selfhost, args.top)
        print_duplicate_report(base, args.top)
        print_duplicate_report(selfhost, args.top)
        type_diff_count, base_type_only, self_type_only = print_type_report(base, selfhost, args.top)
        print_diff_items(diffs, args.top)
        print_single_side("base-only", base_only, base.funcs, args.top)
        print_single_side("self-only", self_only, selfhost.funcs, args.top)
        if args.diff:
            print_unified_diffs(diffs)

        changed = (
            base.rc != 0
            or selfhost.rc != 0
            or bool(base.unreadable)
            or bool(selfhost.unreadable)
            or bool(diffs)
            or bool(base_only)
            or bool(self_only)
            or type_diff_count
            or base_type_only
            or self_type_only
        )
        return 1 if changed else 0
    finally:
        if not args.keep_temps:
            shutil.rmtree(temp_root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
