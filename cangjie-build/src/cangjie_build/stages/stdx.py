from __future__ import annotations

from cangjie_build.config import BuildConfig, RepoName
from cangjie_build.logging_setup import stage
from cangjie_build.runner import CommandPart
from cangjie_build.stages._common import run_build_py, windows_cross_args
from cangjie_build.toolchain import mingw


def run(cfg: BuildConfig) -> None:
    stdx_root = cfg.repo_path(RepoName.STDX)
    compiler_include = cfg.repo_path(RepoName.COMPILER) / "include"

    with stage("stdx"):
        run_build_py(cfg, stdx_root, ["clean"], stage_name="stdx.clean")
        if cfg.target.spec.cross_compile:
            mingw_lib = mingw.install_path(cfg.build_root) / mingw.TARGET_TRIPLE / "lib"
            args: list[CommandPart] = [
                "build",
                "-t",
                cfg.cross_build_type,
                f"--include={compiler_include}",
                f"--target-lib={mingw_lib}",
                *windows_cross_args(cfg),
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
