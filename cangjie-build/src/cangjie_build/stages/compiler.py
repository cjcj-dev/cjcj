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
    windows_cross_args,
)
from cangjie_build.toolchain import static_libs, target_python


def run(cfg: BuildConfig) -> None:
    repo_dir = cfg.repo_path(RepoName.COMPILER)
    with stage("compiler"):
        run_build_py(cfg, repo_dir, ["clean"], stage_name="compiler.clean")

        if cfg.target.spec.cross_compile:
            # Host-side compiler must be built first so the windows-targeted runs have a working cjc.
            run_build_py(
                cfg,
                repo_dir,
                ["build", "-t", cfg.build_type, "--no-tests", "-v", cfg.cangjie_version],
                stage_name="compiler.build.host",
            )
            cross_args = windows_cross_args(cfg)
            # BuildCJDB.cmake's cross-windows path links lldb against
            # ${TARGET_PYTHON_PATH}/python<M><N>.dll and uses headers from
            # include/python<M>.<N>/. Stage a NuGet python bundle and point
            # the build at it. Idempotent — call from here so `build compiler`
            # works without needing a separate install-target-python step.
            tpp = target_python.install(cfg.build_root)
            tpp_env = {"TARGET_PYTHON_PATH": str(tpp)}
            # cross_build_type is forced to 'release' (config.py): cangjie's
            # relwithdebinfo path has multiple MinGW bugs (static-lib switch in
            # src/CMakeLists.txt:272, -fdebug-types-section in pcre2 flags).
            # The lldb-build vs cangjie-frontend race is fixed by fetch.py's
            # cmake patches, so a single pass with --build-cjdb is enough.
            run_build_py(
                cfg,
                repo_dir,
                [
                    "build",
                    "-t",
                    cfg.cross_build_type,
                    "--product",
                    "cjc",
                    "--no-tests",
                    "--build-cjdb",
                    "-v",
                    cfg.cangjie_version,
                    *cross_args,
                ],
                stage_name="compiler.build.windows.cjc",
                extra_env=tpp_env,
            )
            run_build_py(
                cfg,
                repo_dir,
                [
                    "build",
                    "-t",
                    cfg.cross_build_type,
                    "--product",
                    "libs",
                    "-v",
                    cfg.cangjie_version,
                    *cross_args,
                ],
                stage_name="compiler.build.windows.libs",
                extra_env=tpp_env,
            )
            run_build_py(
                cfg,
                repo_dir,
                ["install", "--host", "windows-x86_64"],
                stage_name="compiler.install.windows",
                extra_env=tpp_env,
            )
            run_build_py(cfg, repo_dir, ["install"], stage_name="compiler.install.host")

            # cmake doesn't bundle the runtime DLL itself — only its own
            # site-packages under tools/lib/python<M>.<N>/. Drop python<M><N>.dll
            # next to lldb/cjdb so the binary loads on the windows target.
            target_python.install_runtime_dlls(
                tpp, repo_dir / "output-x86_64-w64-mingw32" / "tools" / "bin"
            )

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
            "-v",
            cfg.cangjie_version,
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
