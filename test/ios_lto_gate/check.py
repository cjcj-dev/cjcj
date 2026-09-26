#!/usr/bin/env python3
"""Observe ParseFromArgs results for the iOS LTO gate.

The product writes the visibility warning to stderr and still returns true.
This script slices IOS_LTO_BEGIN/END markers emitted by Option_test and checks
that text. Return-value checks also live in the unittest @Expect calls.
"""
import argparse
import re
import sys

INEFFECTIVE = "does not take effect under the current configuration"
OLD_DYLIB = "only takes effect when outputting a dylib"
STATICLIB = "iOS LTO only supports --output-type=staticlib."
EXPERIMENTAL = "LTO on iOS is an experimental feature"

BEGIN = re.compile(r"IOS_LTO_BEGIN (\S+)")
END = re.compile(r"IOS_LTO_END (\S+) rc=(true|false)")


def slices(text):
    out = {}
    name = None
    buf = []
    for line in text.splitlines():
        begin = BEGIN.search(line)
        if begin:
            name = begin.group(1)
            buf = []
            continue
        end = END.search(line)
        if end and name == end.group(1):
            out[name] = {"rc": end.group(2) == "true", "text": "\n".join(buf)}
            name = None
            buf = []
            continue
        if name is not None:
            buf.append(line)
    return out


def expect(rows, name, rc, present=(), absent=()):
    item = rows.get(name)
    if item is None:
        print(f"ASSERT {name} MISSING")
        return False
    ok = item["rc"] is rc
    for needle in present:
        if needle not in item["text"]:
            ok = False
    for needle in absent:
        if needle in item["text"]:
            ok = False
    print(
        f"ASSERT {name} rc={'true' if item['rc'] else 'false'} "
        f"expect_rc={'true' if rc else 'false'} "
        f"{'PASS' if ok else 'FAIL'}"
    )
    return ok


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("log")
    parser.add_argument("--suite", choices=("all", "staticlib", "visibility"), default="all")
    args = parser.parse_args()
    text = open(args.log, encoding="utf-8", errors="replace").read()
    rows = slices(text)
    checks = []
    if args.suite in ("all", "staticlib"):
        checks.append(expect(rows, "IosDylibLtoExperimental", True, absent=(STATICLIB,)))
        checks.append(expect(rows, "IosStaticlibLtoExperimental", True))
        checks.append(expect(rows, "IosDylibLtoNoExperimental", False, present=(EXPERIMENTAL,)))
        checks.append(expect(rows, "DarwinLtoRejected", False))
        checks.append(expect(rows, "WindowsLtoRejected", False))
    if args.suite in ("all", "visibility"):
        checks.append(expect(rows, "LinuxExeVisibilityWarns", True, present=(INEFFECTIVE,), absent=(OLD_DYLIB,)))
        checks.append(expect(rows, "LinuxDylibVisibilitySilent", True, absent=(INEFFECTIVE, OLD_DYLIB)))
        checks.append(expect(rows, "IosStaticlibVisibilitySilent", True, absent=(INEFFECTIVE, OLD_DYLIB)))
        checks.append(expect(rows, "IosVisibilityExe", True, absent=(INEFFECTIVE, OLD_DYLIB, STATICLIB)))
        checks.append(expect(rows, "IosVisibilityDylib", True, absent=(INEFFECTIVE, OLD_DYLIB, STATICLIB)))
    failed = sum(1 for item in checks if not item)
    print(f"ASSERT_SUMMARY failed={failed} n={len(checks)} suite={args.suite}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
