#!/usr/bin/env python3
"""Positive and negative fixtures for sdk_verify.py (cjcj#322)."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

PRODUCT = Path(__file__).with_name('sdk_verify.py')
PIN = Path(__file__).resolve().parents[1] / 'runtime_pin.env'
COMMIT = '4c4cbf53b44497103e76e2a47a8fa35f5d7a7287'


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write(path: Path, data: bytes = b'x') -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def identities(compiler: str, runtime_commit: str = COMMIT, llvm_tuple: str | None = None) -> dict:
    payload = {
        'role': 'target',
        'cjc': {'repo': 'cjcj-dev/cjcj', 'commit': '0' * 40, 'compiler_sha256': compiler},
        'std': {'repo': 'cjcj-dev/cangjie', 'commit': '1' * 40, 'compiler_sha256': compiler},
        'runtime': {'repo': 'cjcj-dev/cangjie-runtime', 'commit': runtime_commit},
        'llvm': {'repo': 'cjcj-dev/cjcj-llvm', 'commit': '2' * 40},
        'cjpm': {'repo': 'cjcj-dev/cjcj', 'commit': '0' * 40},
        'boundscheck': {'repo': 'cjcj-dev/cangjie-runtime', 'commit': runtime_commit},
    }
    if llvm_tuple:
        payload['llvm']['llvm_tuple_sha'] = llvm_tuple
    return payload


def make_sdk(root: Path, *, compiler: bytes = b'cjc-good', std: bytes = b'std-good',
             lld: bytes = b'lld-good', runtime: bytes = b'rt-good', extra=None, symlink_cjc=True):
    write(root / 'bin' / 'cjcj-stage1', compiler)
    if symlink_cjc:
        (root / 'bin' / 'cjc').symlink_to('cjcj-stage1')
        (root / 'bin' / 'cjc-frontend').symlink_to('cjcj-stage1')
    else:
        write(root / 'bin' / 'cjc', compiler)
    write(root / 'lib' / 'linux_x86_64_cjnative' / 'libcangjie-std-core.a', std)
    write(root / 'runtime' / 'lib' / 'linux_x86_64_cjnative' / 'libcangjie-runtime.so', runtime)
    write(root / 'runtime' / 'lib' / 'linux_x86_64_cjnative' / 'libboundscheck.so', b'bc')
    write(root / 'third_party' / 'llvm' / 'bin' / 'llc', b'llc-good')
    write(root / 'third_party' / 'llvm' / 'bin' / 'opt', b'opt-good')
    write(root / 'third_party' / 'llvm' / 'bin' / 'ld.lld', lld)
    write(root / 'third_party' / 'llvm' / 'lib' / 'libLLVM-15.so', b'llvm-good')
    write(root / 'tools' / 'bin' / 'cjpm', b'cjpm')
    write(root / 'envsetup.sh', b'# env\n')
    if extra:
        extra(root)


def run_verify(sdk: Path, ident: dict, write_lock=True, extra=None):
    ident_path = sdk / 'identities.json'
    ident_path.write_text(json.dumps(ident))
    cmd = [sys.executable, str(PRODUCT), '--sdk', str(sdk), '--role', ident.get('role', 'target'),
           '--runtime-pin', str(PIN), '--identities', str(ident_path)]
    if write_lock:
        cmd.append('--write-lock')
    if extra:
        cmd.extend(extra)
    return subprocess.run(cmd, capture_output=True, text=True)


def expect_rule(result, rule: str, label: str):
    text = result.stdout + result.stderr
    if result.returncode == 0:
        raise SystemExit(f'{label}: expected fail, got OK\n{text}')
    if f'rule={rule}' not in text:
        raise SystemExit(f'{label}: expected rule={rule} in\n{text}')
    others = [line for line in text.splitlines() if 'SDK-VERIFY-FAIL rule=' in line and f'rule={rule}' not in line]
    print(f'PASS {label} rc={result.returncode} rule={rule} extra_rules={len(others)}')
    return text


def main() -> int:
    work = Path(tempfile.mkdtemp(prefix='sdk-verify-'))
    try:
        good = work / 'good'
        make_sdk(good)
        compiler_sha = sha((good / 'bin' / 'cjcj-stage1').read_bytes())
        ident = identities(compiler_sha)
        result = run_verify(good, ident)
        if result.returncode != 0:
            raise SystemExit(f'good SDK failed: {result.stdout}{result.stderr}')
        if 'SDK-VERIFY-OK' not in result.stdout:
            raise SystemExit(f'good SDK missing OK: {result.stdout}')
        print(f'PASS good rc=0 {result.stdout.strip()}')

        case = work / 'official-std'
        make_sdk(case, std=b'official-std-bytes')
        bad_ident = identities(compiler_sha)
        bad_ident['std']['compiler_sha256'] = 'official-cjc-sha-not-this-sdk'
        expect_rule(run_verify(case, bad_ident), 'STD_CJC', 'official-std')

        case = work / 'old-std'
        make_sdk(case, std=b'old-std')
        bad_ident = identities('deadbeef' * 8)
        expect_rule(run_verify(case, bad_ident), 'STD_CJC', 'old-std-new-cjc')

        case = work / 'old-lld'
        make_sdk(case, lld=b'official-0904-lld')
        ident = identities(sha((case / 'bin' / 'cjcj-stage1').read_bytes()))
        run_verify(case, ident)
        lock = json.loads((case / 'SDK.lock.json').read_text())
        lock['files']['third_party/llvm/bin/ld.lld']['producer']['llvm_tuple_sha'] = 'old-tuple'
        lock['files']['third_party/llvm/bin/llc']['producer']['llvm_tuple_sha'] = 'new-tuple'
        (case / 'SDK.lock.json').write_text(json.dumps(lock, indent=2) + '\n')
        expect_rule(run_verify(case, ident, write_lock=False), 'LLVM_TUPLE', 'old-ld.lld')

        case = work / 'runtime-pin'
        make_sdk(case)
        ident = identities(sha((case / 'bin' / 'cjcj-stage1').read_bytes()), runtime_commit='0' * 40)
        expect_rule(run_verify(case, ident), 'RUNTIME_PIN', 'runtime-pin')

        case = work / 'undeclared'
        make_sdk(case)
        ident = identities(sha((case / 'bin' / 'cjcj-stage1').read_bytes()))
        run_verify(case, ident)
        write(case / 'lib' / 'sneaky-official.so', b'leak')
        expect_rule(run_verify(case, ident, write_lock=False), 'UNDECLARED', 'undeclared-file')

        print('ALL-PASS N=6')
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
