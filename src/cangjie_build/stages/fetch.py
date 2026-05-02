from __future__ import annotations

from pathlib import Path

from cangjie_build.config import BuildConfig, RepoName
from cangjie_build.git import shallow_clone
from cangjie_build.logging_setup import get_logger, stage
from cangjie_build.stages._common import apply_text_patch, ensure_dir

_log = get_logger("cangjie_build.stages.fetch")


# lldb's link consumes cangjie-frontend/cangjie-lsp import libs but its
# ExternalProject only `DEPENDS cjnative`. The existing
# `add_dependencies(lldb cangjie-frontend)` only chains the super-target's
# done-signal, not the build step (CMP0114 OLD makes step deps soft). On a
# fast host lldb's build step wins the race and tries to link before the
# import libs exist. Patch:
#   1. CMP0114 NEW so step-target deps are hard.
#   2. STEP_TARGETS build configure to materialize lldb-build externally.
#   3. add_dependencies(lldb-build cangjie-frontend cangjie-lsp-share) so
#      the build step itself waits.
_BUILDCJDB_EDITS: tuple[tuple[str, str], ...] = (
    (
        "externalproject_get_property(cjnative BINARY_DIR)\n"
        "set(LLVM_GC_BINARY_DIR \"${BINARY_DIR}\")\n",
        "cmake_policy(SET CMP0114 NEW)\n"
        "externalproject_get_property(cjnative BINARY_DIR)\n"
        "set(LLVM_GC_BINARY_DIR \"${BINARY_DIR}\")\n",
    ),
    (
        "    USES_TERMINAL_BUILD ON\n    DEPENDS cjnative)\n",
        "    USES_TERMINAL_BUILD ON\n"
        "    DEPENDS cjnative\n"
        "    STEP_TARGETS build configure)\n",
    ),
)
_BUILDCJDB_MARKER = "STEP_TARGETS build configure"

_SRC_CMAKE_EDITS: tuple[tuple[str, str], ...] = (
    (
        "if(CANGJIE_BUILD_CJDB)\n"
        "    add_dependencies(lldb cangjie-frontend)\n"
        "endif()\n",
        "if(CANGJIE_BUILD_CJDB)\n"
        "    add_dependencies(lldb cangjie-frontend)\n"
        "    if(TARGET lldb-build)\n"
        "        add_dependencies(lldb-build cangjie-frontend cangjie-lsp-share)\n"
        "    endif()\n"
        "endif()\n",
    ),
)
_SRC_CMAKE_MARKER = "add_dependencies(lldb-build cangjie-frontend cangjie-lsp-share)"


def _apply_compiler_cjdb_patches(repo_dir: Path) -> None:
    apply_text_patch(
        repo_dir / "third_party" / "cmake" / "BuildCJDB.cmake",
        _BUILDCJDB_EDITS,
        stage="fetch.patch",
        marker=_BUILDCJDB_MARKER,
    )
    apply_text_patch(
        repo_dir / "src" / "CMakeLists.txt",
        _SRC_CMAKE_EDITS,
        stage="fetch.patch",
        marker=_SRC_CMAKE_MARKER,
    )


def run(cfg: BuildConfig) -> None:
    ensure_dir(cfg.workspace)
    with stage("fetch"):
        for repo in cfg.repos.values():
            target = cfg.workspace / repo.dir_name
            if target.exists():
                _log.info("Repo %s already at %s, skipping clone", repo.name, target)
                continue
            shallow_clone(repo.url, target, tag=repo.tag)
        _apply_compiler_cjdb_patches(cfg.repo_path(RepoName.COMPILER))
