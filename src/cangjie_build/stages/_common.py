"""Internal helpers shared by stage modules."""

from __future__ import annotations

import os
import shutil
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path

from cangjie_build.config import BuildConfig
from cangjie_build.errors import BuildError
from cangjie_build.logging_setup import get_logger
from cangjie_build.runner import CommandPart
from cangjie_build.runner import run as _run
from cangjie_build.toolchain import mingw, static_libs

_log = get_logger("cangjie_build.stages")


def base_env(cfg: BuildConfig) -> dict[str, str]:
    """Compose the env overlay every ``build.py`` invocation needs.

    Mirrors the exports listed in ``ref/cangjie_official_build/docs/linux*_zh.md``.
    """
    env: dict[str, str] = {
        "ARCH": "x86_64",
        "SDK_NAME": cfg.target.spec.sdk_name,
        "CANGJIE_VERSION": cfg.cangjie_version,
        "STDX_VERSION": str(cfg.stdx_version),
        "BUILD_ROOT": str(cfg.build_root),
        "WORKSPACE": str(cfg.workspace),
    }
    # Make clang-15 available without polluting the global PATH.
    extra_path_dirs: list[str] = ["/usr/lib/llvm-15/bin"]
    if cfg.target.spec.needs_mingw:
        env["MINGW_PATH"] = str(mingw.install_path(cfg.build_root))
        extra_path_dirs.insert(0, str(mingw.install_path(cfg.build_root) / "bin"))

    if not cfg.target.spec.cross_compile and sys.platform == "linux":
        # OPENSSL_PATH is required by stdlib and STDX builds on Linux.
        candidate = Path("/usr/lib/x86_64-linux-gnu")
        if candidate.exists():
            env["OPENSSL_PATH"] = str(candidate)
            ld_existing = os.environ.get("LD_LIBRARY_PATH", "")
            env["LD_LIBRARY_PATH"] = (
                f"{candidate}{os.pathsep}{ld_existing}" if ld_existing else str(candidate)
            )

    current_path = os.environ.get("PATH", "")
    env["PATH"] = os.pathsep.join(p for p in [*extra_path_dirs, current_path] if p)
    return env


def cmake_prefix_path_for(cfg: BuildConfig) -> str | None:
    """Compute the value of CMAKE_PREFIX_PATH appropriate for ``cfg``.

    - Native Linux: include the static libedit/ncurses prefixes if present.
    - Cross-compile to Windows: include MinGW sysroot.
    """
    parts: list[str] = []
    if cfg.target.spec.needs_mingw:
        parts.append(str(mingw.install_path(cfg.build_root) / mingw.TARGET_TRIPLE))
    elif sys.platform == "linux":
        ncurses_root = cfg.build_root / f"ncurses-{static_libs.NCURSES_VERSION}" / "usr"
        libedit_root = cfg.build_root / "libedit-3.1"
        if ncurses_root.exists() or libedit_root.exists():
            parts.append(static_libs.cmake_prefix_path(cfg.build_root))
    return os.pathsep.join(parts) if parts else None


def merged_env(cfg: BuildConfig, *extra: Mapping[str, str]) -> dict[str, str]:
    env = base_env(cfg)
    cmake_prefix = cmake_prefix_path_for(cfg)
    if cmake_prefix:
        env["CMAKE_PREFIX_PATH"] = cmake_prefix
    for layer in extra:
        env.update(layer)
    return env


def python_exe() -> str:
    return sys.executable or "python3"


def run_build_py(
    cfg: BuildConfig,
    cwd: Path,
    args: Sequence[CommandPart],
    *,
    stage_name: str,
) -> None:
    """Invoke ``python build.py <args>`` inside ``cwd`` with the standard env overlay."""
    require_dir(cwd, stage=stage_name)
    _run(
        [python_exe(), "build.py", *args],
        cwd=cwd,
        env_overlay=merged_env(cfg),
        stage=stage_name,
    )


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def require_dir(path: Path, *, stage: str) -> Path:
    if not path.is_dir():
        raise BuildError(stage, f"required directory missing: {path}")
    return path


def require_file(path: Path, *, stage: str) -> Path:
    if not path.is_file():
        raise BuildError(stage, f"required file missing: {path}")
    return path


def copytree(src: Path, dst: Path, *, stage: str) -> None:
    require_dir(src, stage=stage)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(src, dst, dirs_exist_ok=True, symlinks=True)


def copy_into(src: Path, dst_dir: Path, *, stage: str) -> Path:
    require_file(src, stage=stage)
    dst_dir.mkdir(parents=True, exist_ok=True)
    target = dst_dir / src.name
    shutil.copy2(src, target)
    return target


def copy_contents(src_dir: Path, dst_dir: Path, *, stage: str) -> None:
    """Mimic ``cp -R src/* dst/`` semantics."""
    require_dir(src_dir, stage=stage)
    dst_dir.mkdir(parents=True, exist_ok=True)
    for entry in src_dir.iterdir():
        target = dst_dir / entry.name
        if entry.is_dir():
            shutil.copytree(entry, target, dirs_exist_ok=True, symlinks=True)
        else:
            shutil.copy2(entry, target)
