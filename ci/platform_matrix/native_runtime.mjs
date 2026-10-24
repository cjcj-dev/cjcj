#!/usr/bin/env zx
// Native build.py/install integration; records actual installed files, not SDK qualification.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {recordRuntimeInputs,runtimeSourceRepository,RUNTIME_INPUTS} from '../../build/lib/runtime-source-inputs.mjs';
import {embeddedStamp} from '../../build/lib/toolchain-identity.mjs';
import {installGcUnitInputs} from '../../build/srcbuild/gc-unit-gate.mjs';
import {buildConfig} from '../../build/lib/config.mjs';
const toolchain = fileURLToPath(new URL('./native_runtime_toolchain.cmake', import.meta.url));
const windowsToolchain = fileURLToPath(new URL('./windows_runtime_toolchain.cmake', import.meta.url));
const sha = value => /^[a-f0-9]{40}$/.test(value || '');
const hostPlatform = () => `${process.platform === 'win32' ? 'windows' : process.platform}_${{x64:'x86_64',arm64:'aarch64'}[process.arch] || process.arch}`;

export function configureNativeRuntime({runtimeTarget}, env = process.env) {
  const windows = hostPlatform() === 'windows_x86_64';
  assert.ok(windows ? runtimeTarget === 'windows-x86_64'
    : runtimeTarget === 'native' && /^(linux|darwin)_(x86_64|aarch64)$/.test(hostPlatform()),
    'NATIVE_RUNTIME_HOST_UNSUPPORTED');
  assert.equal(env.NATIVE_RUNTIME_PLATFORM, hostPlatform(), 'NATIVE_RUNTIME_PLATFORM_MISMATCH');
  assert.ok(sha(env.LLVM_SHA) && sha(env.RUNTIME_REF), 'NATIVE_RUNTIME_PAIR_REQUIRED');
  assert.equal(env.RUNTIME_REF, env.CJCJ_NATIVE_RUNTIME_REF, 'NATIVE_RUNTIME_PAIR_MISMATCH');
  assert.ok(env.RUNTIME_VERSION, 'NATIVE_RUNTIME_VERSION_REQUIRED');
  if (windows) assert.ok(/^\d+\.\d+\.\d+-alpha\.\d+$/.test(env.CJCJ_NATIVE_HOST_VERSION || ''), 'NATIVE_RUNTIME_HOST_VERSION_REQUIRED');
  assert.ok(path.isAbsolute(env.SCCACHE_PATH || '') && fs.existsSync(env.SCCACHE_PATH),
    'NATIVE_RUNTIME_SCCACHE_MISSING');
  fs.accessSync(env.SCCACHE_PATH, fs.constants.X_OK);
  const selectedToolchain = windows ? windowsToolchain : toolchain;
  assert.ok(!env.CMAKE_TOOLCHAIN_FILE || path.resolve(env.CMAKE_TOOLCHAIN_FILE) === selectedToolchain,
    'NATIVE_RUNTIME_TOOLCHAIN_CONFLICT');
  env.CMAKE_TOOLCHAIN_FILE = selectedToolchain;
}

// R79b installs bounds with CMake only on macOS. Linux uses the dependency
// just built by this native invocation, as the existing cross producers do.
export function installNativeRuntimeDependencies({source, installRoot, buildType}) {
  if (!['linux', 'win32'].includes(process.platform)) return;
  const arch = {x64:'x86_64',arm64:'aarch64'}[process.arch];
  const mode = buildType[0].toUpperCase() + buildType.slice(1).toLowerCase();
  const windows = process.platform === 'win32', library = windows ? 'libboundscheck.dll' : 'libboundscheck.so';
  const input = path.join(source, 'runtime/CMakebuild/runtime-staging', windows ? 'bin' : 'lib', `${arch}_${mode}`, library);
  assert.ok(fs.existsSync(input) && fs.lstatSync(input).isFile(), `NATIVE_RUNTIME_BUILD_MISSING: ${input}`);
  const output = path.join(installRoot, 'runtime/lib', `${hostPlatform()}_cjnative`, library);
  fs.mkdirSync(path.dirname(output), {recursive:true});
  fs.copyFileSync(input, output);
  console.log(`native_runtime_dependency=${input} installed=${output}`);
}

