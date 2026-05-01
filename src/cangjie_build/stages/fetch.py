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

    The fix has to be applied at the *top-level* ``CMakeLists.txt`` after
    ``add_subdirectory(src)``: ``cangjie-frontend`` / ``cangjie-lsp`` are
    defined under ``src/`` while ``BuildCJDB.cmake`` runs from
    ``add_subdirectory(third_party)``, which comes earlier — so a dep
    written into BuildCJDB.cmake silently no-ops because the targets don't
    exist yet.

    Tried and failed:
      * Extending ``DEPENDS cjnative cangjie-frontend ...`` — CMake errors
        with 'External project cangjie-frontend has no stamp_dir' (DEPENDS
        only accepts other ExternalProject targets).
      * ``add_dependencies(lldb cangjie-frontend ...)`` in BuildCJDB.cmake —
        targets undefined; CMake silently drops the dep.
      * ``ExternalProject_Add_StepDependencies(lldb build ...)`` in
        BuildCJDB.cmake — same target-undefined silent drop.
    """
    cmake_file = compiler_dir / "CMakeLists.txt"
    if not cmake_file.is_file():
        return
    text = cmake_file.read_text(encoding="utf-8")
    if _PATCH_MARKER in text:
        return  # already patched
    addition = (
        "\n"
        f"{_PATCH_MARKER}\n"
        "if(TARGET lldb AND TARGET cangjie-frontend AND TARGET cangjie-lsp)\n"
        "    ExternalProject_Add_StepDependencies(lldb build cangjie-frontend cangjie-lsp)\n"
        "endif()\n"
    )
    cmake_file.write_text(text.rstrip() + "\n" + addition, encoding="utf-8")
    _log.info("Patched CMakeLists.txt: lldb-build step now waits on cangjie-frontend/cangjie-lsp")
