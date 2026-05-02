from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Literal

from cangjie_build.errors import ConfigError

ArchiveFormat = Literal["tar.gz", "zip"]


@dataclass(frozen=True)
class TargetSpec:
    """Static description of a build target."""

    key: str
    sdk_name: str
    archive_format: ArchiveFormat
    exe_suffix: str
    output_dir_suffix: str  # e.g. "x86_64" used in linux_<bt>_<suffix>
    cross_compile: bool
    needs_mingw: bool


class Target(ABC):
    """Strategy describing platform-specific build glue."""

    spec: TargetSpec

    @abstractmethod
    def compiler_output_dirs(self) -> list[str]:
        """Names of output dirs under cangjie_compiler/ that hold final compiler bits."""

    @abstractmethod
    def runtime_output_subdir(self, build_type: str) -> str:
        """Subdir under cangjie_runtime/runtime/output/common/ produced by build.py install."""

    @abstractmethod
    def runtime_lib_subdir(self, build_type: str) -> str:
        """Subdir under compiler/output/runtime/lib/ for this target's runtime libs.

        Same shape as ``runtime_output_subdir`` but suffixed with ``_cjnative``.
        """

    @abstractmethod
    def stdx_target_subdir(self) -> str:
        """Subdir under cangjie_stdx/target produced by stdx build.py install."""

    @abstractmethod
    def primary_compiler_output(self) -> str:
        """The compiler output dir to be packaged into software/cangjie."""


class _LinuxX64(Target):
    spec = TargetSpec(
        key="linux-x64",
        sdk_name="linux-x64",
        archive_format="tar.gz",
        exe_suffix="",
        output_dir_suffix="x86_64",
        cross_compile=False,
        needs_mingw=False,
    )

    def compiler_output_dirs(self) -> list[str]:
        return ["output"]

    def runtime_output_subdir(self, build_type: str) -> str:
        return f"linux_{build_type.lower()}_x86_64"

    def runtime_lib_subdir(self, build_type: str) -> str:
        return f"linux_{build_type.lower()}_x86_64_cjnative"

    def stdx_target_subdir(self) -> str:
        return "linux_x86_64_cjnative"

    def primary_compiler_output(self) -> str:
        return "output"


class _WindowsX64(Target):
    spec = TargetSpec(
        key="windows-x64",
        sdk_name="windows-x64",
        archive_format="zip",
        exe_suffix=".exe",
        output_dir_suffix="x86_64",
        cross_compile=True,
        needs_mingw=True,
    )

    def compiler_output_dirs(self) -> list[str]:
        return ["output", "output-x86_64-w64-mingw32"]

    def runtime_output_subdir(self, build_type: str) -> str:
        return f"windows_{build_type.lower()}_x86_64"

    def runtime_lib_subdir(self, build_type: str) -> str:
        return f"windows_{build_type.lower()}_x86_64_cjnative"

    def stdx_target_subdir(self) -> str:
        return "windows_x86_64_cjnative"

    def primary_compiler_output(self) -> str:
        return "output-x86_64-w64-mingw32"


_REGISTRY: dict[str, Target] = {
    _LinuxX64.spec.key: _LinuxX64(),
    _WindowsX64.spec.key: _WindowsX64(),
}


def get_target(key: str) -> Target:
    try:
        return _REGISTRY[key]
    except KeyError as exc:
        valid = ", ".join(sorted(_REGISTRY))
        raise ConfigError(f"unknown target {key!r}; valid: {valid}") from exc


def all_targets() -> list[str]:
    return sorted(_REGISTRY)
