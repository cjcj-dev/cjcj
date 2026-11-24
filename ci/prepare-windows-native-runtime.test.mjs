import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {WINDOWS_RUNTIME_CC, defaultWindowsCandidates} from '../build/sdk/producers/platform_matrix/pick_cc.mjs';
import {resolveSccachePath} from './sccache/resolve-path.mjs';

// prepare.yml reaches build_runtime.mjs on all five hosts. On windows-x64 that
// path needs the windows-x86_64 runtime target (native_runtime.mjs
// configureNativeRuntime), an exact host version, the actual MSYS2 bash and the
// actual MINGW64 clang that msys2/setup-msys2 installed under RUNNER_TEMP.
const repo = path.resolve(import.meta.dirname, '..');
const read = file => fs.readFileSync(path.join(repo, file), 'utf8');
const PREPARE = '.github/workflows/prepare.yml';
const TOOLS = '.github/actions/native-windows-tools/action.yml';
const BUILD_STEP = 'Build and install the exact native runtime and bounds';
const DIAGNOSTIC_STEP = 'Show gc_unit gate diagnostics after a Linux runtime failure';
const SCCACHE = '.github/actions/sccache/action.yml';
const SCCACHE_CONFIGURE = 'Configure sccache disk cache and CMake launcher';
const SCCACHE_STATS = 'sccache statistics';

// A step is its `- name:` line and every following line indented deeper.
function steps(text) {
  const lines = text.split('\n'), found = [];
  for (let i = 0; i < lines.length; i++) {
    const match = /^(\s*)- name: (.+)$/.exec(lines[i]);
    if (!match) continue;
    const indent = match[1].length;
    let end = i + 1;
    while (end < lines.length && !(lines[end].trim() && lines[end].search(/\S/) <= indent)) end++;
    found.push({name: match[2].trim(), lines: lines.slice(i, end)});
  }
  return found;
}
function step(file, name) {
  const found = steps(read(file)).filter(entry => entry.name === name);
  assert.equal(found.length, 1, `${file}: exactly one step named ${name}`);
  return found[0];
}
function runBlock({lines}) {
  const start = lines.findIndex(line => /^\s*run: \|\s*$/.test(line));
  assert.notEqual(start, -1, 'step has a literal run block');
  const body = lines.slice(start + 1);
  const indent = Math.min(...body.filter(line => line.trim()).map(line => line.search(/\S/)));
  return body.map(line => line.slice(indent)).join('\n').trimEnd() + '\n';
}
const field = ({lines}, key) => lines.map(line => new RegExp(`^\\s*${key}: (.*)$`).exec(line)?.[1]).find(Boolean);
// GitHub runs `shell: bash` as bash --noprofile --norc -eo pipefail {0}.
const bash = (script, options) => spawnSync('bash', ['--noprofile', '--norc', '-eo', 'pipefail', '-c', script],
  {encoding: 'utf8', ...options});

test('prepare runtime step selects windows-x86_64 only on the Windows runner', () => {
  const value = field(step(PREPARE, BUILD_STEP), 'RUNTIME_TARGET');
  const match = /^\$\{\{ runner\.os == '(\w+)' && '([\w-]+)' \|\| '([\w-]+)' \}\}$/.exec(value || '');
  assert.ok(match, `RUNTIME_TARGET is a runner.os selection: ${value}`);
  const evaluate = runnerOs => runnerOs === match[1] ? match[2] : match[3];
  assert.equal(evaluate('Windows'), 'windows-x86_64');
  for (const runnerOs of ['Linux', 'macOS']) assert.equal(evaluate(runnerOs), 'native', runnerOs);
  // The consumer contract the value must satisfy.
  assert.match(read('build/sdk/producers/platform_matrix/native_runtime.mjs'),
    /windows \? runtimeTarget === 'windows-x86_64'\s*: runtimeTarget === 'native'/);
});

