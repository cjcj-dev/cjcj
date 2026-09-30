#!/usr/bin/env python3
"""Exercise SDK symlink provenance and lock consumption through the real CLI."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

PRODUCT = Path(__file__).with_name('sdk_verify.py')


class Symlinks(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix='sdk-symlinks-')
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        self.source = self.root / 'input'
        self.sdk = self.root / 'sdk'
        (self.source / 'bin').mkdir(parents=True)
        (self.source / 'bin/cjcj-stage1').write_text('compiler')
        (self.source / 'bin/cjc').symlink_to('cjcj-stage1')
        shutil.copytree(self.source, self.sdk, symlinks=True)

    def cli(self, write=False, source=None):
        cmd = [sys.executable, str(PRODUCT), '--sdk', str(self.sdk), '--role', 'host']
        if write:
            cmd.append('--write-lock')
        if source:
            cmd.extend(['--from', str(source)])
        result = subprocess.run(cmd, text=True, capture_output=True)
        print(f'CLI {self._testMethodName} write={write} rc={result.returncode}\n'
              f'{result.stdout}{result.stderr}', flush=True)
        return result

    def good(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('SDK-VERIFY-OK', result.stdout)

    def red(self, result, rel):
        failures = [s for s in result.stderr.splitlines() if 'SDK-VERIFY-FAIL' in s]
        print(f'ASSERT exact-symlink {rel} failures={failures}', flush=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(failures), 1, failures)
        self.assertIn('rule=SYMLINK ', failures[0])
        self.assertIn(f'{rel} -> ', failures[0])

    def test_official_layout(self):
        # Representative upstream soname, tool alias, and directory link layouts.
        for tree in (self.source, self.sdk):
            (tree / 'lib').mkdir()
            (tree / 'lib/libpcre2-8.so.0.1').write_text('library')
            (tree / 'lib/libpcre2-8.so.0').symlink_to('libpcre2-8.so.0.1')
            (tree / 'bin/lld').write_text('linker')
            (tree / 'bin/ld.lld').symlink_to('lld')
            (tree / 'include').symlink_to('lib', target_is_directory=True)
        self.good(self.cli(write=True, source=self.source))
        lock = json.loads((self.sdk / 'SDK.lock.json').read_text())
        for rel in ('lib/libpcre2-8.so.0', 'bin/ld.lld', 'include'):
            self.assertEqual(lock['files'][rel]['link_target'], (self.source / rel).readlink().as_posix())
        self.good(self.cli())

    def test_build_preserves_input_layout(self):
        from test_sdk_exe_symlink import write_libs, plant_runtime, plant_producer, assemble
        libs = self.root / 'fixtures'
        write_libs(libs)
        base = self.root / 'build-input'
        plant_runtime(base, libs)
        (base / 'bin').mkdir()
        shutil.copyfile('/bin/true', base / 'bin/cjc')
        (base / 'bin/cjc').chmod(0o755)
        (base / 'bin/linker').symlink_to('cjc')
        plant_producer(base, base / 'bin/cjc')
        target = self.root / 'assembled'
        _, result = assemble(PRODUCT.with_name('sdk_build.sh'), base, target, libs)
        print(f'ASSERT sdk-build-input-layout rc={result.returncode}\n{result.stdout}', flush=True)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('SDK-BUILD-OK', result.stdout)
        self.assertEqual((target / 'bin/linker').readlink().as_posix(), 'cjc')
        lock = json.loads((target / 'SDK.lock.json').read_text())
        self.assertEqual(lock['files']['bin/linker']['link_target'], 'cjc')

    def test_unregistered(self):
        self.good(self.cli(write=True))
        (self.sdk / 'bin/cjcj-stage9').symlink_to('cjcj-stage1')
        self.red(self.cli(), 'bin/cjcj-stage9')

    def test_changed_target(self):
        self.good(self.cli(write=True))
        (self.sdk / 'bin/cjc').unlink()
        (self.sdk / 'bin/cjc').symlink_to('./cjcj-stage1')
        self.red(self.cli(), 'bin/cjc')

    def test_outside_target(self):
        self.good(self.cli(write=True))
        (self.sdk / 'bin/cjc').unlink()
        (self.sdk / 'bin/cjc').symlink_to('/etc/passwd')
        self.red(self.cli(), 'bin/cjc')

    def test_unchanged_target_outside_moved_sdk(self):
        (self.sdk / 'bin/cjc').unlink()
        (self.sdk / 'bin/cjc').symlink_to(self.sdk / 'bin/cjcj-stage1')
        self.good(self.cli(write=True))
        moved = self.root / 'moved'
        self.sdk.rename(moved)
        self.sdk = moved
        self.red(self.cli(), 'bin/cjc')

    def test_write_rejects_invented(self):
        (self.sdk / 'bin/cjcj-stage9').symlink_to('cjcj-stage1')
        self.red(self.cli(write=True, source=self.source), 'bin/cjcj-stage9')
        self.assertFalse((self.sdk / 'SDK.lock.json').exists())

    def test_write_rejects_changed(self):
        (self.source / 'bin/ld.lld').symlink_to('cjcj-stage1')
        (self.sdk / 'bin/ld.lld').symlink_to('./cjcj-stage1')
        self.red(self.cli(write=True, source=self.source), 'bin/ld.lld')
        self.assertFalse((self.sdk / 'SDK.lock.json').exists())

    def test_write_rejects_escape(self):
        for tree in (self.source, self.sdk):
            (tree / 'bin/cjc').unlink()
            (tree / 'bin/cjc').symlink_to('/etc/passwd')
        self.red(self.cli(write=True, source=self.source), 'bin/cjc')
        self.assertFalse((self.sdk / 'SDK.lock.json').exists())


if __name__ == '__main__':
    print(f'PRODUCT {PRODUCT} sha256={hashlib.sha256(PRODUCT.read_bytes()).hexdigest()}', flush=True)
    unittest.main(verbosity=2)
