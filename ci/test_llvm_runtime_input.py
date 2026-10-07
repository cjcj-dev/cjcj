#!/usr/bin/env python3
"""Real shell/Git input contract, with existing local Git transport mirrors.

Stops build_tuple at the first cmake invocation and observes its actual argv;
this does not configure/build LLVM or emulate a native GHA run. Work and mirror
paths must be supplied explicitly so fixture outputs stay in the caller's lane.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest

PIN = '9733dfc09d29eca27d19cc3937a149838b4e3322'
PRIVATE = '4909b2dec1af7f522133c6401e2ce960b0ef511d'
URL = 'https://github.com/cjcj-dev/cangjie-runtime.git'
INPUTS = ('CJCJ_LLVM_RUNTIME_MODE', 'CJCJ_LLVM_RUNTIME_URL',
          'CJCJ_LLVM_RUNTIME_SHA', 'RUNTIME_REF', 'RUNTIME_SRC_URL')

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--work', required=True, type=Path)
parser.add_argument('--runtime-mirror', required=True, type=Path)
parser.add_argument('--only', help='One test name, for representative admission')
parser.add_argument('--skip', help='Already executed representative test')
args = parser.parse_args()
REPO = Path(__file__).resolve().parents[1]
WORK = args.work.resolve()
WORK.mkdir(parents=True, exist_ok=False)


def git(*argv):
    return subprocess.check_output(['git', *map(str, argv)], text=True).strip()


# One small real repository supplies the other three input trees. Runtime is
# always an actual fixed product commit, never a rewritten fixture pin file.
source = WORK / 'other-source'
source.mkdir()
for name, body in {
    'llvm/include/llvm/Transforms/Scalar/ReflectionInfo.h':
        'enum EnumReflectionType {\n  ERT_NONE,\n};\n',
    'schema/ModuleFormat.fbs': 'table Fixture {}\n',
    'CMakeLists.txt': 'cmake_minimum_required(VERSION 3.16)\n',
}.items():
    path = source / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body)
git('init', source)
git('-C', source, 'add', '.')
git('-C', source, '-c', 'user.name=Zxilly', '-c',
    'user.email=zxilly@outlook.com', 'commit', '-m', 'test: local transport input')
OTHER_SHA = git('-C', source, 'rev-parse', 'HEAD')
base_env = dict(os.environ)
for name in INPUTS:
    base_env.pop(name, None)
base_env.update({
    'CJCJ_SRCBUILD_SOURCE_MIRRORS': f'{URL}=file://{args.runtime_mirror.resolve()}',
    'CJCJ_SRCBUILD_REQUIRE_MIRRORS': '1',
    # Other fixture inputs intentionally use direct file transports.
    'LLVM_URL': f'file://{source}', 'LLVM_SHA': OTHER_SHA,
    'CANGJIE_COMPILER_URL': f'file://{source}', 'CANGJIE_COMPILER_SHA': OTHER_SHA,
    'FLATBUFFERS_URL': f'file://{source}', 'FLATBUFFERS_SHA': OTHER_SHA,
    'TUPLE_PLATFORM': 'linux_x86_64', 'LLVM_TARGETS': 'X86',
    'LC_ALL': 'C',
})
# Retain mirror enforcement for runtime while mapping the other source too.
base_env['CJCJ_SRCBUILD_SOURCE_MIRRORS'] += f';file://{source}=file://{source}'
private_env = {'CJCJ_LLVM_RUNTIME_MODE': 'private',
               'CJCJ_LLVM_RUNTIME_URL': URL, 'CJCJ_LLVM_RUNTIME_SHA': PRIVATE}


class RuntimeInput(unittest.TestCase):
    def run_script(self, label, script, extra=None, argv=(), root=None):
        env = dict(base_env)
        env.update(extra or {})
        for key in list(env):
            if env[key] is None:
                del env[key]
        env['TUPLE_ROOT'] = str(root or WORK / label)
        env['GIT_TRACE'] = str(WORK / f'{label}.trace')
        command = (['npx', '--yes', 'zx@8'] if script.endswith('.mjs') else ['bash'])
        result = subprocess.run([*command, str(REPO / script), *map(str, argv)],
                                env=env, cwd=WORK, capture_output=True, text=True)
        (WORK / f'{label}.log').write_text(result.stdout + result.stderr)
        (WORK / f'{label}.rc').write_text(f'{result.returncode}\n')
        return result

    def target(self, name, actual, expected):
        print(f'ASSERT_REACHED name={name} actual={actual!r} expected={expected!r}', flush=True)
        self.assertEqual(actual, expected, name)
        print(f'ASSERT_PASS name={name}', flush=True)

    def tuple(self, label, inputs):
        return self.run_script(label, 'ci/platform_tuples/fetch_sources.sh', inputs)

    def test_default_pin(self):
        # Legacy environment values remain overwritten by the formal pin.
        result = self.tuple('default', {'RUNTIME_REF': PRIVATE, 'RUNTIME_SRC_URL': 'invalid'})
        self.target('default_fetch_rc', result.returncode, 0)
        actual = git('-C', WORK / 'default/paired-runtime', 'rev-parse', 'HEAD')
        self.target('default_formal_pin', actual, PIN)
        self.target('default_clean', git('-C', WORK / 'default/paired-runtime',
                                        'status', '--porcelain'), '')

    def test_private_selection(self):
        result = self.tuple('private', private_env)
        self.target('private_fetch_rc', result.returncode, 0)
        actual = git('-C', WORK / 'private/paired-runtime', 'rev-parse', 'HEAD')
        self.target('private_actual_head', actual, PRIVATE)
        self.target('private_clean', git('-C', WORK / 'private/paired-runtime',
                                        'status', '--porcelain'), '')

    def reject_before_fetch(self, label, inputs, message):
        result = self.tuple(label, inputs)
        trace = WORK / f'{label}.trace'
        text = trace.read_text() if trace.exists() else ''
        self.target(f'{label}_reject_rc', result.returncode, 1)
        self.target(f'{label}_reason', message in result.stdout + result.stderr, True)
        self.target(f'{label}_no_fetch', ' fetch ' in text, False)
        self.target(f'{label}_no_llvm_checkout', (WORK / label / 'llvm-project').exists(), False)

    def test_missing_url(self):
        self.reject_before_fetch('missing-url', {**private_env, 'CJCJ_LLVM_RUNTIME_URL': None}, 'approved cjcj-dev HTTPS URL')

    def test_missing_sha(self):
        self.reject_before_fetch('missing-sha', {**private_env, 'CJCJ_LLVM_RUNTIME_SHA': None}, '40-digit SHA')

    def test_empty_sha(self):
        self.reject_before_fetch('empty-sha', {**private_env, 'CJCJ_LLVM_RUNTIME_SHA': ''}, '40-digit SHA')

    def test_short_sha(self):
        self.reject_before_fetch('short-sha', {**private_env, 'CJCJ_LLVM_RUNTIME_SHA': PRIVATE[:12]}, '40-digit SHA')

    def test_invalid_sha(self):
        self.reject_before_fetch('invalid-sha', {**private_env, 'CJCJ_LLVM_RUNTIME_SHA': 'z' * 40}, '40-digit SHA')

    def test_unapproved_url(self):
        self.reject_before_fetch('official-url', {**private_env, 'CJCJ_LLVM_RUNTIME_URL': 'https://gitcode.com/Cangjie/cangjie_runtime.git'}, 'approved cjcj-dev HTTPS URL')

    def test_credential_url(self):
        self.reject_before_fetch('credential-url', {**private_env, 'CJCJ_LLVM_RUNTIME_URL': 'https://user:secret@github.com/cjcj-dev/cangjie-runtime.git'}, 'approved cjcj-dev HTTPS URL')

    def test_implicit_private(self):
        self.reject_before_fetch('implicit-private', {**private_env, 'CJCJ_LLVM_RUNTIME_MODE': None}, 'require CJCJ_LLVM_RUNTIME_MODE=private')

    def test_bad_mode(self):
        self.reject_before_fetch('bad-mode', {**private_env, 'CJCJ_LLVM_RUNTIME_MODE': 'release'}, 'must be unset or private')

    def test_mixed_ref(self):
        self.reject_before_fetch('mixed-ref', {**private_env, 'RUNTIME_REF': PIN}, 'do not mix private inputs')

    def test_mixed_url(self):
        self.reject_before_fetch('mixed-url', {**private_env, 'RUNTIME_SRC_URL': URL}, 'do not mix private inputs')

    def checkout_input(self, label, sha=PRIVATE):
        dest = WORK / label / 'paired-runtime'
        dest.parent.mkdir(parents=True)
        git('init', dest)
        git('-C', dest, 'fetch', '--depth=1', f'file://{args.runtime_mirror.resolve()}', sha)
        git('-C', dest, 'checkout', '--detach', 'FETCH_HEAD')
        return dest

    def test_dirty_before_fetch(self):
        dest = self.checkout_input('dirty-fetch')
        with (dest / 'runtime/src/Common/StackType.h').open('a') as out:
            out.write('\n// controlled tracked dirt\n')
        self.reject_before_fetch('dirty-fetch', private_env, 'checkout is dirty')

    def test_untracked_before_fetch(self):
        dest = self.checkout_input('untracked-fetch')
        (dest / 'untracked-input').write_text('controlled dirt')
        self.reject_before_fetch('untracked-fetch', private_env, 'checkout is dirty')

    def test_nonexistent_commit(self):
        result = self.tuple('missing-commit', {**private_env, 'CJCJ_LLVM_RUNTIME_SHA': '0' * 40})
        self.target('missing_commit_rejected', result.returncode != 0, True)
        self.target('missing_commit_no_fallback', (WORK / 'missing-commit/paired-runtime/.git/HEAD').read_text().startswith('ref:'), True)
        trace = (WORK / 'missing-commit.trace').read_text()
        self.target('missing_commit_formal_pin_not_fetched', PIN in trace, False)
        self.target('missing_commit_requested_fetch_observed', '0' * 40 in trace, True)

    def build_entry(self, label, root, extra=None):
        # Observation boundary only: real build_tuple sends its first configure
        # arguments here. Return a sentinel to prevent any LLVM build activity.
        bindir = WORK / f'{label}-bin'
        bindir.mkdir()
        capture = WORK / f'{label}.cmake.json'
        cmake = bindir / 'cmake'
        cmake.write_text('#!/usr/bin/env python3\nimport json,sys\n'
                         f'open({str(capture)!r}, "w").write(json.dumps(sys.argv[1:]))\n'
                         'sys.exit(86)\n')
        cmake.chmod(0o755)
        result = self.run_script(label, 'ci/platform_tuples/build_tuple.sh',
                                 {**private_env, **(extra or {}),
                                  'PATH': f'{bindir}:{base_env["PATH"]}'}, root=root)
        return result, capture

    def test_build_absolute_source(self):
        dest = self.checkout_input('build-source')
        result, capture = self.build_entry('build-source', dest.parent)
        self.target('build_first_cmake_boundary_rc', result.returncode, 86)
        command = json.loads(capture.read_text())
        runtime_args = [x for x in command if x.startswith('-DCANGJIE_RUNTIME_SOURCE_DIR=')]
        self.target('build_absolute_runtime_source', runtime_args,
                    [f'-DCANGJIE_RUNTIME_SOURCE_DIR={dest.resolve()}'])
        self.target('build_llvm_assertions_unchanged', '-DLLVM_ENABLE_ASSERTIONS=OFF' in command, True)

    def test_build_wrong_head(self):
        dest = self.checkout_input('build-wrong-head', PIN)
        result, capture = self.build_entry('build-wrong-head', dest.parent)
        self.target('build_wrong_head_rejected', result.returncode, 1)
        self.target('build_wrong_head_reason', 'HEAD differs from requested SHA' in result.stdout + result.stderr, True)
        self.target('build_wrong_head_no_cmake', capture.exists(), False)

    def test_build_dirty(self):
        dest = self.checkout_input('build-dirty')
        with (dest / 'runtime/src/Common/StackType.h').open('a') as out:
            out.write('\n// controlled dirt at consumer\n')
        result, capture = self.build_entry('build-dirty', dest.parent)
        self.target('build_dirty_rejected', result.returncode, 1)
        self.target('build_dirty_reason', 'checkout is dirty' in result.stdout + result.stderr, True)
        self.target('build_dirty_no_cmake', capture.exists(), False)

    def test_direct_fetch_validation(self):
        result = self.run_script('direct-invalid', 'ci/fetch-llvm-runtime.mjs',
                                 {**private_env, 'CJCJ_LLVM_RUNTIME_SHA': 'short'},
                                 argv=(WORK / 'direct-runtime',))
        self.target('direct_fetch_invalid_rejected', result.returncode, 1)
        self.target('direct_fetch_no_init', (WORK / 'direct-runtime').exists(), False)


names = unittest.defaultTestLoader.getTestCaseNames(RuntimeInput)
if args.only:
    names = [name for name in names if name == args.only]
if args.skip:
    names = [name for name in names if name != args.skip]
if not names:
    parser.error('no selected test')
result = unittest.TextTestRunner(verbosity=2).run(unittest.TestSuite(RuntimeInput(name) for name in names))
sys.exit(not result.wasSuccessful())