test('prepare runtime step resolves the host version step-locally before build_runtime', () => {
  const build = step(PREPARE, BUILD_STEP), script = runBlock(build);
  const resolve = 'CJCJ_NATIVE_HOST_VERSION=$(node build/sdk/producers/release/prepare_native_inputs.mjs host-version --target "${{ matrix.target }}")';
  const lines = script.split('\n');
  const at = lines.indexOf(resolve), exported = lines.indexOf('export CJCJ_NATIVE_HOST_VERSION');
  const entry = lines.findIndex(line => line.includes('platform_matrix/build_runtime.mjs'));
  assert.ok(at >= 0 && exported > at && entry > exported, script);
  const code = build.lines.filter(line => !/^\s*#/.test(line)).join('\n');
  assert.doesNotMatch(code, /GITHUB_ENV/, 'later steps keep their own prepare_native_inputs contract');
  // Execute the exact resolution lines for the Windows matrix entry.
  const snippet = [lines[at], lines[exported], 'printf "%s" "$CJCJ_NATIVE_HOST_VERSION"'].join('\n')
    .replaceAll('${{ matrix.target }}', 'windows-x64');
  const clean = {...process.env};
  for (const key of ['CJCJ_NATIVE_HOST_VERSION', 'CJCJ_NATIVE_LLVM_REF', 'CJCJ_NATIVE_RUNTIME_REF', 'CJCJ_NATIVE_PAIR_SELECTION']) delete clean[key];
  const pinned = bash(snippet, {cwd: repo, env: {...clean, CJCJ_NATIVE_PAIR_SELECTION: 'pinned'}});
  assert.equal(pinned.status, 0, pinned.stderr);
  // native_runtime.mjs NATIVE_RUNTIME_HOST_VERSION_REQUIRED accepts exactly this shape.
  assert.match(pinned.stdout, /^\d+\.\d+\.\d+-alpha\.\d+$/);
  const explicit = bash(snippet, {cwd: repo, env: {...clean, CJCJ_NATIVE_PAIR_SELECTION: 'explicit',
    CJCJ_NATIVE_LLVM_REF: '0123456789abcdef0123456789abcdef01234567'}});
  assert.notEqual(explicit.status, 0);
  assert.match(explicit.stderr, /NATIVE_RUNTIME_EXPLICIT_HOST_REQUIRED/);
  assert.equal(explicit.stdout, '', 'the build entry is never reached with an empty host');
});

test('Linux runtime failure prints the gc_unit gate verdict lines and never fails', () => {
  const all = steps(read(PREPARE)).map(entry => entry.name);
  assert.equal(all[all.indexOf(BUILD_STEP) + 1], DIAGNOSTIC_STEP, 'diagnostics follow the build step');
  const diagnostic = step(PREPARE, DIAGNOSTIC_STEP);
  assert.equal(field(diagnostic, 'if'), "failure() && runner.os == 'Linux'");
  const script = runBlock(diagnostic);
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-gc-unit-diag-'));
  try {
    const absent = bash(script, {cwd: work});
    assert.equal(absent.status, 0, absent.stderr);
    assert.match(absent.stdout, /GC_UNIT_DIAGNOSTICS_ABSENT/);
    const run = path.join(work, 'runtime-source/runtime/tests/gc_unit/build_standalone/gate-runs/run-1');
    fs.mkdirSync(run, {recursive: true});
    const filler = Array.from({length: 30}, (_, i) => `suite line ${i}`).join('\n');
    fs.writeFileSync(path.join(run, 'gate_run.log'), `${filler}\nGC_UNIT_OTHER_VM_2_RC=134\nGATE_RUN_TAIL_MARK\n`);
    fs.writeFileSync(path.join(run, 'other_vm_exit.log'), 'OTHER_VM_EXIT_TAIL_MARK\n');
    fs.writeFileSync(path.join(run, 'teardown-records.log'), 'TEARDOWN_RECORDS_REJECT holder=7\n');
    const present = bash(script, {cwd: work});
    assert.equal(present.status, 0, present.stderr);
    for (const mark of ['GC_UNIT_OTHER_VM_2_RC=134', 'TEARDOWN_RECORDS_REJECT holder=7', 'GATE_RUN_TAIL_MARK',
      'OTHER_VM_EXIT_TAIL_MARK', '::group::', 'gate_run.log', 'other_vm_exit.log', 'teardown-records.log'])
      assert.ok(present.stdout.includes(mark), `${mark}\n${present.stdout}`);
  } finally {
    fs.rmSync(work, {recursive: true, force: true});
  }
});

test('native-windows-tools exports the actual MSYS2 bash that build_runtime enters', () => {
  const tools = step(TOOLS, 'Install supported CMake and expose the actual MinGW tools');
  assert.equal(field(tools, 'shell'), 'msys2 {0}');
  const lines = runBlock(tools).split('\n');
  const check = lines.indexOf('test -x /usr/bin/bash.exe');
  const exported = lines.indexOf('echo "MSYS2_BASH=$(cygpath -w /usr/bin/bash.exe)" >> "$GITHUB_ENV"');
  assert.ok(check >= 0 && exported > check, lines.join('\n'));
  assert.match(read('build/sdk/producers/platform_matrix/build_runtime.mjs'), /const msysBash = process\.env\.MSYS2_BASH \|\|/);
});

test('default Windows compiler candidates probe CJCJ_NATIVE_LLVM_BIN right after CC', () => {
  const bin = 'D:\\a\\_temp\\msys64\\mingw64\\bin', actual = 'D:\\a\\_temp\\msys64\\mingw64\\bin\\clang.exe';
  const legacy = defaultWindowsCandidates({}, path.win32.join);
  assert.ok(!legacy.includes(null) && legacy[0] === 'C:\\msys64\\mingw64\\bin\\clang.exe', legacy.join('\n'));
  const exported = defaultWindowsCandidates({CJCJ_NATIVE_LLVM_BIN: bin}, path.win32.join);
  assert.deepEqual(exported, [actual, ...legacy]);
  assert.match(exported[0], WINDOWS_RUNTIME_CC);
  assert.deepEqual(defaultWindowsCandidates({CC: 'C:\\cc\\clang.exe', CJCJ_NATIVE_LLVM_BIN: bin}, path.win32.join).slice(0, 2),
    ['C:\\cc\\clang.exe', actual]);
  // WINDOWS_RUNTIME_CC is the same pattern build_runtime.mjs applies to the pick
  // (kept inline there: windows-runtime-shell.integration replaces pick_cc.mjs).
  const consumer = /if \(!(\/.+\/i)\.test\(windowsCC\)\)/.exec(read('build/sdk/producers/platform_matrix/build_runtime.mjs'))?.[1];
  assert.equal(consumer, String(WINDOWS_RUNTIME_CC));
  // Red cut: the old last resort cannot satisfy the runtime's MINGW64 requirement.
  assert.doesNotMatch(legacy.at(-1), WINDOWS_RUNTIME_CC);
});

// sccache-action@v0.0.11 exported SCCACHE_PATH=<toolcache>\x64/sccache on
// windows-x64 while the file is sccache.exe; native_runtime.mjs then failed
// NATIVE_RUNTIME_SCCACHE_MISSING (run 45376721209). On Linux `test -f` has no
// MSYS .exe emulation, so a directory holding only sccache.exe is exactly what
// Node's Win32 fs sees on the runner.
const parseEnvFile = file => fs.existsSync(file) ? fs.readFileSync(file, 'utf8').split('\n').filter(Boolean)
  .map(line => [line.slice(0, line.indexOf('=')), line.slice(line.indexOf('=') + 1)]) : [];
function configureSccache(work, sccachePath) {
  const githubEnv = path.join(work, 'github-env'), runnerTemp = path.join(work, 'runner-temp');
  fs.mkdirSync(runnerTemp, {recursive: true});
  const result = bash(runBlock(step(SCCACHE, SCCACHE_CONFIGURE)), {cwd: work, env: {...process.env,
    SCCACHE_PATH: sccachePath, GITHUB_ENV: githubEnv, RUNNER_TEMP: runnerTemp,
    GITHUB_ACTION_PATH: path.join(repo, '.github/actions/sccache'),
    COMPONENT: 'native-runtime', PLATFORM: 'windows_x86_64', PIN: '0123abcd', CACHE_SIZE: '2G'}});
  return {result, entries: parseEnvFile(githubEnv), runnerTemp};
}
const exported = (entries, key) => entries.filter(([name]) => name === key).map(([, value]) => value);

test('sccache start resolves an .exe-less SCCACHE_PATH and exports it with both CMake launchers', () => {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'sccache-exe-'));
  try {
    const bin = path.join(work, 'hostedtoolcache', 'x64');
    fs.mkdirSync(bin, {recursive: true});
    fs.writeFileSync(path.join(bin, 'sccache.exe'), '#!/bin/sh\n', {mode: 0o755});
    const {result, entries} = configureSccache(work, path.join(bin, 'sccache'));
    assert.equal(result.status, 0, result.stdout + result.stderr);
    const executable = path.join(bin, 'sccache.exe');
    for (const key of ['SCCACHE_PATH', 'CMAKE_C_COMPILER_LAUNCHER', 'CMAKE_CXX_COMPILER_LAUNCHER'])
      assert.deepEqual(exported(entries, key), [executable], `${key} in GITHUB_ENV`);
    // The consumer the Windows run failed at (native_runtime.mjs configureNativeRuntime).
    assert.ok(path.isAbsolute(executable) && fs.existsSync(executable));
    // An exact path is kept as it is.
    const exact = configureSccache(work, executable);
    assert.equal(exact.result.status, 0, exact.result.stdout + exact.result.stderr);
    assert.deepEqual(exported(exact.entries, 'SCCACHE_PATH').at(-1), executable);
  } finally {
    fs.rmSync(work, {recursive: true, force: true});
  }
});

