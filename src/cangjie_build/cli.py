from __future__ import annotations

from enum import StrEnum
from pathlib import Path
from typing import Annotated

import typer

from cangjie_build import __version__
from cangjie_build.config import (
    DEFAULT_BUILD_TYPE,
    VALID_BUILD_TYPES,
    BuildConfig,
    RepoName,
    RepoOverride,
    build_config,
)
from cangjie_build.errors import BuildError, ConfigError
from cangjie_build.logging_setup import configure_logging, get_logger
from cangjie_build.targets import all_targets
from cangjie_build.toolchain import sccache

app = typer.Typer(
    name="cangjie-build",
    help="Engineered build pipeline for the Cangjie SDK.",
    no_args_is_help=True,
    pretty_exceptions_enable=False,
)
build_app = typer.Typer(help="Run individual build stages.", no_args_is_help=True)
app.add_typer(build_app, name="build")

_log = get_logger("cangjie_build.cli")


class TargetChoice(StrEnum):
    linux_x64 = "linux-x64"
    windows_x64 = "windows-x64"


class BuildTypeChoice(StrEnum):
    release = "release"
    debug = "debug"
    relwithdebinfo = "relwithdebinfo"


class LogLevel(StrEnum):
    debug = "DEBUG"
    info = "INFO"
    warning = "WARNING"
    error = "ERROR"


_DEFAULT_BUILD_TYPE_CHOICE = BuildTypeChoice(DEFAULT_BUILD_TYPE)


def _version_callback(value: bool) -> None:
    if value:
        typer.echo(__version__)
        raise typer.Exit()


@app.callback()
def main(
    ctx: typer.Context,
    workspace: Annotated[
        Path | None,
        typer.Option(
            "--workspace",
            help="Build workspace directory (default: $CANGJIE_WORKSPACE or ./workspace).",
        ),
    ] = None,
    build_root: Annotated[
        Path | None,
        typer.Option(
            "--build-root",
            help="Toolchain root (default: $CANGJIE_BUILD_ROOT or ./buildtools).",
        ),
    ] = None,
    target: Annotated[
        TargetChoice,
        typer.Option("--target", help=f"Build target ({', '.join(all_targets())})."),
    ] = TargetChoice.linux_x64,
    build_type: Annotated[
        BuildTypeChoice,
        typer.Option(
            "--build-type",
            help=f"Build type ({', '.join(VALID_BUILD_TYPES)}).",
        ),
    ] = _DEFAULT_BUILD_TYPE_CHOICE,
    cangjie_version: Annotated[
        str | None,
        typer.Option(
            "--cangjie-version",
            help="Version label baked into archive names (default: tag or 'main').",
        ),
    ] = None,
    stdx_version: Annotated[
        int,
        typer.Option("--stdx-version", help="STDX archive version suffix."),
    ] = 1,
    log_level: Annotated[
        LogLevel, typer.Option("--log-level", help="Logging level.")
    ] = LogLevel.info,
    version: Annotated[
        bool,
        typer.Option(
            "--version", callback=_version_callback, is_eager=True, help="Show version and exit."
        ),
    ] = False,
) -> None:
    """Global options shared by every sub-command."""
    configure_logging(str(log_level))
    sccache.maybe_enable()
    try:
        cfg = build_config(
            workspace=workspace,
            build_root=build_root,
            target_key=str(target),
            build_type=str(build_type),
            cangjie_version=cangjie_version,
            stdx_version=stdx_version,
        )
    except ConfigError as exc:
        raise typer.BadParameter(str(exc)) from exc
    ctx.obj = cfg


def _cfg(ctx: typer.Context) -> BuildConfig:
    cfg = ctx.obj
    assert isinstance(cfg, BuildConfig), "Typer callback should have initialized BuildConfig"
    return cfg


# ---------------------------------------------------------------------------
# Top-level commands
# ---------------------------------------------------------------------------


@app.command("install-system-deps")
def cmd_install_system_deps() -> None:
    """Install Ubuntu apt packages needed to build the SDK."""
    from cangjie_build.toolchain import system_deps

    system_deps.install()


@app.command("install-static-libs")
def cmd_install_static_libs(ctx: typer.Context) -> None:
    """Build static ncurses + libedit (linux-x64 only, used by compiler stage)."""
    from cangjie_build.toolchain import static_libs

    cfg = _cfg(ctx)
    static_libs.install(cfg.build_root)


@app.command("install-mingw")
def cmd_install_mingw(ctx: typer.Context) -> None:
    """Build llvm-mingw + openssl cross toolchain (windows-x64 target)."""
    from cangjie_build.toolchain import mingw

    cfg = _cfg(ctx)
    if not cfg.target.spec.needs_mingw:
        _log.warning("Target %s does not need MinGW; skipping", cfg.target.spec.key)
        return
    mingw.install(cfg.build_root)


