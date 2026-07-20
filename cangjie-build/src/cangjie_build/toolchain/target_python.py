"""Windows Python distribution staged for cross-compile cjdb.

cangjie_compiler's BuildCJDB.cmake reads ``TARGET_PYTHON_PATH`` for the
linux→windows path (third_party/cmake/BuildCJDB.cmake:131-140) and uses it as
both the include root (``include/python<M>.<N>/Python.h``) and the link target
(``python<M><N>.dll`` directly, since mingw's ld can link against DLLs). It
also derives ``TARGET_PATHON_VERSION`` from the host Python's major.minor —
so the bundle's version must match ``sys.version_info``.

Source: NuGet's ``python`` package, which ships PSF's MSVC-built x64 Windows
Python in a ZIP-extractable nupkg. Mingw's ld can link against MSVC DLLs
directly, so the cross link works without a fabricated import lib.

After build+install, ``compiler.run`` copies the DLL into the windows output
under ``tools/bin/`` next to lldb/cjdb so the binary loads at runtime.
"""

from __future__ import annotations

import shutil
import sys
import zipfile
from pathlib import Path

from cangjie_build.errors import BuildError
from cangjie_build.logging_setup import get_logger, stage
from cangjie_build.toolchain._archive import download

_log = get_logger("cangjie_build.toolchain.target_python")

# Pin per host major.minor. Verify availability on
# https://api.nuget.org/v3-flatcontainer/python/index.json before bumping.
_NUGET_VERSIONS: dict[tuple[int, int], str] = {
    (3, 11): "3.11.9",
    (3, 12): "3.12.10",
}

INSTALL_DIR_NAME = "target-python"


def _host_pyver() -> tuple[int, int]:
    return sys.version_info[0], sys.version_info[1]


def _full_version() -> str:
    key = _host_pyver()
    if key not in _NUGET_VERSIONS:
        major, minor = key
        raise BuildError(
            "target-python",
            f"unsupported host Python {major}.{minor}; add a NuGet version pin "
            "in toolchain/target_python._NUGET_VERSIONS",
        )
    return _NUGET_VERSIONS[key]


def install_path(build_root: Path) -> Path:
    """Directory to set as ``TARGET_PYTHON_PATH``."""
    return build_root / INSTALL_DIR_NAME / _full_version() / "bundle"


def runtime_dll_name() -> str:
    """e.g. ``python311.dll`` — runtime DLL lldb is linked against."""
    major, minor = _host_pyver()
    return f"python{major}{minor}.dll"


_EXTRA_RUNTIME_DLLS = ("python3.dll", "vcruntime140.dll", "vcruntime140_1.dll")


def _runtime_dlls(bundle: Path) -> list[Path]:
    out = [bundle / runtime_dll_name()]
    # python3.dll: stable-ABI shim. vcruntime140*.dll: MSVC C runtime; usually
    # already on modern Windows but bundling avoids "missing dll" surprises on
    # bare Server SKUs and Wine.
    for name in _EXTRA_RUNTIME_DLLS:
        path = bundle / name
        if path.is_file():
            out.append(path)
    return out


def install(build_root: Path) -> Path:
    """Download + lay out a Windows Python suitable for ``TARGET_PYTHON_PATH``.

    Idempotent: keyed on host major.minor, no-op if marker exists.
    """
    bundle = install_path(build_root)
    marker = bundle / ".ready"
    if marker.exists():
        _log.info("Target Python already staged at %s; skipping", bundle)
        return bundle

    version = _full_version()
    major, minor = _host_pyver()
    cache_root = build_root / INSTALL_DIR_NAME / version

    with stage("target-python"):
        cache_root.mkdir(parents=True, exist_ok=True)
        nupkg = cache_root / f"python.{version}.nupkg"
        # v3 flatcontainer is the modern stable URL; v2/api/v2 has dropped 404s
        # for some valid versions in our testing.
        download(
            f"https://api.nuget.org/v3-flatcontainer/python/{version}/python.{version}.nupkg",
            nupkg,
        )

        raw = cache_root / "raw"
        if raw.exists():
            shutil.rmtree(raw)
        raw.mkdir()
        with zipfile.ZipFile(nupkg) as zf:
            for name in zf.namelist():
                if name.startswith("tools/"):
                    zf.extract(name, raw)
        tools = raw / "tools"
        if not tools.is_dir():
            raise BuildError("target-python", f"nupkg missing tools/: {nupkg}")

        if bundle.exists():
            shutil.rmtree(bundle)
        bundle.mkdir(parents=True)

        dll_name = runtime_dll_name()
        src_dll = tools / dll_name
        if not src_dll.is_file():
            raise BuildError("target-python", f"missing {dll_name} in nupkg tools/")
        shutil.copy2(src_dll, bundle / dll_name)
        for name in _EXTRA_RUNTIME_DLLS:
            src = tools / name
            if src.is_file():
                shutil.copy2(src, bundle / name)

        # cmake wants Unix-style include/python<M>.<N>/ but the nuget tools/include
        # is flat — wrap it.
        py_include = bundle / "include" / f"python{major}.{minor}"
        py_include.mkdir(parents=True)
        src_include = tools / "include"
        if not src_include.is_dir():
            raise BuildError("target-python", "missing include/ in nupkg tools/")
        for entry in src_include.iterdir():
            target = py_include / entry.name
            if entry.is_dir():
                shutil.copytree(entry, target)
            else:
                shutil.copy2(entry, target)

        shutil.rmtree(raw)
        marker.touch()
        _log.info("Target Python %s staged at %s", version, bundle)
    return bundle


def install_runtime_dlls(bundle: Path, dest_dir: Path) -> None:
    """Copy ``python3X.dll`` (and ``python3.dll`` if present) into ``dest_dir``.

    Call after the windows install lands so cjdb.exe finds its Python at runtime.
    """
    dest_dir.mkdir(parents=True, exist_ok=True)
    for src in _runtime_dlls(bundle):
        if not src.is_file():
            raise BuildError("target-python", f"runtime DLL missing: {src}")
        shutil.copy2(src, dest_dir / src.name)
        _log.info("Installed %s -> %s", src.name, dest_dir)
