import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {WINDOWS_RUNTIME_CC, defaultWindowsCandidates} from '../build/sdk/producers/platform_matrix/pick_cc.mjs';
import {resolveSccachePath} from './sccache/resolve-path.mjs';
import {windowsRuntimeGitGuard} from '../build/sdk/producers/platform_matrix/windows_runtime_git.mjs';

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

// Run 45385716455 (windows-x64): CMake's first link failed in ld.lld, which could
// not open libclang_rt.builtins.a. MSYS2 clang 23.1.5 depends on neither
// compiler-rt nor libc++/libunwind, while the runtime CMakeLists.txt that build.py
// configures builds with --rtlib=compiler-rt -stdlib=libc++ and
// windows_runtime_toolchain.cmake selects LLD.
const MINGW_TOOLS_STEP = 'Install supported CMake and expose the actual MinGW tools';
function msys2Install() {
  const lines = read(TOOLS).split('\n');
  const at = lines.findIndex(line => /^\s+install: >-\s*$/.test(line));
  assert.notEqual(at, -1, `${TOOLS}: setup-msys2 has a folded install list`);
  const indent = lines[at].search(/\S/), packages = [];
  for (let i = at + 1; i < lines.length && lines[i].trim() && lines[i].search(/\S/) > indent; i++)
    packages.push(...lines[i].trim().split(/\s+/));
  return packages;
}

test('native-windows-tools installs the MINGW64 compiler-rt, libc++, libunwind and LLD the runtime links with', () => {
  const packages = msys2Install();
  const mingw = ['clang', 'gcc', 'ninja', 'llvm', 'openssl', 'binutils', 'compiler-rt', 'libc++', 'libunwind', 'lld', 'llvm-tools'];
  for (const name of ['tar', 'patch', 'make', 'file', 'gzip', 'unzip', ...mingw.map(name => `mingw-w64-x86_64-${name}`)])
    assert.ok(packages.includes(name), `${name} in setup-msys2 install: ${packages.join(' ')}`);
  assert.equal(new Set(packages).size, packages.length, 'no package is listed twice');
  // MSYS2 git would be first on GITHUB_PATH and mark the Git for Windows checkouts dirty.
  assert.ok(!packages.includes('git') && !packages.some(name => /(^|-)git$/.test(name)), packages.join(' '));
  // The consumer that selects the linker these packages provide.
  assert.match(read('build/sdk/producers/platform_matrix/windows_runtime_toolchain.cmake'), /^set\(CMAKE_LINKER_TYPE LLD\)$/m);
});

// The existence checks between llvm-readobj and the MSYS2_BASH export, run against
// a fake MINGW64 tree. The fake clang answers -print-libgcc-file-name like the
// driver: the lib/windows archive MSYS2 compiler-rt installs, else the per-target name.
function mingwToolChecks() {
  const lines = runBlock(step(TOOLS, MINGW_TOOLS_STEP)).split('\n');
  const start = lines.indexOf('test -x /mingw64/bin/llvm-readobj.exe');
  const end = lines.findIndex(line => line.includes('MINGW64_COMPILER_RT_MISSING'));
  const exported = lines.findIndex(line => line.includes('MSYS2_BASH='));
  assert.ok(start >= 0 && end > start && exported > end, lines.join('\n'));
  return lines.slice(start, end + 1).join('\n');
}
const MINGW_TOOL_FILES = ['bin/llvm-readobj.exe', 'bin/ld.lld.exe', 'bin/clang++.exe', 'lib/libc++.a', 'lib/libunwind.a',
  'lib/clang/23/lib/windows/libclang_rt.builtins-x86_64.a'];

