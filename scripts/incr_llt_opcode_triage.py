#!/usr/bin/env python3
"""Re-run incremental LLT text mismatches and compare cached-BC opcode multisets."""

import argparse
import csv
import os
import re
import shutil
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path


SUITE = Path("/root/cj_build/cangjie_test/testsuites/LLT")
FRAMEWORK = Path("/mnt/t/cj/cangjie_test_framework")
CONFIG = SUITE / "configs/cjnative/cjnative_test.cfg"
OPCODE = re.compile(
    r"^\s*(?:(?:tail|musttail|notail|fast|cold|cc|ccc|fastcc|zeroext|signext)\s+)*"
    r"([a-z][a-z0-9_.]*)\b"
)
ASSIGN = re.compile(r'^\s*(?:%[A-Za-z0-9_.$-]+|%"[^"]+")\s*=\s*')


def load_text_failures(path: Path) -> list[str]:
    with path.open(encoding="utf-8") as stream:
        rows = csv.DictReader(stream, delimiter="\t")
        return sorted(
            row["case"]
            for row in rows
            if row["status"] == "FAIL"
            and row["first_diagnostic"] == "SingleLine Compare Failed"
        )


def write_testlist(path: Path, cases: list[str]) -> None:
    with path.open("w", encoding="utf-8") as stream:
        stream.write("[ALL-TEST-CASE]\n")
        stream.writelines(case + "\n" for case in cases)
        stream.write("[EXCLUDE-TEST-CASE]\n")


def prepare_config(path: Path) -> None:
    text = CONFIG.read_text(encoding="utf-8")
    in_root = False
    lines = []
    for line in text.splitlines():
        if line.startswith("["):
            in_root = line.strip() == "[root]"
        if in_root and re.match(r"\s*path\s*=", line):
            line = f"path = {SUITE}"
        lines.append(line)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def run_side(
    label: str,
    compiler: Path,
    root: Path,
    config: Path,
    testlist: Path,
    jobs: int,
    timeout: int,
) -> tuple[int, Path]:
    side = root / label
    temp = side / "tmp"
    logs = side / "logs"
    temp.mkdir(parents=True)
    logs.mkdir(parents=True)
    result = side / "results.json"
    summary = side / "summary.txt"
    command = [
        sys.executable,
        str(FRAMEWORK / "main.py"),
        f"--test_cfg={config}",
        f"--test_list={testlist}",
        "--keep_temp",
        f"-j{jobs}",
        f"--timeout={timeout}",
        "--progress=no_flush_progress",
        f"--temp_dir={temp}",
        f"--log_dir={logs}",
        "--log_level=DEBUG",
        f"--output={summary}",
        f"--json_output={result}",
        "-C",
        f"compiler={compiler} -j1",
        "-C",
        f"cjc={compiler}",
        "-C",
        f"frontendCompiler={compiler} -j1",
        str(SUITE),
    ]
    print(f"RUN_SIDE={label} CASES={sum(1 for _ in testlist.read_text().splitlines()[1:-1])}", flush=True)
    run = subprocess.run(command, cwd=FRAMEWORK, env=os.environ.copy())
    return run.returncode, logs


def workdirs(logs: Path) -> dict[str, Path]:
    out = {}
    for log in logs.glob("*.log"):
        case = None
        work = None
        with log.open(encoding="utf-8", errors="replace") as stream:
            for line in stream:
                if "DEBUG Case Path: " in line:
                    case = line.split("DEBUG Case Path: ", 1)[1].strip()
                elif "DEBUG Work directory: " in line:
                    work = line.split("DEBUG Work directory: ", 1)[1].strip()
                if case is not None and work is not None:
                    break
        if case is not None and work is not None:
            out[Path(case).relative_to(SUITE).as_posix()] = Path(work)
    return out


