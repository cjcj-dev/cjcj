#!/usr/bin/env python3
"""Native Linux runner identity contract, not a stage1 compiler acceptance test.

Optional HOST_IDENTITY_SDK and HOST_IDENTITY_LLVM add a real, fixed-release
three-library receipt against the checked-in declaration. No input sets a pin.
"""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent
RUNNER = Path(os.environ.get('STAGE1_RUNNER_PRODUCT', ROOT / 'stage1_host_runner.sh'))
IDENTITIES = Path(os.environ.get('STAGE1_PIN_PRODUCT', ROOT / 'stage1_host_identities.txt'))
NAMES = ('libcangjie-runtime.so', 'libboundscheck.so', 'libLLVM-15.so')
PLATFORM = 'linux_' + os.uname().machine
OTHER = 'linux_aarch64' if PLATFORM == 'linux_x86_64' else 'linux_x86_64'


def digest(file):
    return hashlib.sha256(Path(file).read_bytes()).hexdigest()


class HostIdentity(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='host-identities-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.host, self.target, self.run_sdk, self.hrt = [self.root / n for n in ('host', 'target', 'run', 'hrt')]
        self.runtime = Path('runtime/lib') / (PLATFORM + '_cjnative')
        for sdk in (self.host, self.target, self.run_sdk):
            for rel in (self.runtime, Path('third_party/llvm/lib'), Path('third_party/llvm/bin'), Path('bin'), Path('tools/bin')):
                (sdk / rel).mkdir(parents=True)
            for rel in ('bin/cjc', 'tools/bin/cjpm', 'third_party/llvm/bin/llc', 'third_party/llvm/bin/opt'):
                shutil.copyfile('/bin/true', sdk / rel)
                (sdk / rel).chmod(0o755)
        self.hrt.mkdir()
        self.files = {}
        for name in NAMES:
            rel = Path('third_party/llvm/lib') / name if name == NAMES[2] else self.runtime / name
            self.files[name] = self.host / rel
            for sdk in (self.host, self.target, self.run_sdk):
                (sdk / rel).write_bytes(('fixture-' + name).encode())
            if name != NAMES[2]:
                shutil.copyfile(self.files[name], self.hrt / name)
        self.pins = {name: digest(file) for name, file in self.files.items()}
        self.identities = self.root / 'identities.txt'
        # Different hashes on the other platform make accidental cross-selection observable.
        self.rows = [f'{OTHER} {name} {"f" * 64}' for name in NAMES]
        self.rows += [f'{PLATFORM} {name} {self.pins[name]}' for name in NAMES]
        self.identities.write_text('\n'.join(self.rows) + '\n')

    def install(self, llvm_sha=None):
        args = ['bash', str(RUNNER), str(self.target), str(self.host), str(self.hrt),
                llvm_sha or self.pins[NAMES[2]], str(self.host / 'bin/cjc'), digest(self.host / 'bin/cjc'),
                str(self.run_sdk), digest(self.run_sdk / 'third_party/llvm/lib/libLLVM-15.so')]
        return subprocess.run(args, env={**os.environ, 'STAGE1_HOST_IDENTITIES': str(self.identities)},
                              capture_output=True, text=True)

    def rejected(self, result, reason):
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(reason, result.stderr)
        self.assertFalse((self.target / '.stage1-host').exists(), result.stdout)
        print('ASSERT rejected-before-install ' + reason, flush=True)

    def accepted(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        binding = dict(line.split('=', 1) for line in (self.target / '.stage1-host/binding.txt').read_text().splitlines())
        self.assertEqual([binding['decl_' + key] for key in ('runtime', 'bounds', 'llvm')],
                         [self.pins[name] for name in NAMES])
        self.assertIn(str(self.host / self.runtime), binding['host_ld'])
        print('ASSERT installed-native-triple ' + PLATFORM + ' ' + ' '.join(self.pins.values()), flush=True)

    def test_native_triple(self):
        self.accepted(self.install())

    def test_other_platform_rows_after_native(self):
        self.identities.write_text('\n'.join(self.rows[3:] + self.rows[:3]) + '\n')
        self.accepted(self.install())

    def test_malformed_selected_pin(self):
        self.identities.write_text('\n'.join(self.rows[:-1] + [f'{PLATFORM} libLLVM-15.so invalid']) + '\n')
        self.rejected(self.install(), 'invalid host identity: ' + PLATFORM)

    def test_other_platform_cannot_fill_missing_pin(self):
        self.identities.write_text('\n'.join(self.rows[:-1]) + '\n')
        self.rejected(self.install(), 'incomplete host identities: ' + PLATFORM)

    def test_duplicate_selected_pin(self):
        self.identities.write_text('\n'.join(self.rows + [self.rows[-1]]) + '\n')
        self.rejected(self.install(), 'duplicate host identity: libLLVM-15.so')

    def test_legacy_unscoped_pin_rejected(self):
        self.identities.write_text('\n'.join(row.split(' ', 1)[1] for row in self.rows[-3:]) + '\n')
        self.rejected(self.install(), 'unknown identity platform: libcangjie-runtime.so')

    def test_wrong_llvm_argument(self):
        self.rejected(self.install('f' * 64), 'llvm sha is not the declared host triple:')

    def test_hrt_runtime_bytes(self):
        (self.hrt / NAMES[0]).write_bytes(b'changed runtime')
        self.rejected(self.install(), 'sha mismatch: ' + str(self.hrt / NAMES[0]))

    def test_hrt_bounds_bytes(self):
        (self.hrt / NAMES[1]).write_bytes(b'changed bounds')
        self.rejected(self.install(), 'sha mismatch: ' + str(self.hrt / NAMES[1]))

    def test_host_runtime_bytes(self):
        self.files[NAMES[0]].write_bytes(b'changed host runtime')
        self.rejected(self.install(), 'sha mismatch: ' + str(self.files[NAMES[0]]))

    def test_host_bounds_bytes(self):
        self.files[NAMES[1]].write_bytes(b'changed host bounds')
        self.rejected(self.install(), 'sha mismatch: ' + str(self.files[NAMES[1]]))

    def test_host_llvm_bytes(self):
        self.files[NAMES[2]].write_bytes(b'changed host llvm')
        self.rejected(self.install(), 'sha mismatch: ' + str(self.files[NAMES[2]]))

    @unittest.skipUnless(os.environ.get('HOST_IDENTITY_SDK') and os.environ.get('HOST_IDENTITY_LLVM'),
                         'real fixed SDK and pinned host LLVM required')
    def test_fixed_release_triple(self):
        sdk = Path(os.environ['HOST_IDENTITY_SDK'])
        for name in NAMES:
            source = Path(os.environ['HOST_IDENTITY_LLVM']) if name == NAMES[2] else sdk / self.runtime / name
            shutil.copyfile(source, self.files[name])
            if name != NAMES[2]:
                shutil.copyfile(source, self.hrt / name)
            self.pins[name] = digest(source)
            print(f'INPUT {name} {self.pins[name]} {source}', flush=True)
        # Pins remain checked-in data; input hashes only observe the result.
        self.identities = IDENTITIES
        self.accepted(self.install())


if __name__ == '__main__':
    unittest.main(verbosity=2)
