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


_PATCH_MARKER = "# cangjie-build: lldb -> cangjie-frontend/lsp dep patch"


def _patch_buildcjdb_deps(compiler_dir: Path) -> None:
    """Make the lldb ExternalProject's build step wait for cangjie-frontend/cangjie-lsp.

    BuildCJDB.cmake declares ``ExternalProject_Add(lldb ... DEPENDS cjnative)``,
    but lldb's link step also needs libcangjie-frontend.dll.a and
    libcangjie-lsp.dll.a (passed via -DCANGJIE_FRONTEND_LIB /
    -DCANGJIE_LSP_LIB). Without an explicit dependency on those library
    targets, ninja runs them in parallel and the lldb link can lose the race.

    Symptom (cross-compile, --cjdb-disable-python on windows): without
    Python plugins lldb's link runs almost immediately after cmake configure
    and reports
        ninja: error: '.../libcangjie-frontend.dll.a' missing.
    The host (linux) build hides the bug because lldb-with-Python is far
    heavier than cangjie-frontend, so cangjie-frontend always finishes first.

    Two non-options:
      * Adding to ``DEPENDS cjnative cangjie-frontend ...`` — CMake errors
        with 'External project cangjie-frontend has no stamp_dir' because
        DEPENDS only accepts other ExternalProject targets there.
      * ``add_dependencies(lldb cangjie-frontend ...)`` — the 'lldb' target
        is the ExternalProject aggregator (runs after install), so this
        only sequences cangjie-frontend before the no-op aggregator step,
        not before the build step that actually links liblldb.dll.

    Use ``ExternalProject_Add_StepDependencies(lldb build ...)``: that's
    the documented way to make the build sub-step depend on a regular
    target.
    """
    cmake_file = compiler_dir / "third_party" / "cmake" / "BuildCJDB.cmake"
    if not cmake_file.is_file():
        return
    text = cmake_file.read_text(encoding="utf-8")
    if _PATCH_MARKER in text:
        return  # already patched
    anchor = "    DEPENDS cjnative)"
    if anchor not in text:
        _log.warning("BuildCJDB.cmake: lldb ExternalProject_Add anchor not found; skipping patch")
        return
    addition = (
        f"\n{_PATCH_MARKER}\n"
        "ExternalProject_Add_StepDependencies(lldb build cangjie-frontend cangjie-lsp)\n"
    )
    cmake_file.write_text(text.replace(anchor, anchor + addition, 1), encoding="utf-8")
    _log.info(
        "Patched BuildCJDB.cmake: lldb-build step now waits on cangjie-frontend/cangjie-lsp"
    )
