from __future__ import annotations

from pathlib import Path

from cangjie_build.config import BuildConfig, RepoName
from cangjie_build.git import shallow_clone
from cangjie_build.logging_setup import get_logger, stage
from cangjie_build.stages._common import ensure_dir

_log = get_logger("cangjie_build.stages.fetch")


def run(cfg: BuildConfig) -> None:
    ensure_dir(cfg.workspace)
    with stage("fetch"):
        for repo in cfg.repos.values():
            target = cfg.workspace / repo.dir_name
            if target.exists():
                _log.info("Repo %s already at %s, skipping clone", repo.name, target)
                continue
            shallow_clone(repo.url, target, tag=repo.tag)

        compiler_dir = cfg.workspace / cfg.repos[RepoName.COMPILER].dir_name
        _patch_buildcjdb_deps(compiler_dir)


def _patch_buildcjdb_deps(compiler_dir: Path) -> None:
    """Add cangjie-frontend/cangjie-lsp to lldb's ExternalProject DEPENDS.

    BuildCJDB.cmake declares ``ExternalProject_Add(lldb ... DEPENDS cjnative)``,
    but lldb's link step needs libcangjie-frontend.dll.a and libcangjie-lsp.dll.a
    (passed via -DCANGJIE_FRONTEND_LIB / -DCANGJIE_LSP_LIB). Without explicit
    target-level deps, ninja runs them in parallel and lldb's link races
    cangjie-frontend's compile. With cjdb-disable-python on Windows, lldb's
    link reaches that step almost immediately after cmake configure, before
    cangjie-frontend has finished — and fails. The host (linux) build doesn't
    hit this because lldb-with-Python is much heavier than cangjie-frontend.
    """
    cmake_file = compiler_dir / "third_party" / "cmake" / "BuildCJDB.cmake"
    if not cmake_file.is_file():
        return
    text = cmake_file.read_text(encoding="utf-8")
    old = "    DEPENDS cjnative)"
    new = "    DEPENDS cjnative cangjie-frontend cangjie-lsp)"
    if new in text:
        return  # already patched
    if old not in text:
        _log.warning("BuildCJDB.cmake: lldb DEPENDS line not found; skipping patch")
        return
    cmake_file.write_text(text.replace(old, new, 1), encoding="utf-8")
    _log.info("Patched BuildCJDB.cmake: added cangjie-frontend/cangjie-lsp to lldb DEPENDS")
