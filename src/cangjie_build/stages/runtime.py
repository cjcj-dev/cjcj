from __future__ import annotations

from cangjie_build.config import BuildConfig, RepoName
from cangjie_build.logging_setup import stage
from cangjie_build.stages._common import (
    copy_contents,
    ensure_dir,
    run_build_py,
    windows_cross_args,
)


def run(cfg: BuildConfig) -> None:
    runtime_root = cfg.repo_path(RepoName.RUNTIME) / "runtime"
    target_dir = runtime_root / "target"
    compiler_output = cfg.repo_path(RepoName.COMPILER) / "output"

    with stage("runtime"):
        ensure_dir(target_dir)

        # Linux x64 runtime is always built (host-side compiler driver needs it).
        run_build_py(cfg, runtime_root, ["clean"], stage_name="runtime.clean.linux")
        run_build_py(
            cfg,
            runtime_root,
            ["build", "-t", cfg.build_type, "-v", cfg.cangjie_version],
            stage_name="runtime.build.linux",
        )
        run_build_py(cfg, runtime_root, ["install"], stage_name="runtime.install.linux")
        copy_contents(runtime_root / "output", target_dir, stage="runtime.snapshot.linux")

        linux_subdir = runtime_root / "output" / "common" / cfg.target.runtime_output_subdir(
            cfg.build_type
        )
        for sub in ("lib", "runtime"):
            copy_contents(linux_subdir / sub, compiler_output / sub, stage="runtime.copy.linux")

        if not cfg.target.spec.cross_compile:
            return

        run_build_py(cfg, runtime_root, ["clean"], stage_name="runtime.clean.windows")
        run_build_py(
            cfg,
            runtime_root,
            [
                "build",
                "-t",
                cfg.cross_build_type,
                *windows_cross_args(cfg, sysroot=False),
                "-v",
                cfg.cangjie_version,
            ],
            stage_name="runtime.build.windows",
        )
        run_build_py(cfg, runtime_root, ["install"], stage_name="runtime.install.windows")
        copy_contents(runtime_root / "output", target_dir, stage="runtime.snapshot.windows")

        windows_subdir = runtime_root / "output" / "common" / cfg.target.runtime_output_subdir(
            cfg.cross_build_type
        )
        compiler_mingw_output = cfg.repo_path(RepoName.COMPILER) / "output-x86_64-w64-mingw32"
        for sub in ("lib", "runtime"):
            copy_contents(
                windows_subdir / sub, compiler_output / sub, stage="runtime.copy.windows.host"
            )
            copy_contents(
                windows_subdir / sub,
                compiler_mingw_output / sub,
                stage="runtime.copy.windows.cross",
            )
