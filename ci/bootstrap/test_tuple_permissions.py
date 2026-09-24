#!/usr/bin/env python3
"""Exercise the actual SDK tuple install using a real pinned tuple and host SDK.

HOST_SDK=/private/sdk LLVM_TUPLE=/pinned/tuple python3 test_tuple_permissions.py
Only private copies are modified. BOOTSTRAP_SDK_PRODUCT selects a cut script.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

PRODUCT = Path(os.environ.get('BOOTSTRAP_SDK_PRODUCT', Path(__file__).with_name('sdk_build.sh')))


class TuplePermissions(unittest.TestCase):
    def test_tuple_tools_execute_after_install(self):
        with tempfile.TemporaryDirectory(prefix='tuple-mode-') as tmp:
            root = Path(tmp)
            source = root / 'tuple'
            shutil.copytree(os.environ['LLVM_TUPLE'], source, symlinks=False)
            # All input bytes and checksums are preserved; change only modes.
            for name in ('llc', 'opt'):
                (source / 'bin' / name).chmod(0o644)
            self.check_install(root, source)

    def test_executable_tuple_control(self):
        with tempfile.TemporaryDirectory(prefix='tuple-mode-control-') as tmp:
            self.check_install(Path(tmp), Path(os.environ['LLVM_TUPLE']))

    def check_install(self, root, source):
        target = root / 'sdk'
        result = subprocess.run(['bash', str(PRODUCT), '--from', os.environ['HOST_SDK'],
                                 '--to', str(target), '--host', '--llvm-tuple', str(source),
                                 '--colour-runtime', os.environ['COLOUR_RUNTIME']],
                                capture_output=True, text=True)
        # The target invariant runs even when the product's verification fails.
        observations = []
        for name in ('llc', 'opt'):
            installed = target / 'third_party/llvm/bin' / name
            same = installed.is_file() and hashlib.sha256(installed.read_bytes()).digest() == hashlib.sha256((source / 'bin' / name).read_bytes()).digest()
            executable = os.access(installed, os.X_OK)
            observations.append({'tool': name, 'same_bytes': same, 'executable': executable})
        print('ASSERT tuple-installed-executable executed ' + json.dumps(observations), flush=True)
        self.assertTrue(all(x['same_bytes'] and x['executable'] for x in observations), result.stdout + result.stderr)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
