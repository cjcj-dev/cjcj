from __future__ import annotations

import tarfile
import zipfile
from pathlib import Path

import pytest

from cangjie_build.config import build_config
from cangjie_build.errors import BuildError
from cangjie_build.stages import package


def _seed_tools_tree(workspace: Path, *, exe_suffix: str) -> None:
    tools = workspace / "cangjie_tools"
    (tools / "cjpm" / "dist").mkdir(parents=True)
    (tools / "cjpm" / "dist" / f"cjpm{exe_suffix}").write_text("#cjpm")

    cjfmt_bin = tools / "cjfmt" / "build" / "build" / "bin"
    cjfmt_bin.mkdir(parents=True)
    (cjfmt_bin / f"cjfmt{exe_suffix}").write_text("#cjfmt")
    cjfmt_cfg = tools / "cjfmt" / "config"
    cjfmt_cfg.mkdir(parents=True)
    (cjfmt_cfg / "default.toml").write_text("style='upstream'\n")

    hle_bin = tools / "hyperlangExtension" / "target" / "bin"
    hle_bin.mkdir(parents=True)
    (hle_bin / f"main{exe_suffix}").write_text("#hle")

    dtsparser_src = tools / "hyperlangExtension" / "src" / "dtsparser"
    dtsparser_src.mkdir(parents=True)
    (dtsparser_src / "parser.ts").write_text("// keep me\n")
    (dtsparser_src / "scratch.cj").write_text("// drop me\n")

    lsp_bin = tools / "cangjie-language-server" / "output" / "bin"
    lsp_bin.mkdir(parents=True)
    (lsp_bin / f"LSPServer{exe_suffix}").write_text("#lsp")


def _seed_compiler_output(workspace: Path, output_name: str, lib_dir: str) -> None:
    out = workspace / "cangjie_compiler" / output_name
    out.mkdir(parents=True)
    (out / "envsetup.sh").write_text("# fake envsetup\n")
    bin_dir = out / "bin"
    bin_dir.mkdir()
    (bin_dir / "cjc").write_text("#cjc")
    lib_root = out / "lib" / lib_dir
    lib_root.mkdir(parents=True)
    (lib_root / "libcangjie-ast-support.a").write_text("ast")  # to be removed
    (lib_root / "libstd.a").write_text("std")


def _seed_stdx(workspace: Path, target_subdir: str) -> None:
    stdx = workspace / "cangjie_stdx" / "target" / target_subdir / "static" / "stdx"
    stdx.mkdir(parents=True)
    (stdx / "libstdx.a").write_text("stdx")


def test_package_linux_layout(tmp_path: Path) -> None:
    workspace = tmp_path / "ws"
    workspace.mkdir()

    _seed_compiler_output(workspace, "output", "linux_x86_64_cjnative")
    _seed_tools_tree(workspace, exe_suffix="")
    _seed_stdx(workspace, "linux_x86_64_cjnative")

    cfg = build_config(
        workspace=workspace,
        build_root=tmp_path / "br",
        target_key="linux-x64",
        cangjie_version="1.2.3",
    )
    sdk, stdx = package.run(cfg)

    assert sdk.exists() and sdk.name == "cangjie-sdk-linux-x64-1.2.3.tar.gz"
    assert stdx.exists() and stdx.name == "cangjie-stdx-linux-x64-1.2.3.1.tar.gz"

    with tarfile.open(sdk, "r:gz") as tf:
        names = set(tf.getnames())

    assert "cangjie/bin/cjc" in names
    assert "cangjie/tools/bin/cjpm" in names
    assert "cangjie/tools/bin/cjfmt" in names
    assert "cangjie/tools/bin/hle" in names
    assert "cangjie/tools/bin/LSPServer" in names
    assert "cangjie/tools/config/default.toml" in names
    assert "cangjie/tools/dtsparser/parser.ts" in names
    # .cj files must be stripped from dtsparser
    assert "cangjie/tools/dtsparser/scratch.cj" not in names
    # ast-support.a must be removed
    assert "cangjie/lib/linux_x86_64_cjnative/libcangjie-ast-support.a" not in names
    assert "cangjie/lib/linux_x86_64_cjnative/libstd.a" in names


def test_package_windows_zip_layout(tmp_path: Path) -> None:
    workspace = tmp_path / "ws"
    workspace.mkdir()

    _seed_compiler_output(workspace, "output-x86_64-w64-mingw32", "windows_x86_64_cjnative")
    _seed_tools_tree(workspace, exe_suffix=".exe")
    _seed_stdx(workspace, "windows_x86_64_cjnative")

    cfg = build_config(
        workspace=workspace,
        build_root=tmp_path / "br",
        target_key="windows-x64",
        cangjie_version="1.2.3",
    )
    sdk, stdx = package.run(cfg)

    assert sdk.exists() and sdk.name == "cangjie-sdk-windows-x64-1.2.3.zip"
    assert stdx.exists() and stdx.name == "cangjie-stdx-windows-x64-1.2.3.1.zip"

    with zipfile.ZipFile(sdk) as zf:
        names = set(zf.namelist())

    assert "cangjie/bin/cjc" in names
    assert "cangjie/tools/bin/cjpm.exe" in names
    assert "cangjie/tools/bin/cjfmt.exe" in names
    assert "cangjie/tools/bin/hle.exe" in names
    assert "cangjie/tools/bin/LSPServer.exe" in names
    assert "cangjie/tools/dtsparser/parser.ts" in names
    assert "cangjie/tools/dtsparser/scratch.cj" not in names


def test_package_strict_failure_when_tool_missing(tmp_path: Path) -> None:
    workspace = tmp_path / "ws"
    workspace.mkdir()
    _seed_compiler_output(workspace, "output", "linux_x86_64_cjnative")
    # Intentionally missing tools tree → BuildError on cjpm.
    cfg = build_config(
        workspace=workspace,
        build_root=tmp_path / "br",
        target_key="linux-x64",
        cangjie_version="1.2.3",
    )
    with pytest.raises(BuildError):
        package.run(cfg)
