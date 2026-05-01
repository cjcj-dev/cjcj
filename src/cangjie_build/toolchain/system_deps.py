from __future__ import annotations

import shutil
import sys

from cangjie_build.errors import BuildError
from cangjie_build.logging_setup import get_logger
from cangjie_build.runner import run

_log = get_logger("cangjie_build.toolchain.system_deps")

# Pinned to the upstream Cangjie SDK build doc for Ubuntu 22.04
# (ref/cangjie_official_build/docs/linux_zh.md §2.2 and linux_cross_windows_zh.md §2.2).
APT_PACKAGES: tuple[str, ...] = (
    "tar",
    "unzip",
    "wget",
    "curl",
    "libcurl4",
    "expat",
    "openssl",
    "make",
    "gcc",
    "g++",
    "gettext",
    "nfs-common",
    "libtool",
    "sqlite3",
    "zlib1g-dev",
    "libssl-dev",
    "cmake",
    "ninja-build",
    "libcurl4-openssl-dev",
    "sudo",
    "autoconf",
    "build-essential",
    "rapidjson-dev",
    "texinfo",
    "binutils",
    "libelf-dev",
    "libdwarf-dev",
    "openssh-client",
    "ssh",
    "dos2unix",
    "libxext-dev",
    "libxtst-dev",
    "libxt-dev",
    "libcups2-dev",
    "clang",
    "clang-15",
    "lld",
    "libxrender-dev",
    "zip",
    "bzip2",
    "libopenmpi-dev",
    "vim",
    "gdb",
    "lldb",
    "libclang-15-dev",
    "libgtest-dev",
    "rpm",
    "patch",
    "libtinfo5",
    "cpio",
    "rpm2cpio",
    "libncurses5",
    "libncurses5-dev",
    "strace",
    "net-tools",
    "swig",
)


def install() -> None:
    if sys.platform != "linux":
        raise BuildError(
            "system_deps",
            f"install-system-deps only supports Linux (current: {sys.platform})",
        )
    if not shutil.which("apt-get"):
        raise BuildError("system_deps", "apt-get not found; an Ubuntu/Debian host is required")

    sudo = ["sudo"] if shutil.which("sudo") else []
    _log.info("Installing %d apt packages", len(APT_PACKAGES))
    run([*sudo, "apt-get", "update"], stage="system_deps.update")
    run(
        [*sudo, "apt-get", "install", "-y", "--no-install-recommends", *APT_PACKAGES],
        stage="system_deps.install",
        env_overlay={"DEBIAN_FRONTEND": "noninteractive"},
    )
