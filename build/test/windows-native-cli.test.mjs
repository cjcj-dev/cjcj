import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {getTarget} from '../lib/targets.mjs';
import {getBuildTarget} from '../lib/build-target.mjs';
import {buildConfig} from '../lib/config.mjs';
import {baseEnv} from '../srcbuild/stages/common.mjs';

// Linux script apparatus only: changing the JS host selector does not execute
// Windows programs or validate Windows path/loader semantics.
function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'windows-native-cli-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const preload = path.join(root, 'host.mjs');
  fs.writeFileSync(preload, "Object.defineProperty(process,'platform',{value:'win32'});\n");
  const tools = path.join(root, 'cjcj-tools');
  for (const name of ['cjpm', 'cjfmt', 'hle', 'lsp', 'cjcov', 'cjtrace-recover', 'cjlint', 'cjprof', 'cjcompat', 'cjhead']) {
    fs.mkdirSync(path.join(tools, 'packages', name, 'build'), {recursive: true});
  }
  fs.writeFileSync(path.join(tools, 'build.mjs'), '// plan-only public root producer\n');
  for(const name of ['cjpm','cjfmt','hle','lsp','cjcov','cjtrace-recover','cjlint','cjprof','cjcompat','cjhead'])fs.writeFileSync(path.join(tools,'packages',name,'build/build.mjs'),'// plan-only package producer\n');
  const env = {...process.env, CANGJIE_BUILD_DRY_RUN: '1', CJCJ_NATIVE_TOOL_DEPENDENCIES: path.join(root,'native-dependencies.json'), CJCJ_NATIVE_LLVM_BIN: path.join(root, 'llvm/bin'),
    CJCJ_NATIVE_OPENSSL_LIB: path.join(root, 'openssl/lib')};
  for (const key of ['CJCJ_OFFICIAL_SDK_ROOT', 'CJCJ_SRCBUILD_CONSUMER_SDK']) delete env[key];
  return {root, env, run({native = true, args = ['--tools-phase','build','--tools-build-set','cjpm,cjcov,hle,cjtrace-recover','--tools-mangle-source',path.join(root,'mangle'),'build','tools'], extra = {}, profile = 'generic'} = {}) {
    const argv = [...(native ? ['--import', preload] : []), 'build/cli.mjs', '--workspace', root,
      '--build-root', path.join(root, 'buildtools'), '--target', 'windows-x64', '--host-profile', profile, ...args];
    return spawnSync(process.execPath, argv, {cwd: path.resolve(import.meta.dirname, '../..'),
      env: {...env, ...extra}, encoding: 'utf8', timeout: 30000});
  }};
}

test('Windows native build context does not change the Linux cross producer registry', () => {
  const cross = getTarget('windows-x64');
  const native = getBuildTarget('windows-x64', {platform: 'win32', arch: 'x64', env: {}});
  assert.equal(native.spec.crossCompile, false);
  assert.equal(native.spec.nodePlatform, 'win32');
  assert.equal(native.spec.hostRuntimeLibrary, 'libcangjie-runtime.dll');
  assert.equal(native.spec.hostRuntimeTuple, native.spec.runtimeTuple);
  assert.equal(native.primaryCompilerOutput(), 'output');
  assert.equal(cross.spec.crossCompile, true);
  assert.equal(cross.spec.nodePlatform, 'linux');
  assert.equal(getBuildTarget('windows-x64', {platform: 'linux', arch: 'x64'}), cross);
});
test('public Windows native CLI plans the four applicable CJ producers without cross arguments', t => {
  const r=fixture(t).run();assert.equal(r.status,0,r.stdout+r.stderr);
  const output=r.stdout+r.stderr;
  for(const name of ['cjpm','cjcov','hle','cjtrace-recover'])assert.match(output,new RegExp('build\\.mjs build --tool '+name+' '));
  assert.doesNotMatch(output,/--target windows-x86_64|--set-rpath|build\.py/);
});
test('public Linux cross CLI preserves the applicable target producer plans', t => {
  const r=fixture(t).run({native:false});assert.equal(r.status,0,r.stdout+r.stderr);
  const output=r.stdout+r.stderr;
  for(const name of ['cjpm','cjcov','hle','cjtrace-recover'])assert.match(output,new RegExp('build\\.mjs build --tool '+name+' [^\\n]*--target windows-x86_64'));
  assert.match(output,/--target-sysroot/);assert.doesNotMatch(output,/--set-rpath|build\.py/);
});
for(const native of [true,false])test('unimplemented Windows analysis set is refused, native='+native,t=>{
 const r=fixture(t).run({native,args:['--tools-phase','build','--tools-build-set','lsp','build','tools']});
 assert.notEqual(r.status,0);assert.match(r.stderr,/Cangjie analysis tools currently support Linux x86-64/);
});
test('public native CLI rejects kkk2 rather than granting a Windows execution slot', t => {
  const r = fixture(t).run({profile: 'kkk2', args: ['print-version']});
  assert.equal(r.status, 2);
  assert.match(r.stderr, /native Windows requires generic host profile/);
});
test('public native CLI requires explicit native dependency paths', t => {
  const r = fixture(t).run({extra: {CJCJ_NATIVE_LLVM_BIN: ''}});
  assert.equal(r.status, 1);
  assert.match(r.stderr, /CJCJ_NATIVE_LLVM_BIN must name an absolute/);
});
test('base environment retains the host DLL directory when adding SDK executables', t => {
  const f = fixture(t), host = path.join(f.root, 'host'), sdk = path.join(f.root, 'target');
  const tuple = 'windows_x86_64_cjnative';
  fs.mkdirSync(path.join(host, 'runtime/lib', tuple), {recursive: true});
  fs.writeFileSync(path.join(host, 'runtime/lib', tuple, 'libcangjie-runtime.dll'), 'fixture DLL marker');
  fs.mkdirSync(path.join(sdk, 'runtime/lib', tuple), {recursive: true});
  const previous = Object.fromEntries(['CANGJIE_BUILD_DRY_RUN', 'CJCJ_OFFICIAL_SDK_ROOT'].map(k => [k, process.env[k]]));
  process.env.CANGJIE_BUILD_DRY_RUN = '1'; process.env.CJCJ_OFFICIAL_SDK_ROOT = host;
  t.after(() => { for (const [k, v] of Object.entries(previous)) { if (v === undefined) delete process.env[k]; else process.env[k] = v; } });
  const config = {...buildConfig({workspace: f.root, consumerSdk: sdk}),
    target: getBuildTarget('windows-x64', {platform: 'win32', arch: 'x64', env: f.env})};
  const env = baseEnv(config);
  console.log('WINDOWS_HOST_DLL_PATH_ASSERT_REACHED');
  assert.ok(env.PATH.split(path.delimiter).includes(path.join(host, 'runtime/lib', tuple)));
  assert.ok(env.PATH.split(path.delimiter).includes(path.join(sdk, 'bin')));
  assert.ok(!env.PATH.split(path.delimiter).includes(path.join(sdk, 'runtime/lib', tuple)));
});
