#!/usr/bin/env python3
"""Cluster package-level sc_bcgate function differences by their first IR divergence.

The input is a persistent work directory produced with the same layout as
``sc_bcgate.py`` (``ref_<pkg>/<compiler-hash>/*.bc`` and
``self_<pkg>/<compiler-hash>/*.bc``).  The output is a deterministic TSV with
one row per differing shared function.  This deliberately uses bcgate's exact
normalization so its row count is directly comparable with sc_bcgate's
``differing=`` total.

Example:
    python3 scripts/sc_diff_clusters.py /tmp/sc_bcgate_abcd \
        option conditional_compilation mangle -o SC_DIFF_FUNCTIONS.tsv
"""

import argparse
import difflib
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bcgate  # noqa: E402


CALL = re.compile(r'\b(?:call|invoke)\b[^@]*@("[^"]+"|[\w.$:]+)')
GLOBAL = re.compile(r'@("[^"]+"|[-\w.$:]+)')
INT = re.compile(r'(?<![A-Za-z0-9_])[-+]?\d+(?![A-Za-z0-9_])')
METADATA_ID = re.compile(r"(?P<prefix>,?\s*![A-Za-z_.][A-Za-z0-9_.]*\s+!)\d+")
METADATA_ATTACHMENT = re.compile(
    r",?\s*![A-Za-z_.][A-Za-z0-9_.]*\s+!(?:\d+|N)"
)
LABEL_LINE = re.compile(r"^L\d+:")
OPCODE = re.compile(
    r"^\s*(?:(?:tail|musttail|notail|fast|cold|cc|ccc|fastcc|zeroext|signext)\s+)*"
    r"([a-z][a-z0-9_.]*)\b"
)


def load_funcs(directory):
    chunks = []
    for bitcode in sorted(directory.glob("*.bc")):
        if bitcode.name.endswith(".opt.bc"):
            continue
        run = subprocess.run(
            [bcgate.DIS, str(bitcode), "-o", "-"], capture_output=True, text=True
        )
        if run.returncode:
            raise RuntimeError(f"llvm-dis failed for {bitcode}: {run.stderr.strip()}")
        chunks.append(run.stdout)

    funcs = {}
    current = None
    name = None
    for line in bcgate.norm_ir("\n".join(chunks)):
        if line.startswith("define "):
            match = bcgate._DEFNAME.match(line)
            name = match.group(1) if match else line
            current = [line]
        elif current is not None:
            current.append(line)
            if line == "}":
                funcs[name] = current
                current = None
    return funcs


def calls(lines):
    return [target for line in lines for target in CALL.findall(line)]


def opcode(line):
    stripped = re.sub(r'^\s*(?:%v\d+\s*=\s*)?', '', line)
    match = OPCODE.match(stripped)
    return match.group(1) if match else ""


def without_constants(line):
    return INT.sub("N", line)


def without_metadata_ids(line):
    return METADATA_ID.sub(r"\g<prefix>N", line)


def first_change(ref_lines, self_lines):
    matcher = difflib.SequenceMatcher(None, ref_lines, self_lines, autojunk=False)
    for tag, ref_start, ref_end, self_start, self_end in matcher.get_opcodes():
        if tag != "equal":
            ref_line = ref_lines[ref_start] if ref_start < ref_end else "<missing>"
            self_line = self_lines[self_start] if self_start < self_end else "<missing>"
            return tag, ref_line, self_line, ref_end - ref_start, self_end - self_start
    raise AssertionError("first_change called for identical functions")


