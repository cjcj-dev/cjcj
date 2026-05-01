from __future__ import annotations

from cangjie_build.config import BuildConfig, RepoName
from cangjie_build.logging_setup import stage
from cangjie_build.runner import CommandPart
from cangjie_build.stages._common import run_build_py

# Each tool lives under cangjie_tools/<subpath>; build.py is invoked in that dir.
_TOOL_PATHS: tuple[tuple[str, str], ...] = (
    ("cjpm", "cjpm/build"),
    ("cjfmt", "cjfmt/build"),
    ("hle", "hyperlangExtension/build"),
    ("lsp", "cangjie-language-server/build"),
)


def _build_args_for(name: str, cfg: BuildConfig) -> list[CommandPart]:
    args: list[CommandPart] = ["build", "-t", cfg.build_type]
    if cfg.target.spec.cross_compile:
        args += ["--target", "windows-x86_64"]
    elif name == "cjpm":
        # Linux native cjpm needs an rpath so it locates the runtime's shared libs at runtime.
        args += ["--set-rpath", "$ORIGIN/../../runtime/lib/linux_x86_64_cjnative"]
    return args


def run(cfg: BuildConfig) -> None:
    tools_root = cfg.repo_path(RepoName.TOOLS)
    with stage("tools"):
        for name, subpath in _TOOL_PATHS:
            cwd = tools_root / subpath
            run_build_py(cfg, cwd, ["clean"], stage_name=f"tools.{name}.clean")
            run_build_py(cfg, cwd, _build_args_for(name, cfg), stage_name=f"tools.{name}.build")
            run_build_py(cfg, cwd, ["install"], stage_name=f"tools.{name}.install")
