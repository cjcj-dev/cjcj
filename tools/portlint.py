#!/usr/bin/env python3
"""Scan added Cangjie porting lines for review-proven translation traps.

Usage:
  portlint.py [base..HEAD] [--cpp path/to/source.cpp] [--repo PATH] [--waivers FILE]
  git diff base..HEAD | portlint.py --diff -

Output is TSV: file:line, rule, evidence, severity.  Only added lines are
examined, so existing debt is not reported as a new-port violation.
"""
import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

DEFAULT_CPP = Path("/root/cj_build/cangjie_compiler/src")
# Review provenance: R1 rv38/rv40; R2 rv37; R3/R4 rv49; R5 rv40;
# R6 identity ruling (0711 21:40); R7 getOrThrow silent-None risk; R8
# platform-branch completeness rule (TempFileManager rejection).
ANCHOR = re.compile(r"//\s*([^\s:]+\.cpp)(?::\d+(?:-\d+)?)?\s+([A-Za-z_]\w*)")
DECL = re.compile(r"^\s*(?:public\s+|private\s+|protected\s+|internal\s+)*(?:func|class)\s+(\w+)")
MAP_ASSIGN = re.compile(r"\b[\w.]+\s*\[[^\]]+\]\s*=")
OBJECT_ID = re.compile(r"\.objectId\s*(?:==|!=)")
INVALID_FALLBACK = re.compile(r"\?\?\s*(?:[\w.]*TypeManager\.)?GetInvalidTy\s*\(|\?\?[^\n]*\bInvalid\w*")
GET_OR_THROW = re.compile(r"\bgetOrThrow\s*\(")
THROW_ABORT = re.compile(r"\bthrow\s+(?:IllegalArgumentException|IllegalStateException)\b")
PLATFORM_CPP = re.compile(r"\b(?:_WIN32|__APPLE__|__OHOS__|__linux__)\b")
PLATFORM_CJ = re.compile(r"@When\s*\[")

@dataclass
class Added:
    path: str
    line: int
    text: str
    context: list
    function: str
    cpp_file: Path | None

def run(cmd, cwd=None, check=True):
    return subprocess.run(cmd, cwd=cwd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=check)

def read_diff(args, repo):
    if args.diff is not None:
        return sys.stdin.read() if args.diff == "-" else Path(args.diff).read_text()
    return run(["git", "diff", "--no-ext-diff", "--unified=12", args.range], cwd=repo).stdout

def cpp_for(name, root, explicit):
    if explicit:
        return explicit
    found = list(root.rglob(name))
    return found[0] if len(found) == 1 else None

def added_lines(diff, cpp_root, explicit_cpp):
    out, path, new_line, context, function, source = [], None, 0, [], "", None
    for raw in diff.splitlines():
        if raw.startswith("+++ b/"):
            candidate = raw[6:]
            path = candidate if candidate.endswith(".cj") else None
            new_line, context, function, source = 0, [], "", None
            continue
        if raw.startswith("@@"):
            m = re.search(r"\+(\d+)(?:,\d+)?", raw)
            new_line = int(m.group(1)) if m else 0
            continue
        if path is None or raw.startswith(("diff ", "index ", "--- ")):
            continue
        if raw.startswith("+"):
            text = raw[1:]
            anchor = ANCHOR.search(text)
            if anchor:
                source = cpp_for(anchor.group(1), cpp_root, explicit_cpp)
                function = anchor.group(2)
            decl = DECL.match(text)
            if decl:
                function = decl.group(1)
            out.append(Added(path, new_line, text, context[-12:], function, source))
            context.append(text)
            new_line += 1
        elif raw.startswith(" "):
            text = raw[1:]
            anchor = ANCHOR.search(text)
            if anchor:
                source = cpp_for(anchor.group(1), cpp_root, explicit_cpp)
                function = anchor.group(2)
            decl = DECL.match(text)
            if decl:
                function = decl.group(1)
            context.append(text)
            new_line += 1
        elif raw.startswith("-"):
            continue
    return out

def cpp_function_body(cpp, function):
    if not cpp or not cpp.exists() or not function:
        return ""
    text = cpp.read_text(errors="replace")
    # Anchor comments name a method; its first mention can be a dispatch-table
    # entry.  The final mention in these translation units is the definition.
    start = text.rfind(function)
    if start < 0:
        return ""
    opening = text.find("{", start)
    if opening < 0:
        return ""
    depth = 0
    for end in range(opening, len(text)):
        if text[end] == "{":
            depth += 1
        elif text[end] == "}":
            depth -= 1
            if depth == 0:
                return text[start:end + 1]
    return text[start:]

def cpp_function_has(cpp, function, needle):
    return needle in cpp_function_body(cpp, function)

def is_map_assignment(text):
    """Conservative spelling gate: arrays/vectors are not HashMap indexing.

    Cangjie ported maps conventionally retain Map/Collection in their field
    names.  The check intentionally leaves ambiguous arbitrary names to human
    review rather than claiming an array write is an emplace translation.
    """
    m = MAP_ASSIGN.search(text)
    if not m:
        return False
    target = m.group(0).split("[")[0].rsplit(".", 1)[-1]
    return target.endswith("Map") or target.endswith("Collection")

def resize_target(text):
    m = re.search(r"\b\w+\.(\w+)\.(?:add|append)\s*\(", text)
    return m.group(1) if m else ""

def cpp_symbol_exists(name, root):
    r = run(["rg", "-l", "--fixed-strings", name, str(root)], check=False)
    return r.returncode == 0 and bool(r.stdout.strip())