def parse_repo_kv(items: list[str], *, opt: str) -> dict[RepoName, str]:
    """Parse ``NAME=VALUE`` items, validating ``NAME`` against :class:`RepoName`."""
    out: dict[RepoName, str] = {}
    for raw in items:
        name, sep, value = raw.partition("=")
        if not sep or not name:
            raise typer.BadParameter(f"{opt}: expected NAME=VALUE, got {raw!r}")
        try:
            key = RepoName(name)
        except ValueError as exc:
            valid = ", ".join(r.value for r in RepoName)
            raise typer.BadParameter(f"{opt}: unknown repo {name!r}; valid: {valid}") from exc
        if key in out:
            raise typer.BadParameter(f"{opt}: repo {name!r} specified more than once")
        out[key] = value
    return out


@app.command("fetch")
def cmd_fetch(
    ctx: typer.Context,
    tag: Annotated[
        str | None,
        typer.Option("--tag", help="Global tag/branch applied to all repositories."),
    ] = None,
    repo_url: Annotated[
        list[str] | None,
        typer.Option(
            "--repo-url",
            help="Override URL for one repo: NAME=URL (NAME ∈ {compiler,runtime,tools,stdx}). Repeatable.",
        ),
    ] = None,
    repo_tag: Annotated[
        list[str] | None,
        typer.Option(
            "--repo-tag",
            help="Override tag for one repo: NAME=TAG. Wins over --tag. Repeatable.",
        ),
    ] = None,
) -> None:
    """Clone the four upstream Cangjie repositories into the workspace."""
    from cangjie_build.stages import fetch

    urls = parse_repo_kv(repo_url or [], opt="--repo-url")
    tags = parse_repo_kv(repo_tag or [], opt="--repo-tag")
    overrides = {
        name: RepoOverride(url=urls.get(name), tag=tags.get(name)) for name in set(urls) | set(tags)
    }
    base = _cfg(ctx)
    cfg = build_config(
        workspace=base.workspace,
        build_root=base.build_root,
        target_key=base.target.spec.key,
        build_type=base.build_type,
        cangjie_version=base.cangjie_version,
        stdx_version=base.stdx_version,
        global_tag=tag,
        repo_overrides=overrides,
    )
    fetch.run(cfg)


# ---------------------------------------------------------------------------
# `build <stage>` subcommands
# ---------------------------------------------------------------------------


@build_app.command("compiler")
def cmd_build_compiler(ctx: typer.Context) -> None:
    """Build cangjie_compiler (and cjdb)."""
    from cangjie_build.stages import compiler

    compiler.run(_cfg(ctx))


@build_app.command("runtime")
def cmd_build_runtime(ctx: typer.Context) -> None:
    """Build the runtime."""
    from cangjie_build.stages import runtime

    runtime.run(_cfg(ctx))


@build_app.command("stdlib")
def cmd_build_stdlib(ctx: typer.Context) -> None:
    """Build the standard library."""
    from cangjie_build.stages import stdlib

    stdlib.run(_cfg(ctx))


@build_app.command("stdx")
def cmd_build_stdx(ctx: typer.Context) -> None:
    """Build the STDX extension library."""
    from cangjie_build.stages import stdx

    stdx.run(_cfg(ctx))


@build_app.command("tools")
def cmd_build_tools(ctx: typer.Context) -> None:
    """Build cjpm / cjfmt / hyperlangExtension / LSPServer."""
    from cangjie_build.stages import tools

    tools.run(_cfg(ctx))


# ---------------------------------------------------------------------------
# Packaging / verification / orchestration
# ---------------------------------------------------------------------------


@app.command("package")
def cmd_package(ctx: typer.Context) -> None:
    """Organize files and produce SDK + STDX archives."""
    from cangjie_build.stages import package

    package.run(_cfg(ctx))


@app.command("verify")
def cmd_verify(ctx: typer.Context) -> None:
    """Smoke-test the freshly-built SDK with hello.cj (linux-x64 only runs the binary)."""
    from cangjie_build.stages import verify

    verify.run(_cfg(ctx))


@app.command("run-all")
def cmd_run_all(
    ctx: typer.Context,
    skip_system_deps: Annotated[bool, typer.Option("--skip-system-deps")] = False,
    skip_install_libs: Annotated[bool, typer.Option("--skip-install-libs")] = False,
) -> None:
    """Run every stage end-to-end (mostly useful for local debugging)."""
    from cangjie_build.stages import (
        compiler,
        fetch,
        package,
        runtime,
        stdlib,
        stdx,
        tools,
        verify,
    )
    from cangjie_build.toolchain import mingw, static_libs, system_deps

    cfg = _cfg(ctx)
    if not skip_system_deps:
        system_deps.install()
    if not skip_install_libs:
        if cfg.target.spec.needs_mingw:
            mingw.install(cfg.build_root)
        else:
            static_libs.install(cfg.build_root)
    fetch.run(cfg)
    compiler.run(cfg)
    runtime.run(cfg)
    stdlib.run(cfg)
    stdx.run(cfg)
    tools.run(cfg)
    package.run(cfg)
    verify.run(cfg)


def entrypoint() -> None:  # pragma: no cover
    try:
        app()
    except BuildError as exc:
        _log.error("%s", exc)
        raise SystemExit(1) from exc
