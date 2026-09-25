#!/usr/bin/env python3
"""Positive and negative fixtures for sdk_verify.py (cjcj#322)."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

PRODUCT = Path(__file__).with_name('sdk_verify.py')
PIN = Path(__file__).resolve().parents[1] / 'runtime_pin.env'
COMMIT = '4c4cbf53b44497103e76e2a47a8fa35f5d7a7287'
LLVM_SHA = 'a' * 40


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


def tagged(payload: bytes, token: str, value: str) -> bytes:
    return payload + f'\n{token}:{value}\n'.encode()


def make_sdk(root: Path, *, compiler: bytes = b'cjc-good', std: bytes = b'std-good',
             lld: bytes = b'lld-good', runtime: bytes = b'rt-good', extra=None, symlink_cjc=True,
             producer=True, producer_sha: str | None = None, runtime_commit: str | None = COMMIT,
             llvm_sha: str | None = None, stamp_tools=False, write_lld=True, lld_stamp=False):
    write(root / 'bin' / 'cjcj-stage1', compiler)
    if symlink_cjc:
        (root / 'bin' / 'cjc').symlink_to('cjcj-stage1')
        (root / 'bin' / 'cjc-frontend').symlink_to('cjcj-stage1')
    else:
        write(root / 'bin' / 'cjc', compiler)
    write(root / 'lib' / 'linux_x86_64_cjnative' / 'libcangjie-std-core.a', std)
    runtime_bytes = tagged(runtime, 'CJRT-COMMIT', runtime_commit) if runtime_commit else runtime
    write(root / 'runtime' / 'lib' / 'linux_x86_64_cjnative' / 'libcangjie-runtime.so', runtime_bytes)
    write(root / 'runtime' / 'lib' / 'linux_x86_64_cjnative' / 'libboundscheck.so', b'bc')

    def tool(rel: str, body: bytes, do_stamp: bool) -> None:
        data = tagged(body, 'CJLLVM-COMMIT', llvm_sha) if do_stamp and llvm_sha else body
        write(root / rel, data)

    tool('third_party/llvm/bin/llc', b'llc-good', stamp_tools)
    tool('third_party/llvm/bin/opt', b'opt-good', stamp_tools)
    if write_lld:
        tool('third_party/llvm/bin/ld.lld', lld, lld_stamp)
    tool('third_party/llvm/lib/libLLVM-15.so', b'llvm-good', stamp_tools)
    if llvm_sha:
        write(root / 'third_party/llvm/MANIFEST', f'LLVM_SHA={llvm_sha}\n'.encode())
    write(root / 'tools' / 'bin' / 'cjpm', b'cjpm')
    write(root / 'envsetup.sh', b'# env\n')
    if producer:
        write(root / 'std-producer.json', json.dumps({'compiler_sha256': producer_sha or sha(compiler)}).encode() + b'\n')
    if extra:
        extra(root)


def run_verify(sdk: Path, ident: dict, write_lock=True, extra=None):
    ident_path = sdk / 'identities.json'
    ident_path.write_text(json.dumps(ident))
    cmd = [sys.executable, str(PRODUCT), '--sdk', str(sdk), '--role', ident.get('role', 'target'),
           '--runtime-pin', str(PIN), '--identities', str(ident_path),
           '--target-tuple', 'linux_x86_64_cjnative']
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
    if others:
        raise SystemExit(f'{label}: extra rules {others}\n{text}')
    print(f'PASS {label} rc={result.returncode} rule={rule} extra_rules=0')
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
        make_sdk(case, std=b'OFFICIAL-NIGHTLY-STD-BYTES', producer=False)
        forged = identities(compiler_sha)
        expect_rule(run_verify(case, forged), 'STD_CJC', 'official-std')

        case = work / 'old-std'
        make_sdk(case, std=b'old-std', producer_sha='b' * 64)
        forged = identities(sha((case / 'bin' / 'cjcj-stage1').read_bytes()))
        expect_rule(run_verify(case, forged), 'STD_CJC', 'old-std-new-cjc')

        case = work / 'old-lld'
        make_sdk(case, lld=b'official-0904-lld', llvm_sha=LLVM_SHA, stamp_tools=True, lld_stamp=False)
        forged = identities(sha((case / 'bin' / 'cjcj-stage1').read_bytes()))
        expect_rule(run_verify(case, forged), 'LLVM_TUPLE', 'old-ld.lld')

        case = work / 'missing-lld'
        make_sdk(case, write_lld=False)
        forged = identities(sha((case / 'bin' / 'cjcj-stage1').read_bytes()))
        expect_rule(run_verify(case, forged), 'LLVM_TUPLE', 'missing-ld.lld')

        case = work / 'runtime-pin'
        make_sdk(case, runtime_commit='0' * 40)
        forged = identities(sha((case / 'bin' / 'cjcj-stage1').read_bytes()), runtime_commit=COMMIT)
        expect_rule(run_verify(case, forged), 'RUNTIME_PIN', 'runtime-pin')

        case = work / 'undeclared'
        make_sdk(case)
        forged = identities(sha((case / 'bin' / 'cjcj-stage1').read_bytes()))
        run_verify(case, forged)
        write(case / 'lib' / 'sneaky-official.so', b'leak')
        expect_rule(run_verify(case, forged, write_lock=False), 'UNDECLARED', 'undeclared-file')

        print('ALL-PASS N=7')
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
