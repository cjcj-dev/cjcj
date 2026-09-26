#!/usr/bin/env python3
"""Refresh current vendored file hashes, preserving upstream TOOLS records."""

import hashlib
from pathlib import Path


def main():
    directory = Path(__file__).resolve().parent
    source = directory / "SOURCE.env"
    lines = source.read_text().splitlines(keepends=True)
    for index, line in enumerate(lines):
        if line.startswith("VENDOR_"):
            key, _ = line.rstrip("\n").split("=", 1)
            digest = hashlib.sha256((directory / key.removeprefix("VENDOR_")).read_bytes()).hexdigest()
            lines[index] = f"{key}={digest}\n"
    source.write_text("".join(lines))


if __name__ == "__main__":
    main()
