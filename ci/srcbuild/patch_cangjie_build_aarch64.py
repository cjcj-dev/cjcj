#!/usr/bin/env python3
"""Add the native Linux aarch64 tuple to pinned cjcj-build@60c485c."""

from pathlib import Path
import sys


ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()


def replace_once(relative: str, old: str, new: str) -> None:
    path = ROOT / relative
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one patch anchor, found {count}")
    path.write_text(text.replace(old, new), encoding="utf-8")


replace_once(
    "src/cangjie_build/cli.py",
    '    linux_x64 = "linux-x64"\n',
    '    linux_x64 = "linux-x64"\n    linux_aarch64 = "linux-aarch64"\n',
)

replace_once(
    "src/cangjie_build/stages/_common.py",
    '        "ARCH": "x86_64",\n',
    '        "ARCH": cfg.target.spec.output_dir_suffix,\n',
)
replace_once(
    "src/cangjie_build/stages/_common.py",
    '        candidate = Path("/usr/lib/x86_64-linux-gnu")\n',
    '        candidate = Path(f"/usr/lib/{cfg.target.spec.output_dir_suffix}-linux-gnu")\n',
)

replace_once(
    "src/cangjie_build/stages/package.py",
    '    base = "windows" if cfg.target.spec.cross_compile else "linux"\n'
    '    return f"{base}_x86_64_cjnative"\n',
    '    if cfg.target.spec.cross_compile:\n'
    '        return "windows_x86_64_cjnative"\n'
    '    return f"linux_{cfg.target.spec.output_dir_suffix}_cjnative"\n',
)

replace_once(
    "src/cangjie_build/stages/runtime.py",
    "from cangjie_build.logging_setup import stage\n",
    "from cangjie_build.logging_setup import stage\nfrom cangjie_build.targets import get_target\n",
)
replace_once(
    "src/cangjie_build/stages/runtime.py",
    "        # Linux native runtime always lands in linux_<bt>_x86_64 — no --target was\n"
    "        # passed to build.py above, so the subdir name doesn't follow cfg.target.\n"
    "        # cfg.target.runtime_output_subdir gives windows_* for the cross-compile\n"
    "        # target and would mis-resolve here.\n"
    '        linux_subdir = runtime_root / "output" / "common" / f"linux_{cfg.build_type.lower()}_x86_64"\n',
    '        native_target = get_target("linux-x64") if cfg.target.spec.cross_compile else cfg.target\n'
    '        linux_subdir = runtime_root / "output" / "common" / native_target.runtime_output_subdir(cfg.build_type)\n',
)

arm_target = '''class _LinuxAArch64(Target):
    spec = TargetSpec(
        key="linux-aarch64",
        sdk_name="linux-aarch64",
        archive_format="tar.gz",
        exe_suffix="",
        output_dir_suffix="aarch64",
        cross_compile=False,
        needs_mingw=False,
    )

    def compiler_output_dirs(self) -> list[str]:
        return ["output"]

    def runtime_output_subdir(self, build_type: str) -> str:
        return f"linux_{build_type.lower()}_aarch64"

    def runtime_lib_subdir(self, build_type: str) -> str:
        return f"linux_{build_type.lower()}_aarch64_cjnative"

    def stdx_target_subdir(self) -> str:
        return "linux_aarch64_cjnative"

    def primary_compiler_output(self) -> str:
        return "output"


'''
replace_once(
    "src/cangjie_build/targets.py",
    "class _WindowsX64(Target):\n",
    arm_target + "class _WindowsX64(Target):\n",
)
replace_once(
    "src/cangjie_build/targets.py",
    "    _LinuxX64.spec.key: _LinuxX64(),\n",
    "    _LinuxX64.spec.key: _LinuxX64(),\n"
    "    _LinuxAArch64.spec.key: _LinuxAArch64(),\n",
)

print("patched pinned cjcj-build with native linux-aarch64 target")
