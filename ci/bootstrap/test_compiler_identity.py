#!/usr/bin/env python3
"""SDK assembly/verification device tests through their real shell/CLI entries.

Fixture ELFs model distinct producer bytes, not a functioning Cangjie compiler.
Use --compiler and --official-frontend for the real-input guard rehearsal.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
COMPILER = OFFICIAL = None


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class CompilerIdentityTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.base = self.root / 'base'
        self.sdk = self.root / 'sdk'
        for rel in ('bin/cjc', 'bin/cjc-frontend', 'tools/bin/cjpm',
                    'third_party/llvm/bin/llc', 'third_party/llvm/bin/opt', 'third_party/llvm/bin/ld.lld'):
            path = self.base / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile('/bin/true', path)
            path.chmod(0o755)
        if OFFICIAL:
            shutil.copyfile(OFFICIAL, self.base / 'bin/cjc-frontend')
        self.product = self.root / 'product'
        if COMPILER:
            shutil.copyfile(COMPILER, self.product)
        else:
            source = self.root / 'driver.c'
            source.write_text('#include <stdio.h>\nint main(void) { puts("fixture producer"); return 0; }\n')
            subprocess.run(['cc', str(source), '-o', str(self.product)], check=True)
        self.product.chmod(0o755)
        runtime = self.base / 'runtime/lib/linux_x86_64_cjnative'
        runtime.mkdir(parents=True)
        source = self.root / 'host.c'
        source.write_text('int host_runtime_fixture;\n')
        self.host = runtime / 'libcangjie-runtime.so'
        subprocess.run(['cc', '-shared', '-fPIC', str(source), '-o', str(self.host)], check=True)
        shutil.copyfile(self.host, runtime / 'libboundscheck.so')
        llvm = self.base / 'third_party/llvm/lib/libLLVM-15.so'
        llvm.parent.mkdir(parents=True)
        shutil.copyfile(self.host, llvm)
        obj = self.root / 'host.o'
        subprocess.run(['cc', '-c', str(source), '-o', str(obj)], check=True)
        static = self.base / 'lib/linux_x86_64_cjnative'
        static.mkdir(parents=True)
        subprocess.run(['ar', 'rcs', str(static / 'libcangjie-std-core.a'), str(obj)], check=True)
        source.write_text('int g_cjLoadBadMask;\n')
        self.colour = self.root / 'colour.so'
        subprocess.run(['cc', '-shared', '-fPIC', str(source), '-o', str(self.colour)], check=True)
        # Real compiler rehearsal only uses the identity installer below, not this
        # model runtime. Never execute a real compiler against fixture libraries.
        (self.base / 'envsetup.sh').write_text('# fixture SDK environment\n')

    def test_shell_assembly(self):
        if COMPILER:
            self.skipTest('real compiler identity rehearsal uses installer, not fixture runtime')
        process = subprocess.run(['bash', str(HERE / 'sdk_build.sh'), '--from', str(self.base),
                                  '--to', str(self.sdk), '--host', '--cjc', str(self.product),
                                  '--colour-runtime', str(self.colour), '--host-runtime', str(self.host)],
                                 capture_output=True, text=True)
        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
        actual = sha(self.sdk / 'bin/cjc-frontend')
        print('SDK_SHELL_FRONTEND_TARGET', actual, 'expected', sha(self.product))
        self.assertEqual(actual, sha(self.product), 'SDK_SHELL_FRONTEND_TARGET producer identity')
        self.assertEqual(os.readlink(self.sdk / 'bin/cjc-frontend'), 'cjcj-stage1')
        self.assertEqual(sha(self.sdk / 'bin/cjc'), sha(self.product))

    def test_verifier_rejects_official_frontend(self):
        shutil.copytree(self.base, self.sdk)
        subprocess.run([sys.executable, str(HERE / 'compiler_identity.py'), str(self.sdk),
                        '--install', str(self.product)], check=True, stdout=subprocess.DEVNULL)
        frontend = self.sdk / 'bin/cjc-frontend'
        frontend.unlink()
        shutil.copyfile(self.base / 'bin/cjc-frontend', frontend)
        process = subprocess.run([sys.executable, str(HERE / 'sdk_verify.py'), '--sdk', str(self.sdk),
                                  '--role', 'host', '--write-lock'], capture_output=True, text=True)
        text = process.stdout + process.stderr
        print('SDK_VERIFY_FRONTEND_TARGET rc=', process.returncode, 'producer=', sha(self.product),
              'frontend=', sha(frontend))
        self.assertEqual(process.returncode, 1, 'SDK_VERIFY_FRONTEND_TARGET must reject inherited frontend')
        self.assertIn('rule=COMPILER_IDENTITY', text)
        failures = [line for line in text.splitlines() if 'SDK-VERIFY-FAIL rule=' in line]
        self.assertEqual(len(failures), 1, text)
        self.assertIn('cjc-frontend: producer hash mismatch', text)
        frontend.unlink()
        frontend.symlink_to('cjcj-stage1')
        restored = subprocess.run([sys.executable, str(HERE / 'sdk_verify.py'), '--sdk', str(self.sdk),
                                   '--role', 'host', '--write-lock'], capture_output=True, text=True)
        self.assertEqual(restored.returncode, 0, restored.stdout + restored.stderr)
        print('SDK_VERIFY_FRONTEND_RESTORED rc=0')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('--compiler', type=Path)
    parser.add_argument('--official-frontend', type=Path)
    args, rest = parser.parse_known_args()
    COMPILER, OFFICIAL = args.compiler, args.official_frontend
    unittest.main(argv=[sys.argv[0], *rest], verbosity=2)
