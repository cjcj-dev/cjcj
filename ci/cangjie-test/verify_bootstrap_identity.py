#!/usr/bin/env python3
"""Exercise the real installer, identity CLI and suite entry before input admission.

Optional real compiler inputs are inspected as bytes, never executed against a
fixture runtime. Expected identity comes from the separate build artifact.
"""
import argparse
import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
COMPILER = Path('/bin/true')
OFFICIAL = Path('/bin/false')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class BootstrapIdentityTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.sdk = self.root / 'sdk'
        self.sdk.mkdir()
        (self.sdk / 'envsetup.sh').write_text('# unused: stop at input admission\n')
        self.expected = sha(COMPILER)
        self.cli = HERE.parent / 'bootstrap/compiler_identity.py'

    def command(self, args):
        return subprocess.run([sys.executable, *map(str, args)], capture_output=True, text=True)

    def install(self, producer):
        result = self.command([self.cli, self.sdk, '--install', producer])
        self.assertEqual(result.returncode, 0, result.stderr)

    def entry(self, arm='bootstrap', expected=True):
        args = [HERE / 'run.py', self.sdk, self.root / 'unused-output',
                '--inputs', self.root / 'absent-inputs', '--arm', arm]
        if expected:
            args += ['--bootstrap-compiler-sha256', self.expected]
        return self.command(args)

    def test_independent_producer_accepted(self):
        self.install(COMPILER)
        guard = self.command([self.cli, self.sdk, '--expected-producer-sha256', self.expected])
        result = self.entry()
        print('BOOTSTRAP_OWN_TARGET guard_rc=', guard.returncode,
              'entry_reached_inputs=', 'missing input:' in result.stderr)
        self.assertEqual(guard.returncode, 0, guard.stderr)
        self.assertIn('missing input:', result.stderr)
        self.assertEqual(result.returncode, 2)

    def test_official_producer_rejected(self):
        # Use the genuine installer with the wrong producer; never forge lineage.
        self.assertNotEqual(sha(OFFICIAL), self.expected)
        self.install(OFFICIAL)
        result = self.entry()
        rejected = 'COMPILER_IDENTITY independent bootstrap producer mismatch' in result.stderr
        print('BOOTSTRAP_OFFICIAL_TARGET rejected=', rejected,
              'entry_rc=', result.returncode, 'official=', sha(OFFICIAL), 'expected=', self.expected)
        self.assertTrue(rejected, result.stdout + result.stderr)
        self.assertNotIn('missing input:', result.stderr)
        self.assertNotEqual(result.returncode, 0)

    def test_missing_independent_identity_rejected(self):
        self.install(COMPILER)
        result = self.entry(expected=False)
        self.assertIn('bootstrap requires --bootstrap-compiler-sha256', result.stderr)
        self.assertNotIn('missing input:', result.stderr)

    def test_malformed_identity_rejected(self):
        self.install(COMPILER)
        self.expected = 'z' * 64
        result = self.entry()
        self.assertIn('invalid expected producer SHA-256', result.stderr)
        self.assertNotIn('missing input:', result.stderr)

    def test_official_host_remains_accepted(self):
        self.install(OFFICIAL)
        guard = self.command([self.cli, self.sdk])
        result = self.entry(arm='official', expected=False)
        print('OFFICIAL_HOST_TARGET guard_rc=', guard.returncode,
              'entry_reached_inputs=', 'missing input:' in result.stderr)
        self.assertEqual(guard.returncode, 0, guard.stderr)
        self.assertIn('missing input:', result.stderr)
        self.assertEqual(result.returncode, 2)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('--compiler', type=Path, default=COMPILER)
    parser.add_argument('--official-frontend', type=Path, default=OFFICIAL)
    args, rest = parser.parse_known_args()
    COMPILER, OFFICIAL = args.compiler, args.official_frontend
    unittest.main(argv=[sys.argv[0], *rest], verbosity=2)
