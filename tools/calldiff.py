#!/usr/bin/env python3
"""Diff direct LLVM-IR callee multisets for matching mangled functions.

Both reference C++ cjc and selfhost cjc emit the same Cangjie ABI mangling, so
the function definition symbol and every direct ``call``/``invoke`` target are
already comparable.  This intentionally works below source syntax and needs
neither a C++→Cangjie dictionary nor a source parser.

Inputs may be a .ll file, a .bc file, or a directory recursively containing
saved ``.bc``/``.ll`` files from sc_bcgate.  Bitcode is disassembled with
llvm-dis.  ``missing_calls`` is reference-minus-self; ``extra_calls`` is
self-minus-reference.  Values use ``symbol*count`` when a target repeats.

Examples:
  python3 tools/calldiff.py --ref /tmp/sc_bcgate/ref_codegen --self /tmp/sc_bcgate/self_codegen \
    --check-identical 3 --top 30 --output reports/CALLDIFF_CODEGEN_0712.tsv
  python3 tools/calldiff.py --ref ref.ll --self self.ll --output /tmp/calls.tsv
"""
from __future__ import annotations

import argparse
import csv
import re
import subprocess
from collections import Counter
from pathlib import Path

DEFAULT_LLVM_DIS = Path("/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029/third_party/llvm/bin/llvm-dis")
DEFINE = re.compile(r'^define\b.*?@(?:"(?P<quoted>[^"]+)"|(?P<plain>[-$._A-Za-z0-9]+))\s*\(', re.M)
# Direct calls only. Indirect calls have no @symbol and are intentionally not
# guessed; their count is separately exposed in the TSV.
DIRECT_CALL = re.compile(r'\b(?:call|invoke)\b(?:(?!\b(?:call|invoke)\b).)*?@(?:"(?P<quoted>[^"]+)"|(?P<plain>[-$._A-Za-z0-9]+))\s*\(', re.S)
ANY_CALL = re.compile(r'\b(?:call|invoke)\b')
# Same normalization contract as scripts/cmpir.py and sc_bcgate: debug and
# attribute noise, local SSA names, block labels, and volatile generated-global
# hash suffixes are not a semantic function difference.
DROP_LINE = re.compile(r"^(;|![0-9]|source_filename|target |attributes #)")
SUBS = [(re.compile(r",? ?!dbg ![0-9]+"), ""), (re.compile(r", ![a-zA-Z.]+ ![0-9]+"), ""),
        (re.compile(r" #[0-9]+ "), " "), (re.compile(r"\s{2,};"), " ;"),
        (re.compile(r"[ \t]*,?[ \t]*$"), "")]
LOCAL = re.compile(r"%[A-Za-z0-9_.$]+|%\"[^\"]+\"")
LABEL = re.compile(r"^([A-Za-z0-9_.$]+):")
HASHGLOBAL = re.compile(r"(@\"?\$?(?:const_cjstring|const|lambda|Cl|env)[A-Za-z0-9_.$]*?)[.+][A-Za-z0-9_+/-]{6,}(\"?)")


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--ref", type=Path, required=True, help="reference .ll/.bc or saved-temps directory")
    ap.add_argument("--self", dest="self_path", type=Path, required=True, help="selfhost .ll/.bc or saved-temps directory")
    ap.add_argument("--llvm-dis", type=Path, default=DEFAULT_LLVM_DIS)
    ap.add_argument("--top", type=int, default=0, help="write only top N nonzero call-set diffs (0=all)")
    ap.add_argument("--check-identical", type=int, default=0, help="assert this many byte-identical function bodies have zero call diff")
    ap.add_argument("--output", type=Path, required=True)
    return ap.parse_args()


def inputs(path: Path) -> list[Path]:
    if path.is_file():
        return [path]
    # sc_bcgate keeps both .bc and .opt.bc. The latter is an optimization
    # derivative, not the compiler output used by its function comparison.
    return [p for p in sorted(path.rglob("*")) if p.suffix in {".ll", ".bc"} and not p.name.endswith(".opt.bc")]


def ir_text(path: Path, llvm_dis: Path) -> str:
    if path.suffix == ".ll":
        return path.read_text(errors="replace")
    result = subprocess.run([str(llvm_dis), str(path), "-o", "-"], text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"llvm-dis failed for {path}: {result.stderr.strip()}")
    return result.stdout


