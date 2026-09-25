#!/usr/bin/env python3
"""Assemble SDK.lock.json and fail-closed verify an assembled SDK tree."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ALLOWED_SYMLINKS = {'bin/cjc', 'bin/cjc-frontend'}
LOCK_NAME = 'SDK.lock.json'
SKIP_NAMES = {'.', LOCK_NAME}

COMPONENT_PREFIXES = (
    ('bin/cjc', 'cjc'),
    ('bin/cjcj-stage1', 'cjc'),
    ('bin/cjc-frontend', 'cjc'),
    ('tools/bin/cjpm', 'cjpm'),
    ('third_party/llvm/', 'llvm'),
    ('runtime/lib/', 'runtime'),
    ('lib/', 'std'),
    ('modules/', 'std'),
    ('runtime/include/', 'runtime'),
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def classify(rel: str) -> str:
    if rel == LOCK_NAME:
        return 'sdk-meta'
    for prefix, component in COMPONENT_PREFIXES:
        if rel == prefix or rel.startswith(prefix):
            if component == 'runtime' and 'libboundscheck' in Path(rel).name:
                return 'boundscheck'
            if component == 'std' and Path(rel).name.startswith('libcangjie-runtime'):
                return 'runtime'
            return component
    return 'official-retain'


def iter_files(sdk: Path):
    for path in sorted(sdk.rglob('*')):
        rel = path.relative_to(sdk).as_posix()
        if path.is_dir():
            continue
        yield path, rel


def load_pin(path: Path) -> dict:
    values = {}
    for line in path.read_text().splitlines():
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        values[key.strip()] = value.strip()
    return values


def nm_undefined(path: Path) -> set[str]:
    result = subprocess.run(['nm', '-A', str(path)], capture_output=True, text=True)
    if result.returncode:
        raise ValueError(f'nm rc={result.returncode} file={path}: {result.stderr.strip()}')
    found = set()
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) < 2:
            continue
        kind, name = fields[-2:]
        if kind == 'U':
            found.add(name.split('@', 1)[0])
    return found


def nm_defined(path: Path) -> set[str]:
    result = subprocess.run(['nm', '-D', '--defined-only', str(path)], capture_output=True, text=True)
    if result.returncode:
        raise ValueError(f'nm rc={result.returncode} file={path}: {result.stderr.strip()}')
    found = set()
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) < 2:
            continue
        kind, name = fields[-2:]
        if kind not in ('U', 'w', 'v'):
            found.add(name.split('@', 1)[0])
    return found


def llvm_tuple_sha(sdk: Path) -> str:
    names = [
        'third_party/llvm/bin/llc',
        'third_party/llvm/bin/opt',
        'third_party/llvm/bin/ld.lld',
        'third_party/llvm/lib/libLLVM-15.so',
    ]
    digest = hashlib.sha256()
    for name in names:
        path = sdk / name
        if not path.is_file():
            digest.update(f'MISSING:{name}\n'.encode())
            continue
        digest.update(name.encode())
        digest.update(b'\n')
        digest.update(sha256_file(path).encode())
        digest.update(b'\n')
    return digest.hexdigest()


def build_lock(sdk: Path, role: str, identities: dict) -> dict:
    files = {}
    official = {}
    for path, rel in iter_files(sdk):
        if rel == LOCK_NAME:
            continue
        component = classify(rel)
        digest = None
        if path.is_file():
            target = path.resolve() if path.is_symlink() else path
            if target.is_file():
                digest = sha256_file(target)
        entry = {
            'sha256': digest,
            'component': component,
            'symlink': path.is_symlink(),
            'producer': dict(identities.get(component, {})),
        }
        if path.is_symlink():
            entry['link_target'] = os.readlink(path)
        files[rel] = entry
        if component == 'official-retain':
            official[rel] = identities.get('official_retain_reason', 'copied from --from baseline; not replaced this assembly')
    cjc = files.get('bin/cjc', {})
    runtime_so = None
    for rel, entry in files.items():
        if rel.endswith('libcangjie-runtime.so') and entry['component'] == 'runtime':
            runtime_so = entry
            break
    lock = {
        'version': 1,
        'role': role,
        'files': files,
        'official_retain': official,
        'components': {
            'cjc': {'sha256': cjc.get('sha256')},
            'runtime': {
                'commit': identities.get('runtime', {}).get('commit'),
                'so_sha256': runtime_so.get('sha256') if runtime_so else None,
            },
            'llvm_tuple': {'sha256': llvm_tuple_sha(sdk)},
        },
    }
    return lock


def fail(code: str, message: str, errors: list) -> None:
    errors.append(f'SDK-VERIFY-FAIL rule={code} {message}')


def verify(sdk: Path, lock: dict, pin: dict, identities: dict, errors: list) -> None:
    on_disk = {}
    for path, rel in iter_files(sdk):
        on_disk[rel] = path
    lock_files = lock.get('files') or {}
    for rel, path in on_disk.items():
        if rel == LOCK_NAME:
            continue
        if rel not in lock_files:
            fail('UNDECLARED', f'file not in lock: {rel}', errors)
        if path.is_symlink() and rel not in ALLOWED_SYMLINKS:
            fail('SYMLINK', f'symlink not in allow-list: {rel}', errors)
    for rel in lock_files:
        if rel != LOCK_NAME and rel not in on_disk:
            fail('UNDECLARED', f'lock entry missing on disk: {rel}', errors)
    for rel, entry in lock_files.items():
        if entry.get('component') == 'official-retain' and rel not in (lock.get('official_retain') or {}):
            fail('UNDECLARED', f'official-retain without reason: {rel}', errors)
        if entry.get('component') not in {
            'cjc', 'std', 'runtime', 'llvm', 'cjpm', 'boundscheck', 'official-retain', 'sdk-meta',
        }:
            fail('UNDECLARED', f'unknown component for {rel}', errors)

    cjc_sha = (lock.get('components') or {}).get('cjc', {}).get('sha256')
    for rel, entry in lock_files.items():
        if entry.get('component') != 'std':
            continue
        producer = entry.get('producer') or {}
        compiler = producer.get('compiler_sha256')
        if compiler and cjc_sha and compiler != cjc_sha:
            fail('STD_CJC', f'std {rel} producer compiler {compiler} != sdk cjc {cjc_sha}', errors)
        if identities.get('expect_std_compiler') and compiler != identities['expect_std_compiler']:
            fail('STD_CJC', f'std compiler identity mismatch for {rel}', errors)

    expected_tuple = (lock.get('components') or {}).get('llvm_tuple', {}).get('sha256')
    actual_tuple = llvm_tuple_sha(sdk)
    if expected_tuple and expected_tuple != actual_tuple:
        fail('LLVM_TUPLE', f'llc/opt/ld.lld/libLLVM tuple sha mismatch lock={expected_tuple} disk={actual_tuple}', errors)
    llc = sdk / 'third_party/llvm/bin/llc'
    lld = sdk / 'third_party/llvm/bin/ld.lld'
    opt = sdk / 'third_party/llvm/bin/opt'
    libllvm = sdk / 'third_party/llvm/lib/libLLVM-15.so'
    present = [p for p in (llc, opt, lld, libllvm) if p.is_file()]
    if len(present) >= 2:
        shas = {sha256_file(p)[:16] for p in present}
        declared = set()
        for path in present:
            rel = path.relative_to(sdk).as_posix()
            producer = (lock_files.get(rel) or {}).get('producer') or {}
            if producer.get('llvm_tuple_sha'):
                declared.add(producer['llvm_tuple_sha'])
        if len(declared) > 1:
            fail('LLVM_TUPLE', f'llvm tools declare mixed tuple shas {sorted(declared)}', errors)

    pin_commit = pin.get('RUNTIME_REF', '').lower()
    runtime_commit = ((lock.get('components') or {}).get('runtime') or {}).get('commit')
    if pin_commit and lock.get('role') == 'target':
        if not runtime_commit:
            fail('RUNTIME_PIN', 'lock missing runtime commit while pin is present', errors)
        elif runtime_commit.lower() != pin_commit:
            fail('RUNTIME_PIN', f'runtime commit {runtime_commit} != pin {pin_commit}', errors)
    colour_manifest = identities.get('colour_runtime_sha256')
    runtime_so_sha = ((lock.get('components') or {}).get('runtime') or {}).get('so_sha256')
    if colour_manifest and runtime_so_sha and colour_manifest != runtime_so_sha and lock.get('role') == 'target':
        fail('RUNTIME_PIN', f'target runtime so {runtime_so_sha} != colour manifest {colour_manifest}', errors)

    role = lock.get('role')
    if role not in ('host', 'target'):
        fail('HOST_TARGET_CROSS', f'lock.role must be host or target, got {role!r}', errors)
    host_marker = any('sdk-host' in rel or rel.startswith('host/') for rel in lock_files)
    target_marker = any('sdk-target' in rel or rel.startswith('target/') for rel in lock_files)
    if host_marker and target_marker:
        fail('HOST_TARGET_CROSS', 'host and target trees mixed in one SDK', errors)
    if role == 'host' and target_marker:
        fail('HOST_TARGET_CROSS', 'host SDK contains target-side paths', errors)
    if role == 'target' and host_marker:
        fail('HOST_TARGET_CROSS', 'target SDK contains host-side paths', errors)

    runtime_so = None
    std_objs = []
    for rel, path in on_disk.items():
        name = Path(rel).name
        if name == 'libcangjie-runtime.so':
            runtime_so = path
        if name.endswith(('.so', '.a')) and classify(rel) in ('std', 'runtime', 'boundscheck'):
            if name != 'libcangjie-runtime.so':
                std_objs.append(path)
    if runtime_so and runtime_so.is_file() and not runtime_so.is_symlink() and std_objs:
        try:
            exports = nm_defined(runtime_so)
        except ValueError:
            exports = None
        if exports is not None:
            for obj in std_objs:
                if not obj.is_file() or obj.is_symlink():
                    continue
                try:
                    undefined = nm_undefined(obj)
                except ValueError:
                    continue
                extra = {name for name in undefined if name.startswith('g_cj') or name.startswith('CJ_') or name.startswith('MRT_')}
                missing = extra - exports
                if missing:
                    fail('STD_RUNTIME_COLOUR', f'{obj.relative_to(sdk)} undefined not in runtime: {sorted(missing)[:8]}', errors)


def write_lock(path: Path, lock: dict) -> str:
    text = json.dumps(lock, indent=2, sort_keys=True) + '\n'
    path.write_text(text)
    return sha256_file(path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', type=Path, required=True)
    parser.add_argument('--role', choices=('host', 'target'))
    parser.add_argument('--runtime-pin', type=Path)
    parser.add_argument('--write-lock', action='store_true')
    parser.add_argument('--identities', type=Path)
    parser.add_argument('--colour-runtime-sha256')
    parser.add_argument('--lock-sha-out', type=Path)
    args = parser.parse_args()
    sdk = args.sdk.resolve()
    if not sdk.is_dir():
        print(f'SDK-VERIFY-FAIL rule=UNDECLARED sdk missing: {sdk}', file=sys.stderr)
        return 1
    identities = {}
    if args.identities:
        identities = json.loads(args.identities.read_text())
    if args.colour_runtime_sha256:
        identities['colour_runtime_sha256'] = args.colour_runtime_sha256
    pin = load_pin(args.runtime_pin) if args.runtime_pin else {}
    lock_path = sdk / LOCK_NAME
    if args.write_lock:
        role = args.role or identities.get('role')
        if role not in ('host', 'target'):
            print('SDK-VERIFY-FAIL rule=HOST_TARGET_CROSS --write-lock requires --role', file=sys.stderr)
            return 1
        lock = build_lock(sdk, role, identities)
        lock_sha = write_lock(lock_path, lock)
    else:
        if not lock_path.is_file():
            print(f'SDK-VERIFY-FAIL rule=UNDECLARED missing {LOCK_NAME}', file=sys.stderr)
            return 1
        lock = json.loads(lock_path.read_text())
        lock_sha = sha256_file(lock_path)
        if args.role and lock.get('role') != args.role:
            print(f'SDK-VERIFY-FAIL rule=HOST_TARGET_CROSS lock.role={lock.get("role")} arg={args.role}', file=sys.stderr)
            return 1
    errors = []
    verify(sdk, lock, pin, identities, errors)
    if errors:
        for item in errors:
            print(item, file=sys.stderr)
        print(f'SDK-VERIFY-LOCK-SHA {lock_sha}')
        return 1
    print(f'SDK-VERIFY-OK lock_sha256={lock_sha} role={lock.get("role")} files={len(lock.get("files") or {})}')
    if args.lock_sha_out:
        args.lock_sha_out.write_text(lock_sha + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
