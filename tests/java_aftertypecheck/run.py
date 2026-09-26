#!/usr/bin/env python3
"""Compile Java AfterTypeCheck fixtures with a candidate stage1 compiler."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def ast_text(dest):
    path = dest / "result_AST" / "5_desugar_ast.txt"
    return path.read_text() if path.exists() else ""


def brace_section(text, token, from_idx=0):
    start = text.find(token, from_idx)
    if start < 0:
        return ""
    line_start = text.rfind("\n", 0, start) + 1
    depth = 0
    section = []
    for line in text[line_start:].splitlines(True):
        section.append(line)
        depth += line.count("{") - line.count("}")
        if depth == 0 and len(section) > 1:
            return "".join(section)
    return "".join(section)


def setter_section(ast, name):
    return brace_section(ast, "FuncDecl: $" + name + "set")


def value_arg(setter):
    idx = 0
    found = ""
    while True:
        start = setter.find("FuncArg {", idx)
        if start < 0:
            return found
        block = brace_section(setter, "FuncArg {", start)
        idx = start + len("FuncArg {")
        if "RefExpr: set {" in block and "Java_CFFI_get_env" not in block:
            if not found or len(block) < len(found):
                found = block


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--compiler", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--expect-callsite-cut", action="store_true")
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    fixtures = Path(__file__).resolve().parent
    imports = a.out / "imports"
    (imports / "java").mkdir(parents=True, exist_ok=True)
    result = {
        "compiler": str(a.compiler),
        "compiler_sha256": sha(a.compiler),
        "affinity": sorted(os.sched_getaffinity(0)),
        "uptime_before": subprocess.check_output(["uptime"], text=True).strip(),
        "expect_callsite_cut": a.expect_callsite_cut,
        "fixtures": {f.name: sha(f) for f in sorted(fixtures.glob("*.cj"))},
        "cases": {},
    }

    def compile_one(name, stub=False):
        dest = a.out / name
        dest.mkdir(exist_ok=True)
        command = [
            str(a.compiler),
            str(fixtures / (name + ".cj")),
            "--import-path",
            str(imports),
            "--output-type=staticlib",
            "--diagnostic-format=noColor",
        ]
        if stub:
            command += ["--output-dir", str(imports / "java"), "-o", name + ".a"]
        else:
            command += ["--dump-ast", "-o", str(dest / "result")]
        start = time.monotonic()
        with (dest / "compiler.log").open("w") as log:
            run = subprocess.run(command, cwd=dest, stdout=log, stderr=subprocess.STDOUT, timeout=180)
        (dest / "compiler.rc").write_text(str(run.returncode) + "\n")
        return {"rc": run.returncode, "command": command, "wall": time.monotonic() - start,
                "log": str(dest / "compiler.log")}

    for name in ("internal", "lang"):
        observed = compile_one(name, True)
        text = Path(observed["log"]).read_text()
        observed["log_tail"] = text[-2000:]
        if name == "lang":
            ast = ast_text(a.out / name)
            if not ast:
                # Stub compiles omit --dump-ast. Recompile lang with a dump.
                dumped = compile_one("lang_dump", False)
                # lang_dump uses lang_dump.cj which does not exist. Dump via a second command below.
                observed["dump_note"] = "separate"
            result["cases"][name] = observed
        else:
            result["cases"][name] = observed
        if observed["rc"]:
            result["uptime_after"] = subprocess.check_output(["uptime"], text=True).strip()
            (a.out / "result.json").write_text(json.dumps(result, indent=2) + "\n")
            print("FAIL " + name + " rc=" + str(observed["rc"]), flush=True)
            return 2

    def compile_dump(name):
        dest = a.out / name
        dest.mkdir(exist_ok=True)
        command = [
            str(a.compiler),
            str(fixtures / (name + ".cj")),
            "--import-path",
            str(imports),
            "--output-type=staticlib",
            "--diagnostic-format=noColor",
            "--dump-ast",
            "-o",
            str(dest / "result"),
        ]
        start = time.monotonic()
        with (dest / "compiler.log").open("w") as log:
            run = subprocess.run(command, cwd=dest, stdout=log, stderr=subprocess.STDOUT, timeout=180)
        (dest / "compiler.rc").write_text(str(run.returncode) + "\n")
        text = Path(dest / "compiler.log").read_text()
        ast = ast_text(dest)
        return {"rc": run.returncode, "command": command, "wall": time.monotonic() - start,
                "log": str(dest / "compiler.log"), "log_tail": text[-2000:], "ast_bytes": len(ast), "ast": ast}

    lang = compile_dump("lang")
    lang_ast = lang.pop("ast")
    lang_hit = {
        "exit": lang["rc"] == 0,
        "javaref": "$javaref" in lang_ast,
        "swap": "Java_CFFI_swapLocalWithGlobalRef" in lang_ast,
        "cstring": "Java_CFFI_CangjieStringToJava" in lang_ast,
        "new_array": "Java_CFFI_newJavaArray" in lang_ast,
    }
    if a.expect_callsite_cut:
        lang["assertions"] = {
            "exit": lang["rc"] == 0,
            "javaref": "$javaref" in lang_ast,
            "swap": "Java_CFFI_swapLocalWithGlobalRef" in lang_ast,
            "cstring": "Java_CFFI_CangjieStringToJava" in lang_ast,
            "new_array_absent": "Java_CFFI_newJavaArray" not in lang_ast,
        }
    else:
        lang["assertions"] = lang_hit
    lang["passed"] = all(lang["assertions"].values())
    result["cases"]["lang"] = lang

    callsite = compile_dump("callsite")
    callsite_ast = callsite.pop("ast")
    callsite_hit = {
        "exit": callsite["rc"] == 0,
        "cast": "Java_CFFI_isInstanceOf" in callsite_ast,
        "jni_sig": 'String "I"' in callsite_ast or "String \"I\"" in callsite_ast,
    }
    if a.expect_callsite_cut:
        callsite["assertions"] = {
            "exit": callsite["rc"] == 0,
            "cast_absent": "Java_CFFI_isInstanceOf" not in callsite_ast,
            "jni_sig_absent": 'String "I"' not in callsite_ast and "String \"I\"" not in callsite_ast,
        }
    else:
        callsite["assertions"] = callsite_hit
    callsite["passed"] = all(callsite["assertions"].values())
    result["cases"]["callsite"] = callsite

    missing = compile_dump("missing_lib")
    missing.pop("ast")
    missing_log = Path(missing["log"]).read_text()
    missing["assertions"] = {
        "rejected": missing["rc"] != 0,
        "diag": "java.lang must be imported to use java interoperability" in missing_log,
    }
    missing["passed"] = all(missing["assertions"].values())
    result["cases"]["missing_lib"] = missing

    mirror = compile_dump("mirror_user")
    mirror_ast = mirror.pop("ast")
    flag = value_arg(setter_section(mirror_ast, "flag"))
    count = value_arg(setter_section(mirror_ast, "count"))
    name = value_arg(setter_section(mirror_ast, "name"))
    mirror["assertions"] = {
        "exit": mirror["rc"] == 0,
        "flag_jvalue": "IfExpr" in flag and "ty: UInt8" in flag and "asJObject" not in flag,
        "count_jvalue": "RefExpr: set" in count and "ty: Int32" in count and "asJObject" not in count and "IfExpr" not in count,
        "name_jobject": "asJObject" in name and "RefExpr: set" in name and "IfExpr" not in name,
    }
    mirror["passed"] = all(mirror["assertions"].values())
    result["cases"]["mirror_user"] = mirror

    impl = compile_dump("impl_user")
    impl_ast = impl.pop("ast")
    init_sec = brace_section(impl_ast, "FuncDecl: Java_demo_Child_initCJObject")
    ping_sec = brace_section(impl_ast, "FuncDecl: Java_demo_Child_pingi")
    delete_sec = brace_section(impl_ast, "FuncDecl: Java_demo_Child_deleteCJObject")
    impl["assertions"] = {
        "exit": impl["rc"] == 0,
        "init_c": "NO_MANGLE" in init_sec and "UNSAFE, C," in init_sec,
        "ping_c": "NO_MANGLE" in ping_sec and "UNSAFE, C," in ping_sec,
        "delete_c": "NO_MANGLE" in delete_sec and "UNSAFE, C," in delete_sec,
        "delete_remove": "Java_CFFI_removeFromRegistry" in delete_sec,
        "no_alias_sig": "TypeAlias-JNIEnv_ptr" not in init_sec and "TypeAlias-jobject" not in init_sec,
    }
    impl["passed"] = all(impl["assertions"].values())
    result["cases"]["impl_user"] = impl

    result["uptime_after"] = subprocess.check_output(["uptime"], text=True).strip()
    result["passed"] = all(row.get("passed", row["rc"] == 0) for row in result["cases"].values())
    (a.out / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    for name, row in result["cases"].items():
        if "passed" in row:
            print(("PASS " if row["passed"] else "FAIL ") + name + " " + json.dumps(row["assertions"]), flush=True)
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
