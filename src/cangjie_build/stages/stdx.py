from __future__ import annotations

from cangjie_build.config import BuildConfig, RepoName
from cangjie_build.logging_setup import stage
from cangjie_build.runner import CommandPart
from cangjie_build.stages._common import run_build_py
from cangjie_build.toolchain import mingw


def run(cfg: BuildConfig) -> None:
    stdx_root = cfg.repo_path(RepoName.STDX)
    compiler_include = cfg.repo_path(RepoName.COMPILER) / "include"

    with stage("stdx"):
        run_build_py(cfg, stdx_root, ["clean"], stage_name="stdx.clean")
        if cfg.target.spec.cross_compile:
            mingw_path = mingw.install_path(cfg.build_root)
            args: list[CommandPart] = [
                "build",
                "-t",
                cfg.build_type,
                f"--include={compiler_include}",
                f"--target-lib={mingw_path / mingw.TARGET_TRIPLE / 'lib'}",
                "--target",
                "windows-x86_64",
                "--target-sysroot",
                f"{mingw_path}/",
                "--target-toolchain",
                str(mingw_path / "bin"),
            ]
        else:
            args = [
                "build",
                "-t",
                cfg.build_type,
                f"--include={compiler_include}",
            ]
        run_build_py(cfg, stdx_root, args, stage_name="stdx.build")
        run_build_py(cfg, stdx_root, ["install"], stage_name="stdx.install")
