#!/usr/bin/env python3
"""Make an independent IR-test SDK; never link back to shared installations."""
import argparse
import json
from pathlib import Path
import shlex
import subprocess


def copy(source, destination):
    subprocess.run(["cp", "-aL", str(source), str(destination)], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--tuple", type=Path, required=True)
    parser.add_argument("--compilers", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = args.output.resolve()
    # A fresh directory keeps previous evidence and installations untouched.
    root.mkdir(parents=True, exist_ok=False)
    host = root / "host"
    sdk = root / "sdk"
    copy(args.host, host)
    copy(args.tuple, root / "tuple")
    sdk.mkdir()
    for entry in host.iterdir():
        if entry.name not in ("bin", "third_party"):
            copy(entry, sdk / entry.name)
    (sdk / "bin").mkdir()
    for name in ("cjcj-strength", "cjcj-r1", "cjcj-r2", "cjcj-r3"):
        copy(args.compilers / name, sdk / "bin" / name)
    (sdk / "third_party").mkdir()
    for entry in (host / "third_party").iterdir():
        if entry.name != "llvm":
            copy(entry, sdk / "third_party" / entry.name)
    llvm = sdk / "third_party/llvm"
    llvm.mkdir()
    for entry in (host / "third_party/llvm").iterdir():
        if entry.name != "bin":
            copy(root / "tuple/lib" if entry.name == "lib" else entry, llvm / entry.name)
    (llvm / "bin").mkdir()
    # Host auxiliary tools require their own LLVM ABI. Both executables and
    # libraries are physical private copies, including those behind wrappers.
    loader = ":".join(str(host / path) for path in (
        "third_party/llvm/lib", "runtime/lib/linux_x86_64_cjnative", "tools/lib"))
    for entry in (host / "third_party/llvm/bin").iterdir():
        destination = llvm / "bin" / entry.name
        if entry.name in ("opt", "llc"):
            copy(root / "tuple/bin" / entry.name, destination)
        else:
            destination.write_text("#!/bin/sh\nexport LD_LIBRARY_PATH=" + shlex.quote(loader)
                                   + "\nexec " + shlex.quote(str(entry)) + ' "$@"\n')
            destination.chmod(0o755)
    links = [str(path) for path in root.rglob("*") if path.is_symlink()]
    (root / "sdk-links.json").write_text(json.dumps(links, indent=2) + "\n")
    if links:
        raise RuntimeError("Private SDK contains symbolic links: " + repr(links))


if __name__ == "__main__":
    main()
