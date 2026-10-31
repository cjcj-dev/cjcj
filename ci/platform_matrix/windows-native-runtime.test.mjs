import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {RUNTIME_INPUTS} from '../../build/lib/runtime-source-inputs.mjs';
import {configureNativeRuntime, installNativeRuntimeDependencies, recordNativeRuntime} from './native_runtime.mjs';

// Linux controlled installer fixture. It never runs a Windows native producer.
async function fixture(t, body) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'windows-runtime-install-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const source = path.join(root, 'source'), installRoot = path.join(root, 'install');
  const cache = path.join(root, 'sccache'); fs.writeFileSync(cache, 'fixture', {mode: 0o755});
  const env = {NATIVE_RUNTIME_PLATFORM: 'windows_x86_64', CJCJ_NATIVE_LLVM_REF: 'a'.repeat(40),
    CJCJ_NATIVE_RUNTIME_REF: 'b'.repeat(40), RUNTIME_VERSION: '1.3.0-fixture',
    CJCJ_NATIVE_HOST_VERSION: '1.3.0-alpha.20260925001050', SCCACHE_PATH: cache};
  const put = (file, text) => { fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, text); };
  put(path.join(source, 'runtime/fixture.txt'), 'Explicit controlled installer fixture, not a Windows runtime build\n');
  const git = args => { const result = spawnSync('git', ['-C', source, ...args], {encoding:'utf8'});
    assert.equal(result.status, 0, result.stderr); return result.stdout.trim(); };
  git(['init','-q']); git(['add','.']);
  git(['-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','Controlled runtime installer fixture']);
  env.CJCJ_NATIVE_RUNTIME_REF = git(['rev-parse','HEAD']);

  const tuple='windows_x86_64_cjnative',preinstall=path.join(root,'cjthread-install'),runtime=path.join(source,'runtime'),build=path.join(runtime,'CMakebuild');
  put(path.join(build,'CMakeCache.txt'),`CMAKE_HOME_DIRECTORY:INTERNAL=${runtime}\nCMAKE_INSTALL_PREFIX:PATH=${preinstall}\nCMAKE_BUILD_TYPE:STRING=Release\nCANGJIE_COMPILER_CACHE:FILEPATH=${cache}\nCMAKE_C_COMPILER_LAUNCHER:STRING=${cache}\nCMAKE_CXX_COMPILER_LAUNCHER:STRING=${cache}\n`);
  put(path.join(build,'cjthread-build/CMakeCache.txt'),`CMAKE_HOME_DIRECTORY:INTERNAL=${runtime}/src/CJThread\nCMAKE_INSTALL_PREFIX:PATH=${preinstall}\nTARGET_ARCH:STRING=${tuple}\nCMAKE_BUILD_TYPE:STRING=Release\n`);
  const archives=['thread','aio'].map(name=>path.join(preinstall,'lib',tuple,`libcangjie-${name}.a`));
  archives.forEach((file,i)=>put(file,'installed '+['thread','aio'][i]));
  put(path.join(build,'cjthread-build/install_manifest.txt'),archives.join('\n'));
  const bounds=path.join(build,'runtime-staging/bin/x86_64_Release/libboundscheck.dll');
  const links=['boundscheck','cangjie-runtime'].map(name=>path.join(build,`src/CMakeFiles/${name}.dir/link.txt`));
  put(links[0],'clang -shared -o '+bounds);put(links[1],'clang '+bounds+'.a');
  put(path.join(build,'runtime-link-inputs.txt'),links.join('\n'));
  const platform = Object.getOwnPropertyDescriptor(process, 'platform');
  Object.defineProperty(process, 'platform', {value: 'win32'});
  try { await body({root, source, installRoot, env, put}); }
  finally { Object.defineProperty(process, 'platform', platform); }
}
test('native Windows uses the explicit Windows build.py route and original cache toolchain', t => fixture(t, ({env}) => {
  assert.throws(() => configureNativeRuntime({runtimeTarget: 'native'}, env), /NATIVE_RUNTIME_HOST_UNSUPPORTED/);
  configureNativeRuntime({runtimeTarget: 'windows-x86_64'}, env);
  assert.equal(path.basename(env.CMAKE_TOOLCHAIN_FILE), 'windows_runtime_toolchain.cmake');
  assert.match(fs.readFileSync(env.CMAKE_TOOLCHAIN_FILE, 'utf8'), /include\("\$\{CMAKE_CURRENT_LIST_DIR\}\/native_runtime_toolchain.cmake"\)/);
}));
test('native Windows copies this invocation bounds DLL and records Windows layout plus actual command input', t => fixture(t, async f => {
  const tuple = 'windows_x86_64_cjnative';
  f.put(path.join(f.source, 'runtime/CMakebuild/runtime-staging/bin/x86_64_Release/libboundscheck.dll'), 'produced bounds fixture');
  f.put(path.join(f.installRoot, 'runtime/lib', tuple, 'libcangjie-runtime.dll'), 'runtime fixture\nCJRT-COMMIT:' + f.env.CJCJ_NATIVE_RUNTIME_REF + '\n');
  f.put(path.join(f.installRoot, 'lib', tuple, 'libcangjie-runtime.a'), 'archive fixture\nCJRT-COMMIT:' + f.env.CJCJ_NATIVE_RUNTIME_REF + '\n');
  installNativeRuntimeDependencies({...f, buildType: 'release'});
  for(const name of ['thread','aio'])assert.equal(fs.readFileSync(path.join(f.installRoot,'lib',tuple,`libcangjie-${name}.a`),'utf8'),'installed '+name);
  console.log('WINDOWS_BOUNDS_INSTALL_ASSERT_REACHED');
  assert.equal(fs.readFileSync(path.join(f.installRoot, 'runtime/lib', tuple, 'libboundscheck.dll'), 'utf8'), 'produced bounds fixture');
  const options = {...f, actualRef: f.env.CJCJ_NATIVE_RUNTIME_REF, version: f.env.RUNTIME_VERSION, buildType: 'release'};
  await assert.rejects(recordNativeRuntime(options, f.env), /NATIVE_RUNTIME_COMMANDS_REQUIRED/);
  const commands = [['fixture-program', 'fixture-only-not-native-execution']];
  await recordNativeRuntime({...options, commands}, f.env);
  const facts = JSON.parse(fs.readFileSync(path.join(f.installRoot, 'NATIVE-INPUTS.json')));
  assert.equal(facts.platform, 'windows_x86_64'); assert.deepEqual(facts.commands, commands);
  assert.ok(facts.files['runtime/lib/' + tuple + '/libboundscheck.dll']);
  assert.deepEqual(Object.keys(facts.files).sort(), [RUNTIME_INPUTS, 'SOURCE_SHA',
    `runtime/lib/${tuple}/libcangjie-runtime.dll`, `runtime/lib/${tuple}/libboundscheck.dll`,
    ...['runtime','thread','aio'].map(name=>`lib/${tuple}/libcangjie-${name}.a`)].sort());
  assert.ok(facts.files[RUNTIME_INPUTS]);
  const original = JSON.parse(fs.readFileSync(path.join(f.installRoot, RUNTIME_INPUTS)));
  assert.equal(original.source.repository, f.source);
  assert.equal(original.source.commit, f.env.CJCJ_NATIVE_RUNTIME_REF);
  assert.equal(original.embedded_stamp, 'CJRT-COMMIT:' + f.env.CJCJ_NATIVE_RUNTIME_REF);
  assert.deepEqual(original.artifacts.map(row => row.path), [
    'runtime/lib/' + tuple + '/libcangjie-runtime.dll', 'lib/' + tuple + '/libcangjie-runtime.a']);
}));
test('native Windows refuses missing newly produced bounds even if an installed DLL exists', t => fixture(t, f => {
  f.put(path.join(f.installRoot, 'runtime/lib/windows_x86_64_cjnative/libboundscheck.dll'), 'stale');
  assert.throws(() => installNativeRuntimeDependencies({...f, buildType: 'release'}), /NATIVE_RUNTIME_BUILD_MISSING/);
}));
