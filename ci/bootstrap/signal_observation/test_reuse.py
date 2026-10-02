#!/usr/bin/env python3
"""Bounded offline batch: real archive/configuration; stop at LLDB argv only."""
import contextlib
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import time
import unittest

# Inputs are retained real entities, not synthetic SDKs or mocked digests.
HERE = Path(__file__).resolve().parent
BASE = Path(os.environ['SIGNAL_REUSE_TEST_ROOT']).resolve()
BASE.mkdir(parents=True, exist_ok=True)
os.environ['RUNNER_TEMP'] = str(BASE / 'runner')
import reuse
import run

ARCHIVE = Path(os.environ['SIGNAL_REUSE_ARCHIVE'])
MANIFEST = Path(os.environ['SIGNAL_REUSE_MANIFEST'])
SOURCE = Path(os.environ['SIGNAL_REUSE_SOURCE'])
RESULTS = []
LAUNCHES = []


class StopAtLLDB(Exception):
    pass


def boundary(argv, log, timeout=120, env=None):
    assert argv[0] == '/usr/bin/lldb'
    config = json.loads(Path(env['SIGNAL_OBSERVER_CONFIG']).read_text())
    receipt_path = run.OUT / 'run-input-receipt.json'
    receipt = json.loads(receipt_path.read_text())
    saved = Path(env['SIGNAL_OBSERVER_CONFIG']).with_suffix('.receipt.json')
    shutil.copyfile(receipt_path, saved)
    LAUNCHES.append({'argv': argv, 'timeout': timeout, 'config': config, 'receipt': receipt})
    raise StopAtLLDB()


class ReuseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        start = time.monotonic()
        retained = os.environ.get('SIGNAL_REUSE_RETAINED_ROOT')
        cls.root = Path(retained).resolve(strict=True) if retained else reuse.materialize(ARCHIVE, MANIFEST, SOURCE, BASE / 'relocated')
        cls.retained = bool(retained)
        cls.hashes_before = {p: reuse.digest(cls.root / p) for p in reuse.IDENTITIES}
        (run.OUT / 'calibration.json').write_text(Path(os.environ['SIGNAL_REUSE_CALIBRATION']).read_text())
        run.command = boundary  # sole expensive boundary: never run LLDB/helper/product
        print('MATERIALIZED wall=' + str(time.monotonic() - start), flush=True)

    @classmethod
    def tearDownClass(cls):
        after = {p: reuse.digest(cls.root / p) for p in reuse.IDENTITIES}
        assert after == cls.hashes_before, 'entities changed during offline batch'
        receipt = json.loads((cls.root.parent / 'mapping-receipt.json').read_text())
        evidence = {'entity_hashes_before': cls.hashes_before, 'entity_hashes_after': after,
                    'source_hashes': {p.name: reuse.digest(p) for p in (HERE / 'run.py', HERE / 'reuse.py', HERE / 'observer.py', HERE / 'test_reuse.py')},
                    'launch_requests_intercepted': LAUNCHES,
                    'historical_manifest_paths': receipt['historical_manifest_paths'],
                    'additional_regular_files': receipt['additional_regular_files'],
                    'link_mappings': [m for m in receipt['mapping'] if m['was_link']]}
        (BASE / 'evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
        # Keep receipts; discard the copied SDKs after obtaining the result.
        if not cls.retained:
            shutil.rmtree(cls.root)

    def target(self, label, assertion):
        print('TARGET_REACHED ' + label, flush=True)
        assertion()
        print('TARGET_OK ' + label, flush=True)

    @contextlib.contextmanager
    def changed(self, relative, replacement=None, remove=False):
        path = self.root / relative
        backup = BASE / 'changed-backup'
        shutil.copyfile(path, backup)
        if remove:
            path.unlink()
        elif replacement is None:
            path.write_bytes(b'incorrect-entity')
        else:
            shutil.copyfile(replacement, path)
        try:
            yield
        finally:
            shutil.copyfile(backup, path)
            backup.unlink()

    def configure(self, root=None, size=131072):
        before = len(LAUNCHES)
        with self.assertRaises(StopAtLLDB):
            run.observe(self.root / 'candidate/cjc', 'product', size, root or self.root)
        self.assertEqual(len(LAUNCHES), before + 1)
        # Consume the files observe actually wrote, after its final configuration.
        config = run.OUT / ('product-' + str(size) + '.config.json')
        cfg = json.loads(config.read_text())
        self.assertEqual(cfg, LAUNCHES[-1]['config'])
        return cfg

    def rejected(self, label, action, text):
        before = len(LAUNCHES)
        self.target(label, lambda: self.assertRaisesRegex((ValueError, FileNotFoundError), text, action))
        self.assertEqual(len(LAUNCHES), before, 'rejected input reached LLDB')

    def test_01_runtime_wiring(self):
        cfg = self.configure()
        expected = str(self.root / 'host-runtime/runtime/lib' / reuse.TUPLE)
        self.target('runtime-loader-config', lambda: self.assertEqual(cfg['environment']['DYLD_LIBRARY_PATH'].split(':')[0], expected))
        receipt = json.loads((run.OUT / 'run-input-receipt.json').read_text())
        self.assertEqual(receipt['selected_libraries']['libcangjie-runtime.dylib'], expected + '/libcangjie-runtime.dylib')

    def test_02_llvm_role(self):
        cfg = self.configure()
        self.target('process-sdk-config', lambda: self.assertEqual(cfg['environment']['CANGJIE_HOME'], str(self.root / 'sdk-stage0-run')))
        self.assertEqual(cfg['expected_libraries']['libLLVM.dylib'], reuse.IDENTITIES['sdk-stage0-run/third_party/llvm/lib/libLLVM.dylib'])

    def test_13_final_llvm_directory(self):
        cfg = self.configure(size=131073)
        directories = [Path(p) for p in cfg['environment']['DYLD_LIBRARY_PATH'].split(':')]
        expected = self.root / 'sdk-stage0-run/third_party/llvm/lib'
        def check():
            self.assertEqual(directories[3], expected, 'final LLVM search directory')
            first = next((p / 'libLLVM.dylib' for p in directories if (p / 'libLLVM.dylib').is_file()), None)
            self.assertEqual(first, expected / 'libLLVM.dylib', 'first LLVM loader match')
        self.target('final-llvm-directory', check)

    def test_14_final_llvm_receipt(self):
        cfg = self.configure(size=131074)
        receipt = json.loads((run.OUT / 'run-input-receipt.json').read_text())
        sdk = str(self.root / 'sdk-stage0-run')
        llvm = sdk + '/third_party/llvm/lib/libLLVM.dylib'
        def check():
            self.assertEqual(receipt['selected_libraries']['libLLVM.dylib'], llvm, 'receipt LLVM selected path')
            self.assertEqual(receipt['roles'], {'compilation_sdk': str(self.root / 'sdk-stage0'), 'process_sdk': sdk}, 'receipt SDK roles')
            self.assertEqual(receipt['environment'], {k: cfg['environment'][k] for k in ('CANGJIE_HOME', 'DYLD_LIBRARY_PATH')}, 'receipt final cfg environment')
            self.assertEqual(receipt['expected_libraries']['libLLVM.dylib'], cfg['expected_libraries']['libLLVM.dylib'], 'receipt LLVM identity')
        self.target('final-llvm-receipt', check)

    def test_03_old_runtime_root(self):
        relative = 'host-runtime/runtime/lib/' + reuse.TUPLE + '/libcangjie-runtime.dylib'
        with self.changed(relative, remove=True):
            self.rejected('missing-real-runtime', self.configure, 'libcangjie-runtime')
        self.assertTrue((self.root / 'host-runtime/lib' / reuse.TUPLE / 'libboundscheck.dylib').is_file())

    def test_04_bad_runtime(self):
        relative = 'host-runtime/runtime/lib/' + reuse.TUPLE + '/libcangjie-runtime.dylib'
        with self.changed(relative):
            self.rejected('bad-runtime-hash', self.configure, 'entity-identity: ' + relative)

    def test_05_bad_bounds(self):
        relative = 'host-runtime/runtime/lib/' + reuse.TUPLE + '/libboundscheck.dylib'
        with self.changed(relative):
            self.rejected('bad-bounds-hash', self.configure, 'entity-identity: ' + relative)

    def test_06_host_llvm(self):
        relative = 'sdk-stage0-run/third_party/llvm/lib/libLLVM.dylib'
        with self.changed(relative, self.root / 'sdk-stage0/third_party/llvm/lib/libLLVM.dylib'):
            self.rejected('host-llvm-rejected', self.configure, 'entity-identity: ' + relative)

    def test_07_wrong_root(self):
        self.rejected('no-build-tree-fallback', lambda: self.configure(BASE / 'old-runner-root'), 'old-runner-root')

    def test_08_outside_root(self):
        path = self.root / 'host-runtime/runtime/lib' / reuse.TUPLE / 'libcangjie-runtime.dylib'
        copy = BASE / 'outside-runtime'
        shutil.copyfile(path, copy)
        path.unlink()
        path.symlink_to(copy)
        try:
            self.rejected('outside-private-root', self.configure, 'outside-entity-root')
        finally:
            path.unlink()
            shutil.copyfile(copy, path)
            copy.unlink()

    def test_09_loader_expected_source(self):
        # Shadow LLVM in an earlier real loader directory with the SAME bytes.
        path = self.root / 'host-runtime/runtime/lib' / reuse.TUPLE / 'libLLVM.dylib'
        shutil.copyfile(self.root / 'sdk-stage0-run/third_party/llvm/lib/libLLVM.dylib', path)
        try:
            self.rejected('loader-expected-same-source', self.configure, 'loader-expected-path: libLLVM')
        finally:
            path.unlink()

    def test_10_transport_receipt(self):
        receipt = json.loads((self.root.parent / 'mapping-receipt.json').read_text())
        self.target('archive-mapping', lambda: self.assertEqual(receipt['archive_sha256'], reuse.ARCHIVE_SHA))
        self.assertEqual(reuse.digest(self.root.parent / 'original-keep.sha256'), reuse.MANIFEST_SHA)
        self.assertTrue(all(not Path(m['path']).is_symlink() and reuse.digest(m['path']) == m['sha256'] for m in receipt['mapping']))
        covered = set(receipt['historical_manifest_paths'])
        regular = {m['archive_path'][5:] for m in receipt['mapping'] if not m['was_link']}
        additional = {m['archive_path'][5:] for m in receipt['additional_regular_files']}
        self.assertEqual(regular - covered, additional)
        self.assertFalse(covered & additional)

    def test_11_module_path(self):
        selection = reuse.select(self.root)
        modules = [{'path': p, 'sha256': selection['expected_libraries'][n]} for n, p in selection['selected_libraries'].items()]
        reuse.validate_modules({'modules': modules}, selection)
        modules[0]['path'] = str(self.root / 'sdk-stage0-run/runtime/lib' / reuse.TUPLE / 'libcangjie-runtime.dylib')
        self.rejected('module-path-identity', lambda: reuse.validate_modules({'modules': modules}, selection), 'module-path')

    def test_12_module_hash(self):
        selection = reuse.select(self.root)
        modules = [{'path': p, 'sha256': selection['expected_libraries'][n]} for n, p in selection['selected_libraries'].items()]
        modules[0]['sha256'] = '0' * 64
        self.rejected('module-hash-identity', lambda: reuse.validate_modules({'modules': modules}, selection), 'module-hash')


if __name__ == '__main__':
    start = time.monotonic()
    names = os.environ.get('SIGNAL_REUSE_TEST_NAMES')
    suite = unittest.TestSuite(ReuseTests(name) for name in names.split(',')) if names else unittest.defaultTestLoader.loadTestsFromTestCase(ReuseTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    summary = {'ran': result.testsRun, 'failures': [t.id() for t, _ in result.failures],
               'errors': [t.id() for t, _ in result.errors], 'wall': time.monotonic() - start,
               'rc': 0 if result.wasSuccessful() else 1}
    (BASE / 'result.json').write_text(json.dumps(summary, indent=2) + '\n')
    raise SystemExit(summary['rc'])
