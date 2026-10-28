#!/usr/bin/env zx
// Native build.py/install integration; records actual installed files, not SDK qualification.
import fs from 'node:fs';
import {nativeSourceSelection} from '../bootstrap/native-source-selection.mjs';
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

// The gate already records the exact linked ELF and library paths before
// running cases. Keep those libraries beside that ELF for the existing always
// upload, including when build.py exits before install. Do not select another
// configuration, strip debug information, or recompute its recorded identity.
export function retainNativeGateLibraries(source) {
  const runtime = path.resolve(source, 'runtime');
  const runs = path.join(runtime, 'tests/gc_unit/build_standalone/gate-runs');
  if (!fs.existsSync(runs)) {
    console.log('NATIVE_GATE_LIBRARIES_NOT_RECORDED: no gate run directory');
    return;
  }
  let failed = false;
  for (const entry of fs.readdirSync(runs, {withFileTypes:true})) {
    if (!entry.isDirectory()) continue;
    const run = path.join(runs, entry.name), identity = path.join(run, 'test-artifacts.sha256');
    if (!fs.existsSync(identity)) {
      console.log(`NATIVE_GATE_LIBRARIES_NOT_RECORDED: ${identity}`);
      continue;
    }
    const record = {identity, files:[], error:null};
    try {
      const rows = fs.readFileSync(identity, 'utf8').trim().split(/\r?\n/).map(line => {
        const match = /^([a-f0-9]{64}) [ *](.+)$/.exec(line);
        assert.ok(match, 'NATIVE_GATE_IDENTITY_LINE');
        return {recordedSha256:match[1], source:match[2]};
      });
      const names = ['cj_gc_unit', 'cj_gc_forwarding_publication_unit', 'libcangjie-runtime.so', 'libboundscheck.so'];
      for (const name of names) {
        const selected = rows.filter(row => path.basename(row.source) === name);
        assert.equal(selected.length, 1, `NATIVE_GATE_IDENTITY_MISSING: ${name}`);
        const row = selected[0], real = fs.realpathSync(row.source);
        const relative = path.relative(fs.realpathSync(runtime), real);
        assert.ok(relative && !relative.startsWith('..' + path.sep) && !path.isAbsolute(relative),
          `NATIVE_GATE_SOURCE_OUTSIDE_RUNTIME: ${row.source}`);
        assert.ok(fs.statSync(real).isFile(), `NATIVE_GATE_NOT_FILE: ${row.source}`);
        const library = name.endsWith('.so');
        if (!library) assert.equal(path.resolve(row.source), path.join(run, name), 'NATIVE_GATE_ELF_RUN_MISMATCH');
        const retained = library ? path.join(run, 'selected-libraries', name) : row.source;
        if (library) {
          fs.mkdirSync(path.dirname(retained), {recursive:true});
          fs.copyFileSync(real, retained);
        }
        record.files.push({...row, retained, bytes:fs.statSync(retained).size});
      }
    } catch (error) {
      record.error = error.message;
      failed = true;
    }
    fs.writeFileSync(path.join(run, 'selected-libraries.json'), JSON.stringify(record, null, 2) + '\n');
    console.log('NATIVE_GATE_LIBRARIES ' + JSON.stringify(record));
  }
  assert.ok(!failed, 'NATIVE_GATE_LIBRARY_RETENTION_FAILED');
}