test('sccache start fails loudly when neither SCCACHE_PATH nor SCCACHE_PATH.exe exists', () => {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'sccache-missing-'));
  try {
    const {result, entries} = configureSccache(work, path.join(work, 'x64', 'sccache'));
    assert.notEqual(result.status, 0);
    assert.match(result.stdout, /^::error::SCCACHE_PATH_MISSING: /m);
    assert.match(result.stderr, /SCCACHE_PATH_MISSING: neither /);
    assert.deepEqual(entries, [], 'nothing reaches GITHUB_ENV for a missing binary');
  } finally {
    fs.rmSync(work, {recursive: true, force: true});
  }
});

test('the Windows SCCACHE_PATH is spelled with .exe and forward slashes for Node, cygpath, CMake and bash', () => {
  const raw = 'C:\\hostedtoolcache\\windows\\sccache\\0.18.0\\x64/sccache';
  const resolved = resolveSccachePath(raw, {platform: 'win32', exists: candidate => candidate === raw + '.exe'});
  assert.equal(resolved, 'C:/hostedtoolcache/windows/sccache/0.18.0/x64/sccache.exe');
  assert.ok(path.win32.isAbsolute(resolved));
  assert.equal(resolveSccachePath(raw + '.exe', {platform: 'win32', exists: candidate => candidate === raw + '.exe'}), resolved);
  assert.throws(() => resolveSccachePath(raw, {platform: 'win32', exists: () => false}), /SCCACHE_PATH_MISSING/);
  assert.throws(() => resolveSccachePath('', {platform: 'win32', exists: () => true}), /SCCACHE_PATH_MISSING/);
});