def opcode_multiset(work: Path, llvm_dis: Path) -> tuple[Counter[str], list[Path], list[str]]:
    bitcodes = sorted(work.glob(".cached/*_cache.bc"))
    counts: Counter[str] = Counter()
    errors = []
    for bitcode in bitcodes:
        run = subprocess.run(
            [str(llvm_dis), str(bitcode), "-o", "-"], capture_output=True, text=True
        )
        if run.returncode != 0:
            errors.append(f"{bitcode.name}:{run.stderr.strip()}")
            continue
        in_function = False
        depth = 0
        for line in run.stdout.splitlines():
            if line.startswith("define "):
                in_function = True
                depth = line.count("{") - line.count("}")
                continue
            if not in_function:
                continue
            depth += line.count("{") - line.count("}")
            stripped = line.strip()
            if stripped and not stripped.endswith(":") and stripped != "}":
                match = OPCODE.match(ASSIGN.sub("", stripped))
                if match:
                    counts[match.group(1)] += 1
            if depth <= 0:
                in_function = False
    return counts, bitcodes, errors


def counter_delta(left: Counter[str], right: Counter[str]) -> str:
    keys = sorted(set(left) | set(right))
    parts = [f"{key}:{right[key] - left[key]:+d}" for key in keys if left[key] != right[key]]
    return ",".join(parts) if parts else "equal"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-cases", type=Path, required=True)
    parser.add_argument("--official", type=Path, required=True)
    parser.add_argument("--selfhost", type=Path, required=True)
    parser.add_argument("--llvm-dis", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--jobs", type=int, default=80)
    parser.add_argument("--timeout", type=int, default=240)
    args = parser.parse_args()

    cases = load_text_failures(args.self_cases)
    root = Path(tempfile.mkdtemp(prefix="incr_llt_opcode_"))
    print(f"WORK_ROOT={root} CASES={len(cases)}", flush=True)
    try:
        testlist = root / "testlist"
        config = root / "test.cfg"
        write_testlist(testlist, cases)
        prepare_config(config)
        official_rc, official_logs = run_side(
            "official", args.official, root, config, testlist, args.jobs, args.timeout
        )
        self_rc, self_logs = run_side(
            "selfhost", args.selfhost, root, config, testlist, args.jobs, args.timeout
        )
        official_work = workdirs(official_logs)
        self_work = workdirs(self_logs)
        counts = Counter()
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("w", encoding="utf-8", newline="") as stream:
            fields = ["case", "bucket", "evidence"]
            writer = csv.DictWriter(stream, fields, delimiter="\t", lineterminator="\n")
            writer.writeheader()
            for case in cases:
                off_dir = official_work.get(case)
                self_dir = self_work.get(case)
                if off_dir is None or self_dir is None:
                    bucket = "FUNCTIONAL_ARTIFACT_MISSING"
                    evidence = f"official_work={off_dir};selfhost_work={self_dir}"
                else:
                    off_ops, off_bc, off_errors = opcode_multiset(off_dir, args.llvm_dis)
                    self_ops, self_bc, self_errors = opcode_multiset(self_dir, args.llvm_dis)
                    if off_errors or self_errors or not off_bc or not self_bc:
                        bucket = "FUNCTIONAL_ARTIFACT_MISSING"
                    elif off_ops == self_ops:
                        bucket = "COSMETIC_OPCODE_MULTISET_EQUAL"
                    else:
                        bucket = "FUNCTIONAL_OPCODE_MULTISET_DIFF"
                    evidence = (
                        f"official_bc={len(off_bc)};selfhost_bc={len(self_bc)};"
                        f"official_opcodes={sum(off_ops.values())};selfhost_opcodes={sum(self_ops.values())};"
                        f"delta={counter_delta(off_ops, self_ops)};"
                        f"errors={'|'.join(off_errors + self_errors)}"
                    )
                writer.writerow({"case": case, "bucket": bucket, "evidence": evidence})
                counts[bucket] += 1
                if off_dir is not None:
                    shutil.rmtree(off_dir, ignore_errors=True)
                if self_dir is not None:
                    shutil.rmtree(self_dir, ignore_errors=True)
        print(f"OFFICIAL_MAPLE_RC={official_rc} SELFHOST_MAPLE_RC={self_rc}")
        for bucket, count in sorted(counts.items()):
            print(f"{bucket}={count}")
        print(f"OUTPUT={args.output}")
        return 0
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
