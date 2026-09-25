#!/usr/bin/env python3
import argparse
import re
from pathlib import Path


def require(value, message):
    if not value:
        raise AssertionError(message)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ir", type=Path, required=True)
    args = parser.parse_args()
    ir = args.ir.read_text()
    functions = re.findall(r"^define [^\n]+\{\n.*?^\}", ir, re.M | re.S)
    results = {}

    def run(name, check):
        try:
            check()
            results[name] = "PASS"
        except AssertionError as error:
            results[name] = "FAIL: " + str(error)
        print("TARGET_ASSERT_RAN " + name)
        print(results[name] + " " + name)

    def function(token):
        matches = [body for body in functions if token in body.splitlines()[0]]
        require(len(matches) == 1, "expected one " + token + " entry; got " + str(len(matches)))
        return matches[0]

    def generic_of():
        body = function("genericOf")
        header = body.splitlines()[0]
        require(re.search(r"\(%TypeInfo\* %ti\.T[,)]", header),
                "generic TypeInfo is not LLVM arg0")
        require(re.search(r"bitcast %TypeInfo\* %ti\.T to i8\*", body),
                "generic path does not bitcast arg0 TypeInfo to i8*")
        require("CJ_MCC_GetTypeByMangledName" not in body,
                "generic path still calls CJ_MCC_GetTypeByMangledName")

    def concrete_int64():
        body = function("concreteInt64")
        require(re.search(r"bitcast %TypeInfo\* @Int64\.ti to i8\*", body),
                "concrete path does not bitcast Int64.ti to i8*")
        require("CJ_MCC_GetTypeByMangledName" not in body,
                "concrete path still calls CJ_MCC_GetTypeByMangledName")

    def reflect_still_calls_runtime():
        body = function("reflectStillCallsRuntime")
        require("call " in body and "CJ_MCC_IsSubType" in body,
                "other reflect intrinsic no longer calls its runtime function")
        require("CJ_MCC_GetTypeByMangledName" not in body,
                "control function unexpectedly calls GetTypeByMangledName")

    run("genericOf", generic_of)
    run("concreteInt64", concrete_int64)
    run("reflectStillCallsRuntime", reflect_still_calls_runtime)
    failed = [name for name, status in results.items() if status != "PASS"]
    if failed:
        raise SystemExit("failed: " + ",".join(failed))


if __name__ == "__main__":
    main()