test('sccache report mode runs the SCCACHE_PATH that start mode exported', () => {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'sccache-report-'));
  try {
    const bin = path.join(work, 'x64'), calls = path.join(work, 'calls');
    fs.mkdirSync(bin, {recursive: true});
    const fixture = path.join(repo, 'ci/sccache/fixtures-stats-v0.18.0.json');
    fs.writeFileSync(path.join(bin, 'sccache.exe'), `#!/bin/sh\necho "$0 $*" >> '${calls}'\n` +
      `case "$*" in *--stats-format=json*) cat '${fixture}';; esac\n`, {mode: 0o755});
    const start = configureSccache(work, path.join(bin, 'sccache'));
    assert.equal(start.result.status, 0, start.result.stdout + start.result.stderr);
    // Report mode reads SCCACHE_PATH from GITHUB_ENV only: no step env overrides it.
    for (const name of [SCCACHE_STATS, 'Start sccache server on the restored cache'])
      assert.equal(field(step(SCCACHE, name), 'SCCACHE_PATH'), undefined, name);
    const env = {...process.env, ...Object.fromEntries(start.entries), RUNNER_TEMP: start.runnerTemp,
      GITHUB_ACTION_PATH: path.join(repo, '.github/actions/sccache'), GITHUB_STEP_SUMMARY: path.join(work, 'summary'),
      GITHUB_OUTPUT: path.join(work, 'output'), COMPONENT: 'native-runtime', PLATFORM: 'windows_x86_64', REQUIRE_COMPILES: 'false'};
    const report = bash(runBlock(step(SCCACHE, SCCACHE_STATS)), {cwd: work, env});
    assert.equal(report.status, 0, report.stdout + report.stderr);
    assert.doesNotMatch(report.stdout, /SCCACHE_PATH is unset/);
    const invoked = fs.readFileSync(calls, 'utf8').trim().split('\n').map(line => line.split(' ')[0]);
    assert.deepEqual([...new Set(invoked)], [path.join(bin, 'sccache.exe')]);
  } finally {
    fs.rmSync(work, {recursive: true, force: true});
  }
});
