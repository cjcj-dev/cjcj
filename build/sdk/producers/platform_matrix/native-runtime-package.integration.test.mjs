import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {boundsProbeSymbol} from './native_bounds_probe.mjs';

// Real native objects, loader, tar and public package process; no runtime/SDK qualification.
const platform = `${process.platform}_${process.arch === 'arm64' ? 'aarch64' : 'x86_64'}`;
const suffix = process.platform === 'darwin' ? '.dylib' : '.so';
const entry = fileURLToPath(new URL('./native_runtime_package.mjs', import.meta.url));
const evidence = process.env.NATIVE_PACKAGE_EVIDENCE;
assert.ok(evidence && path.isAbsolute(evidence), 'NATIVE_PACKAGE_EVIDENCE must retain all cases');
fs.mkdirSync(evidence, {recursive:true});
function fixture(body, boundsBody = 'return dst && n <= cap ? (std::memcpy(dst, src, n), 0) : 22;', boundsSource = null) {
  const root = fs.mkdtempSync(path.join(evidence, 'case-'));
  const source = path.join(root, 'source'), output = path.join(root, 'output');
  const install = path.join(output, 'runtime-install'), lib = path.join(install, 'runtime/lib', `${platform}_cjnative`);
  fs.mkdirSync(lib, {recursive:true});
  fs.mkdirSync(path.join(source, 'runtime/CMakebuild'), {recursive:true});
  const commands = [];
  const execute = (label, argv, options = {}) => {
    const started = new Date().toISOString();
    const result = spawnSync(argv[0], argv.slice(1), {encoding:'utf8', cwd:root, ...options});
    fs.writeFileSync(path.join(root, `${label}.stdout`), result.stdout || '');
    fs.writeFileSync(path.join(root, `${label}.stderr`), result.stderr || '');
    commands.push({label, argv, cwd:root, started, ended:new Date().toISOString(),
      rc:result.status, signal:result.signal, error:result.error?.message || null});
    fs.writeFileSync(path.join(root, 'commands.json'), JSON.stringify(commands, null, 2));
    return result;
  };
  const found = execute('compiler-path', ['which', process.env.CXX || 'clang++']);
  assert.equal(found.status, 0, found.stderr);
  const compiler = found.stdout.trim();
  fs.writeFileSync(path.join(source, 'runtime/CMakebuild/CMakeCache.txt'), `CMAKE_CXX_COMPILER:FILEPATH=${compiler}\n`);
  const sha = 'a'.repeat(40);
  fs.writeFileSync(path.join(install, 'SOURCE_SHA'), sha+'\n');
  fs.writeFileSync(path.join(install, 'NATIVE-INPUTS.json'), JSON.stringify({platform, runtime_sha:sha, paired_llvm_sha:'b'.repeat(40)}));
  for (const [name, code] of [
    ['cangjie-runtime', '#include <cstdlib>\nextern "C" void CJ_MCC_HandleReturnSafepoint() { std::abort(); }\n'],
    ['boundscheck', boundsSource ?? '#include <cstring>\nextern "C" int memcpy_s(void* dst, size_t cap, const void* src, size_t n) { '+boundsBody+' }\n'],
  ]) {
    const cpp = path.join(root, name+'.cpp'); fs.writeFileSync(cpp, code);
    const built = execute('build-'+name, [compiler, '-std=c++17', ...(process.platform === 'darwin' ? ['-dynamiclib'] : ['-shared', '-fPIC']),
      cpp, '-o', path.join(lib, 'lib'+name+suffix)]);
    assert.equal(built.status, 0, built.stderr);
  }
  const run = (selectedOutput = output, label = 'public-package') => execute(label, [process.execPath, entry], {env:{...process.env,
    PLATFORM_CI_ROOT:selectedOutput, RUNTIME_SOURCE:source, NATIVE_RUNTIME_PLATFORM:platform, CJCJ_NATIVE_RUNTIME_REF:sha}});
  const restored = () => {
    const next = path.join(root, 'restored-output'); fs.mkdirSync(next);
    fs.cpSync(install, path.join(next, 'runtime-install'), {recursive:true});
    const result = run(next, 'public-restored'); assert.equal(result.status, 0, result.stdout+result.stderr);
  };
  const summary = () => JSON.parse(fs.readFileSync(path.join(output, 'native-consumers/summary.json')));
  const command = name => JSON.parse(fs.readFileSync(path.join(output, 'native-consumers', name+'.json')));
  body({root, output, lib, run, summary, command, restored, execute, compiler});
}
test('public native package calls bounds and loads the same installed and unpacked objects', () => fixture(({run, summary, command, output}) => {
  const result = run();
  console.log('NATIVE_PACKAGE_BOUNDS_TARGET_REACHED');
  assert.equal(result.status, 0, result.stdout+result.stderr);
  const facts = summary(); assert.equal(facts.rc, 0);
  for (const stage of ['installed', 'unpacked']) {
    for (const role of ['runtime', 'bounds']) assert.equal(command(`${stage}-${role}`).rc, 0);
    assert.match(fs.readFileSync(path.join(output, 'native-consumers', stage+'-bounds.stdout'), 'utf8'), /NATIVE_BOUNDS_CALL_OK/);
  }
  assert.equal(facts.installed.runtime.sha256, facts.unpacked.runtime.sha256);
  assert.equal(facts.installed.bounds.sha256, facts.unpacked.bounds.sha256);
  for (const stage of ['installed', 'unpacked']) {
    assert.equal(facts[stage].bounds.symbol, boundsProbeSymbol(process.platform));
    assert.equal(command(`${stage}-bounds`).args[1], boundsProbeSymbol(process.platform));
  }
  assert.notEqual(facts.installed.runtime.library, facts.unpacked.runtime.library);
}));
test('public native package rejects missing bounds while runtime loading remains independent', () => fixture(({run, lib, command, summary, restored}) => {
  fs.renameSync(path.join(lib, 'libboundscheck'+suffix), path.join(lib, 'libboundscheck.saved'));
  const result = run(); assert.equal(result.status, 1);
  assert.match(result.stderr, /NATIVE_LIBRARY_MISSING installed bounds/);
  assert.equal(command('installed-runtime').rc, 0);
  assert.equal(summary().package, 'NOT_RUN');
  fs.renameSync(path.join(lib, 'libboundscheck.saved'), path.join(lib, 'libboundscheck'+suffix));
  restored();
}));
test('public native package rejects a callable bounds symbol that does not copy bytes', () => fixture(({run, command, summary}) => {
  const result = run(); assert.equal(result.status, 71, result.stdout+result.stderr);
  assert.equal(command('installed-runtime').rc, 0);
  assert.equal(command('installed-bounds').rc, 71);
  assert.equal(summary().unpacked, 'NOT_RUN');
}, 'return 0;'));
test('public native package rejects a bounds symbol loaded from a different library and restores', () => fixture(({root, lib, run, command, restored, execute, compiler}) => {
  const foreign = path.join(root, 'libforeign'+suffix), bridge = path.join(root, 'bridge.cpp');
  assert.equal(execute('foreign-library', [compiler, ...(process.platform === 'darwin' ? ['-dynamiclib'] : ['-shared', '-fPIC']),
    path.join(root, 'boundscheck.cpp'), '-o', foreign]).status, 0);
  fs.writeFileSync(bridge, '#include <cstddef>\nextern "C" int memcpy_s(void*, size_t, const void*, size_t);\nextern "C" int bridge() { return memcpy_s(nullptr, 0, nullptr, 0); }\n');
  const bounds = path.join(lib, 'libboundscheck'+suffix);
  fs.renameSync(bounds, bounds+'.saved');
  assert.equal(execute('bridge-library', [compiler, ...(process.platform === 'darwin' ? ['-dynamiclib'] : ['-shared', '-fPIC']),
    bridge, foreign, '-o', bounds]).status, 0);
  const result = run(); assert.equal(result.status, 68, result.stdout+result.stderr);
  assert.match(result.stderr, /DARWIN_LOADED_PATH_MISMATCH/);
  assert.equal(command('installed-runtime').rc, 0);
  assert.equal(command('installed-bounds').rc, 68);
  fs.renameSync(bounds, bounds+'.wrong-origin'); fs.renameSync(bounds+'.saved', bounds);
  // Keep the rejected carrier outside the restored installation.
  fs.renameSync(bounds+'.wrong-origin', path.join(root, 'rejected-origin'+suffix));
  restored();
}));

