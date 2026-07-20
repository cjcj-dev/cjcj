from __future__ import annotations

from pathlib import Path

from cangjie_build.errors import BuildError
from cangjie_build.logging_setup import get_logger
from cangjie_build.runner import run

_log = get_logger("cangjie_build.git")


def shallow_clone(url: str, dest: Path, *, tag: str | None = None) -> None:
    """Shallow-clone ``url`` into ``dest``. ``dest`` must not already exist."""
    if dest.exists():
        raise BuildError("git", f"destination already exists: {dest}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    cmd: list[str] = ["git", "clone", "--depth", "1"]
    if tag:
        cmd += ["--branch", tag]
    cmd += [url, str(dest)]
    _log.info("Cloning %s%s into %s", url, f" @ {tag}" if tag else "", dest)
    run(cmd, stage="git.clone")