test('native-windows-tools stops before CMake when any MINGW64 linker input is missing', () => {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'mingw64-tools-'));
  try {
    const root = path.join(work, 'mingw64'), stub = path.join(work, 'stub');
    fs.mkdirSync(stub);
    // cygpath -u leaves an already-POSIX path unchanged.
    fs.writeFileSync(path.join(stub, 'cygpath'), '#!/bin/sh\n[ "$1" = -u ] && printf "%s\\n" "$2"\n', {mode: 0o755});
    const script = mingwToolChecks().replaceAll('/mingw64/', `${root}/`);
    const builtins = path.join(root, MINGW_TOOL_FILES.at(-1));
    const perTarget = path.join(root, 'lib/clang/23/lib/x86_64-w64-windows-gnu/libclang_rt.builtins.a');
    const populate = missing => {
      fs.rmSync(root, {recursive: true, force: true});
      for (const file of ['bin/clang.exe', ...MINGW_TOOL_FILES.filter(file => file !== missing)]) {
        fs.mkdirSync(path.dirname(path.join(root, file)), {recursive: true});
        fs.writeFileSync(path.join(root, file), '', {mode: 0o755});
      }
      fs.writeFileSync(path.join(root, 'bin/clang.exe'),
        `#!/bin/sh\nif [ -f '${builtins}' ]; then echo '${builtins}'; else echo '${perTarget}'; fi\n`);
      return bash(script, {env: {...process.env, PATH: `${stub}:${process.env.PATH}`}});
    };
    const complete = populate(null);
    assert.equal(complete.status, 0, complete.stdout + complete.stderr);
    for (const missing of MINGW_TOOL_FILES)
      assert.notEqual(populate(missing).status, 0, `${missing} absent must stop the step`);
    // Without compiler-rt the step names the archive run 45385716455's link could not open.
    assert.match(populate(MINGW_TOOL_FILES.at(-1)).stderr,
      /MINGW64_COMPILER_RT_MISSING .*\/lib\/clang\/23\/lib\/x86_64-w64-windows-gnu\/libclang_rt\.builtins\.a/);
  } finally {
    fs.rmSync(work, {recursive: true, force: true});
  }
});

// Run 45401980497: MSYS2 git saw the Git for Windows runtime checkout as dirty and
// the provenance stamp became <sha>-dirty. The guard runs with fake gits on PATH.
test('Windows runtime build refuses a non-Git-for-Windows git and prints the porcelain status first', t => {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'runtime-git-guard-'));
  t.after(() => fs.rmSync(work, {recursive: true, force: true}));
  const run = version => {
    const bin = path.join(work, version.replace(/\W/g, '_'));
    fs.mkdirSync(bin, {recursive: true});
    fs.writeFileSync(path.join(bin, 'git'), `#!/bin/sh\nif [ "$1" = --version ]; then echo "${version}"; else echo "git $*"; fi\n`, {mode: 0o755});
    fs.writeFileSync(path.join(bin, 'cygpath'), '#!/bin/sh\n[ "$1" = -m ] && printf "%s\\n" "$2" | sed -E "s|^/([a-z])/|\\1:/|"\n', {mode: 0o755});
    const script = ['set -euo pipefail', 'runtime_source=/d/a/cjcj/cjcj/runtime-source', ...windowsRuntimeGitGuard('runtime_source'), 'echo REACHED_BUILD'].join('\n');
    return spawnSync('bash', ['-c', script], {encoding: 'utf8', env: {...process.env, PATH: `${bin}:/usr/bin:/bin`}});
  };
  const windows = run('git version 2.56.1.windows.1');
  assert.equal(windows.status, 0, windows.stderr);
  assert.match(windows.stdout, /RUNTIME_SOURCE_STATUS_BEGIN\ngit -C d:\/a\/cjcj\/cjcj\/runtime-source status --porcelain\nRUNTIME_SOURCE_STATUS_END\nREACHED_BUILD/);
  const msys = run('git version 2.56.1');
  assert.equal(msys.status, 5);
  assert.match(msys.stderr, /FATAL: runtime provenance needs Git for Windows/);
  assert.doesNotMatch(msys.stdout, /REACHED_BUILD/);
  const source = read('build/sdk/producers/platform_matrix/build_runtime.mjs');
  const guard = source.indexOf("...windowsRuntimeGitGuard('runtime_source'),");
  assert.ok(guard > source.indexOf('runtime_source="$(cygpath -u') && guard < source.indexOf('run build -- python3 build.py build'), 'guard runs before build.py build');
});

