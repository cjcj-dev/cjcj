from __future__ import annotations

from pathlib import Path

from cangjie_build.config import BuildConfig, RepoName
from cangjie_build.errors import BuildError
from cangjie_build.logging_setup import get_logger, stage
from cangjie_build.runner import CommandPart
from cangjie_build.stages._common import require_file, run_build_py

_log = get_logger("cangjie_build.stages.tools")

# Each tool lives under cangjie_tools/<subpath>; build.py is invoked in that dir.
_TOOL_PATHS: tuple[tuple[str, str], ...] = (
    ("cjpm", "cjpm/build"),
    ("cjfmt", "cjfmt/build"),
    ("hle", "hyperlangExtension/build"),
    ("lsp", "cangjie-language-server/build"),
)

# cjpm's cross-windows link line hardcodes /opt/buildtools/llvm-mingw-w64
# (matching upstream linux_cross_windows_zh.md's BUILD_ROOT). Our build_root
# is per-runner, so we rewrite it to honor $MINGW_PATH instead — same shape
# as cjpm's native-windows branch already uses for the mingw lib dir.
_CJPM_OPT_PATH = "-L /opt/buildtools/llvm-mingw-w64/x86_64-w64-mingw32/lib"
_CJPM_OPT_PATH_FIXED = (
    "-L {os.path.join(os.environ['MINGW_PATH'], 'x86_64-w64-mingw32', 'lib')}"
)
# cjpm's main() returns the subcommand's exit code but the entry point
# discards it (`if __name__ == '__main__': main()`), so a failed link still
# exits 0 and our runner thinks the build succeeded. Make it propagate.
_CJPM_MAIN_OLD = "if __name__ == '__main__':\n    main()\n"
_CJPM_MAIN_NEW = "if __name__ == '__main__':\n    import sys\n    sys.exit(main())\n"


def _patch_cjpm_build_py(build_py: Path) -> None:
    text = build_py.read_text()
    original = text
    if _CJPM_OPT_PATH in text:
        text = text.replace(_CJPM_OPT_PATH, _CJPM_OPT_PATH_FIXED)
    if _CJPM_MAIN_OLD in text:
        text = text.replace(_CJPM_MAIN_OLD, _CJPM_MAIN_NEW)
    if text != original:
        build_py.write_text(text)
        _log.info("Patched %s", build_py)


def _build_args_for(name: str, cfg: BuildConfig) -> list[CommandPart]:
    if cfg.target.spec.cross_compile:
        return ["build", "-t", cfg.cross_build_type, "--target", "windows-x86_64"]
    args: list[CommandPart] = ["build", "-t", cfg.build_type]
    if name == "cjpm":
        # Linux native cjpm needs an rpath so it locates the runtime's shared libs at runtime.
        args += ["--set-rpath", "$ORIGIN/../../runtime/lib/linux_x86_64_cjnative"]
    return args


def run(cfg: BuildConfig) -> None:
    tools_root = cfg.repo_path(RepoName.TOOLS)
    suffix = cfg.target.spec.exe_suffix
    with stage("tools"):
        _patch_cjpm_build_py(tools_root / "cjpm" / "build" / "build.py")
        for name, subpath in _TOOL_PATHS:
            cwd = tools_root / subpath
            run_build_py(cfg, cwd, ["clean"], stage_name=f"tools.{name}.clean")
            run_build_py(cfg, cwd, _build_args_for(name, cfg), stage_name=f"tools.{name}.build")
            run_build_py(cfg, cwd, ["install"], stage_name=f"tools.{name}.install")

        # Defense in depth: if a tool's build.py silently swallowed a failure
        # (cjpm's main() pattern, possibly others), surface it now.
        require_file(
            tools_root / "cjpm" / "dist" / f"cjpm{suffix}",
            stage="tools.cjpm.verify",
        )
