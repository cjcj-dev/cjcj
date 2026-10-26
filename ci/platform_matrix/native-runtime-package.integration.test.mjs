import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

// Real native objects, loader, tar and public package process; no runtime/SDK qualification.
const platform = `${process.platform}_${process.arch === 'arm64' ? 'aarch64' : 'x86_64'}`;
const suffix = process.platform === 'darwin' ? '.dylib' : '.so';
const entry = fileURLToPath(new URL('./native_runtime_package.mjs', import.meta.url));
const evidence = process.env.NATIVE_PACKAGE_EVIDENCE;
assert.ok(evidence && path.isAbsolute(evidence), 'NATIVE_PACKAGE_EVIDENCE must retain all cases');
fs.mkdirSync(evidence, {recursive:true});
function fixture(body, boundsBody = 'return dst && n <= cap ? (std::memcpy(dst, src, n), 0) : 22;') {
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
    ['boundscheck', '#include <cstring>\nextern "C" int memcpy_s(void* dst, size_t cap, const void* src, size_t n) { '+boundsBody+' }\n'],
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
