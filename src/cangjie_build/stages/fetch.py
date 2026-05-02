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


_BUILDCJDB_OLD = """externalproject_get_property(cjnative SOURCE_DIR)
ExternalProject_Add("""

_BUILDCJDB_NEW = """# cangjie-build patch: under CMP0114 OLD (cangjie's default — set by
# cmake_minimum_required(VERSION 3.16.5)), ExternalProject step targets
# don't adopt their underlying custom_command's deps. So
# add_dependencies(lldb-build X) is a soft target-level edge that ninja
# does NOT propagate into the custom_command — cangjie-frontend ends up
# racing lldb's build step. NEW policy makes step targets fully adopt
# their custom_commands so the dep actually blocks.
cmake_policy(SET CMP0114 NEW)

externalproject_get_property(cjnative SOURCE_DIR)
ExternalProject_Add("""

_BUILDCJDB_STEP_OLD = """    USES_TERMINAL_BUILD ON
    DEPENDS cjnative)"""

_BUILDCJDB_STEP_NEW = """    USES_TERMINAL_BUILD ON
    # Expose 'lldb-build' as a top-level target so src/CMakeLists.txt
    # can add_dependencies() onto the actual build sub-step (without
    # STEP_TARGETS, ExternalProject only exposes the aggregator).
    STEP_TARGETS build
    DEPENDS cjnative)"""

_SRC_OLD = """if(CANGJIE_BUILD_CJDB)
    add_dependencies(lldb cangjie-frontend)
endif()"""

_SRC_NEW = """if(CANGJIE_BUILD_CJDB)
    add_dependencies(lldb cangjie-frontend)
    # cangjie-build patch: the 'lldb' aggregator target above runs *after*
    # install — it doesn't sequence libs before the actual lldb build step.
    # 'lldb-build' is exposed by STEP_TARGETS in third_party/cmake/BuildCJDB.cmake;
    # hooking it ensures libcangjie-frontend.dll.a / libcangjie-lsp.dll.a
    # exist before lldb's nested ninja tries to link against them.
    add_dependencies(lldb-build cangjie-frontend)
    if(TARGET cangjie-lsp-share)
        add_dependencies(lldb-build cangjie-lsp-share)
    endif()
endif()"""


def _patch_lldb_step_deps(compiler_dir: Path) -> None:
    """Two-file patch to make lldb's build sub-step wait for cangjie-frontend.

    cangjie's ``src/CMakeLists.txt:394`` already does
    ``add_dependencies(lldb cangjie-frontend)``, but ``lldb`` is the
    ExternalProject aggregator (post-install no-op) so it doesn't sequence
    cangjie-frontend before the build sub-step that actually runs lldb's
    nested ninja and links against ``libcangjie-frontend.dll.a`` /
    ``libcangjie-lsp.dll.a``. On slow hosts lldb-with-Python is heavy
    enough that cangjie-frontend always finishes first; on F16als_v7 the
    race fires.

    Two patches are needed:

      * ``third_party/cmake/BuildCJDB.cmake``: add ``STEP_TARGETS build``
        to ``ExternalProject_Add(lldb ...)`` so CMake creates the
        ``lldb-build`` top-level target. Without this, ``add_dependencies``
        on ``lldb-build`` errors with ``Cannot add target-level dependencies
        to non-existent target``.
      * ``src/CMakeLists.txt``: add the two ``add_dependencies(lldb-build
        ...)`` calls (works cross-directory; ``add_custom_command APPEND``,
        which is what ``ExternalProject_Add_StepDependencies`` uses, doesn't).
    """
    buildcjdb = compiler_dir / "third_party" / "cmake" / "BuildCJDB.cmake"
    if buildcjdb.is_file():
        text = buildcjdb.read_text(encoding="utf-8")
        changed = False
        if _BUILDCJDB_NEW not in text:
            if _BUILDCJDB_OLD in text:
                text = text.replace(_BUILDCJDB_OLD, _BUILDCJDB_NEW, 1)
                changed = True
            else:
                _log.warning("BuildCJDB.cmake: CMP0114 anchor not found; skipping")
        if _BUILDCJDB_STEP_NEW not in text:
            if _BUILDCJDB_STEP_OLD in text:
                text = text.replace(_BUILDCJDB_STEP_OLD, _BUILDCJDB_STEP_NEW, 1)
                changed = True
            else:
                _log.warning("BuildCJDB.cmake: STEP_TARGETS anchor not found; skipping")
        if changed:
            buildcjdb.write_text(text, encoding="utf-8")
            _log.info("Patched BuildCJDB.cmake: CMP0114 NEW + STEP_TARGETS build")

    src_cmake = compiler_dir / "src" / "CMakeLists.txt"
    if src_cmake.is_file():
        text = src_cmake.read_text(encoding="utf-8")
        if _SRC_NEW in text:
            return
        if _SRC_OLD not in text:
            _log.warning("src/CMakeLists.txt: lldb dep block not found verbatim; skipping")
            return
        src_cmake.write_text(text.replace(_SRC_OLD, _SRC_NEW, 1), encoding="utf-8")
        _log.info(
            "Patched src/CMakeLists.txt: lldb-build now waits on cangjie-frontend/cangjie-lsp-share"
        )
