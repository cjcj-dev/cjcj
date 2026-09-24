#!/usr/bin/env python3
"""Check real frontend wrapper results and their lowered executable calls."""
import argparse
import json
from pathlib import Path
import re
import subprocess


def require(value, message):
    if not value:
        raise AssertionError(message)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ir", type=Path, required=True)
    parser.add_argument("--elf", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    ir = args.ir.read_text()
    functions = re.findall(r"^define [^\n]+\{\n.*?^\}", ir, re.M | re.S)
    results = {}

    def run(name, check):
        try:
            check()
            results[name] = "PASS"
        except (AssertionError, OSError) as error:
            results[name] = "FAIL: " + str(error)
        print(f"{results[name]} {name}")

    def function(method):
        matches = [f for f in functions if method in f.splitlines()[0]
                   and "withoutTI" not in f.splitlines()[0]]
        require(len(matches) == 1, f"expected one {method} entry; got {len(matches)}")
        return matches[0]

    def payload(method, sret):
        body = function(method)
        require(("sret(" in body.splitlines()[0]) == sret, "wrong return ABI exercised")
        # All three operands must come from this wrapper, not a helper or model.
        copy = re.search(r"call void @llvm\.cj\.gcread\.generic\.payload\(i8\* (%[\w.]+), "
                         r"i8 addrspace\(1\)\* %this\.withTI, i32 (%[\w.]+)\)", body)
        require(copy, "receiver copy does not use its object's dynamic reference layout")
        dest, size = copy.groups()
        require(re.search(re.escape(dest) + r" = alloca i8, i32 " + re.escape(size) + r",", body),
                "copy destination/size differs from native payload allocation")
        require(re.search(re.escape(size) + r" = load i32, i32\* %ti.size,", body),
                "copy size does not come from runtime TypeInfo")
        require("%ti.size = getelementptr inbounds %TypeInfo, %TypeInfo* %ti, i32 0, i32 4" in body
                and "%ti = load %TypeInfo*, %TypeInfo* addrspace(1)* %obj.ti.slot" in body
                and "%obj.ti.slot = bitcast i8 addrspace(1)* %this.withTI" in body,
                "TypeInfo does not belong to this receiver")
        calls = [line for line in body.splitlines() if "call " in line and "$withoutTI" in line]
        require(len(calls) == 1 and "i8* " + dest in calls[0], "copied result is not consumed by method")
        require(body.index(calls[0]) > copy.end(), "method consumes payload before barrier copy")
        require("llvm.cj.gcread.struct" not in body, "synthetic static bitmap path remains")

    def mutable_control():
        body = function("replaceNode")
        calls = [line for line in body.splitlines() if "call " in line and "$withoutTI" in line]
        require(len(calls) == 1 and "i8 addrspace(1)* %bitcast, i8 addrspace(1)* %this.withTI" in calls[0],
                "mutable receiver did not forward payload and base together")
        require("gcread.generic.payload" not in body and "alloca" not in body,
                "mutable receiver was unexpectedly copied")

    def concrete_control():
        body = function("concreteRead")
        require("record.default:ConcreteReceiver" in body and "load i8 addrspace(1)*" in body,
                "concrete receiver no longer reads its typed field")
        require("this.withTI" not in body and "gcread.generic.payload" not in body,
                "known layout entered dynamic wrapper")

    def lowered(method):
        body = function(method)
        symbol = re.search(r'@([^ (]+)\(', body.splitlines()[0]).group(1).strip('"')
        process = subprocess.run(["objdump", "-d", "--disassemble=" + symbol, str(args.elf)],
                                 text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (args.out / (method + ".disasm")).write_text(process.stdout)
        require(process.returncode == 0, f"objdump rc={process.returncode}")
        require("<" + symbol + ">:" in process.stdout, "wrapper missing from real ELF")
        require(re.search(r"call[^\n]*<CJ_MCC_ReadGenericPayload(?:@plt)?>", process.stdout),
                "lowered wrapper does not call dynamic payload read")
        require(not re.search(r"call[^\n]*<CJ_MCC_ReadStructField", process.stdout),
                "lowered wrapper retained static bitmap read")

    # Each target runs independently, including on a red arm.
    run("ordinaryReturnDynamicLayout", lambda: payload("readNode", False))
    run("sretReturnDynamicLayout", lambda: payload("readPayload", True))
    run("mutableBaseForwardingControl", mutable_control)
    run("concreteLayoutControl", concrete_control)
    run("ordinaryReturnLoweredCall", lambda: lowered("readNode"))
    run("sretReturnLoweredCall", lambda: lowered("readPayload"))
    (args.out / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    return 0 if all(v == "PASS" for v in results.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
