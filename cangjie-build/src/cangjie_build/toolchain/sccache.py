from __future__ import annotations

import os
import shutil

from cangjie_build.logging_setup import get_logger

_log = get_logger("cangjie_build.toolchain.sccache")

_LAUNCHER_VARS = ("CMAKE_C_COMPILER_LAUNCHER", "CMAKE_CXX_COMPILER_LAUNCHER")


def describe_backends() -> str:
    """Summarise the configured sccache storage chain for log output.

    Order matches sccache's own backend selection precedence — see
    https://github.com/mozilla/sccache/blob/main/docs/Configuration.md
    (multilevel chain > GHA > azure > S3 > GCS > redis > memcached >
    webdav > local disk).
    """
    chain = os.environ.get("SCCACHE_MULTILEVEL_CHAIN")
    if chain:
        return f"multi-level [{chain}]"
    if os.environ.get("SCCACHE_GHA_ENABLED", "").lower() in {"1", "true", "yes"}:
        return "github-actions"
    if os.environ.get("SCCACHE_AZURE_CONNECTION_STRING"):
        container = os.environ.get("SCCACHE_AZURE_BLOB_CONTAINER", "?")
        return f"azblob[{container}]"
    if os.environ.get("SCCACHE_BUCKET"):
        return f"s3[{os.environ['SCCACHE_BUCKET']}]"
    if os.environ.get("SCCACHE_GCS_BUCKET"):
        return f"gcs[{os.environ['SCCACHE_GCS_BUCKET']}]"
    if os.environ.get("SCCACHE_REDIS") or os.environ.get("SCCACHE_REDIS_ENDPOINT"):
        return "redis"
    if os.environ.get("SCCACHE_MEMCACHED") or os.environ.get("SCCACHE_MEMCACHED_ENDPOINT"):
        return "memcached"
    if os.environ.get("SCCACHE_WEBDAV_ENDPOINT"):
        return "webdav"
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