def report(rows, item, rule, severity, evidence=None):
    rows.append((item.path, str(item.line), rule, severity, evidence or item.text.strip()))

def read_waivers(path):
    if path is None:
        return {}
    waivers = {}
    lines = path.read_text().splitlines()
    if not lines or lines[0].split("\t") != ["file:line", "rule", "reason"]:
        raise ValueError("waiver TSV header must be: file:line<TAB>rule<TAB>reason")
    for number, raw in enumerate(lines[1:], 2):
        if not raw.strip() or raw.startswith("#"):
            continue
        fields = raw.split("\t")
        if len(fields) != 3:
            raise ValueError(f"{path}:{number}: expected exactly three TSV columns")
        location, rule, reason = fields
        if not re.fullmatch(r"[^:\s]+(?:/[^:\s]+)*:\d+", location):
            raise ValueError(f"{path}:{number}: invalid file:line: {location}")
        if not re.search(r"C\+\+\s+[^\s]+\.cpp:\d+", reason):
            raise ValueError(f"{path}:{number}: reason lacks a C++ file:line anchor")
        key = (location, rule)
        if key in waivers:
            raise ValueError(f"{path}:{number}: duplicate waiver: {location} {rule}")
        waivers[key] = reason
    return waivers

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("range", nargs="?", default="HEAD", help="git diff range (default: HEAD, working tree)")
    ap.add_argument("--repo", default=".", help="repository containing the diff")
    ap.add_argument("--cpp", type=Path, help="C++ comparison file (enables exact platform count too)")
    ap.add_argument("--cpp-root", type=Path, default=DEFAULT_CPP)
    ap.add_argument("--diff", help="read a unified diff from this file, or '-' for stdin")
    ap.add_argument("--waivers", type=Path, help="reviewed TSV waivers: file:line, rule, C++-anchored reason")
    args = ap.parse_args()
    repo, cpp_root = Path(args.repo).resolve(), args.cpp_root.resolve()
    diff = read_diff(args, repo)
    rows = []
    items = added_lines(diff, cpp_root, args.cpp)
    for item in items:
        text = item.text
        if INVALID_FALLBACK.search(text):
            report(rows, item, "R1-invalid-fallback", "ERROR")
        if OBJECT_ID.search(text):
            report(rows, item, "R6-bare-objectId-identity", "ERROR")
        if GET_OR_THROW.search(text):
            report(rows, item, "R7-new-getOrThrow", "WARN")
        if THROW_ABORT.search(text) and cpp_function_has(item.cpp_file, item.function, "CJC_ABORT"):
            report(rows, item, "R5-throw-for-CJC_ABORT", "ERROR",
                   f"{text.strip()} | C++ {item.cpp_file.name}:{item.function} contains CJC_ABORT")
        decl = DECL.match(text)
        if decl and not cpp_symbol_exists(decl.group(1), cpp_root):
            report(rows, item, "R2-invented-symbol", "ERROR", decl.group(1))
        if is_map_assignment(text) and cpp_function_has(item.cpp_file, item.function, ".emplace("):
            report(rows, item, "R3-map-overwrite-vs-emplace", "WARN",
                   f"{text.strip()} | C++ {item.cpp_file.name}:{item.function} uses emplace")
        target = resize_target(text)
        if target and re.search(rf"(?:->|\.){re.escape(target)}\.resize\s*\(",
                                cpp_function_body(item.cpp_file, item.function)):
            report(rows, item, "R4-append-vs-resize-index", "WARN",
                   f"{text.strip()} | C++ {item.cpp_file.name}:{item.function} resizes {target}")
    if args.cpp:
        cpp_count = len(PLATFORM_CPP.findall(args.cpp.read_text(errors="replace")))
        cj_count = sum(1 for item in items if PLATFORM_CJ.search(item.text))
        if cpp_count > cj_count:
            pseudo = Added(str(args.cpp), 1, "@When count comparison", [], "", args.cpp)
            report(rows, pseudo, "R8-platform-branch-count", "ERROR",
                   f"C++ macro directives/tokens={cpp_count}; added @When branches={cj_count}")
    try:
        waivers = read_waivers(args.waivers)
    except (OSError, ValueError) as error:
        print(f"portlint: {error}", file=sys.stderr)
        return 2
    used = set()
    waived_rows = []
    for path, line, rule, severity, evidence in rows:
        location = f"{path}:{line}"
        key = (location, rule)
        if severity == "ERROR" and key in waivers:
            used.add(key)
            waived_rows.append((path, line, rule, "INFO", f"{evidence} | WAIVED: {waivers[key]}"))
        else:
            waived_rows.append((path, line, rule, severity, evidence))
    unused = set(waivers) - used
    if unused:
        for location, rule in sorted(unused):
            print(f"portlint: unused waiver: {location} {rule}", file=sys.stderr)
        return 2
    rows = waived_rows
    print("file:line\trule\tevidence\tseverity")
    for row in rows:
        location = f"{row[0]}:{row[1]}"
        print("\t".join(x.replace("\t", " ") for x in (location, row[2], row[4], row[3])))
    errors = sum(row[3] == "ERROR" for row in rows)
    warns = sum(row[3] == "WARN" for row in rows)
    infos = sum(row[3] == "INFO" for row in rows)
    print(f"SUMMARY\t-\t-\t-\tERROR={errors} WARN={warns} INFO={infos}", file=sys.stderr)
    return 1 if errors else 0

if __name__ == "__main__":
    raise SystemExit(main())
