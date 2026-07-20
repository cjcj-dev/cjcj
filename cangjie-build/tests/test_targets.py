from __future__ import annotations

import pytest

from cangjie_build.errors import ConfigError
from cangjie_build.targets import all_targets, get_target


def test_linux_target_specifics() -> None:
    t = get_target("linux-x64")
    assert t.spec.archive_format == "tar.gz"
    assert t.spec.exe_suffix == ""
    assert t.spec.cross_compile is False
    assert t.spec.needs_mingw is False
    assert t.compiler_output_dirs() == ["output"]
    assert t.primary_compiler_output() == "output"
    assert t.runtime_output_subdir("release") == "linux_release_x86_64"
    assert t.runtime_output_subdir("RelWithDebInfo") == "linux_relwithdebinfo_x86_64"
    assert t.stdx_target_subdir() == "linux_x86_64_cjnative"


def test_windows_target_specifics() -> None:
    t = get_target("windows-x64")
    assert t.spec.archive_format == "zip"
    assert t.spec.exe_suffix == ".exe"
    assert t.spec.cross_compile is True
    assert t.spec.needs_mingw is True
    assert t.compiler_output_dirs() == ["output", "output-x86_64-w64-mingw32"]
    assert t.primary_compiler_output() == "output-x86_64-w64-mingw32"
    assert t.runtime_output_subdir("release") == "windows_release_x86_64"
    assert t.stdx_target_subdir() == "windows_x86_64_cjnative"


def test_unknown_target_raises() -> None:
    with pytest.raises(ConfigError):
        get_target("aix-power")


def test_registered_targets() -> None:
    assert set(all_targets()) == {"linux-x64", "windows-x64"}