export function configureNativeRuntime({runtimeTarget,selection}, env = process.env) {
  selection??=nativeSourceSelection(env).selection;
  const windows = hostPlatform() === 'windows_x86_64';
  assert.ok(windows ? runtimeTarget === 'windows-x86_64'
    : runtimeTarget === 'native' && /^(linux|darwin)_(x86_64|aarch64)$/.test(hostPlatform()),
    'NATIVE_RUNTIME_HOST_UNSUPPORTED');
  assert.equal(env.NATIVE_RUNTIME_PLATFORM, hostPlatform(), 'NATIVE_RUNTIME_PLATFORM_MISMATCH');
  assert.ok(sha(selection.llvm.commit) && sha(selection.runtime.commit), 'NATIVE_RUNTIME_PAIR_REQUIRED');
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

// The main install and configure-time CJThread install are separate CMake
// graphs. Transfer their actual installed archives and linked bounds target
// through one normal CMake install component; never substitute a stale SDK.
export function installNativeRuntimeDependencies({source, installRoot, buildType}) {
  const runtime = path.resolve(source, 'runtime'), build = path.join(runtime, 'CMakebuild');
  const tuple = `${hostPlatform()}_cjnative`;
  const cache = directory => {
    const text = fs.readFileSync(path.join(directory, 'CMakeCache.txt'), 'utf8');
    return key => new RegExp(`^${key}:[^=]+=(.*)$`, 'm').exec(text)?.[1]?.trim();
  };
  const parent = cache(build), childBuild = path.join(build, 'cjthread-build'), child = cache(childBuild);
  const samePath = (a,b) => path.resolve(a || '') === path.resolve(b);
  assert.ok(samePath(parent('CMAKE_HOME_DIRECTORY'), runtime), 'NATIVE_RUNTIME_BUILD_SOURCE');
  assert.ok(samePath(child('CMAKE_HOME_DIRECTORY'), path.join(runtime,'src/CJThread')), 'NATIVE_CJTHREAD_BUILD_SOURCE');
  const prefix = child('CMAKE_INSTALL_PREFIX');
  assert.ok(path.isAbsolute(prefix || ''), 'NATIVE_CJTHREAD_INSTALL_PREFIX');
  assert.ok(samePath(parent('CMAKE_INSTALL_PREFIX'), prefix), 'NATIVE_CJTHREAD_PARENT_PREFIX');
  assert.equal(child('TARGET_ARCH'), tuple, 'NATIVE_CJTHREAD_INSTALL_TARGET');
  for (const value of [parent,child])
    assert.equal(value('CMAKE_BUILD_TYPE')?.toLowerCase(), buildType.toLowerCase(), 'NATIVE_CJTHREAD_INSTALL_CONFIGURATION');
  const manifest = fs.readFileSync(path.join(childBuild,'install_manifest.txt'),'utf8').trim().split(/\r?\n/).map(file=>path.resolve(file));
  const archives = ['thread','aio'].map(name => {
    const file = path.join(prefix,'lib',tuple,`libcangjie-${name}.a`);
    assert.ok(manifest.includes(path.resolve(file)), `NATIVE_CJTHREAD_INSTALL_MANIFEST: ${file}`);
    assert.ok(fs.existsSync(file) && fs.lstatSync(file).isFile(), `NATIVE_CJTHREAD_INSTALL_MISSING: ${file}`);
    return file;
  });
  const arch = {x64:'x86_64',arm64:'aarch64'}[process.arch];
  const mode = buildType[0].toUpperCase() + buildType.slice(1).toLowerCase();
  const windows = process.platform === 'win32', suffix = windows ? 'dll' : process.platform === 'darwin' ? 'dylib' : 'so';
  const bounds = path.join(build,'runtime-staging',windows?'bin':'lib',`${arch}_${mode}`,`libboundscheck.${suffix}`);
  assert.ok(fs.existsSync(bounds) && fs.lstatSync(bounds).isFile(), `NATIVE_RUNTIME_BUILD_MISSING: ${bounds}`);
  const links = fs.readFileSync(path.join(build,'runtime-link-inputs.txt'),'utf8').trim().split(/\r?\n/);
  const link = target => {
    const matches = links.filter(file=>file.replaceAll('\\','/').includes(`/CMakeFiles/${target}.dir/`));
    assert.equal(matches.length,1,`NATIVE_RUNTIME_LINK_TARGET: ${target}`);
    return {file:matches[0],text:fs.readFileSync(matches[0],'utf8').replaceAll('\\','/')};
  };
  const producer = link('boundscheck'), consumer = link('cangjie-runtime');
  const binaryDirectory = path.dirname(path.dirname(producer.file));
  assert.ok([bounds,path.relative(build,bounds),path.relative(binaryDirectory,bounds)]
    .some(file=>producer.text.includes(file.replaceAll('\\','/'))), 'NATIVE_BOUNDS_PRODUCER_OUTPUT');
  assert.match(consumer.text, /(?:libboundscheck|(?:^|\s)-lboundscheck)(?:[.\s]|$)/, 'NATIVE_BOUNDS_RUNTIME_LINK');
  const project = fileURLToPath(new URL('./native_runtime_dependencies/',import.meta.url));
  const installer = path.resolve(installRoot)+'.dependencies';
  const run = args => {
    const result = spawnSync('cmake',args,{stdio:'inherit'});
    console.log('native_runtime_dependency_command='+JSON.stringify({argv:['cmake',...args],rc:result.status,signal:result.signal,error:result.error?.message}));
    assert.equal(result.signal,null,'NATIVE_RUNTIME_DEPENDENCY_INSTALL_SIGNAL');
    assert.equal(result.status,0,'NATIVE_RUNTIME_DEPENDENCY_INSTALL_FAILED');
  };
  run(['-S',project,'-B',installer,'-DCMAKE_TOOLCHAIN_FILE=',
    '-DCJ_RUNTIME_TUPLE='+tuple,'-DCJ_THREAD_ARCHIVE='+archives[0],'-DCJ_AIO_ARCHIVE='+archives[1],'-DCJ_BOUNDS_LIBRARY='+bounds]);
  run(['--install',installer,'--prefix',path.resolve(installRoot),'--component','native-runtime-dependencies']);
}

// Normal native build/install carries the actual test sources, generated
// headers and compile command used by the later installed language gate.
export function installNativeRuntimeInputs({source,installRoot,gateStatus,selection}) {
  if(process.platform!=='linux')return;
  const config=buildConfig({targetKey:process.arch==='arm64'?'linux-aarch64':'linux-x64',nativeSelection:selection});
  installGcUnitInputs(config,path.join(source,'runtime'),installRoot,{gateStatus});
}

export async function recordNativeRuntime({source, installRoot, actualRef, version, buildType, commands,selection,repository=source}, env = process.env) {
  selection??=nativeSourceSelection(env).selection;
  assert.equal(actualRef, selection.runtime.commit, 'NATIVE_RUNTIME_SOURCE_MISMATCH');
  if (process.platform === 'win32') assert.ok(Array.isArray(commands) && commands.length > 0, 'NATIVE_RUNTIME_COMMANDS_REQUIRED');
  const platform = hostPlatform();
  const suffix = process.platform === 'darwin' ? 'dylib' : process.platform === 'win32' ? 'dll' : 'so';
  const tuple = `${platform}_cjnative`;
  const required = [`runtime/lib/${tuple}/libcangjie-runtime.${suffix}`,
    `runtime/lib/${tuple}/libboundscheck.${suffix}`, `lib/${tuple}/libcangjie-runtime.a`,
    `lib/${tuple}/libcangjie-thread.a`, `lib/${tuple}/libcangjie-aio.a`];
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
  const sourceRepository=await runtimeSourceRepository(repository);
  const configuration={buildType,version,hostVersion:env.CJCJ_NATIVE_HOST_VERSION||version,pairedLlvmCommit:selection.llvm.commit};
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
    runtime_sha:actualRef, paired_llvm_sha:selection.llvm.commit, platform, version, build_type:buildType,
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

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv[2], 'retain-gate', 'expected retain-gate <runtime source>');
  assert.ok(process.argv[3], 'runtime source required');
  retainNativeGateLibraries(process.argv[3]);
}
