#!/usr/bin/env python3
"""Integration assertions over the real AST producer output and SDK installer.

Arguments: artifact compiler-source compiler-build nightly-sdk empty-workdir
"""
import hashlib
from pathlib import Path
import subprocess
import sys
import unittest

artifact, compiler, build, nightly, work = map(Path, sys.argv[1:])
sdk = work / 'sdk'
sdk.mkdir(parents=True)
# A stale schema exercises replacement, not just first-time file creation.
(sdk / 'schema').mkdir()
(sdk / 'schema/StdAstFormat.fbs').write_text('stale schema\n')
installer = Path(__file__).with_name('install_std_sdk_inputs.py')
result = subprocess.run([sys.executable, installer, artifact, sdk, 'linux_x86_64_cjnative'], check=False)


class Inputs(unittest.TestCase):
    def test_installer_process(self):
        self.assertEqual(result.returncode, 0)

    def test_archive(self):
        self.assertEqual((sdk / 'lib/linux_x86_64_cjnative/libcangjie-ast-support.a').read_bytes(),
                         (build / 'lib/libcangjie-ast-support.a').read_bytes())
        print('ASSERT SDK archive bytes match producer build')

    def test_generated_header(self):
        self.assertEqual((sdk / 'include/flatbuffers/StdAstFormat_generated.h').read_bytes(),
                         (build / 'schema/flatbuffers/StdAstFormat_generated.h').read_bytes())
        print('ASSERT SDK generated header bytes match producer build')

    def test_schema(self):
        self.assertEqual((sdk / 'schema/StdAstFormat.fbs').read_bytes(),
                         (compiler / 'schema/StdAstFormat.fbs').read_bytes())
        print('ASSERT SDK schema bytes match compiler source')

    def test_public_headers(self):
        for source in (compiler / 'include/cangjie').rglob('*'):
            if source.is_file():
                with self.subTest(file=source.name):
                    dest = sdk / 'include/cangjie' / source.relative_to(compiler / 'include/cangjie')
                    self.assertEqual(dest.read_bytes(), source.read_bytes())
        print('ASSERT SDK public headers match compiler source')

    def test_flatbuffers(self):
        for source in (nightly / 'third_party/flatbuffers').rglob('*'):
            if source.is_file():
                with self.subTest(file=source.name):
                    dest = sdk / 'third_party/flatbuffers' / source.relative_to(nightly / 'third_party/flatbuffers')
                    self.assertEqual(dest.read_bytes(), source.read_bytes())
                    self.assertFalse(dest.is_symlink())
        print('ASSERT SDK flatbuffers matches official nightly bytes')


unittest.main(argv=[sys.argv[0]], verbosity=2)