def function_bodies(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for match in DEFINE.finditer(text):
        open_brace = text.find("{", match.end())
        if open_brace < 0:
            continue
        depth = 0
        for end in range(open_brace, len(text)):
            if text[end] == "{":
                depth += 1
            elif text[end] == "}":
                depth -= 1
                if depth == 0:
                    name = match.group("quoted") or match.group("plain")
                    result[name] = text[match.start():end + 1]
                    break
    return result


def normalize(text: str) -> list[str]:
    out = []
    for line in text.splitlines():
        if DROP_LINE.match(line):
            continue
        for pattern, replacement in SUBS:
            line = pattern.sub(replacement, line)
        out.append(line)
    return out


def canonicalize(lines: list[str]) -> list[str]:
    out, names, labels, next_name, next_label = [], {}, {}, [0], [0]
    def local(match):
        key = match.group(0)
        if key not in names:
            next_name[0] += 1; names[key] = f"%v{next_name[0]}"
        return names[key]
    for line in lines:
        if line.startswith("define "):
            names, labels, next_name, next_label = {}, {}, [0], [0]
        line = HASHGLOBAL.sub(lambda m: m.group(1) + ".H" + (m.group(2) or ""), line)
        label = LABEL.match(line)
        if label:
            key = label.group(1)
            if key not in labels:
                next_label[0] += 1; labels[key] = f"L{next_label[0]}"
            line = labels[key] + ":" + line[label.end():]
        line = re.sub(r"label %([A-Za-z0-9_.$]+)", lambda m: "label %" + labels.setdefault(
            m.group(1), f"L{(next_label.__setitem__(0, next_label[0] + 1) or next_label[0])}"), line)
        out.append(LOCAL.sub(local, line))
    return out


def load_functions(path: Path, llvm_dis: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    files = inputs(path)
    if not files:
        raise RuntimeError(f"no .ll/.bc inputs under {path}")
    for item in files:
        # Mangle names are globally unique within a package; if a malformed
        # archive repeats one, retain the final TU exactly as sc_bcgate does.
        result.update(function_bodies("\n".join(canonicalize(normalize(ir_text(item, llvm_dis))))))
    return result


def callees(body: str) -> tuple[Counter[str], int]:
    direct = Counter((m.group("quoted") or m.group("plain")) for m in DIRECT_CALL.finditer(body))
    return direct, max(0, len(ANY_CALL.findall(body)) - sum(direct.values()))


def display(values: Counter[str]) -> str:
    return ";".join(name if count == 1 else f"{name}*{count}" for name, count in sorted(values.items()))


def row(name: str, ref_body: str, self_body: str) -> dict[str, object]:
    ref_calls, ref_indirect = callees(ref_body)
    self_calls, self_indirect = callees(self_body)
    missing, extra = ref_calls - self_calls, self_calls - ref_calls
    return {
        "func": name,
        "cpp_callees": display(ref_calls),
        "cj_callees": display(self_calls),
        "missing_calls": display(missing),
        "extra_calls": display(extra),
        "unmapped": "",  # IR symbols are already ABI-aligned; no mapping stage exists.
        "missing_count": sum(missing.values()),
        "extra_count": sum(extra.values()),
        "score": sum(missing.values()) + sum(extra.values()),
        "cpp_indirect_calls": ref_indirect,
        "cj_indirect_calls": self_indirect,
        "body_identical": int(ref_body == self_body),
    }


def main() -> int:
    args = parse_args()
    ref, selfhost = load_functions(args.ref, args.llvm_dis), load_functions(args.self_path, args.llvm_dis)
    shared = sorted(ref.keys() & selfhost.keys())
    rows = [row(name, ref[name], selfhost[name]) for name in shared]
    identical = [r for r in rows if r["body_identical"]]
    checked = identical[:args.check_identical]
    checked_pass = sum(r["score"] == 0 for r in checked)
    if args.check_identical and len(checked) < args.check_identical:
        raise RuntimeError(f"IDENTICAL_CHECK needs {args.check_identical}, found only {len(checked)}")
    if checked_pass != len(checked):
        raise RuntimeError(f"IDENTICAL_CHECK failed: PASS={checked_pass}/{len(checked)}")
    differing = [r for r in rows if not r["body_identical"]]
    suspects = [r for r in differing if r["score"]]
    suspects.sort(key=lambda r: (-int(r["score"]), -int(r["missing_count"]), -int(r["extra_count"]), str(r["func"])))
    output = suspects[:args.top] if args.top else suspects
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fields = ["func", "cpp_callees", "cj_callees", "missing_calls", "extra_calls", "unmapped", "missing_count", "extra_count", "score", "cpp_indirect_calls", "cj_indirect_calls", "body_identical"]
    with args.output.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t")
        writer.writeheader(); writer.writerows(output)
    print(f"CALLDIFF SHARED={len(shared)} BODY_DIFFERING={len(differing)} CALLEE_SUSPECTS={len(suspects)} TOP_WRITTEN={len(output)} IDENTICAL_CHECK={len(checked)} PASS={checked_pass} OUTPUT={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
