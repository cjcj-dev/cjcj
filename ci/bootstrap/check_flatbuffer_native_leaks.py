#!/usr/bin/env python3
"""Check Memcheck records for the product's native FlatBuffer allocations.

Runtime/package initialization records are not buffer allocations. Preserve the
complete XML and report other Memcheck errors separately; this check establishes
only the FlatBuffer allocation lifetime invariant.
"""
import argparse
import json
import re
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("xml")
    args = parser.parse_args()
    root = ET.parse(args.xml).getroot()
    states = [node.text for node in root.findall("status/state")]
    if "FINISHED" not in states:
        raise SystemExit("Memcheck did not finish")
    records = []
    unrelated = 0
    for error in root.findall("error"):
        functions = [node.text or "" for node in error.findall(".//fn")]
        owned = any("cjcj:flatbuffers" in name and
                    re.search(r"VectorDownward|Allocate|ReallocateDownward|DetachedBuffer|WriteFlatBufferToFile", name)
                    for name in functions)
        if not owned:
            unrelated += 1
            continue
        records.append({"kind": error.findtext("kind"),
                        "bytes": int(error.findtext("xwhat/leakedbytes") or 0),
                        "blocks": int(error.findtext("xwhat/leakedblocks") or 0),
                        "functions": functions})
    result = {"native_records": records, "native_bytes": sum(r["bytes"] for r in records),
              "native_blocks": sum(r["blocks"] for r in records), "unrelated_records": unrelated}
    print(json.dumps(result, indent=2))
    print("ASSERT native FlatBuffer allocations released:", "PASS" if not records else "FAIL")
    return int(bool(records))


if __name__ == "__main__":
    raise SystemExit(main())