// Normal native build/install carries the actual test sources, generated
// headers and compile command used by the later installed language gate.
export function installNativeRuntimeInputs({source,installRoot,gateStatus}) {
  if(process.platform!=='linux')return;
  const config=buildConfig({targetKey:process.arch==='arm64'?'linux-aarch64':'linux-x64'});
  installGcUnitInputs(config,path.join(source,'runtime'),installRoot,{gateStatus});
}

export async function recordNativeRuntime({source, installRoot, actualRef, version, buildType, commands}, env = process.env) {
  assert.equal(actualRef, env.RUNTIME_REF, 'NATIVE_RUNTIME_SOURCE_MISMATCH');
  if (process.platform === 'win32') assert.ok(Array.isArray(commands) && commands.length > 0, 'NATIVE_RUNTIME_COMMANDS_REQUIRED');
  const platform = hostPlatform();
  const suffix = process.platform === 'darwin' ? 'dylib' : process.platform === 'win32' ? 'dll' : 'so';
  const tuple = `${platform}_cjnative`;
  const required = [`runtime/lib/${tuple}/libcangjie-runtime.${suffix}`,
    `runtime/lib/${tuple}/libboundscheck.${suffix}`, `lib/${tuple}/libcangjie-runtime.a`];
  for (const relative of required) {
    assert.ok(fs.existsSync(path.join(installRoot, relative)), `NATIVE_RUNTIME_INSTALL_MISSING: ${relative}`);
  }
  const cache = fs.readFileSync(path.join(source, 'runtime/CMakebuild/CMakeCache.txt'), 'utf8');
  const cacheValue = key => new RegExp(`^${key}:[^=]+=(.*)$`, 'm').exec(cache)?.[1];
  const normalize = value => process.platform === 'win32' && value ? path.normalize(value).toLowerCase() : value;
  assert.ok(path.isAbsolute(env.SCCACHE_PATH || ''), 'NATIVE_RUNTIME_CACHE_PATH');
  assert.equal(normalize(cacheValue('CANGJIE_COMPILER_CACHE')), normalize(env.SCCACHE_PATH),
    'NATIVE_RUNTIME_CACHE_MISMATCH: CANGJIE_COMPILER_CACHE');
  const compilerCache = {};
  for (const language of ['C', 'CXX']) {
    const key = `CMAKE_${language}_COMPILER_LAUNCHER`, launcher = cacheValue(key);
    const compiler = cacheValue(`CMAKE_${language}_COMPILER`);
    if (launcher) {
      // Preserve the configured launcher contract, including rejecting lists or
      // a different launcher instead of silently falling back to a wrapper.
      assert.equal(normalize(launcher), normalize(env.SCCACHE_PATH), `NATIVE_RUNTIME_CACHE_MISMATCH: ${key}`);
      compilerCache[language] = {mode:'launcher', launcher, ...(compiler ? {compiler} : {})};
    } else {
      // ccache's documented compiler-name symlinks are an alternative producer
      // shape. A directory or basename alone is not proof: the executable must
      // resolve to the very cache selected in this CMake configuration.
      const names = language === 'C' ? /^(?:[\w.+-]+-)?(?:cc|gcc|clang)(?:-\d+(?:\.\d+)*)?$/
        : /^(?:[\w.+-]+-)?(?:c\+\+|g\+\+|clang\+\+)(?:-\d+(?:\.\d+)*)?$/;
      let wrapper = false;
      if (process.platform !== 'win32' && path.isAbsolute(compiler || '') && names.test(path.basename(compiler))) {
        try {
          fs.accessSync(compiler, fs.constants.X_OK);
          wrapper = fs.realpathSync(compiler) === fs.realpathSync(env.SCCACHE_PATH);
        } catch { /* An absent or broken wrapper is a configuration mismatch. */ }
      }
      assert.ok(wrapper, `NATIVE_RUNTIME_CACHE_MISMATCH: ${key}`);
      compilerCache[language] = {mode:'compiler-wrapper', compiler, cache:env.SCCACHE_PATH};
    }
  }
  const repository=env.RUNTIME_GIT_REPOSITORY || source;
  const sourceRepository=env.RUNTIME_SOURCE_REPOSITORY || await runtimeSourceRepository(repository);
  const configuration={buildType,version,hostVersion:env.CJCJ_NATIVE_HOST_VERSION||version,pairedLlvmCommit:env.LLVM_SHA};
  const artifacts=[required[0],required[2]];
  const stamps=embeddedStamp(fs.readFileSync(path.join(installRoot,artifacts[0])),'CJRT-COMMIT');
  let runtimeInputs;
  if(stamps.length===1&&/^src-[0-9a-f]{64}$/.test(stamps[0])) {
    runtimeInputs=await recordRuntimeInputs({repository,sourceRepository,commit:actualRef,sourceRoot:path.join(source,'runtime'),
      install:installRoot,artifacts,configuration,work:installRoot});
  } else {
    assert.deepEqual(stamps,[actualRef],'NATIVE_RUNTIME_SOURCE_STAMP');
    for(const relative of artifacts)assert.deepEqual(embeddedStamp(fs.readFileSync(path.join(installRoot,relative)),'CJRT-COMMIT'),[actualRef],'NATIVE_RUNTIME_PAIR_STAMP');
    runtimeInputs={source:{status:'resolved',repository:sourceRepository,commit:actualRef},embedded_stamp:'CJRT-COMMIT:'+actualRef,
      build:{configuration},artifacts:artifacts.map(relative=>({path:relative,sha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(installRoot,relative))).digest('hex')}))};
    fs.writeFileSync(path.join(installRoot,RUNTIME_INPUTS),JSON.stringify(runtimeInputs,null,2)+'\n');
  }
  // This is the same producer fact for full builds and normal installation of
  // a completed build. Keep it here so install callers never hand-fill it.
  fs.writeFileSync(path.join(installRoot, 'SOURCE_SHA'), `${actualRef}\n`);
  const files = {};
  function walk(directory) {
    for (const entry of fs.readdirSync(directory, {withFileTypes:true})) {
      const file = path.join(directory, entry.name);
      const relative = path.relative(installRoot, file).split(path.sep).join('/');
      if (entry.isDirectory()) walk(file);
      else {
        assert.ok(entry.isFile(), `NATIVE_RUNTIME_INSTALL_NOT_REGULAR: ${relative}`);
        if (relative !== 'NATIVE-INPUTS.json') files[relative] = crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
      }
    }
  }
  walk(installRoot);
  fs.writeFileSync(path.join(installRoot, 'NATIVE-INPUTS.json'), JSON.stringify({
    runtime_sha:actualRef, paired_llvm_sha:env.LLVM_SHA, platform, version, build_type:buildType,
    source:runtimeInputs.source, configuration,
    producer_sha:env.GITHUB_SHA || null, run_id:env.GITHUB_RUN_ID || null,
    run_attempt:env.GITHUB_RUN_ATTEMPT || null, compiler_cache:env.SCCACHE_PATH,
    compiler_cache_configuration:compilerCache,
    language_test_mode:env.GC_UNIT_GATE_LANGUAGE_TESTS || 'all',
    commands:commands || [['python3','build.py','build','--target','native','--build-type',buildType,
      '--prefix', env.RUNNER_TEMP || path.join(path.dirname(installRoot),'runtime-preinstall'), '-v',version],
      ['python3','build.py','install','--prefix',installRoot]], files,
  }, null, 2) + '\n');
}
