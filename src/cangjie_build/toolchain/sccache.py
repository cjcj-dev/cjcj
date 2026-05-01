from __future__ import annotations

import os
import shutil

from cangjie_build.logging_setup import get_logger

_log = get_logger("cangjie_build.toolchain.sccache")

_LAUNCHER_VARS = ("CMAKE_C_COMPILER_LAUNCHER", "CMAKE_CXX_COMPILER_LAUNCHER")


def describe_backends() -> str:
    """Summarise the configured sccache storage chain for log output."""
    chain = os.environ.get("SCCACHE_MULTILEVEL_CHAIN")
    if chain:
        return f"multi-level [{chain}]"
    if os.environ.get("SCCACHE_GHA_ENABLED", "").lower() in {"1", "true", "yes"}:
        return "github-actions"
    if os.environ.get("SCCACHE_DIR"):
        return "disk"
    return "default (disk)"


def maybe_enable() -> bool:
    """If ``sccache`` is on PATH, enable it via CMake compiler-launcher env vars.

    Returns True when sccache was activated. Idempotent — pre-existing values are
    preserved (the user / CI may have configured a custom launcher already).
    """
    sccache_path = shutil.which("sccache")
    if not sccache_path:
        _log.debug("sccache not found on PATH; skipping launcher injection")
        return False

    enabled = False
    for var in _LAUNCHER_VARS:
        existing = os.environ.get(var)
        if existing:
            _log.debug("%s already set to %r; leaving as-is", var, existing)
            continue
        os.environ[var] = "sccache"
        enabled = True

    if enabled:
        _log.info(
            "sccache enabled via CMAKE_*_COMPILER_LAUNCHER (%s, backend: %s)",
            sccache_path,
            describe_backends(),
        )
    return enabled
