#!/usr/bin/env python3
"""Exercise the real bootstrap preparation and runner with an actual LLVM DSO.

COLOUR_LLVM_SO supplies the reviewed library. The process fixture calls that
library's C API and records its loader maps; it is not a self-hosting compiler.
Keep an independent real stage1 compile receipt for compiler acceptance.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent
BOOTSTRAP = Path(os.environ.get('BOOTSTRAP_PRODUCT', ROOT / 'bootstrap.sh'))
RUNNER = Path(os.environ.get('STAGE1_RUNNER_PRODUCT', ROOT / 'stage1_host_runner.sh'))
LIB = Path(os.environ['COLOUR_LLVM_SO']).resolve()
HOST_LIB = Path(os.environ['HOST_LLVM_SO']).resolve()


def digest(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


class ColourLLVM(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='colour-llvm-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.host = self.root / 'sdk-stage0'
        self.target = self.root / 'sdk-stage1'
        self.run_sdk = self.root / 'sdk-stage0-run'
        self.platform = f'linux_{os.uname().machine}_cjnative'
        self.runtime = Path('runtime/lib') / self.platform
        for sdk in (self.host, self.target):
            for rel in (self.runtime, Path('third_party/llvm/lib'), Path('tools/bin'), Path('bin'), Path('third_party/llvm/bin')):
                (sdk / rel).mkdir(parents=True)
            for rel in ('bin/cjc', 'tools/bin/cjpm', 'third_party/llvm/bin/opt', 'third_party/llvm/bin/llc'):
                shutil.copyfile('/bin/true', sdk / rel)
                (sdk / rel).chmod(0o755)
            # These are identity fixtures, not loaded runtimes. The process is
            # Python; only libLLVM is actually loaded and called in this test.
            for name in ('libcangjie-runtime.so', 'libboundscheck.so'):
                (sdk / self.runtime / name).write_text(name)
        self.host_lib = self.host / 'third_party/llvm/lib/libLLVM-15.so'
        shutil.copyfile(HOST_LIB, self.host_lib)
        self.assertNotEqual(digest(LIB), digest(HOST_LIB), 'positive control requires different libraries')
        shutil.copyfile(LIB, self.target / 'third_party/llvm/lib/libLLVM-15.so')
        self.pin = digest(LIB)
        self.identities = self.root / 'identities.txt'
        self.identities.write_text('\n'.join(f'{n} {digest(p)}' for n, p in [
            ('libLLVM-15.so', self.host_lib),
            *[(n, self.host / self.runtime / n) for n in ('libcangjie-runtime.so', 'libboundscheck.so')]]) + '\n')
        self.compiler = self.root / 'process-fixture'
        self.compiler.write_text('''#!/usr/bin/python3
import ctypes, json
from pathlib import Path
llvm = ctypes.CDLL('libLLVM-15.so')
llvm.LLVMContextCreate.restype = ctypes.c_void_p
llvm.LLVMContextDispose.argtypes = [ctypes.c_void_p]
ctx = llvm.LLVMContextCreate()
assert ctx
llvm.LLVMContextDispose(ctx)
print(json.dumps({'context_created': bool(ctx), 'maps': Path('/proc/self/maps').read_text()}))
''')
        self.compiler.chmod(0o755)

    def prepare(self, so=LIB):
        result = subprocess.run(['bash', '-c', '''source "$1"
WORK=$2 COLOUR_LLVM_SO=$3 COLOUR_LLVM_SHA256=$4 HOST_LLVM_SHA256=$5 DRY=0
prepare_stage0_run_sdk
''', 'bash', str(BOOTSTRAP), str(self.root), str(so), self.pin, digest(self.host_lib)], capture_output=True, text=True)
        return result

    def install(self, pin=None, backend_runtime=None):
        return subprocess.run(['bash', str(RUNNER), str(self.target), str(self.host), str(self.host),
                               digest(self.host_lib), str(self.compiler), digest(self.compiler),
                               str(self.run_sdk), pin or self.pin] + ([str(backend_runtime)] if backend_runtime else []), env={**os.environ, 'STAGE1_HOST_IDENTITIES': str(self.identities)},
                              capture_output=True, text=True)

    def test_loaded_library_and_call(self):
        prep = self.prepare()
        self.assertEqual(prep.returncode, 0, prep.stdout + prep.stderr)
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        call = subprocess.run([str(self.target / 'bin/cjc')], capture_output=True, text=True)
        self.assertEqual(call.returncode, 0, call.stderr)
        data = json.loads(call.stdout)
        loaded = {line.split()[-1] for line in data['maps'].splitlines() if 'libLLVM' in line}
        expected = self.run_sdk / 'third_party/llvm/lib/libLLVM-15.so'
        self.assertEqual(loaded, {str(expected)}, data['maps'])
        self.assertEqual(digest(expected), self.pin)
        self.assertTrue(data['context_created'])
        self.assertFalse(expected.is_symlink())
        self.assertIn(str(self.host / 'third_party/llvm/lib'), (self.target / 'tools/bin/cjpm').read_text())
        print('ASSERT loaded-pin-and-context executed', flush=True)

    def test_official_tool_uses_host_library(self):
        # This child inherits the compiler's colour environment; the product
        # wrapper must replace it with the official host tool environment.
        tool = self.target / 'third_party/llvm/bin/llvm-objcopy'
        shutil.copyfile(self.compiler, tool)
        tool.chmod(0o755)
        prep = self.prepare()
        self.assertEqual(prep.returncode, 0, prep.stdout + prep.stderr)
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        call = subprocess.run([str(tool)], capture_output=True, text=True,
                              env={**os.environ, 'LD_LIBRARY_PATH': str(self.run_sdk / 'third_party/llvm/lib')})
        self.assertEqual(call.returncode, 0, call.stderr)
        data = json.loads(call.stdout)
        loaded = {line.split()[-1] for line in data['maps'].splitlines() if 'libLLVM' in line}
        self.assertEqual(loaded, {str(self.host_lib)}, data['maps'])
        self.assertTrue(data['context_created'])
        print('ASSERT official-tool-host-library executed', flush=True)

    def test_bootstrap_backend_runtime_is_separate_from_host_pair(self):
        backend_runtime = self.root / 'colour-runtime'
        backend_runtime.mkdir()
        for name in ('libcangjie-runtime.so', 'libboundscheck.so'):
            (backend_runtime / name).write_text('colour-' + name)
        tool = self.target / 'third_party/llvm/bin/llc'
        tool.write_text('#!/usr/bin/python3\nimport os, json\nprint(json.dumps(dict(os.environ)))\n')
        tool.chmod(0o755)
        prep = self.prepare()
        self.assertEqual(prep.returncode, 0, prep.stdout + prep.stderr)
        result = self.install(backend_runtime=backend_runtime)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        call = subprocess.run([str(tool)], capture_output=True, text=True)
        self.assertEqual(call.returncode, 0, call.stderr)
        environment = json.loads(call.stdout)
        self.assertEqual(environment['LD_LIBRARY_PATH'].split(':')[0], str(backend_runtime))
        self.assertEqual(environment['CANGJIE_HOME'], str(self.target))
        self.assertEqual((self.target / self.runtime / 'libcangjie-runtime.so').read_text(),
                         'libcangjie-runtime.so')
        print('ASSERT bootstrap-backend-runtime-separation executed', flush=True)

    def test_producer_rejects_wrong_library(self):
        result = self.prepare(self.host_lib)
        self.assertIn('BOOTSTRAP-FAIL [init] colour-llvm sha256 不匹配', result.stdout + result.stderr)
        self.assertNotEqual(result.returncode, 0)
        print('ASSERT producer-identity executed', flush=True)

    def test_consumer_rejects_wrong_library(self):
        prep = self.prepare()
        self.assertEqual(prep.returncode, 0, prep.stdout + prep.stderr)
        wrong = self.run_sdk / 'third_party/llvm/lib/libLLVM-15.so'
        shutil.copyfile(self.host_lib, wrong)
        result = self.install()
        self.assertIn(f'sha mismatch: {wrong} expected={self.pin}', result.stderr)
        self.assertNotEqual(result.returncode, 0)
        print('ASSERT consumer-identity executed', flush=True)


if __name__ == '__main__':
    unittest.main()