// Windows libboundscheck.dll is built from memset_s/snprintf_s/vsnprintf_s only
// (the C runtime supplies memcpy_s), so its consumer probe must bind memset_s.
test('bounds probe binds memset_s on Windows and memcpy_s on Linux and Darwin', () => {
  assert.equal(boundsProbeSymbol('win32'), 'memset_s');
  assert.equal(boundsProbeSymbol('linux'), 'memcpy_s');
  assert.equal(boundsProbeSymbol('darwin'), 'memcpy_s');
  assert.throws(() => boundsProbeSymbol('freebsd'), /NATIVE_BOUNDS_PROBE_PLATFORM freebsd/);
});
// A Windows-shaped bounds library (memset_s only) is rejected by the Linux/Darwin
// public consumer: it must still bind memcpy_s there, not whatever is exported.
test('public native package on Linux/Darwin still requires memcpy_s from a memset_s-only bounds library', () => fixture(({run, command, summary}) => {
  const result = run(); assert.equal(result.status, 67, result.stdout+result.stderr);
  assert.match(result.stderr, /DARWIN_LOADED_SYMBOL_MISSING memcpy_s/);
  assert.equal(command('installed-runtime').rc, 0);
  assert.equal(command('installed-bounds').rc, 67);
  assert.equal(summary().installed.bounds.symbol, 'memcpy_s');
  assert.equal(summary().package, 'NOT_RUN');
}, undefined, memsetOnly('return dst && n <= cap ? (std::memset(dst, c, n), 0) : (dst && cap ? (std::memset(dst, 0, cap), 34) : 22);')));

