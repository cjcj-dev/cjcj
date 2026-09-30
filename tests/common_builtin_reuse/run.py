#!/usr/bin/env python3
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import time


BUILTINS = {0: "RawArray", 1: "VArray", 2: "CPointer", 3: "CString", 4: "CFunc"}


class Cjo:
    def __init__(self, path):
        self.data = bytearray(path.read_bytes())
        if self.data[4:8] != b"CJOF":
            raise ValueError("not a CJO FlatBuffer")
        self.root = self.scalar(0, "I")

    def scalar(self, offset, kind):
        return struct.unpack_from("<" + kind, self.data, offset)[0]

    def field(self, table, index):
        vtable = table - self.scalar(table, "i")
        slot = 4 + 2 * index
        if slot >= self.scalar(vtable, "H"):
            return None
        relative = self.scalar(vtable + slot, "H")
        return table + relative if relative else None

    def indirect(self, offset):
        return offset + self.scalar(offset, "I")

    def table(self, table, index):
        offset = self.field(table, index)
        return self.indirect(offset) if offset is not None else None

    def vector(self, table, index, kind="I"):
        offset = self.table(table, index)
        if offset is None:
            return []
        width = struct.calcsize(kind)
        return [self.scalar(offset + 4 + width * ordinal, kind)
                for ordinal in range(self.scalar(offset, "I"))]

    def string(self, table, index):
        offset = self.table(table, index)
        if offset is None:
            return ""
        return self.data[offset + 4:offset + 4 + self.scalar(offset, "I")].decode()

    def declarations(self):
        offset = self.table(self.root, 8)
        return [self.indirect(offset + 4 + 4 * ordinal)
                for ordinal in range(self.scalar(offset, "I"))]

    def builtins(self):
        records = []
        for ordinal, table in enumerate(self.declarations(), 1):
            kind = self.field(table, 0)
            top = self.field(table, 1)
            if kind is None or self.scalar(kind, "H") != 13 or top is None or not self.scalar(top, "?"):
                continue
            info = self.table(table, 17)
            builtin_field = self.field(info, 0)
            builtin = self.scalar(builtin_field, "B") if builtin_field is not None else 0
            generic = self.table(table, 4)
            parameters = self.vector(generic, 0) if generic is not None else []
            constraints = self.vector(generic, 1) if generic is not None else []
            parameter_names = [self.string(self.declarations()[index - 1], 7) for index in parameters]
            records.append({"index": ordinal, "type": builtin, "name": self.string(table, 7),
                            "parameters": parameter_names, "constraints": len(constraints),
                            "attributes": self.vector(table, 9, "Q"),
                            "file": list(struct.unpack_from("<IIii", self.data, self.field(table, 5)))[:2]})
        return records

    def omit_top_level_builtin(self, builtin, path):
        matches = [record for record in self.builtins() if record["type"] == builtin]
        if len(matches) != 1:
            raise ValueError("partial common fixture requires one builtin of the selected type")
        table = self.declarations()[matches[0]["index"] - 1]
        self.data[self.field(table, 1)] = 0
        path.write_bytes(self.data)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compile_source(compiler, source, output, common=None, mode="chir", no_prelude=True):
    output.mkdir(parents=True, exist_ok=True)
    command = [str(compiler), str(source), "--experimental", "--output-type=" + mode,
               "-O2", "--jobs", "192"]
    if no_prelude:
        command += ["--no-prelude"]
    if common is not None:
        command += ["--common-part-cjo", str(common[0]), "--common-part-chir", str(common[1])]
    if mode == "staticlib":
        command += ["--emit-chir=opt", "--dump-chir", "-o", str(output / "output.chir")]
    else:
        command += ["-o", str(output) + "/"]
    start = time.monotonic()
    with (output / "compiler.log").open("w") as log:
        completed = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=120)
    text = (output / "compiler.log").read_text()
    result = {"command": command, "rc": completed.returncode, "wall": time.monotonic() - start,
              "exception": "begin of range is zero" in text,
              "artifacts": {path.name: sha256(path) for path in output.iterdir()
                            if path.is_file() and path.suffix in {".cjo", ".chir"}}}
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    return result, text


def unique_builtins(path):
    records = Cjo(path).builtins()
    counts = {kind: sum(record["type"] == kind for record in records) for kind in BUILTINS}
    generic_ok = all(record["parameters"] == ([] if record["type"] == 3 else ["T"])
                     and record["constraints"] == (1 if record["type"] == 2 else 0)
                     for record in records)
    return all(count == 1 for count in counts.values()) and generic_ok, {"counts": counts, "records": records}