// The composite action itself refuses an MSYS2 git before any producer runs.
test('native-windows-tools fails when MSYS2 git shadows Git for Windows', t => {
  const lines = runBlock(step(TOOLS, MINGW_TOOLS_STEP)).split('\n');
  const at = lines.findIndex(line => line.includes('MSYS2_GIT_SHADOWS_GIT_FOR_WINDOWS'));
  assert.ok(at > 0 && lines[at + 1].includes('GIT_NOT_GIT_FOR_WINDOWS'), lines.join('\n'));
  assert.ok(at < lines.findIndex(line => line.includes('MSYS2_BASH=')), 'checked before producers are exposed');
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'tools-git-'));
  t.after(() => fs.rmSync(work, {recursive: true, force: true}));
  const run = (version, msysGit) => {
    const usr = path.join(work, `usr-${msysGit}`), bin = path.join(work, version.replace(/\W/g, '_'));
    fs.mkdirSync(usr, {recursive: true}); fs.mkdirSync(bin, {recursive: true});
    if (msysGit) fs.writeFileSync(path.join(usr, 'git.exe'), '');
    fs.writeFileSync(path.join(bin, 'git'), `#!/bin/sh\necho "${version}"\n`, {mode: 0o755});
    const script = lines.slice(at, at + 2).join('\n').replaceAll('/usr/bin/', `${usr}/`) + '\necho CHECKED';
    return bash(script, {env: {...process.env, PATH: `${bin}:/usr/bin:/bin`}});
  };
  const ok = run('git version 2.56.1.windows.1', false);
  assert.equal(ok.status, 0, ok.stderr);
  assert.match(ok.stdout, /CHECKED/);
  assert.match(run('git version 2.56.1.windows.1', true).stderr, /MSYS2_GIT_SHADOWS_GIT_FOR_WINDOWS/);
  const msys = run('git version 2.56.1', false);
  assert.notEqual(msys.status, 0);
  assert.match(msys.stderr, /GIT_NOT_GIT_FOR_WINDOWS/);
});

// Pinned third_party_flatbuffers c3e4d69c commits these eight files; Git for
// Windows refuses each one ("error: invalid path", run 45420757561). Linux Git
// ignores core.protectNTFS for these names, so the test checks what each
// checkout writes against Git's is_valid_win32_path rules instead.
const FETCH_STEP = 'Fetch the selected compiler source for cjdb, the shim and AST support';
const ZONE = ['android/gradle/wrapper/gradle-wrapper.jar', 'android/gradlew.bat', 'kotlin/gradle/wrapper/gradle-wrapper.jar',
  'kotlin/gradlew.bat', 'tests/FlatBuffers.Test/NetTest.bat', 'tests/LobsterTest.bat', 'tests/LuaTest.bat', 'tests/RustTest.bat']
  .map(file => `${file}:Zone.Identifier`);
const REAL = ['CMakeLists.txt', 'include/flatbuffers/flatbuffers.h', 'src/flatc.cpp', 'android/gradlew.bat', 'tests/RustTest.bat'];
const ntfsInvalid = file => file.split('/').some(part => /[:*?"<>|\\\x00-\x1f]/.test(part) || /[. ]$/.test(part)
  || /^(aux|con|conin\$|conout\$|nul|prn|com[1-9]|lpt[1-9]) *(\.|$)/i.test(part));
const git = (cwd, ...args) => spawnSync('git', ['-C', cwd, ...args], {encoding: 'utf8'});
function flatbuffersSource(t, extra = []) {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'flatbuffers-ntfs-'));
  t.after(() => fs.rmSync(work, {recursive: true, force: true}));
  const source = path.join(work, 'source');
  for (const file of [...REAL, ...ZONE, ...extra]) {
    fs.mkdirSync(path.dirname(path.join(source, file)), {recursive: true});
    fs.writeFileSync(path.join(source, file), `${file}\n`);
  }
  for (const args of [['init', '-q'], ['add', '-A'], ['-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qm', 'fixture']])
    assert.equal(git(source, ...args).status, 0);
  return {work, source, sha: git(source, 'rev-parse', 'HEAD').stdout.trim()};
}
// What the checkout put on disk and kept in the index.
function written(dir) {
  const files = [];
  const walk = rel => { for (const entry of fs.readdirSync(path.join(dir, rel), {withFileTypes: true})) {
    const name = rel ? `${rel}/${entry.name}` : entry.name;
    if (name === '.git') continue;
    entry.isDirectory() ? walk(name) : files.push(name);
  } };
  walk('');
  return files.sort();
}
function flatbuffersBlock() {
  const script = runBlock(step(PREPARE, FETCH_STEP));
  const start = script.indexOf('git init flatbuffers');
  assert.notEqual(start, -1, 'the fetch step checks out flatbuffers');
  return script.slice(start);
}

