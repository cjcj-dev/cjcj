#!/usr/bin/env python3
"""Real stage1 SDK handoff: set RUNNER_INPUTS to an authenticated input JSON.

Each case installs the product runner into a physical private SDK copy, observes
compiler bytes, and compiles a native program. No fixture compiler or pin edits.
Cases share the temporary output directory sequentially; independent cut arms
must use different RUNNER_OUTPUT directories.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import unittest

ROOT = Path(__file__).resolve().parent


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


class CompilerAlias(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inputs = json.loads(Path(os.environ['RUNNER_INPUTS']).read_text())
        cls.output = Path(os.environ['RUNNER_OUTPUT'])
        cls.output.mkdir(parents=True, exist_ok=True)
        cls.runner = Path(os.environ.get('STAGE1_RUNNER_PRODUCT', ROOT / 'stage1_host_runner.sh'))
        cls.receipts = []

    @classmethod
    def tearDownClass(cls):
        (cls.output / 'results.json').write_text(json.dumps(cls.receipts, indent=2) + '\n')

    def setUp(self):
        self.work = self.output / self._testMethodName
        self.work.mkdir()
        self.sdk = self.work / 'sdk'
        # Copy all payload bytes; preserve only the two compiler aliases, using
        # their actual producer link text rather than synthesizing a layout.
        original = Path(self.inputs['sdk'])
        aliases = ('cjc', 'cjc-frontend')
        links = {name: os.readlink(original / 'bin' / name) for name in aliases}
        self.assertEqual(links, {name: 'cjcj-stage1' for name in aliases})
        def omit_aliases(directory, names):
            return list(aliases) if Path(directory) == original / 'bin' else []
        shutil.copytree(original, self.sdk, symlinks=False, ignore=omit_aliases)
        self.addCleanup(shutil.rmtree, self.sdk)
        for name, target in links.items():
            (self.sdk / 'bin' / name).symlink_to(target)
        self.before = digest(self.sdk / 'bin/cjcj-stage1')
        self.assertEqual(self.before, self.inputs['compiler_sha256'])
        self.row = {'test': self._testMethodName, 'runner_sha256': digest(self.runner),
                    'test_sha256': digest(__file__), 'compiler_before': self.before}
        self.receipts.append(self.row)

    def install(self):
        i = self.inputs
        start = time.monotonic()
        result = subprocess.run(['bash', str(self.runner), str(self.sdk), i['host'], i['host_runtime'],
                                 i['host_llvm_sha256'], i['compiler'], i['compiler_sha256'],
                                 i['run_sdk'], i['colour_llvm_sha256']], capture_output=True, text=True)
        records = self.row.setdefault('installations', [])
        (self.work / f'install-{len(records)}.log').write_text(result.stdout + result.stderr)
        records.append({'rc': result.returncode, 'subcase': getattr(self, 'subcase', '')})
        self.row.update(install_rc=result.returncode, install_wall=time.monotonic() - start,
                        compiler_after=digest(self.sdk / 'bin/cjcj-stage1'))
        return result

    def compile(self):
        # Check the actual installed product value before attempting execution.
        print('ASSERT compiler-bytes-preserved', self._testMethodName,
              self.row['compiler_after'], flush=True)
        self.assertEqual(self.row['compiler_after'], self.before, 'compiler-bytes-preserved')
        self.assertFalse((self.sdk / 'bin/cjc').is_symlink(), 'workspace wrapper must be physical')
        source = self.work / 'hello.cj'
        source.write_text('main() { println("runner-alias") }\n')
        product = self.work / 'hello'
        start = time.monotonic()
        result = subprocess.run([str(self.sdk / 'bin/cjc'), str(source), '--static-std', '-o', str(product)],
                                env={**os.environ, 'cjHeapSize': '32768MB'},
                                capture_output=True, text=True, timeout=240)
        (self.work / 'compile.log').write_text(result.stdout + result.stderr)
        self.row.update(compile_rc=result.returncode, compile_wall=time.monotonic() - start)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(product.read_bytes()[:4], b'\x7fELF', 'native-ELF-produced')
        self.row['elf_sha256'] = digest(product)
        print('ASSERT native-ELF-produced', self._testMethodName, self.row['elf_sha256'], flush=True)
        product.unlink()

    def test_same_directory_alias(self):
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.compile()

    def test_regular_input(self):
        entry = self.sdk / 'bin/cjc'
        entry.unlink()
        shutil.copyfile(self.inputs['compiler'], entry)
        entry.chmod(0o755)
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.compile()

    def test_other_link_rejected(self):
        # An executable with identical bytes still cannot authorize another path.
        outside = self.work / 'other-compiler'
        shutil.copyfile(self.inputs['compiler'], outside)
        outside.chmod(0o755)
        entry = self.sdk / 'bin/cjc'
        entry.unlink()
        entry.symlink_to(outside)
        result = self.install()
        print('ASSERT other-link-rejected', result.returncode, flush=True)
        self.assertEqual(result.returncode, 1, 'other-link-rejected')
        self.assertRegex(result.stderr, r'STAGE1-RUNNER-FAIL (unsupported executable link:|regular executable required:) bin/cjc')
        self.assertEqual(digest(outside), self.before, 'rejected target unchanged')
        self.assertEqual(self.row['compiler_after'], self.before)
        self.assertFalse((self.sdk / '.stage1-host').exists(), 'rejected before installation')
        outside.unlink()

    def test_compiler_link_chain_rejected(self):
        real = self.work / 'compiler-payload'
        shutil.copyfile(self.inputs['compiler'], real)
        real.chmod(0o755)
        compiler = self.sdk / 'bin/cjcj-stage1'
        compiler.unlink()
        compiler.symlink_to(real)
        result = self.install()
        self.assertEqual(result.returncode, 1, 'compiler-link-chain-rejected')
        self.assertRegex(result.stderr, r'STAGE1-RUNNER-FAIL (unsupported executable link:|regular executable required:) bin/cjc')
        self.assertEqual(digest(real), self.before)
        self.assertFalse((self.sdk / '.stage1-host').exists())
        real.unlink()

    def test_noncompiler_links_rejected(self):
        for relative in ('tools/bin/cjpm', 'third_party/llvm/bin/opt', 'third_party/llvm/bin/llc'):
            with self.subTest(relative=relative):
                entry = self.sdk / relative
                saved = entry.read_bytes()
                entry.unlink()
                entry.symlink_to(self.sdk / 'bin/cjcj-stage1')
                self.subcase = relative
                result = self.install()
                print('ASSERT noncompiler-link-rejected', relative, result.returncode, flush=True)
                self.assertEqual(result.returncode, 1, 'noncompiler-link-rejected')
                self.assertRegex(result.stderr, r'STAGE1-RUNNER-FAIL (unsupported executable link:|regular executable required:) ' + relative)
                self.assertEqual(self.row['compiler_after'], self.before)
                self.assertFalse((self.sdk / '.stage1-host').exists())
                entry.unlink()
                entry.write_bytes(saved)
                entry.chmod(0o755)


if __name__ == '__main__':
    unittest.main(verbosity=2)