def classify(ref_lines, self_lines):
    raw_tag, raw_ref_line, raw_self_line, _, _ = first_change(ref_lines, self_lines)
    semantic_ref = [without_metadata_ids(line) for line in ref_lines]
    semantic_self = [without_metadata_ids(line) for line in self_lines]

    def result(cluster, impact, tag, ref_line, self_line):
        return (
            cluster,
            impact,
            raw_tag,
            raw_ref_line,
            raw_self_line,
            tag,
            ref_line,
            self_line,
        )

    if semantic_ref == semantic_self:
        return result(
            "CG-METADATA-NUMBERING",
            "cosmetic",
            "equal",
            "<identical after metadata-number normalization>",
            "<identical after metadata-number normalization>",
        )

    tag, ref_line, self_line, _, _ = first_change(semantic_ref, semantic_self)
    ref_calls, self_calls = calls(ref_lines), calls(self_lines)

    if semantic_ref[0] != semantic_self[0]:
        if semantic_ref[0].split("{")[0].rstrip().endswith("unnamed_addr") != semantic_self[0].split("{")[0].rstrip().endswith("unnamed_addr"):
            return result("CG-FUNCTION-ATTRIBUTE", "cosmetic", tag, ref_line, self_line)
        return result("CG-FUNCTION-SIGNATURE", "functional", tag, ref_line, self_line)

    if ref_calls != self_calls:
        if Counter(ref_calls) == Counter(self_calls):
            return result("CG-CALL-ORDER", "functional", tag, ref_line, self_line)
        if len(self_calls) < len(ref_calls):
            return result("CG-MISSING-CALL", "functional", tag, ref_line, self_line)
        if len(self_calls) > len(ref_calls):
            return result("CG-EXTRA-CALL", "functional", tag, ref_line, self_line)
        return result("CG-CALL-TARGET", "functional", tag, ref_line, self_line)

    if tag == "delete":
        return result("CG-MISSING-INSTRUCTION", "functional", tag, ref_line, self_line)
    if tag == "insert":
        return result("CG-EXTRA-INSTRUCTION", "functional", tag, ref_line, self_line)

    if LABEL_LINE.match(ref_line) or LABEL_LINE.match(self_line):
        return result("CG-BLOCK-LAYOUT", "functional", tag, ref_line, self_line)

    ref_op, self_op = opcode(ref_line), opcode(self_line)
    if ref_op and self_op and ref_op != self_op:
        return result("CG-INSTRUCTION-SELECTION", "functional", tag, ref_line, self_line)

    if METADATA_ATTACHMENT.sub("", ref_line) == METADATA_ATTACHMENT.sub("", self_line):
        return result("CG-METADATA-ATTACHMENT", "functional", tag, ref_line, self_line)

    if "sret" in ref_line or "sret" in self_line:
        return result("CG-CALLSITE-ATTRIBUTE", "functional", tag, ref_line, self_line)

    if ref_op == "icmp" and self_op == "icmp":
        return result("CG-ICMP-PREDICATE", "functional", tag, ref_line, self_line)

    ref_globals, self_globals = GLOBAL.findall(ref_line), GLOBAL.findall(self_line)
    if ref_globals != self_globals:
        return result("CG-MANGLED-GLOBAL-REFERENCE", "functional", tag, ref_line, self_line)

    if without_constants(ref_line) == without_constants(self_line):
        return result("CG-CONSTANT", "functional", tag, ref_line, self_line)

    if ref_op == "phi" or self_op == "phi":
        return result("CG-PHI-OPERAND-ORDER", "cosmetic", tag, ref_line, self_line)
    if ref_op in ("br", "switch") or self_op in ("br", "switch"):
        return result("CG-BRANCH-OPERAND", "functional", tag, ref_line, self_line)
    if ref_op == "ret" or self_op == "ret":
        return result("CG-RETURN-OPERAND", "functional", tag, ref_line, self_line)
    return result("CG-OPERAND-OR-TYPE", "functional", tag, ref_line, self_line)


def side_directory(root, side, package):
    candidates = sorted((root / f"{side}_{package}").glob("*"))
    candidates = [path for path in candidates if path.is_dir()]
    if len(candidates) != 1:
        raise RuntimeError(
            f"expected one compiler-hash directory below {root / f'{side}_{package}'}, "
            f"found {len(candidates)}"
        )
    return candidates[0]


def clean(value):
    return value.replace("\t", "\\t").replace("\r", "\\r").replace("\n", "\\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("work_dir", type=Path)
    parser.add_argument("packages", nargs="+")
    parser.add_argument("-o", "--output", type=Path, required=True)
    args = parser.parse_args()

    rows = []
    package_totals = []
    for package in args.packages:
        ref = load_funcs(side_directory(args.work_dir, "ref", package))
        selfhost = load_funcs(side_directory(args.work_dir, "self", package))
        shared = sorted(set(ref) & set(selfhost))
        differing = [name for name in shared if ref[name] != selfhost[name]]
        package_totals.append((package, len(shared), len(differing)))
        for name in differing:
            (
                cluster,
                impact,
                raw_tag,
                raw_ref_line,
                raw_self_line,
                semantic_tag,
                semantic_ref_line,
                semantic_self_line,
            ) = classify(ref[name], selfhost[name])
            rows.append(
                (
                    package,
                    name,
                    cluster,
                    impact,
                    raw_tag,
                    raw_ref_line,
                    raw_self_line,
                    semantic_tag,
                    semantic_ref_line,
                    semantic_self_line,
                )
            )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as stream:
        stream.write(
            "package\tfunction\tcluster\timpact\traw_first_edit\traw_first_ref_ir\t"
            "raw_first_self_ir\tsemantic_first_edit\tsemantic_first_ref_ir\t"
            "semantic_first_self_ir\n"
        )
        for row in rows:
            stream.write("\t".join(clean(value) for value in row) + "\n")

    for package, shared, differing in package_totals:
        print(f"{package}: shared={shared} differing={differing}")
    print(f"TOTAL: differing={len(rows)} output={args.output}")
    for cluster, count in Counter(row[2] for row in rows).most_common():
        print(f"{count:5d}\t{cluster}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
