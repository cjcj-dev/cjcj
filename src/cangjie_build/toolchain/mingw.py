from __future__ import annotations

import os
import shutil
from pathlib import Path

from cangjie_build.logging_setup import get_logger, stage
from cangjie_build.runner import run
from cangjie_build.toolchain._archive import download, extract

_log = get_logger("cangjie_build.toolchain.mingw")

# mstorsjo publishes ready-to-use llvm-mingw cross toolchains under
# https://github.com/mstorsjo/llvm-mingw/releases. Building llvm + clang +
# lld + libc++ + mingw-w64 from scratch took ~30-60 min and ~40 GB of disk
# even on a 16-core VM; the prebuilt drops in at ~150 MB / 2 minutes.
#
# Cangjie's runtime/stdlib/stdx don't depend on OpenHarmony's LLVM patches
# when targeting windows-x64 (those patches are for the OHOS triple, not
# x86_64-w64-mingw32), so vanilla LLVM is sufficient. The only thing the
# prebuilt doesn't include is OpenSSL — we still build that statically
# below and drop it next to the cross compiler's sysroot.
LLVM_MINGW_TAG = "20220906"
LLVM_MINGW_FLAVOR = "msvcrt"
LLVM_MINGW_PREBUILT_BASENAME = (
    f"llvm-mingw-{LLVM_MINGW_TAG}-{LLVM_MINGW_FLAVOR}-ubuntu-18.04-x86_64"
)
LLVM_MINGW_PREBUILT_URL = (
    f"https://github.com/mstorsjo/llvm-mingw/releases/download/{LLVM_MINGW_TAG}/"
    f"{LLVM_MINGW_PREBUILT_BASENAME}.tar.xz"
)

OPENSSL_VERSION = "3.0.9"
OPENSSL_URL = (
    f"https://github.com/openssl/openssl/archive/refs/tags/openssl-{OPENSSL_VERSION}.tar.gz"
)

INSTALL_DIR_NAME = "llvm-mingw-w64"
TARGET_TRIPLE = "x86_64-w64-mingw32"


def install_path(build_root: Path) -> Path:
    return build_root / INSTALL_DIR_NAME


def is_installed(build_root: Path) -> bool:
    """Cheap sentinel: cross compiler binary + bundled OpenSSL static lib."""
    install = install_path(build_root)
    return (install / "bin" / f"{TARGET_TRIPLE}-clang").exists() and (
        install / TARGET_TRIPLE / "lib" / "libssl.a"
    ).exists()


def install(build_root: Path, *, jobs: int | None = None) -> None:
    if is_installed(build_root):
        _log.info("MinGW toolchain already present at %s; skipping", install_path(build_root))
        return

    build_root.mkdir(parents=True, exist_ok=True)
    cpus = jobs if jobs is not None else (os.cpu_count() or 2)
    install = install_path(build_root)

    with stage("mingw:llvm-mingw"):
        archive = build_root / f"{LLVM_MINGW_PREBUILT_BASENAME}.tar.xz"
        download(LLVM_MINGW_PREBUILT_URL, archive)
        extracted = extract(archive, build_root)
        if install.exists():
            shutil.rmtree(install)
        extracted.rename(install)

        # Aliases that the upstream Cangjie build doc expects to find next to
        # the mingw runtime libs. The prebuilt ships libmingwex.a but not
        # these alternative names.
        target_lib_dir = install / TARGET_TRIPLE / "lib"
        src = target_lib_dir / "libmingwex.a"
        for alias in ("libssp.a", "libssp_nonshared.a"):
            shutil.copy2(src, target_lib_dir / alias)

    with stage("mingw:openssl"):
        openssl_archive = build_root / f"openssl-{OPENSSL_VERSION}.tar.gz"
        download(OPENSSL_URL, openssl_archive)
        openssl_src = extract(openssl_archive, build_root)
        build_dir = openssl_src / "build"
        build_dir.mkdir(exist_ok=True)
        path_overlay = {"PATH": f"{install / 'bin'}{os.pathsep}{os.environ.get('PATH', '')}"}
        run(
            [
                str(openssl_src / "Configure"),
                "mingw64",
                f"--prefix={install / TARGET_TRIPLE}",
                f"--cross-compile-prefix={TARGET_TRIPLE}-",
                "--libdir=lib",
            ],
            cwd=build_dir,
            env_overlay=path_overlay,
            stage="mingw.openssl.configure",
        )
        run(
            ["make", f"-j{cpus}"],
            cwd=build_dir,
            env_overlay=path_overlay,
            stage="mingw.openssl.make",
        )
        run(
            ["make", "install"],
            cwd=build_dir,
            env_overlay=path_overlay,
            stage="mingw.openssl.install",
        )