test('prepare checks out the pinned flatbuffers tree without its NTFS-invalid Zone.Identifier files', t => {
  const {work, source, sha} = flatbuffersSource(t);
  fs.mkdirSync(path.join(work, 'build/lib'), {recursive: true});
  fs.copyFileSync(path.join(repo, 'build/lib/srcbuild_git.sh'), path.join(work, 'build/lib/srcbuild_git.sh'));
  const result = bash(flatbuffersBlock(), {cwd: work, env: {...process.env, FLATBUFFERS_URL: `file://${source}`, FLATBUFFERS_SHA: sha,
    GIT_CONFIG_COUNT: '1', GIT_CONFIG_KEY_0: 'core.protectNTFS', GIT_CONFIG_VALUE_0: 'true'}});
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const dest = path.join(work, 'flatbuffers');
  assert.equal(git(dest, 'rev-parse', 'HEAD').stdout.trim(), sha);
  assert.equal(git(dest, 'status', '--porcelain').stdout, '');
  assert.deepEqual(written(dest), [...REAL].sort());
  assert.deepEqual(written(dest).filter(ntfsInvalid), []);
  const skipped = git(dest, 'ls-files', '-t').stdout.split('\n').filter(line => line.startsWith('S ')).map(line => line.slice(2));
  assert.deepEqual(skipped.sort(), [...ZONE].sort());
});

test('an unguarded flatbuffers checkout writes every NTFS-invalid Zone.Identifier file', t => {
  const {work, source, sha} = flatbuffersSource(t);
  const dest = path.join(work, 'plain');
  for (const args of [['init', '-q', dest]]) assert.equal(spawnSync('git', args).status, 0);
  assert.equal(git(dest, 'fetch', '-q', '--depth=1', `file://${source}`, sha).status, 0);
  assert.equal(git(dest, '-c', 'core.protectNTFS=true', 'checkout', '--detach', 'FETCH_HEAD').status, 0);
  assert.deepEqual(written(dest).filter(ntfsInvalid), [...ZONE].sort());
});

test('the Zone.Identifier checkout refuses any other NTFS-unsafe path before writing', t => {
  const {work, source, sha} = flatbuffersSource(t, ['src/aux.c']);
  const dest = path.join(work, 'flatbuffers');
  assert.equal(spawnSync('git', ['init', '-q', dest]).status, 0);
  assert.equal(git(dest, 'fetch', '-q', '--depth=1', `file://${source}`, sha).status, 0);
  const refused = spawnSync('bash', ['-c', '. "$1"; srcbuild_git_checkout_skip_zone_identifier "$2"', 'checkout',
    path.join(repo, 'build/lib/srcbuild_git.sh'), dest], {encoding: 'utf8'});
  assert.equal(refused.status, 1);
  assert.match(refused.stderr, /NTFS_UNSAFE_PATH src\/aux\.c/);
  assert.notEqual(git(dest, 'rev-parse', '--verify', '-q', 'HEAD').status, 0, 'nothing was checked out');
});

test('the Zone.Identifier checkout refuses the CONIN$ and CONOUT$ console devices too', t => {
  const devices = ['src/CONIN$', 'src/conin$.txt', 'tools/Conout$', 'tools/CONOUT$ .log'];
  const {work, source, sha} = flatbuffersSource(t, [...devices, 'src/conin.c', 'src/conout$x.c']);
  const dest = path.join(work, 'flatbuffers');
  assert.equal(spawnSync('git', ['init', '-q', dest]).status, 0);
  assert.equal(git(dest, 'fetch', '-q', '--depth=1', `file://${source}`, sha).status, 0);
  const refused = spawnSync('bash', ['-c', '. "$1"; srcbuild_git_checkout_skip_zone_identifier "$2"', 'checkout',
    path.join(repo, 'build/lib/srcbuild_git.sh'), dest], {encoding: 'utf8'});
  assert.equal(refused.status, 1);
  const named = refused.stderr.replace(/^NTFS_UNSAFE_PATH /, '').trim().split('\n').sort();
  assert.deepEqual(named, [...devices].sort());
  assert.deepEqual(devices.filter(file => !ntfsInvalid(file)), []);
  assert.notEqual(git(dest, 'rev-parse', '--verify', '-q', 'HEAD').status, 0, 'nothing was checked out');
});

test('the Windows LLVM tuple fetch checks out flatbuffers through the Zone.Identifier checkout', () => {
  const body = read('build/sdk/producers/platform_tuples/fetch_sources.mjs');
  assert.match(body, /fetchExact\(required\('FLATBUFFERS_URL', \d+\), required\('FLATBUFFERS_SHA', \d+\), `\$\{root\}\/flatbuffers`, '', true\)/);
  assert.match(body, /if \(skipZoneIdentifier\) await run\(\['bash', '-c', '[^']*srcbuild_git_checkout_skip_zone_identifier "\$2"'/);
});
