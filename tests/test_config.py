from __future__ import annotations

from pathlib import Path

import pytest

from cangjie_build.config import RepoName, RepoOverride, build_config, make_repos
from cangjie_build.errors import ConfigError


def test_default_repo_set_uses_gitcode() -> None:
    repos = make_repos(global_tag=None)
    assert set(repos) == set(RepoName)
    for r in repos.values():
        assert r.url.startswith("https://gitcode.com/Cangjie/")
        assert r.tag is None


def test_global_tag_propagates_when_no_override() -> None:
    repos = make_repos(global_tag="v1.0.0")
    assert all(r.tag == "v1.0.0" for r in repos.values())


def test_empty_string_override_treated_as_unset() -> None:
    repos = make_repos(
        global_tag="v1.0.0",
        overrides={RepoName.COMPILER: RepoOverride(url="", tag="")},
    )
    assert repos[RepoName.COMPILER].url.startswith("https://gitcode.com")
    assert repos[RepoName.COMPILER].tag == "v1.0.0"


def test_per_repo_overrides_win_over_global_tag() -> None:
    overrides = {
        RepoName.COMPILER: RepoOverride(url="https://example.com/cc.git", tag="feature-x"),
        RepoName.RUNTIME: RepoOverride(tag="v2.0.0"),
    }
    repos = make_repos(global_tag="v1.0.0", overrides=overrides)

    assert repos[RepoName.COMPILER].url == "https://example.com/cc.git"
    assert repos[RepoName.COMPILER].tag == "feature-x"

    assert repos[RepoName.RUNTIME].url.startswith("https://gitcode.com")
    assert repos[RepoName.RUNTIME].tag == "v2.0.0"

    assert repos[RepoName.TOOLS].tag == "v1.0.0"
    assert repos[RepoName.STDX].tag == "v1.0.0"


def test_build_config_defaults(tmp_path: Path) -> None:
    cfg = build_config(workspace=tmp_path / "ws", build_root=tmp_path / "br")
    assert cfg.workspace == (tmp_path / "ws").resolve()
    assert cfg.build_root == (tmp_path / "br").resolve()
    assert cfg.target.spec.key == "linux-x64"
    assert cfg.build_type == "relwithdebinfo"
    assert cfg.cangjie_version == "main"
    assert cfg.stdx_version == 1
    assert cfg.software_dir == cfg.workspace / "software"


def test_build_config_global_tag_used_as_version_when_unset(tmp_path: Path) -> None:
    cfg = build_config(workspace=tmp_path, build_root=tmp_path, global_tag="v9.9.9")
    assert cfg.cangjie_version == "v9.9.9"


def test_build_config_rejects_invalid_build_type(tmp_path: Path) -> None:
    with pytest.raises(ConfigError):
        build_config(workspace=tmp_path, build_root=tmp_path, build_type="lto")


def test_build_config_rejects_unknown_target(tmp_path: Path) -> None:
    with pytest.raises(ConfigError):
        build_config(workspace=tmp_path, build_root=tmp_path, target_key="macos-arm64")


def test_repo_path_resolves(tmp_path: Path) -> None:
    cfg = build_config(workspace=tmp_path, build_root=tmp_path)
    assert cfg.repo_path("compiler") == tmp_path.resolve() / "cangjie_compiler"
    assert cfg.repo_path("stdx") == tmp_path.resolve() / "cangjie_stdx"
    with pytest.raises(ConfigError):
        cfg.repo_path("nope")
