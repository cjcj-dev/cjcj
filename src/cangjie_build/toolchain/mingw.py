from __future__ import annotations

import os
import shutil
from pathlib import Path

from cangjie_build.logging_setup import get_logger, stage
from cangjie_build.runner import run
from cangjie_build.toolchain._archive import download, extract

_log = get_logger("cangjie_build.toolchain.mingw")

LLVM_MINGW_TAG = "20220906"
LLVM_MINGW_URL = f"https://github.com/mstorsjo/llvm-mingw/archive/refs/tags/{LLVM_MINGW_TAG}.tar.gz"
LLVM_PROJECT_REMOTE = "https://gitee.com/openharmony/third_party_llvm-project.git"
LLVM_PROJECT_COMMIT = "5c68a1cb123161b54b72ce90e7975d95a8eaf2a4"
MINGW_W64_REMOTE = "https://gitee.com/openharmony/third_party_mingw-w64.git"

OPENSSL_VERSION = "3.0.9"
OPENSSL_URL = (
    f"https://github.com/openssl/openssl/archive/refs/tags/openssl-{OPENSSL_VERSION}.tar.gz"
)

INSTALL_DIR_NAME = "llvm-mingw-w64"
TARGET_TRIPLE = "x86_64-w64-mingw32"


def install_path(build_root: Path) -> Path:
    return build_root / INSTALL_DIR_NAME


def is_installed(build_root: Path) -> bool:
    """Cheap sentinel check: a complete toolchain has the mingw cross compiler."""
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
        llvm_archive = build_root / f"llvm-mingw-{LLVM_MINGW_TAG}.tar.gz"
        download(LLVM_MINGW_URL, llvm_archive)
        llvm_src = extract(llvm_archive, build_root)

        # llvm-project is fetched at a specific commit (not a tag/branch); we cannot use shallow_clone.
        llvm_project = llvm_src / "llvm-project"
        if not llvm_project.exists():
            llvm_project.mkdir(parents=True)
            run(["git", "init"], cwd=llvm_project, stage="mingw.llvm.init")
            run(
                ["git", "remote", "add", "origin", LLVM_PROJECT_REMOTE],
                cwd=llvm_project,
                stage="mingw.llvm.remote",
            )
            run(
                ["git", "fetch", "--depth", "1", "origin", LLVM_PROJECT_COMMIT],
                cwd=llvm_project,
                stage="mingw.llvm.fetch",
            )
            run(
                ["git", "checkout", "FETCH_HEAD"],
                cwd=llvm_project,
                stage="mingw.llvm.checkout",
            )

        mingw_w64 = llvm_src / "mingw-w64"
        if not mingw_w64.exists():
            run(
                ["git", "clone", "--depth", "1", MINGW_W64_REMOTE, str(mingw_w64)],
                stage="mingw.mingw-w64.clone",
            )

        toolchain_env = {"TOOLCHAIN_ARCHS": "x86_64"}
        mold = shutil.which("mold")
        # mold is a Linux ELF linker; it cannot link the Windows PE/COFF
        # outputs that the cross-target scripts produce. Apply it only to
        # the host LLVM bootstrap, which is where >90% of the link time is.
        host_link_prefix = ["mold", "-run"] if mold else []

        def script(name: str, *extra: str, with_mold: bool = False) -> None:
            cmd: list[str] = []
            if with_mold:
                cmd.extend(host_link_prefix)
            cmd.append(str(llvm_src / name))
            cmd.extend([str(install), *extra])
            run(
                cmd,
                cwd=llvm_src,
                env_overlay={**toolchain_env, "MAKEFLAGS": f"-j{cpus}"},
                stage=f"mingw.{name}",
            )

        script("build-llvm.sh", "--disable-lldb", with_mold=True)
        script("strip-llvm.sh")
        script("install-wrappers.sh")
        script("build-mingw-w64.sh", "--with-default-msvcrt=msvcrt")
        script("build-mingw-w64-tools.sh")
        script("build-compiler-rt.sh")
        script("build-libcxx.sh")
        script("build-mingw-w64-libraries.sh")

        # Aliases referenced by the upstream build doc.
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
