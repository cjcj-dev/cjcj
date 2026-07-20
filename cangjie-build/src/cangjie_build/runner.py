from __future__ import annotations

import os
import shlex
import subprocess
from collections.abc import Mapping, Sequence
from pathlib import Path

from cangjie_build.errors import BuildError
from cangjie_build.logging_setup import get_logger

_log = get_logger("cangjie_build.runner")

CommandPart = str | os.PathLike[str]


def _format_cmd(cmd: Sequence[CommandPart]) -> str:
    return shlex.join(str(p) for p in cmd)


def run(
    cmd: Sequence[CommandPart],
    *,
    cwd: Path | None = None,
    env_overlay: Mapping[str, str] | None = None,
    stage: str = "run",
    check: bool = True,
    echo: bool = True,
) -> int:
    """Run a subprocess with streaming stdout/stderr.

    - Never uses ``shell=True``; pass commands as a list.
    - Streams the child's combined output line-by-line through the logger.
    - Raises :class:`BuildError` on non-zero exit when ``check`` is true.
    """
    if not cmd:
        raise BuildError(stage, "empty command")

    env: dict[str, str] | None
    if env_overlay:
        env = dict(os.environ)
        env.update(env_overlay)
    else:
        env = None

    cwd_str = str(cwd) if cwd is not None else None
    if echo:
        prefix = f"(cd {shlex.quote(cwd_str)} && )" if cwd_str else ""
        _log.info("$ %s%s", prefix, _format_cmd(cmd))

    proc = subprocess.Popen(
        [str(p) for p in cmd],
        cwd=cwd_str,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=1,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    assert proc.stdout is not None
    try:
        for line in proc.stdout:
            _log.info(line.rstrip())
    finally:
        proc.stdout.close()
    rc = proc.wait()
    if check and rc != 0:
        raise BuildError(stage, f"command failed: {_format_cmd(cmd)}", returncode=rc)
    return rc
