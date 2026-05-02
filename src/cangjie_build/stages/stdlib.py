from __future__ import annotations

from cangjie_build.config import BuildConfig, RepoName
from cangjie_build.logging_setup import stage
from cangjie_build.stages._common import copy_contents, run_build_py, windows_cross_args
from cangjie_build.toolchain import mingw


def run(cfg: BuildConfig) -> None:
    stdlib_root = cfg.repo_path(RepoName.RUNTIME) / "stdlib"
    runtime_target = cfg.repo_path(RepoName.RUNTIME) / "runtime" / "target"
    stdlib_output = stdlib_root / "output"
    compiler_output = cfg.repo_path(RepoName.COMPILER) / "output"

    with stage("stdlib"):
        run_build_py(cfg, stdlib_root, ["clean"], stage_name="stdlib.clean.linux")
        run_build_py(
            cfg,
            stdlib_root,
            ["build", "-t", cfg.build_type, f"--target-lib={runtime_target}"],
            stage_name="stdlib.build.linux",
        )
        run_build_py(cfg, stdlib_root, ["install"], stage_name="stdlib.install.linux")
        copy_contents(stdlib_output, compiler_output, stage="stdlib.copy.linux")

        if not cfg.target.spec.cross_compile:
            return

        run_build_py(cfg, stdlib_root, ["clean"], stage_name="stdlib.clean.windows")
        mingw_lib = mingw.install_path(cfg.build_root) / mingw.TARGET_TRIPLE / "lib"
        run_build_py(
            cfg,
            stdlib_root,
            [
                "build",
                "-t",
                cfg.cross_build_type,
                f"--target-lib={runtime_target}",
                f"--target-lib={mingw_lib}",
                *windows_cross_args(cfg),
            ],
            stage_name="stdlib.build.windows",
        )
        run_build_py(cfg, stdlib_root, ["install"], stage_name="stdlib.install.windows")
        copy_contents(stdlib_output, compiler_output, stage="stdlib.copy.windows.host")
        copy_contents(
            stdlib_output,
            cfg.repo_path(RepoName.COMPILER) / "output-x86_64-w64-mingw32",
            stage="stdlib.copy.windows.cross",
        )
