from __future__ import annotations

from cangjie_build.config import BuildConfig, RepoName
from cangjie_build.logging_setup import get_logger, stage
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

_log = get_logger("cangjie_build.stages.compiler")


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
            # cangjie's src/CMakeLists.txt:272 force-enables
            # WIN_DEBUG_USE_STATIC_LIB on MinGW for build types matching
            # ^(Debug|RelWithDebInfo|MinSizeRelWithDebInfo)$, which builds
            # cangjie-frontend as STATIC (.a) instead of SHARED (.dll +
            # .dll.a). But BuildCJDB.cmake still tells lldb to link against
            # libcangjie-frontend.dll.a — file that never gets produced
            # under that build type. Pass 'release' for the windows cross
            # build to dodge that branch and get a real shared lib +
            # import lib. Upstream's linux_cross_windows_zh.md does the same.
            cross_build_type = "release"
            cjc_base_args: list[CommandPart] = [
                "build",
                "-t",
                cross_build_type,
                "--product",
                "cjc",
                "--no-tests",
                *cross_args,
            ]
            # Cangjie's BuildCJDB.cmake declares lldb's ExternalProject with
            # `DEPENDS cjnative` only — no dep on cangjie-frontend / cangjie-lsp,
            # whose import libs lldb's link consumes. Slow hosts mask the race
            # because lldb-with-Python is heavier than cangjie-frontend; with
            # --cjdb-disable-python on a fast host (F16als_v7) lldb hits its
            # link step almost immediately and loses. None of our cmake patch
            # attempts wired the dep correctly (CMP0114 OLD makes target-level
            # deps soft, NEW didn't fix it; ExternalProject_Add_StepDependencies
            # uses add_custom_command APPEND with a hard cross-directory limit).
            #
            # Sequence the build into two passes from the harness:
            #   Pass 1: --product cjc (no --build-cjdb)
            #     → cmake configures with -DCANGJIE_BUILD_CJDB=OFF, lldb is
            #       not in the build graph at all. ninja builds cjc.exe,
            #       cangjie-frontend (.dll + .dll.a), cangjie-lsp-share
            #       (libcangjie-lsp.dll). No race possible.
            #   rm build.ninja
            #     → cangjie's build.py only re-runs cmake when build.ninja
            #       is absent. Removing it forces pass 2 to reconfigure
            #       with the new flag.
            #   Pass 2: --product cjc --build-cjdb --cjdb-disable-python
            #     → cmake re-runs with -DCANGJIE_BUILD_CJDB=ON, adds the
            #       lldb ExternalProject. ninja sees cangjie-frontend's
            #       outputs already on disk (timestamps unchanged), only
            #       schedules the new lldb-build step. lldb's nested
            #       link finds the import libs and succeeds.
            run_build_py(cfg, repo_dir, cjc_base_args, stage_name="compiler.build.windows.cjc")
            # cangjie's build.py passes args.target through TARGET_DICTIONARY:
            # "windows-x86_64" → "x86_64-w64-mingw32", and the cmake build dir
            # is build/build-cjc-<mapped-triple>.
            ninja_file = repo_dir / "build" / "build-cjc-x86_64-w64-mingw32" / "build.ninja"
            if ninja_file.is_file():
                _log.info("Removing %s to force cmake re-run in pass 2", ninja_file)
                ninja_file.unlink()
            run_build_py(
                cfg,
                repo_dir,
                [*cjc_base_args, "--build-cjdb", "--cjdb-disable-python"],
                stage_name="compiler.build.windows.cjdb",
            )
            run_build_py(
                cfg,
                repo_dir,
                [
                    "build",
                    "-t",
                    cross_build_type,
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
