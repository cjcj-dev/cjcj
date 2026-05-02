from __future__ import annotations

from cangjie_build.config import BuildConfig, RepoName
from cangjie_build.logging_setup import stage
from cangjie_build.runner import CommandPart
from cangjie_build.stages._common import apply_text_patch, require_file, run_build_py

# Each tool lives under cangjie_tools/<subpath>; build.py is invoked in that dir.
_TOOL_PATHS: tuple[tuple[str, str], ...] = (
    ("cjpm", "cjpm/build"),
    ("cjfmt", "cjfmt/build"),
    ("hle", "hyperlangExtension/build"),
    ("lsp", "cangjie-language-server/build"),
)

# cjpm's cross-windows link line hardcodes /opt/buildtools/llvm-mingw-w64
# (matching upstream linux_cross_windows_zh.md's BUILD_ROOT). Our build_root
# is per-runner, so we rewrite the literal to interpolate $MINGW_PATH at
# runtime. The surrounding string in cjpm/build.py is an f-string, so the
# braces are evaluated by cjpm itself when it builds the cjc command.
#
# The native-windows branch (`is_windows`) in upstream already uses the same
# {os.path.join(os.environ['MINGW_PATH']...)} expression, so a positive
# marker on that substring would falsely report "already patched" and let
# the cross-windows /opt/buildtools/... literal slip through. Instead use
# the *absence* of /opt/buildtools/llvm-mingw-w64 as the "patched" signal —
# that string only appears in the cross-windows branch and is gone after
# we substitute.
_CJPM_NEEDLE = "/opt/buildtools/llvm-mingw-w64"
_CJPM_EDITS: tuple[tuple[str, str], ...] = (
    (
        "-L /opt/buildtools/llvm-mingw-w64/x86_64-w64-mingw32/lib",
        "-L {os.path.join(os.environ['MINGW_PATH'], 'x86_64-w64-mingw32', 'lib')}",
    ),
)


def _build_args_for(name: str, cfg: BuildConfig) -> list[CommandPart]:
    if cfg.target.spec.cross_compile:
        return ["build", "-t", cfg.cross_build_type, "--target", "windows-x86_64"]
    args: list[CommandPart] = ["build", "-t", cfg.build_type]
    if name == "cjpm":
        rpath = f"$ORIGIN/../../runtime/lib/{cfg.target.runtime_lib_subdir(cfg.build_type)}"
        args += ["--set-rpath", rpath]
    return args


def run(cfg: BuildConfig) -> None:
    tools_root = cfg.repo_path(RepoName.TOOLS)
    suffix = cfg.target.spec.exe_suffix
    with stage("tools"):
        cjpm_build_py = tools_root / "cjpm" / "build" / "build.py"
        if _CJPM_NEEDLE in cjpm_build_py.read_text():
            apply_text_patch(
                cjpm_build_py,
                _CJPM_EDITS,
                stage="tools.cjpm.patch",
            )
        for name, subpath in _TOOL_PATHS:
            cwd = tools_root / subpath
            run_build_py(cfg, cwd, ["clean"], stage_name=f"tools.{name}.clean")
            run_build_py(cfg, cwd, _build_args_for(name, cfg), stage_name=f"tools.{name}.build")
            run_build_py(cfg, cwd, ["install"], stage_name=f"tools.{name}.install")

        # cjpm's main() discards the subcommand return code, so a failed
        # link still exits 0. Catch that here by asserting the artifact.
        require_file(
            tools_root / "cjpm" / "dist" / f"cjpm{suffix}",
            stage="tools.cjpm.verify",
        )