function memsetOnly(body) {
  return '#include <cstring>\nextern "C" int memset_s(void* dst, size_t cap, int c, size_t n) { '+body+' }\n';
}
// The real loader against real shared libraries exporting ONLY memset_s.
function loaderCase(label, body) {
  const root = fs.mkdtempSync(path.join(evidence, `loader-${label}-`));
  const run = (name, argv) => {
    const result = spawnSync(argv[0], argv.slice(1), {encoding:'utf8', cwd:root});
    fs.writeFileSync(path.join(root, `${name}.json`), JSON.stringify({argv, rc:result.status, signal:result.signal,
      error:result.error?.message || null, stdout:result.stdout, stderr:result.stderr}, null, 2));
    return result;
  };
  const compiler = process.env.CXX || 'clang++';
  const loader = path.join(root, 'native-loader');
  const built = run('compile-loader', [compiler, '-std=c++17', fileURLToPath(new URL('../release/darwin_loader.cpp', import.meta.url)),
    ...(process.platform === 'linux' ? ['-ldl'] : []), '-o', loader]);
  assert.equal(built.status, 0, built.stderr);
  const cpp = path.join(root, 'boundscheck.cpp'), library = path.join(root, 'libboundscheck'+suffix);
  fs.writeFileSync(cpp, memsetOnly(body));
  const shared = run('build-bounds', [compiler, '-std=c++17', ...(process.platform === 'darwin' ? ['-dynamiclib'] : ['-shared', '-fPIC']),
    cpp, '-o', library]);
  assert.equal(shared.status, 0, shared.stderr);
  const symbols = run('exports', ['nm', ...(process.platform === 'darwin' ? ['-gU'] : ['-D', '--defined-only']), library]);
  assert.equal(symbols.status, 0, symbols.stderr);
  assert.match(symbols.stdout, /\b_?memset_s\s*$/m);
  assert.doesNotMatch(symbols.stdout, /\b_?memcpy_s\s*$/m);
  return {probe: symbol => run(`probe-${symbol}`, [loader, library, symbol, 'boundscheck'])};
}
const conforming = 'return dst && n <= cap ? (std::memset(dst, c, n), 0) : (dst && cap ? (std::memset(dst, 0, cap), 34) : 22);';
test('native loader calls memset_s from a memset_s-only bounds library and rejects a memcpy_s probe', () => {
  const {probe} = loaderCase('memset-ok', conforming);
  const ok = probe('memset_s');
  console.log('NATIVE_LOADER_MEMSET_TARGET_REACHED');
  assert.equal(ok.status, 0, ok.stdout+ok.stderr);
  assert.match(ok.stdout, /NATIVE_BOUNDS_CALL_OK/);
  const missing = probe('memcpy_s');
  assert.equal(missing.status, 67, missing.stdout+missing.stderr);
  assert.match(missing.stderr, /DARWIN_LOADED_SYMBOL_MISSING memcpy_s/);
  assert.doesNotMatch(missing.stdout, /NATIVE_BOUNDS_CALL_OK/);
});
for (const [label, body] of [
  ['nonzero', 'return 22;'],
  ['unfilled', 'return 0;'],
  ['short-fill', 'return dst && n <= cap ? (std::memset(dst, c, n - 1), 0) : 22;'],
  ['unchecked-count', 'return (std::memset(dst, c, n), 0);'],
  ['overflow-write', 'if (n > cap) { std::memset(dst, c, n); return 34; } return (std::memset(dst, c, n), 0);'],
]) {
  test(`native loader rejects a memset_s that is not a bounds-checked fill (${label}) with rc 71`, () => {
    const result = loaderCase(label, body).probe('memset_s');
    assert.equal(result.status, 71, result.stdout+result.stderr);
    assert.doesNotMatch(result.stdout, /NATIVE_BOUNDS_CALL_OK/);
  });
}
