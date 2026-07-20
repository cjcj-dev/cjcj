from __future__ import annotations

import os
from pathlib import Path

from cangjie_build.logging_setup import get_logger, stage
from cangjie_build.runner import run
from cangjie_build.toolchain._archive import download, extract

_log = get_logger("cangjie_build.toolchain.static_libs")

NCURSES_VERSION = "6.5"
NCURSES_URL = f"https://ftp.gnu.org/pub/gnu/ncurses/ncurses-{NCURSES_VERSION}.tar.gz"
LIBEDIT_TARBALL = "libedit-20210910-3.1"
LIBEDIT_URL = f"https://thrysoee.dk/editline/{LIBEDIT_TARBALL}.tar.gz"


def _ncurses_lib(build_root: Path) -> Path:
    return build_root / f"ncurses-{NCURSES_VERSION}" / "usr" / "lib" / "libncurses.a"


def _libedit_lib(build_root: Path) -> Path:
    return build_root / "libedit-3.1" / "lib" / "libedit.a"


def is_installed(build_root: Path) -> bool:
    return _ncurses_lib(build_root).is_file() and _libedit_lib(build_root).is_file()


def install(build_root: Path, *, jobs: int | None = None) -> None:
    """Build static ncurses 6.5 + libedit 3.1 inside ``build_root``.

    Layout (mirrors the upstream Cangjie build doc):
    - ``$BUILD_ROOT/ncurses-6.5/usr/{lib,include}``
    - ``$BUILD_ROOT/libedit-3.1/{lib,include}``
    """
    if is_installed(build_root):
        _log.info("Static libs already present at %s; skipping", build_root)
        return

    build_root.mkdir(parents=True, exist_ok=True)
    cpus = jobs if jobs is not None else (os.cpu_count() or 2)

    with stage("static_libs:ncurses"):
        ncurses_archive = build_root / f"ncurses-{NCURSES_VERSION}.tar.gz"
        download(NCURSES_URL, ncurses_archive)
        ncurses_src = extract(ncurses_archive, build_root)
        ncurses_install = build_root / f"ncurses-{NCURSES_VERSION}"
        configure_env = {
            "CC": "clang",
            "CXX": "clang++",
            "CFLAGS": "-fPIC -fstack-protector-strong -Wl,-z,relro,-z,now,-z,noexecstack",
            "CXXFLAGS": "-fstack-protector-strong -Wl,-z,relro,-z,now,-z,noexecstack",
        }
        run(
            [
                "./configure",
                "--with-termlib",
                "--with-terminfo-dirs=/etc/terminfo:/lib/terminfo:/usr/share/terminfo",
                "--disable-widec",
                "--disable-overwrite",
                "--disable-root-environ",
            ],
            cwd=ncurses_src,
            env_overlay=configure_env,
            stage="static_libs.ncurses.configure",
        )
        run(["make", f"-j{cpus}"], cwd=ncurses_src, stage="static_libs.ncurses.make")
        run(
            ["make", "install", f"DESTDIR={ncurses_install}"],
            cwd=ncurses_src,
            stage="static_libs.ncurses.install",
        )

    with stage("static_libs:libedit"):
        libedit_archive = build_root / f"{LIBEDIT_TARBALL}.tar.gz"
        download(LIBEDIT_URL, libedit_archive)
        libedit_src = extract(libedit_archive, build_root)
        libedit_prefix = build_root / "libedit-3.1"
        run(
            [
                "./configure",
                "--with-pic",
                "--enable-shared=no",
                f"--prefix={libedit_prefix}",
            ],
            cwd=libedit_src,
            stage="static_libs.libedit.configure",
        )
        run(["make", f"-j{cpus}"], cwd=libedit_src, stage="static_libs.libedit.make")
        run(["make", "install"], cwd=libedit_src, stage="static_libs.libedit.install")


def cmake_prefix_path(build_root: Path) -> str:
    return os.pathsep.join(
        [
            str(build_root / "libedit-3.1"),
            str(build_root / f"ncurses-{NCURSES_VERSION}" / "usr"),
        ]
    )


def target_lib_path(build_root: Path) -> Path:
    return build_root / f"ncurses-{NCURSES_VERSION}" / "usr" / "lib"
