#!/usr/bin/env python3
"""Assemble SDK.lock.json and fail-closed verify an assembled SDK tree."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys

ALLOWED_SYMLINKS = {'bin/cjc', 'bin/cjc-frontend'}
LOCK_NAME = 'SDK.lock.json'
SKIP_NAMES = {'.', LOCK_NAME}
LLVM_TOOLS = (
    'third_party/llvm/bin/llc',
    'third_party/llvm/bin/opt',
    'third_party/llvm/bin/ld.lld',
    'third_party/llvm/lib/libLLVM-15.so',
)
CJLLVM_RE = re.compile(rb'CJLLVM-COMMIT:([0-9a-fA-F]{40})')
CJRT_RE = re.compile(rb'CJRT-COMMIT:([0-9a-fA-F]{40})')
HEX64_RE = re.compile(r'^[0-9a-f]{64}$')

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
    if rel == 'std-producer.json':
        return 'std'
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


def measured_cjc_sha(sdk: Path) -> str | None:
    stage1 = sdk / 'bin/cjcj-stage1'
    cjc = sdk / 'bin/cjc'
    if stage1.is_file():
        return sha256_file(stage1)
    if cjc.is_file():
        return sha256_file(cjc)
    return None


def std_producer_sha(sdk: Path) -> str | None:
    path = sdk / 'std-producer.json'
    if not path.is_file():
        return None
    try:
        payload = json.loads(path.read_text())
    except json.JSONDecodeError:
        return ''
    compiler = payload.get('compiler_sha256') if isinstance(payload, dict) else None
    if not isinstance(compiler, str):
        return ''
    compiler = compiler.strip().lower()
    if not HEX64_RE.fullmatch(compiler):
        return ''
    return compiler


def file_stamps(path: Path, pattern: re.Pattern) -> list[str]:
    return [match.group(1).decode().lower() for match in pattern.finditer(path.read_bytes())]


def manifest_llvm_sha(sdk: Path) -> str | None:
    path = sdk / 'third_party/llvm/MANIFEST'
    if not path.is_file():
        return None
    match = re.search(r'(?m)^LLVM_SHA=([0-9a-fA-F]{40})\s*$', path.read_text(errors='replace'))
    if not match:
        return None
    return match.group(1).lower()


def runtime_so_path(sdk: Path, target_tuple: str | None) -> Path | None:
    if target_tuple:
        candidate = sdk / 'runtime/lib' / target_tuple / 'libcangjie-runtime.so'
        return candidate if candidate.is_file() else None
    found = []
    for path, rel in iter_files(sdk):
        if Path(rel).name == 'libcangjie-runtime.so' and classify(rel) == 'runtime':
            found.append(path)
    if len(found) == 1:
        return found[0]
    return None


def build_lock(sdk: Path, role: str, identities: dict, target_tuple: str | None = None) -> dict:
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
    cjc = files.get('bin/cjcj-stage1') or files.get('bin/cjc') or {}
    runtime_path = runtime_so_path(sdk, target_tuple)
    runtime_commit = None
    runtime_digest = None
    if runtime_path is not None and runtime_path.is_file():
        commits = sorted(set(file_stamps(runtime_path, CJRT_RE)))
        runtime_commit = commits[0] if len(commits) == 1 else None
        runtime_digest = sha256_file(runtime_path)
    lock = {
        'version': 1,
        'role': role,
        'files': files,
        'official_retain': official,
        'components': {
            'cjc': {'sha256': cjc.get('sha256')},
            'runtime': {
                'commit': runtime_commit,
                'so_sha256': runtime_digest,
            },
            'llvm_tuple': {'sha256': manifest_llvm_sha(sdk)},
        },
    }
    return lock


def fail(code: str, message: str, errors: list) -> None:
    errors.append(f'SDK-VERIFY-FAIL rule={code} {message}')


def verify(sdk: Path, lock: dict, pin: dict, identities: dict, errors: list, target_tuple: str | None = None) -> None:
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

    role = lock.get('role')
    measured = measured_cjc_sha(sdk)
    producer = std_producer_sha(sdk)
    has_std = any(
        entry.get('component') == 'std' and rel != 'std-producer.json'
        for rel, entry in lock_files.items()
    )
    if has_std:
        if producer is None:
            if role == 'target':
                fail('STD_CJC', 'target std has no std-producer.json compiler lineage', errors)
        elif producer == '' or not measured or producer != measured:
            fail('STD_CJC', f'std-producer compiler {producer or "invalid"} != on-disk cjc {measured}', errors)

    if (sdk / 'third_party/llvm').exists():
        missing = [rel for rel in LLVM_TOOLS if not (sdk / rel).is_file()]
        if missing:
            fail('LLVM_TUPLE', 'missing ' + ','.join(missing), errors)
        else:
            expected = manifest_llvm_sha(sdk)
            stamped = {rel: sorted(set(file_stamps(sdk / rel, CJLLVM_RE))) for rel in LLVM_TOOLS}
            any_stamp = any(stamped.values())
            if role == 'target' and ((sdk / 'third_party/llvm/MANIFEST').is_file() or any_stamp):
                if not expected:
                    fail('LLVM_TUPLE', 'colour llvm tools have no MANIFEST LLVM_SHA to compare', errors)
                else:
                    for rel, uniq in stamped.items():
                        if uniq != [expected]:
                            shown = ','.join(uniq) if uniq else 'none'
                            fail('LLVM_TUPLE', f'{rel} CJLLVM-COMMIT {shown} != MANIFEST LLVM_SHA {expected}', errors)
            elif role == 'host' and expected:
                opt_sha = stamped['third_party/llvm/bin/opt']
                if opt_sha and opt_sha != [expected]:
                    shown = ','.join(opt_sha)
                    fail('LLVM_TUPLE', f'opt CJLLVM-COMMIT {shown} != MANIFEST LLVM_SHA {expected}', errors)

    pin_commit = pin.get('RUNTIME_REF', '').lower()
    if pin_commit and role == 'target':
        runtime_so = runtime_so_path(sdk, target_tuple)
        if runtime_so is None:
            fail('RUNTIME_PIN', 'target runtime libcangjie-runtime.so missing', errors)
        else:
            commits = sorted(set(file_stamps(runtime_so, CJRT_RE)))
            if commits != [pin_commit]:
                shown = ','.join(commits) if commits else 'none'
                rel = runtime_so.relative_to(sdk).as_posix()
                fail('RUNTIME_PIN', f'{rel} CJRT-COMMIT {shown} != pin {pin_commit}', errors)
    if pin_commit and role == 'host':
        for path, rel in iter_files(sdk):
            if Path(rel).name != 'libcangjie-runtime.so' or classify(rel) != 'runtime':
                continue
            if pin_commit in set(file_stamps(path, CJRT_RE)):
                fail('RUNTIME_PIN', f'host runtime {rel} carries colour pin {pin_commit}', errors)
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
    parser.add_argument('--target-tuple')
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
        lock = build_lock(sdk, role, identities, args.target_tuple)
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
    verify(sdk, lock, pin, identities, errors, args.target_tuple)
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
