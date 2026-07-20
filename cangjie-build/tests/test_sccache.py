from __future__ import annotations

import os
from collections.abc import Generator

import pytest

from cangjie_build.toolchain import sccache


@pytest.fixture(autouse=True)
def isolate_env(monkeypatch: pytest.MonkeyPatch) -> Generator[None]:
    for var in (
        "CMAKE_C_COMPILER_LAUNCHER",
        "CMAKE_CXX_COMPILER_LAUNCHER",
        "SCCACHE_MULTILEVEL_CHAIN",
        "SCCACHE_GHA_ENABLED",
        "SCCACHE_DIR",
    ):
        monkeypatch.delenv(var, raising=False)
    yield


def _fake_which(result: str | None):
    def _which(_: str) -> str | None:
        return result

    return _which


def test_enabled_when_sccache_in_path(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "cangjie_build.toolchain.sccache.shutil.which", _fake_which("/usr/bin/sccache")
    )
    assert sccache.maybe_enable() is True
    assert os.environ["CMAKE_C_COMPILER_LAUNCHER"] == "sccache"
    assert os.environ["CMAKE_CXX_COMPILER_LAUNCHER"] == "sccache"


def test_disabled_when_sccache_missing(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("cangjie_build.toolchain.sccache.shutil.which", _fake_which(None))
    assert sccache.maybe_enable() is False
    assert "CMAKE_C_COMPILER_LAUNCHER" not in os.environ
    assert "CMAKE_CXX_COMPILER_LAUNCHER" not in os.environ


def testdescribe_backends_default() -> None:
    assert sccache.describe_backends() == "default (disk)"


def testdescribe_backends_disk(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SCCACHE_DIR", "/tmp/sccache")
    assert sccache.describe_backends() == "disk"


def testdescribe_backends_gha(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SCCACHE_GHA_ENABLED", "true")
    assert sccache.describe_backends() == "github-actions"


def testdescribe_backends_multilevel(monkeypatch: pytest.MonkeyPatch) -> None:
    # Multi-level chain wins over individual backend hints.
    monkeypatch.setenv("SCCACHE_GHA_ENABLED", "true")
    monkeypatch.setenv("SCCACHE_DIR", "/tmp/sccache")
    monkeypatch.setenv("SCCACHE_MULTILEVEL_CHAIN", "disk,gha")
    assert sccache.describe_backends() == "multi-level [disk,gha]"


def test_existing_launcher_is_preserved(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CMAKE_C_COMPILER_LAUNCHER", "ccache")
    monkeypatch.setattr(
        "cangjie_build.toolchain.sccache.shutil.which", _fake_which("/usr/bin/sccache")
    )
    sccache.maybe_enable()
    assert os.environ["CMAKE_C_COMPILER_LAUNCHER"] == "ccache"
    # The other one should still be set to sccache because no prior value existed.
    assert os.environ["CMAKE_CXX_COMPILER_LAUNCHER"] == "sccache"
