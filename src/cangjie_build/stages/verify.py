from __future__ import annotations

from cangjie_build.config import BuildConfig
from cangjie_build.errors import BuildError
from cangjie_build.logging_setup import get_logger, stage
from cangjie_build.runner import run as run_cmd
from cangjie_build.stages._common import ensure_dir, require_file

_log = get_logger("cangjie_build.stages.verify")

_HELLO_SOURCE = 'main() { println("Hello, Cangjie") }\n'


def run(cfg: BuildConfig) -> None:
    """Smoke-test the freshly-built SDK by compiling and running hello.cj.

    Cross-compiled targets (Windows) cannot be executed on the Linux runner;
    we only validate that the headline artifacts landed.
    """
    cangjie_dir = cfg.software_dir / "cangjie"
    envsetup = require_file(cangjie_dir / "envsetup.sh", stage="verify")

    if cfg.target.spec.cross_compile:
        # Windows binaries can't be exec'd on the linux runner — just check
        # the headline artifacts landed where the SDK tree expects them.
        suffix = cfg.target.spec.exe_suffix
        require_file(cangjie_dir / "bin" / f"cjc{suffix}", stage="verify.cjc")
        require_file(
            cangjie_dir / "tools" / "bin" / f"cjpm{suffix}", stage="verify.cjpm"
        )
        _log.info("Cross-compile target; SDK artifacts present")
        return

    work = ensure_dir(cfg.workspace / "verify")
    hello = work / "hello.cj"
    hello.write_text(_HELLO_SOURCE, encoding="utf-8")

    with stage("verify"):
        run_cmd(
            ["bash", "-c", f"set -e; source '{envsetup}'; cjc hello.cj -o hello && ./hello"],
            cwd=work,
            stage="verify.hello",
        )
        executable = work / "hello"
        if not executable.exists():
            raise BuildError("verify", "hello binary was not produced")