def run(compiler, output, jobs, common_export):
    fixtures = Path(__file__).resolve().parent
    output.mkdir(parents=True, exist_ok=True)
    identity = {"compiler": str(compiler), "sha256": sha256(compiler)}
    (output / "compiler.json").write_text(json.dumps(identity, indent=2) + "\n")
    exported, _ = compile_source(compiler, fixtures / "root.cj", output / "ordinary")
    export_cjo = output / "ordinary/std.core.cjo"
    export_chir = output / "ordinary/std.core.chir"
    ordinary_ok, ordinary_state = unique_builtins(export_cjo) if export_cjo.exists() else (False, {})
    results = [{"name": "ordinary_unique_builtins", "pass": exported["rc"] == 0 and ordinary_ok,
                "target_executed": True, "compile": exported, "state": ordinary_state}]
    common_directory = common_export if common_export is not None else output / "ordinary"
    common = (common_directory / "std.core.cjo", common_directory / "std.core.chir")
    seed_ok, seed_state = unique_builtins(common[0])
    if not seed_ok or not common[1].is_file():
        raise ValueError("common fixture must contain the five original builtins and its paired CHIR")
    (output / "common-input.json").write_text(json.dumps({"cjo_sha256": sha256(common[0]),
                                                          "chir_sha256": sha256(common[1]),
                                                          "state": seed_state}, indent=2) + "\n")

    def common_case(name, source, selected_common, mode="staticlib"):
        compiled, _ = compile_source(compiler, source, output / name, selected_common, mode)
        product = output / name / "std.core.cjo"
        unique, state = unique_builtins(product) if product.exists() else (False, {})
        chir = output / name / ("output.chir" if mode == "staticlib" else "std.core.chir")
        passed = compiled["rc"] == 0 and unique and chir.exists() and chir.stat().st_size > 0
        return {"name": name, "pass": passed, "target_executed": True,
                "compile": compiled, "state": state}

    tasks = [("original_common", fixtures / "platform.cj", common, "staticlib"),
             ("typed_common", fixtures / "typed_platform.cj", common, "chir")]
    for kind, name in BUILTINS.items():
        partial = output / ("partial-" + name + ".cjo")
        Cjo(common[0]).omit_top_level_builtin(kind, partial)
        tasks.append(("partial_" + name, fixtures / "platform.cj", (partial, common[1]), "staticlib"))
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        results.extend(pool.map(lambda task: common_case(*task), tasks))

    def negative_case(name, source, selected_common):
        compiled, text = compile_source(compiler, source, output / name, selected_common, "chir")
        expected = "redefinition" in text.lower() if name == "user_duplicate" else compiled["exception"]
        rejected = compiled["rc"] != 0 and expected
        return {"name": name, "pass": rejected, "target_executed": True, "compile": compiled}

    negatives = [("user_duplicate", fixtures / "user_duplicate.cj", common),
                 ("user_builtin_name", fixtures / "user_builtin_name.cj", common),
                 ("ordinary_user_builtin_name", fixtures / "user_builtin_name.cj", None)]
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        results.extend(pool.map(lambda task: negative_case(*task), negatives))
    control_export, _ = compile_source(compiler, fixtures / "common.cj", output / "noncore-export", no_prelude=False)
    control_common = (output / "noncore-export/common_builtin_control.cjo",
                      output / "noncore-export/common_builtin_control.chir")
    control_import, _ = compile_source(compiler, fixtures / "specific.cj", output / "noncore-import", control_common,
                                       no_prelude=False)
    results.append({"name": "noncore_common_specific", "pass": control_export["rc"] == 0 and control_import["rc"] == 0,
                    "target_executed": True, "export": control_export, "import": control_import})
    for result in results:
        print(("PASS" if result["pass"] else "FAIL") + " TARGET " + result["name"], flush=True)
    summary = {"identity": identity, "results": results, "passed": sum(result["pass"] for result in results),
               "failed": [result["name"] for result in results if not result["pass"]]}
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    return bool(summary["failed"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("compiler", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--common-export", type=Path)
    arguments = parser.parse_args()
    common_export = arguments.common_export.resolve() if arguments.common_export is not None else None
    raise SystemExit(run(arguments.compiler.resolve(), arguments.output.resolve(), arguments.jobs, common_export))
