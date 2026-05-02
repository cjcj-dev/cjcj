from __future__ import annotations

from pathlib import Path

from cangjie_build.config import BuildConfig, RepoName
from cangjie_build.git import shallow_clone
from cangjie_build.logging_setup import get_logger, stage
from cangjie_build.stages._common import ensure_dir

_log = get_logger("cangjie_build.stages.fetch")


# BuildCJDB.cmake declares lldb's ExternalProject with `DEPENDS cjnative`
# only — no dep on cangjie-frontend / cangjie-lsp-share, whose import libs
# lldb's link consumes. src/CMakeLists.txt:395 has `add_dependencies(lldb
# cangjie-frontend)`, but that pins only the ExternalProject super-target,
# not its build step (CMP0114 OLD makes that dep effectively soft). On a
# fast host, lldb's build step wins the race and tries to link before
# cangjie-frontend's import libs exist.
#
# Patch:
#   1. CMP0114 NEW at the top of BuildCJDB.cmake so step targets carry
#      proper dependency edges.
#   2. STEP_TARGETS build configure on ExternalProject_Add(lldb ...) so
#      `lldb-build` becomes an externally-named target.
#   3. add_dependencies(lldb-build cangjie-frontend cangjie-lsp-share) in
#      src/CMakeLists.txt so the build step itself waits.
_BUILDCJDB_POLICY_MARKER = "cmake_policy(SET CMP0114 NEW)"
_BUILDCJDB_HEADER_OLD = (
    "externalproject_get_property(cjnative BINARY_DIR)\n"
    "set(LLVM_GC_BINARY_DIR \"${BINARY_DIR}\")\n"
)
_BUILDCJDB_HEADER_NEW = (
    "cmake_policy(SET CMP0114 NEW)\n"
    "externalproject_get_property(cjnative BINARY_DIR)\n"
    "set(LLVM_GC_BINARY_DIR \"${BINARY_DIR}\")\n"
)
_BUILDCJDB_DEPENDS_OLD = "    USES_TERMINAL_BUILD ON\n    DEPENDS cjnative)\n"
_BUILDCJDB_DEPENDS_NEW = (
    "    USES_TERMINAL_BUILD ON\n"
    "    DEPENDS cjnative\n"
    "    STEP_TARGETS build configure)\n"
)
_SRC_DEPS_OLD = (
    "if(CANGJIE_BUILD_CJDB)\n"
    "    add_dependencies(lldb cangjie-frontend)\n"
    "endif()\n"
)
_SRC_DEPS_NEW = (
    "if(CANGJIE_BUILD_CJDB)\n"
    "    add_dependencies(lldb cangjie-frontend)\n"
    "    if(TARGET lldb-build)\n"
    "        add_dependencies(lldb-build cangjie-frontend cangjie-lsp-share)\n"
    "    endif()\n"
    "endif()\n"
)


def _apply_compiler_cjdb_patches(repo_dir: Path) -> None:
    buildcjdb = repo_dir / "third_party" / "cmake" / "BuildCJDB.cmake"
    src_cmake = repo_dir / "src" / "CMakeLists.txt"
    if not buildcjdb.is_file() or not src_cmake.is_file():
        _log.warning("Skipping cjdb cmake patches: expected files missing")
        return

    text = buildcjdb.read_text()
    if _BUILDCJDB_POLICY_MARKER not in text:
        if _BUILDCJDB_HEADER_OLD not in text:
            raise RuntimeError(
                f"BuildCJDB.cmake header changed; refusing to patch {buildcjdb}"
            )
        text = text.replace(_BUILDCJDB_HEADER_OLD, _BUILDCJDB_HEADER_NEW, 1)
    if "STEP_TARGETS build configure" not in text:
        if _BUILDCJDB_DEPENDS_OLD not in text:
            raise RuntimeError(
                f"BuildCJDB.cmake ExternalProject_Add tail changed; refusing to patch {buildcjdb}"
            )
        text = text.replace(_BUILDCJDB_DEPENDS_OLD, _BUILDCJDB_DEPENDS_NEW, 1)
    buildcjdb.write_text(text)
    _log.info("Patched %s", buildcjdb)

    src_text = src_cmake.read_text()
    if "add_dependencies(lldb-build cangjie-frontend cangjie-lsp-share)" not in src_text:
        if _SRC_DEPS_OLD not in src_text:
            raise RuntimeError(
                f"src/CMakeLists.txt cjdb dep block changed; refusing to patch {src_cmake}"
            )
        src_text = src_text.replace(_SRC_DEPS_OLD, _SRC_DEPS_NEW, 1)
        src_cmake.write_text(src_text)
        _log.info("Patched %s", src_cmake)


def _apply_patches(cfg: BuildConfig) -> None:
    compiler_dir = cfg.repo_path(RepoName.COMPILER)
    if compiler_dir.is_dir():
        _apply_compiler_cjdb_patches(compiler_dir)


def run(cfg: BuildConfig) -> None:
    ensure_dir(cfg.workspace)
    with stage("fetch"):
        for repo in cfg.repos.values():
            target = cfg.workspace / repo.dir_name
            if target.exists():
                _log.info("Repo %s already at %s, skipping clone", repo.name, target)
                continue
            shallow_clone(repo.url, target, tag=repo.tag)
        _apply_patches(cfg)
