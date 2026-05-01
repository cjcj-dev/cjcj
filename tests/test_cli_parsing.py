from __future__ import annotations

import pytest
import typer

from cangjie_build.cli import parse_repo_kv
from cangjie_build.config import RepoName


def test_parse_empty_input_returns_empty_dict() -> None:
    assert parse_repo_kv([], opt="--repo-url") == {}


def test_parse_well_formed_pairs() -> None:
    out = parse_repo_kv(
        ["compiler=https://example.com/cc.git", "stdx=v2.0.0"],
        opt="--repo-url",
    )
    assert out == {
        RepoName.COMPILER: "https://example.com/cc.git",
        RepoName.STDX: "v2.0.0",
    }


def test_parse_value_may_contain_equals_sign() -> None:
    out = parse_repo_kv(
        ["compiler=https://example.com/repo.git?token=abc=def"],
        opt="--repo-url",
    )
    assert out[RepoName.COMPILER] == "https://example.com/repo.git?token=abc=def"


def test_parse_rejects_missing_equals() -> None:
    with pytest.raises(typer.BadParameter, match="expected NAME=VALUE"):
        parse_repo_kv(["compiler"], opt="--repo-url")


def test_parse_rejects_missing_name() -> None:
    with pytest.raises(typer.BadParameter, match="expected NAME=VALUE"):
        parse_repo_kv(["=value"], opt="--repo-url")


def test_parse_rejects_unknown_repo() -> None:
    with pytest.raises(typer.BadParameter, match="unknown repo"):
        parse_repo_kv(["mystery=v1"], opt="--repo-tag")


def test_parse_rejects_duplicate_name() -> None:
    with pytest.raises(typer.BadParameter, match="more than once"):
        parse_repo_kv(["compiler=a", "compiler=b"], opt="--repo-url")
