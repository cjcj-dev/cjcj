import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';

// cjcj#73 invariant 3: every job that compiles C or C++ on GitHub Actions goes
// through sccache, with a cache key bound to the pin and platform, and closes
// with a report whose zero-compile check can turn the job red. The wiring is two
// composite actions; this file checks that every such job uses both, in order,
// and that no job compiles C++ without them.

const root = path.resolve(import.meta.dirname, '..', '..', '..');
const dir = path.join(root, '.github/workflows');
const uncommented = text => text.split('\n').map(line => line.replace(/(^|\s)#.*$/, '$1')).join('\n');

function jobs(text) {
  const body = uncommented(text).split('\njobs:\n')[1] || '';
  const parsed = new Map();
  let current;
  for (const line of body.split('\n')) {
    const header = line.match(/^ {2}([A-Za-z0-9_-]+):\s*$/);
    if (header) parsed.set(current = header[1], []);
    else if (current) parsed.get(current).push(line);
  }
  return new Map([...parsed].map(([name, lines]) => [name, lines.join('\n')]));
}

// The jobs that drive a C/C++ compiler, and the pin their cache key must carry.
// build-llvm-tools / platform-tuples: llc, opt, flatc, the shim object.
// build-llvm-dylib: shared LLVM; the caller selects the cache namespace.
// build-release-package: the coloured runtime (ci/build_patched_runtime.mjs).
// build-windows-runtime: the MinGW cross runtime, flatc, the std-ast object.
// srcbuild: support libraries, stage3 std FFI, stdx, tools, shim, Windows cross runtime.
// ci.yml / platform-matrix.yml: the patched runtime on a runtime-cache miss plus
// the shim objects, per runner (the runtime links the builder's glibc).
const CXX_JOBS = new Map([
  ['build-host-llvm.yml/host', {component: 'host-llvm', pin: /steps\.pin\.outputs\.sha/}],
  ['build-llvm-dylib.yml/dylib', {component: '${{ inputs.cache-component }}', pin: /steps\.pin\.outputs\.sha/}],
  ['build-llvm-tools.yml/build-tools', {component: 'llvm', pin: /steps\.llvm-pin\.outputs\.sha/}],
  ['platform-tuples.yml/build-tuple', {component: 'llvm-tuple', pin: /steps\.llvm-pin\.outputs\.sha/}],
  ['build-release-package.yml/package', {component: 'runtime', pin: /env\.RUNTIME_REF/}],
  ['build-windows-runtime.yml/build-runtime', {component: 'windows-runtime', pin: /env\.RUNTIME_REF/}],
  ['srcbuild.yml/srcbuild', {component: 'srcbuild', pin: /env\.RUNTIME_REF/}],
  ['ci.yml/build', {component: 'runtime', pin: /env\.RUNTIME_REF/}],
  ['platform-matrix.yml/colour-runtime', {component: 'runtime', pin: /env\.RUNTIME_REF/}],
  ['platform-matrix.yml/platform', {component: 'runtime', pin: /env\.RUNTIME_REF/}],
]);

// What a C/C++ compile looks like in a run: step. Wide on purpose: a match here
// only means "this job must be in CXX_JOBS", and the assertion below says which
// job is new and unwired. Narrow is the dangerous direction -- a job that drives
// a compiler this list does not name is invisible, and then CXX_JOBS is a list
// checked against itself. So the build drivers (cmake, ninja, make, build.py,
// the repository's own build scripts) sit next to the compiler front ends
// themselves (cc, gcc, g++, clang, clang++), and anything that merely installs
// or configures one is excluded below rather than left out here.
// `cc` needs the extra guard: a bare word boundary also matches the end of a
// filename like src/foo.cc, and a file being copied is not a compile.
const COMPILES = /(\bcmake\b|\bninja\b|\bmake\b|build\.py build|(?<![.\w-])cc\b|\bgcc\b|\bg\+\+|clang\+\+|\bclang\b|build_patched_runtime\.mjs|build_runtime\.mjs|build_tuple\.sh|install-static-libs|gha_run\.sh|build-stage3\.mjs|build-windows-final-std\.mjs|build_shim\.mjs|build_windows_std_ast\.mjs)/;
// Only the package managers. Every other exclusion tried here -- the MSYS2
// package list, --gcc-toolchain, CMAKE_C*_COMPILER=, shellcheck/actionlint --
// was measured and carried nothing: dropping all six leaves the suite at the
// same 13 failures with no false positive. They only open doors, and a review
// wrote four lines that compile C++ and would have been swallowed by them
// (`cmake -DCMAKE_CXX_COMPILER=clang++ --build build`,
// `clang++ --gcc-toolchain=/usr -c foo.cpp`,
// `/mingw64/bin/mingw-w64-clang++ -c foo.cpp`,
// `shellcheck x.sh && gcc -c probe.c`). An exclusion belongs here only once a
// real false positive forces it.
const INSTALLS = /\b(apt-get|brew|pacman|pip3?|choco)\b/;
const compilesIn = step => /^\s*run:/m.test(step)
  && step.split('\n').some(line => COMPILES.test(line) && !INSTALLS.test(line));

async function workflows() {
  const loaded = new Map();
  for (const name of (await fs.readdir(dir)).filter(entry => entry.endsWith('.yml'))) {
    loaded.set(name, await fs.readFile(path.join(dir, name), 'utf8'));
  }
  return loaded;
}

const stepBlocks = job => job.split(/\n {6}- /).slice(1);

test('every C/C++ compile job starts sccache before compiling and reports after, with the pin in the key', async () => {
  const all = await workflows();
  for (const [id, {component, pin}] of CXX_JOBS) {
    const [file, jobName] = id.split('/');
    const job = jobs(all.get(file) ?? '').get(jobName);
    assert.ok(job, `${id}: job not found`);
    const steps = stepBlocks(job);
    const start = steps.findIndex(step => /uses:\s*\.\/\.github\/actions\/sccache\s*$/m.test(step));
    const report = steps.findIndex(step => /uses:\s*\.\/\.github\/actions\/sccache-report\s*$/m.test(step));
    const firstCompile = steps.findIndex(compilesIn);
    assert.ok(start >= 0, `${id}: no ./.github/actions/sccache step`);
    assert.ok(report >= 0, `${id}: no ./.github/actions/sccache-report step`);
    assert.ok(firstCompile >= 0, `${id}: no compile step found; CXX_JOBS is stale`);
    assert.ok(start < firstCompile, `${id}: sccache starts at step ${start}, after the first compile at step ${firstCompile}`);
    assert.ok(report > firstCompile, `${id}: sccache reports at step ${report}, before the last compile`);
    for (const index of [start, report]) {
      assert.equal(steps[index].match(/^\s*component:\s*(.+?)\s*$/m)?.[1], component,
        `${id}: step ${index} names component ${component}`);
    }
    assert.match(steps[start], pin, `${id}: cache key does not carry the pin`);
    assert.match(steps[report], /^\s*if: always\(\)/m, `${id}: the report must run when the build failed too`);
    // Enforced on green jobs only: a job that already failed before its first
    // compile must not gain a second, misleading error from the report.
    assert.match(steps[report], /^\s*require-compiles: \$\{\{ job\.status == 'success' \}\}\s*$/m,
      `${id}: the report must require compiles exactly when the job is otherwise green`);
    // A launcher only works for a job whose compile steps see it: the start
    // step must not be guarded by a condition the compile steps do not share.
    const guard = steps[start].match(/^\s*if:\s*(.+)$/m)?.[1];
    if (guard) {
      assert.match(steps[firstCompile], /^\s*if:/m, `${id}: sccache start is conditional (${guard}) but the first compile is not`);
    }
  }
});

test('no workflow job compiles C or C++ outside the sccache-wired set', async () => {
  const all = await workflows();
  const unwired = [];
  for (const [file, text] of all) {
    for (const [jobName, job] of jobs(text)) {
      const compiles = stepBlocks(job).some(compilesIn);
      if (!compiles) continue;
      if (!CXX_JOBS.has(`${file}/${jobName}`)) unwired.push(`${file}/${jobName}`);
    }
  }
  assert.deepEqual(unwired, [], 'jobs that compile without sccache; add them to CXX_JOBS and wire both actions');
});

test('the composite actions export both CMake launcher variables, bind key to component/platform/pin, and gate on zero compiles', async () => {
  const start = await fs.readFile(path.join(root, '.github/actions/sccache/action.yml'), 'utf8');
  for (const contract of [
    'CMAKE_C_COMPILER_LAUNCHER=$SCCACHE_PATH',
    'CMAKE_CXX_COMPILER_LAUNCHER=$SCCACHE_PATH',
    'SCCACHE_GHA_ENABLED=false',
    'key: sccache-${{ inputs.component }}-${{ inputs.platform }}-${{ inputs.pin }}-${{ github.run_id }}-${{ github.run_attempt }}',
    'sccache-${{ inputs.component }}-${{ inputs.platform }}-${{ inputs.pin }}-',
    'uses: mozilla-actions/sccache-action@',
  ]) assert.ok(start.includes(contract), contract);
  assert.match(start, /^\s*version: \$\{\{ inputs\.sccache-version \}\}/m, 'the sccache release is pinned, not latest');
  const report = await fs.readFile(path.join(root, '.github/actions/sccache-report/action.yml'), 'utf8');
  assert.ok(report.includes('ci/sccache/report.mjs'));
  assert.ok(report.includes('--require-compiles'));
  assert.ok(report.includes('--summary "$GITHUB_STEP_SUMMARY"'));
  assert.match(report, /uses: actions\/cache\/save@/);
  assert.match(report, /steps\.stats\.outputs\.save == 'true'/, 'the cache is saved only when sccache wrote something');
  // A job whose sccache never started is red when it would otherwise be green,
  // and only a warning on a job that already failed.
  assert.match(report, /::error::SCCACHE_PATH is unset/);
  assert.match(report, /::warning::SCCACHE_PATH is unset/);
  // The diagnostics upload has to outlive a failing statistics step, which is
  // exactly when its stats.json and error log are worth having.
  const upload = report.slice(report.indexOf('- name: Upload sccache diagnostics'));
  assert.match(upload.slice(0, upload.indexOf('uses:')), /^\s*if: always\(\)\s*$/m,
    'the sccache diagnostics upload must run even after the statistics step failed');
});

test('build/cli.mjs keeps a launcher the workflow already exported', async () => {
  const sccache = await fs.readFile(path.join(root, 'build/toolchain/sccache.mjs'), 'utf8');
  assert.match(sccache, /if \(process\.env\[variable\]\) \{[\s\S]*?continue;/, 'maybeEnable must leave a preset CMAKE_*_COMPILER_LAUNCHER alone');
  const shim = await fs.readFile(path.join(root, 'runtime_shim/build_shim.mjs'), 'utf8');
  assert.match(shim, /CMAKE_CXX_COMPILER_LAUNCHER/, 'the shim compile honours the launcher');
  const staticLibs = await fs.readFile(path.join(root, 'build/toolchain/static-libs.mjs'), 'utf8');
  assert.match(staticLibs, /CMAKE_C_COMPILER_LAUNCHER/, 'autotools support libraries carry the launcher in CC');
  const tuple = await fs.readFile(path.join(root, 'ci/platform_tuples/build_tuple.sh'), 'utf8');
  assert.match(tuple, /\$\{SCCACHE_PATH:\+"\$SCCACHE_PATH"\} clang\+\+/, 'the tuple shim compile goes through sccache');
});
