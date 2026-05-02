from __future__ import annotations

import os
from collections.abc import Mapping
from dataclasses import dataclass, field, replace
from enum import StrEnum
from pathlib import Path

from cangjie_build.errors import ConfigError
from cangjie_build.targets import Target, get_target

VALID_BUILD_TYPES = ("release", "debug", "relwithdebinfo")
DEFAULT_BUILD_TYPE = "relwithdebinfo"


class RepoName(StrEnum):
    COMPILER = "compiler"
    RUNTIME = "runtime"
    TOOLS = "tools"
    STDX = "stdx"


_REPO_DEFAULTS: dict[RepoName, tuple[str, str]] = {
    RepoName.COMPILER: ("https://gitcode.com/Cangjie/cangjie_compiler.git", "cangjie_compiler"),
    RepoName.RUNTIME: ("https://gitcode.com/Cangjie/cangjie_runtime.git", "cangjie_runtime"),
    RepoName.TOOLS: ("https://gitcode.com/Cangjie/cangjie_tools.git", "cangjie_tools"),
    RepoName.STDX: ("https://gitcode.com/Cangjie/cangjie_stdx.git", "cangjie_stdx"),
}


@dataclass(frozen=True)
class RepoSpec:
    name: RepoName
    url: str
    tag: str | None  # None → default branch
    dir_name: str


@dataclass(frozen=True)
class RepoOverride:
    """Per-repo URL/tag override. ``None`` (or empty string) means inherit default."""

    url: str | None = None
    tag: str | None = None


@dataclass(frozen=True)
class BuildConfig:
    workspace: Path
    build_root: Path
    target: Target
    build_type: str
    cangjie_version: str
    stdx_version: int
    repos: dict[RepoName, RepoSpec] = field(default_factory=dict[RepoName, RepoSpec])

    @property
    def software_dir(self) -> Path:
        return self.workspace / "software"

    @property
    def cross_build_type(self) -> str:
        """Build type to use for cross-compile (windows) sub-builds.

        cangjie's build glue has multiple ``relwithdebinfo``-only bugs on
        MinGW: ``src/CMakeLists.txt:272`` flips cangjie-frontend to a static
        ``.a`` (which BuildCJDB.cmake then can't find as ``.dll.a``), and
        ``-fdebug-types-section`` is added to pcre2's compile flags but
        clang refuses it on the ``x86_64-w64-windows-gnu`` triple. Upstream's
        ``linux_cross_windows_zh.md`` always uses ``release`` for the windows
        cross-compile invocations, so we do the same — independent of what
        the user picked for the linux-host build_type.
        """
        return "release" if self.target.spec.cross_compile else self.build_type

    def repo(self, name: RepoName | str) -> RepoSpec:
        try:
            key = RepoName(name)
        except ValueError as exc:
            raise ConfigError(f"unknown repo {name!r}") from exc
        try:
            return self.repos[key]
        except KeyError as exc:
            raise ConfigError(f"unknown repo {name!r}") from exc

    def repo_path(self, name: RepoName | str) -> Path:
        return self.workspace / self.repo(name).dir_name


def _abs(path: Path | str) -> Path:
    return Path(path).expanduser().resolve()


def make_repos(
    *,
    global_tag: str | None,
    overrides: Mapping[RepoName, RepoOverride] | None = None,
) -> dict[RepoName, RepoSpec]:
    """Build the canonical repo set with optional per-repo URL/tag overrides.

    GHA passes empty strings for unset inputs; both ``None`` and ``""`` are
    treated as "unset" so the global tag wins.
    """
    overrides = overrides or {}
    out: dict[RepoName, RepoSpec] = {}
    for name, (default_url, dir_name) in _REPO_DEFAULTS.items():
        ov = overrides.get(name, RepoOverride())
        url = ov.url or default_url
        tag = ov.tag or global_tag
        out[name] = RepoSpec(name=name, url=url, tag=tag or None, dir_name=dir_name)
    return out


def build_config(
    *,
    workspace: Path | str | None = None,
    build_root: Path | str | None = None,
    target_key: str = "linux-x64",
    build_type: str = DEFAULT_BUILD_TYPE,
    cangjie_version: str | None = None,
    stdx_version: int = 1,
    global_tag: str | None = None,
    repo_overrides: Mapping[RepoName, RepoOverride] | None = None,
) -> BuildConfig:
    if build_type not in VALID_BUILD_TYPES:
        raise ConfigError(
            f"invalid build_type {build_type!r}; valid: {', '.join(VALID_BUILD_TYPES)}"
        )
    target = get_target(target_key)

    ws = _abs(workspace or os.environ.get("CANGJIE_WORKSPACE") or Path.cwd() / "workspace")
    br = _abs(build_root or os.environ.get("CANGJIE_BUILD_ROOT") or Path.cwd() / "buildtools")
    version = cangjie_version or os.environ.get("CANGJIE_VERSION") or (global_tag or "main")

    return BuildConfig(
        workspace=ws,
        build_root=br,
        target=target,
        build_type=build_type,
        cangjie_version=version,
        stdx_version=stdx_version,
        repos=make_repos(global_tag=global_tag, overrides=repo_overrides),
    )


def with_build_type(cfg: BuildConfig, build_type: str) -> BuildConfig:
    if build_type not in VALID_BUILD_TYPES:
        raise ConfigError(f"invalid build_type {build_type!r}")
    return replace(cfg, build_type=build_type)
