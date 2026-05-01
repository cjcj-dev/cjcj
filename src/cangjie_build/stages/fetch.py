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
        _patch_lldb_step_deps(compiler_dir)


_PATCH_OLD = """if(CANGJIE_BUILD_CJDB)
    add_dependencies(lldb cangjie-frontend)
endif()"""

_PATCH_NEW = """if(CANGJIE_BUILD_CJDB)
    add_dependencies(lldb cangjie-frontend)
    # cangjie-build patch: add_dependencies(lldb X) only sequences X before
    # the ExternalProject aggregator (a no-op target that runs after install).
    # The 'lldb-build' sub-target is the one that actually invokes lldb's
    # nested ninja, and that's where the link to libcangjie-frontend.dll.a /
    # libcangjie-lsp.dll.a happens. Without this, fast hosts race lldb's
    # link against cangjie-frontend's compile and fail with the import lib
    # missing. Slow hosts hide the bug because lldb-with-Python is heavy
    # enough that cangjie-frontend always finishes first.
    add_dependencies(lldb-build cangjie-frontend)
    if(TARGET cangjie-lsp-share)
        add_dependencies(lldb-build cangjie-lsp-share)
    endif()
endif()"""


def _patch_lldb_step_deps(compiler_dir: Path) -> None:
    """Wire cangjie-frontend / cangjie-lsp-share into lldb-build's deps.

    The fix targets ``src/CMakeLists.txt`` which already calls
    ``add_dependencies(lldb cangjie-frontend)`` — but that uses the
    ExternalProject aggregator target and doesn't actually sequence the
    libs before lldb's build sub-step. We append two ``add_dependencies``
    calls that hit the real ``lldb-build`` step target, which CMake creates
    automatically for each ExternalProject step.

    Done from src/ rather than third_party/ because by the time src/ is
    processed both ``lldb-build`` (created by ``add_subdirectory(third_party)``
    earlier) and ``cangjie-frontend`` / ``cangjie-lsp-share`` (defined in
    src/CMakeLists.txt) are visible. ``add_dependencies`` works across
    directory scope, unlike ``add_custom_command(APPEND)`` which we hit
    when we tried ``ExternalProject_Add_StepDependencies``.
    """
    cmake_file = compiler_dir / "src" / "CMakeLists.txt"
    if not cmake_file.is_file():
        return
    text = cmake_file.read_text(encoding="utf-8")
    if _PATCH_NEW in text:
        return
    if _PATCH_OLD not in text:
        _log.warning("src/CMakeLists.txt: lldb dep block not found verbatim; skipping patch")
        return
    cmake_file.write_text(text.replace(_PATCH_OLD, _PATCH_NEW, 1), encoding="utf-8")
    _log.info("Patched src/CMakeLists.txt: lldb-build now waits on cangjie-frontend/cangjie-lsp-share")
