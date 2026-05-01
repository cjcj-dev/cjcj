from __future__ import annotations

import sys
from pathlib import Path

import pytest

from cangjie_build.errors import BuildError
from cangjie_build.runner import run


def test_run_zero_exit() -> None:
    rc = run([sys.executable, "-c", "print('ok')"], stage="t.ok", echo=False)
    assert rc == 0


def test_run_non_zero_raises_build_error() -> None:
    with pytest.raises(BuildError) as ei:
        run([sys.executable, "-c", "import sys; sys.exit(7)"], stage="t.fail", echo=False)
    assert ei.value.returncode == 7
    assert ei.value.stage == "t.fail"


def test_run_check_false_returns_code() -> None:
    rc = run(
        [sys.executable, "-c", "import sys; sys.exit(2)"],
        stage="t.no_check",
        check=False,
        echo=False,
    )
    assert rc == 2


def test_run_passes_env_overlay(tmp_path: Path) -> None:
    out = tmp_path / "out.txt"
    script = f"import os, pathlib;pathlib.Path(r'{out}').write_text(os.environ.get('FOO', ''))"
    run(
        [sys.executable, "-c", script],
        stage="t.env",
        env_overlay={"FOO": "bar123"},
        echo=False,
    )
    assert out.read_text() == "bar123"


def test_run_uses_cwd(tmp_path: Path) -> None:
    out = tmp_path / "where.txt"
    script = f"import os, pathlib; pathlib.Path(r'{out}').write_text(os.getcwd())"
    sub = tmp_path / "sub"
    sub.mkdir()
    run([sys.executable, "-c", script], cwd=sub, stage="t.cwd", echo=False)
    # Some platforms return long paths; compare resolved real paths.
    assert Path(out.read_text()).resolve() == sub.resolve()


def test_run_rejects_empty_command() -> None:
    with pytest.raises(BuildError):
        run([], stage="t.empty", echo=False)
