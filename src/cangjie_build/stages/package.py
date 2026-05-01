from __future__ import annotations

import shutil
from collections.abc import Iterable
from pathlib import Path

from cangjie_build.config import BuildConfig, RepoName
from cangjie_build.errors import BuildError
from cangjie_build.logging_setup import get_logger, stage
from cangjie_build.stages._common import (
    copy_into,
    copytree,
    ensure_dir,
    require_dir,
    require_file,
)

_log = get_logger("cangjie_build.stages.package")

_ARCHIVE_FORMATS: dict[str, str] = {"tar.gz": "gztar", "zip": "zip"}


def _suffix(cfg: BuildConfig) -> str:
    return cfg.target.spec.exe_suffix


def _platform_lib_dir_name(cfg: BuildConfig) -> str:
    base = "windows" if cfg.target.spec.cross_compile else "linux"
    return f"{base}_x86_64_cjnative"


def _make_archive(cfg: BuildConfig, src_dir: Path, base_name: str) -> Path:
    fmt = cfg.target.spec.archive_format
    shutil_fmt = _ARCHIVE_FORMATS[fmt]
    cfg.software_dir.mkdir(parents=True, exist_ok=True)
    archive_base = cfg.software_dir / base_name
    _log.info("Creating %s archive %s.%s", fmt, archive_base, fmt)
    produced = shutil.make_archive(
        base_name=str(archive_base),
        format=shutil_fmt,
        root_dir=str(src_dir.parent),
        base_dir=src_dir.name,
    )
    return Path(produced)


def _glob_or_fail(pattern_dir: Path, pattern: str, *, stage_name: str) -> list[Path]:
    matches = sorted(pattern_dir.glob(pattern))
    if not matches:
        raise BuildError(stage_name, f"no files match {pattern_dir}/{pattern}")
    return matches


def _remove_files(paths: Iterable[Path]) -> None:
    for p in paths:
        if p.is_file():
            p.unlink()


def _organize_sdk_tree(cfg: BuildConfig, dest: Path) -> None:
    """Mirrors §5 of the upstream build doc, but with strict-failure semantics."""
    suffix = _suffix(cfg)
    tools_root = cfg.repo_path(RepoName.TOOLS)

    # ast-support.a is intentionally excluded from the SDK by the upstream build doc.
    ast_support = dest / "lib" / _platform_lib_dir_name(cfg) / "libcangjie-ast-support.a"
    if ast_support.is_file():
        ast_support.unlink()
        _log.info("Removed %s", ast_support)

    tools_bin = ensure_dir(dest / "tools" / "bin")
    tools_config = ensure_dir(dest / "tools" / "config")

    cjpm = require_file(tools_root / "cjpm" / "dist" / f"cjpm{suffix}", stage="package.cjpm")
    copy_into(cjpm, tools_bin, stage="package.cjpm")

    cjfmt = require_file(
        tools_root / "cjfmt" / "build" / "build" / "bin" / f"cjfmt{suffix}",
        stage="package.cjfmt",
    )
    copy_into(cjfmt, tools_bin, stage="package.cjfmt")
    for toml in _glob_or_fail(
        tools_root / "cjfmt" / "config", "*.toml", stage_name="package.cjfmt.config"
    ):
        copy_into(toml, tools_config, stage="package.cjfmt.config")

    hle_src = require_file(
        tools_root / "hyperlangExtension" / "target" / "bin" / f"main{suffix}",
        stage="package.hle",
    )
    shutil.copy2(hle_src, tools_bin / f"hle{suffix}")

    dtsparser_src = require_dir(
        tools_root / "hyperlangExtension" / "src" / "dtsparser",
        stage="package.dtsparser",
    )
    dtsparser_dst = dest / "tools" / "dtsparser"
    copytree(dtsparser_src, dtsparser_dst, stage="package.dtsparser")
    _remove_files(dtsparser_dst.glob("*.cj"))

    lsp = require_file(
        tools_root / "cangjie-language-server" / "output" / "bin" / f"LSPServer{suffix}",
        stage="package.lsp",
    )
    copy_into(lsp, tools_bin, stage="package.lsp")


def _package_main_sdk(cfg: BuildConfig) -> Path:
    compiler_output = cfg.repo_path(RepoName.COMPILER) / cfg.target.primary_compiler_output()
    require_dir(compiler_output, stage="package.compiler_output")

    cangjie_dir = ensure_dir(cfg.software_dir) / "cangjie"
    if cangjie_dir.exists():
        shutil.rmtree(cangjie_dir)
    shutil.copytree(compiler_output, cangjie_dir, symlinks=True)

    _organize_sdk_tree(cfg, cangjie_dir)

    base_name = f"cangjie-sdk-{cfg.target.spec.sdk_name}-{cfg.cangjie_version}"
    return _make_archive(cfg, cangjie_dir, base_name)


def _package_stdx(cfg: BuildConfig) -> Path:
    stdx_dir = cfg.repo_path(RepoName.STDX) / "target" / cfg.target.stdx_target_subdir()
    require_dir(stdx_dir, stage="package.stdx")

    staged = ensure_dir(cfg.software_dir) / stdx_dir.name
    if staged.exists():
        shutil.rmtree(staged)
    shutil.copytree(stdx_dir, staged, symlinks=True)

    base_name = f"cangjie-stdx-{cfg.target.spec.sdk_name}-{cfg.cangjie_version}.{cfg.stdx_version}"
    return _make_archive(cfg, staged, base_name)


def run(cfg: BuildConfig) -> tuple[Path, Path]:
    """Produce the SDK and STDX archives. Returns ``(sdk_archive, stdx_archive)``."""
    with stage("package"):
        ensure_dir(cfg.software_dir)
        sdk = _package_main_sdk(cfg)
        stdx = _package_stdx(cfg)
        _log.info("SDK   -> %s", sdk)
        _log.info("STDX  -> %s", stdx)
        return sdk, stdx
