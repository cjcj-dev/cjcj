"""Download + extract helpers shared by toolchain modules."""

from __future__ import annotations

import shutil
import tarfile
import urllib.request
from pathlib import Path

from cangjie_build.errors import BuildError
from cangjie_build.logging_setup import get_logger

_log = get_logger("cangjie_build.toolchain.archive")


def download(url: str, dest: Path) -> None:
    """Download ``url`` to ``dest`` (atomic via .part rename). No-op if cached."""
    if dest.exists():
        _log.info("Reusing cached download: %s", dest)
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    _log.info("Downloading %s", url)
    tmp = dest.with_suffix(dest.suffix + ".part")
    with urllib.request.urlopen(url, timeout=60) as resp, tmp.open("wb") as f:
        shutil.copyfileobj(resp, f)
    tmp.replace(dest)


def extract(tarball: Path, dest_dir: Path) -> Path:
    """Extract ``tarball`` into ``dest_dir`` and return the resulting top-level path.

    Mode is auto-detected from the file's extensions; .tar.gz, .tar.xz and
    .tar.bz2 all work.
    """
    dest_dir.mkdir(parents=True, exist_ok=True)
    _log.info("Extracting %s into %s", tarball.name, dest_dir)
    with tarfile.open(tarball, "r:*") as tf:
        first = next(iter(tf), None)
        if first is None:
            raise BuildError("archive", f"empty tarball: {tarball}")
        top = first.name.split("/", 1)[0]
        tf.extractall(dest_dir, filter="data")
    return dest_dir / top
