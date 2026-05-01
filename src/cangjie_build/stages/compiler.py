from __future__ import annotations

from cangjie_build.config import BuildConfig, RepoName
from cangjie_build.logging_setup import stage
from cangjie_build.runner import CommandPart
from cangjie_build.runner import run as run_cmd
from cangjie_build.stages._common import (
    copy_contents,
    merged_env,
    python_exe,
    require_dir,
    run_build_py,
)
from cangjie_build.toolchain import mingw, static_libs


def run(cfg: BuildConfig) -> None:
    repo_dir = cfg.repo_path(RepoName.COMPILER)
    with stage("compiler"):
        run_build_py(cfg, repo_dir, ["clean"], stage_name="compiler.clean")

        if cfg.target.spec.cross_compile:
            # Host-side compiler must be built first so the windows-targeted runs have a working cjc.
            run_build_py(
                cfg,
                repo_dir,
                ["build", "-t", cfg.build_type, "--no-tests"],
                stage_name="compiler.build.host",
            )
            mingw_path = mingw.install_path(cfg.build_root)
            cross_args: list[CommandPart] = [
                "--target",
                "windows-x86_64",
                "--target-sysroot",
                f"{mingw_path}/",
                "--target-toolchain",
                str(mingw_path / "bin"),
            ]
            run_build_py(
                cfg,
                repo_dir,
                [
                    "build",
                    "-t",
                    cfg.build_type,
                    "--product",
                    "cjc",
                    "--no-tests",
                    *cross_args,
                    "--build-cjdb",
                ],
                stage_name="compiler.build.windows.cjc",
            )
            run_build_py(
                cfg,
                repo_dir,
                [
                    "build",
                    "-t",
                    cfg.build_type,
                    "--product",
                    "libs",
                    *cross_args,
                ],
                stage_name="compiler.build.windows.libs",
            )
            run_build_py(
                cfg,
                repo_dir,
                ["install", "--host", "windows-x86_64"],
                stage_name="compiler.install.windows",
            )
            run_build_py(cfg, repo_dir, ["install"], stage_name="compiler.install.host")

            copy_contents(
                repo_dir / "output-x86_64-w64-mingw32",
                repo_dir / "output",
                stage="compiler.merge",
            )
            return

        target_lib = static_libs.target_lib_path(cfg.build_root)
        build_args: list[CommandPart] = [
            "build",
            "-t",
            cfg.build_type,
            "--no-tests",
            "--build-cjdb",
        ]
        if target_lib.exists():
            build_args.extend(["--target-lib", str(target_lib)])
        run_build_py(cfg, repo_dir, build_args, stage_name="compiler.build.linux")
        run_build_py(cfg, repo_dir, ["install"], stage_name="compiler.install")


def run_tests(cfg: BuildConfig) -> None:
    """Run the compiler's own test suite (Linux native only)."""
    if cfg.target.spec.cross_compile:
        return
    repo_dir = cfg.repo_path(RepoName.COMPILER)
    envsetup = repo_dir / "output" / "envsetup.sh"
    require_dir(repo_dir, stage="compiler.test")
    if not envsetup.is_file():
        raise FileNotFoundError(envsetup)
    run_cmd(
        ["bash", "-c", f"set -e; source '{envsetup}'; {python_exe()} build.py test"],
        cwd=repo_dir,
        env_overlay=merged_env(cfg),
        stage="compiler.test",
    )
