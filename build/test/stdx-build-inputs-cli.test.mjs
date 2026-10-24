#!/usr/bin/env zx
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {STDX_BUILD_INPUTS} from '../srcbuild/stdx-build-inputs.mjs';
import {readInstalledStdxInputs} from '../lib/installed-stdx-inputs.mjs';
import {installedInputs} from '../../ci/srcbuild/lib/installed-inputs.mjs';
import {writeInstalledReleaseManifest} from '../lib/release-manifest.mjs';
import {fixture, tuple, run} from './fixtures/stdx-native.mjs';

function executorFixture(t) {
  const f = fixture(t), contract = process.env.STDX_HOST_CONTRACT_FILE;
  assert(contract && path.isAbsolute(contract), 'STDX_HOST_CONTRACT_FILE: fixed b107 MakeHostCJNATIVESharedLib.cmake');
  fs.copyFileSync(contract, path.join(f.stdx, 'MakeHostCJNATIVESharedLib.cmake'));
  fs.mkdirSync(path.join(f.host, 'bin'), {recursive:true});
  fs.copyFileSync(path.join(f.sdk, 'bin/cjc'), path.join(f.host, 'bin/cjc'));
  for (const sdk of [f.sdk, f.host]) {
    const cjc = path.join(sdk, 'bin/cjc');
    fs.writeFileSync(cjc, fs.readFileSync(cjc, 'utf8').replace('#!/bin/sh\n',
      '#!/bin/sh\nprintf "%s %s\\n" "$0" "$CANGJIE_HOME" >> "$FIXTURE_EXECUTOR_TRACE"\n'));
  }
  const py = path.join(f.stdx, 'build.py');
  fs.writeFileSync(py, fs.readFileSync(py, 'utf8')
    .replace("build=pathlib.Path('build_temp/build')", `build=pathlib.Path('build_temp/build')
with (root/'executor-env.jsonl').open('a') as stream:
 stream.write(json.dumps(dict(phase=sys.argv[1],macro=os.environ.get('STDX_HOST_CANGJIE_HOME'),baseline=os.environ.get('CJCJ_SRCBUILD_HOST_SDK'),home=os.environ.get('CANGJIE_HOME'),cjc=shutil.which('cjc')))+'\\n')`)
    .replace('if not build.exists():', "if not build.exists() or os.environ.get('CANGJIE_SCHEMA_DIR'):"));
  fs.appendFileSync(path.join(f.stdx, 'CMakeLists.txt'), `
include(\${CMAKE_CURRENT_SOURCE_DIR}/MakeHostCJNATIVESharedLib.cmake)
if(STDX_HOST_CLOSURE_ENABLED)
  add_custom_target(selected_macro_executor ALL COMMAND "\${STDX_HOST_CJC}" --macro-probe VERBATIM)
endif()
if(DEFINED ENV{FIXTURE_EXECUTOR_FAIL_CONFIGURE})
  message(FATAL_ERROR "EXECUTOR_CONFIGURE_FAILURE")
endif()
`);
  f.freezeSource();
  const schema = path.join(f.root, 'schema'); fs.mkdirSync(schema);
  const env = {CANGJIE_SCHEMA_DIR:schema, FIXTURE_EXECUTOR_TRACE:path.join(f.root, 'executor-trace.txt')};
  const rows = () => fs.readFileSync(path.join(f.root, 'executor-env.jsonl'), 'utf8').trim().split('\n').map(JSON.parse);
  return {...f, executorEnv:env, executorRows:rows};
}

const read = root => JSON.parse(fs.readFileSync(path.join(root, STDX_BUILD_INPUTS), 'utf8'));
const successful = result => assert.equal(result.status, 0, result.stdout + '\n' + result.stderr);
function inspectProducts(root, facts) {
  for (const artifact of facts.artifacts) {
    assert.ok(!path.isAbsolute(artifact.path)); assert.ok(!artifact.path.split('/').includes('..'));
    const bytes = fs.readFileSync(path.join(root, artifact.path));
    assert.equal(bytes.length, artifact.size);
  }
}

test('public full producer carries actual source, native configuration and installed products through relocation', t => {
  const f = fixture(t); successful(f.build());
  console.log('STDX_FIRST_CONFIGURE_ASSERT_REACHED');
  successful(f.build(['--stdx-build-mode','incremental']));
  successful(f.build());
  console.log('STDX_FACTS_PUBLICATION_ASSERT_REACHED');
  const facts = read(f.sdk);
  console.log('STDX_FACTS_SOURCE_ASSERT_REACHED');
  assert.equal(facts.source.commit, f.commit);
  assert.equal(facts.source.repository, 'https://gitcode.com/Cangjie/cangjie_stdx.git');
  assert.equal(facts.build.requestedProfile, 'full');
  assert.equal(facts.build.rc, 0); assert.equal(facts.install.rc, 0);
  assert.equal(facts.build.configuration.values.CANGJIE_BUILD_WITHOUT_CHIR, 'OFF');
  console.log('STDX_FACTS_ARTIFACTS_ASSERT_REACHED');
  assert.equal(facts.artifacts.length, 24, 'inventory must contain actual full native installation');
  inspectProducts(f.sdk, facts);
  const archive = path.join(f.root, 'installation.tar');
  run('tar', ['-cf', archive, '-C', f.sdk, '.']);
  fs.renameSync(f.sdk, f.sdk + '.unreachable');
  const unpack = path.join(f.root, 'unpacked'); fs.mkdirSync(unpack);
  run('tar', ['-xf', archive, '-C', unpack]);
  assert.deepEqual(read(unpack), facts); inspectProducts(unpack, read(unpack));
  const lib = path.join(unpack, 'stdx', tuple, 'dynamic/stdx');
  const executable = path.join(f.root, 'consumer');
  run('cc', ['-x', 'c', '-', '-L' + lib, '-lbase_shared', '-Wl,-rpath,' + lib, '-o', executable],
    {input: '#include <stdio.h>\nint stdx_fixture_value(void); int main(void){printf("%d\\n",stdx_fixture_value());}\n'});
  assert.equal(run(executable, []).stdout.trim(), '42');
});

test('public sdk-tools producer records its actual subset configuration in its own installation', t => {
  const f = fixture(t); successful(f.build(['--stdx-profile', 'sdk-tools']));
  console.log('STDX_SUBSET_FACTS_ASSERT_REACHED');
  assert.equal(fs.existsSync(path.join(f.sdk, STDX_BUILD_INPUTS)), false);
  const target = path.join(f.stdx, 'target'), facts = read(target);
  assert.equal(facts.build.requestedProfile, 'sdk-tools');
  assert.ok(facts.build.argv.includes('--skip-chir'));
  assert.equal(facts.build.configuration.values.CANGJIE_BUILD_WITHOUT_CHIR, 'ON');
  assert.equal(facts.artifacts.length, 4); inspectProducts(target, facts);
  assert.ok(facts.artifacts.every(artifact => !artifact.path.includes('chir')));
});

for (const [phase, rc] of [['CONFIGURE', 25], ['BUILD', 23], ['INSTALL', 24]]) {
  test(`public failed ${phase.toLowerCase()} invalidates prior installed success and preserves it`, t => {
    const f = fixture(t); successful(f.build());
    const before = fs.readFileSync(path.join(f.sdk, STDX_BUILD_INPUTS));
    const result = f.build([], {['FIXTURE_FAIL_' + phase]: '1'});
    console.log('STDX_FAILED_' + phase + '_ASSERT_REACHED');
    // The public CLI maps a BuildError to 1; retain the child producer's own
    // 23/24 from the runner diagnostic instead of conflating parent/child rc.
    assert.equal(result.status, 1, result.stderr);
    assert.match(result.stderr, new RegExp('\\(exit=' + rc + '\\)'));
    assert.equal(fs.existsSync(path.join(f.sdk, STDX_BUILD_INPUTS)), false);
    const directory = path.dirname(path.join(f.sdk, STDX_BUILD_INPUTS));
    const previous = fs.readdirSync(directory).find(name => name.startsWith('stdx.json.previous-'));
    assert.ok(previous); assert.deepEqual(fs.readFileSync(path.join(directory, previous)), before);
    if (phase === 'INSTALL') {
      const built = JSON.parse(fs.readFileSync(path.join(f.root, 'build/stdx/build-inputs.json')));
      assert.equal(built.build.rc, 0); assert.equal(built.install, undefined);
    }
  });
}

test('actual CMake subset configuration cannot be reported as a requested full build', t => {
  const f = fixture(t);
  const cmake = path.join(f.stdx, 'CMakeLists.txt');
  fs.appendFileSync(cmake, '\nset(CANGJIE_BUILD_WITHOUT_CHIR ON CACHE BOOL "forced subset" FORCE)\n');
  f.freezeSource();
  const result = f.build();
  console.log('STDX_EFFECTIVE_CONFIG_ASSERT_REACHED');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /effective configuration mismatch: CANGJIE_BUILD_WITHOUT_CHIR=ON/);
  assert.equal(fs.existsSync(path.join(f.sdk, STDX_BUILD_INPUTS)), false);
});

test('installed facts and release rows carry full native stdx through an unavailable old root', async t => {
 const f=fixture(t);successful(f.build());
 const facts=await readInstalledStdxInputs({sdk:f.sdk,platform:'linux_x86_64',requireFull:true});
 const installed=await installedInputs(f.sdk,'linux_x86_64');
 assert.deepEqual(installed.components.find(row=>row.component==='stdx'),facts);
 assert.ok(installed.inputs[STDX_BUILD_INPUTS]);
 const release=await writeInstalledReleaseManifest({stage:f.sdk,platform:'linux_x86_64',...installed});
 assert.equal(release.rows.find(row=>row.component==='stdx').source.commit,f.commit);
 const archive=path.join(f.root,'consumer-facts.tar');run('tar',['-cf',archive,'-C',f.sdk,'.']);
 fs.renameSync(f.sdk,f.sdk+'.parked');const unpack=path.join(f.root,'consumer-unpacked');fs.mkdirSync(unpack);
 run('tar',['-xf',archive,'-C',unpack]);
 assert.deepEqual(await readInstalledStdxInputs({sdk:unpack,platform:'linux_x86_64',requireFull:true}),facts);
 const row=(await installedInputs(unpack,'linux_x86_64')).components.find(row=>row.component==='stdx');assert.deepEqual(row,facts);
 const product=path.join(unpack,facts.artifacts[0].path);fs.renameSync(product,product+'.saved');
 console.log('STDX_CONSUMER_PATH_ASSERT_REACHED');
 await assert.rejects(installedInputs(unpack,'linux_x86_64'),/ENOENT/);
 fs.renameSync(product+'.saved',product);await readInstalledStdxInputs({sdk:unpack,platform:'linux_x86_64',requireFull:true});
});

test('installed consumer rejects subset even when requested profile is relabeled full', async t => {
 const f=fixture(t);successful(f.build(['--stdx-profile','sdk-tools']));
 const sdk=path.join(f.stdx,'target'),file=path.join(sdk,STDX_BUILD_INPUTS),original=fs.readFileSync(file),facts=JSON.parse(original);
 await readInstalledStdxInputs({sdk,platform:'linux_x86_64'});
 facts.build.requestedProfile='full';fs.writeFileSync(file,JSON.stringify(facts));
 console.log('STDX_CONSUMER_FULL_ASSERT_REACHED');
 await assert.rejects(readInstalledStdxInputs({sdk,platform:'linux_x86_64',requireFull:true}),/INSTALLED_STDX_FULL_CONFIGURATION/);
 fs.writeFileSync(file,original);await readInstalledStdxInputs({sdk,platform:'linux_x86_64'});
});

test('failed configure resumes cached dependencies and checks existing and regenerated runtime commands', t => {
  const f = fixture(t);
  const producer = path.join(f.stdx, 'build.py');
  // Fixed stdx 6fd build.py:213 retries configure for an explicit schema input.
  fs.writeFileSync(producer, fs.readFileSync(producer, 'utf8')
    .replace('if not build.exists():', "if not build.exists() or os.environ.get('CANGJIE_SCHEMA_DIR'):"));
  const cmake = path.join(f.stdx, 'CMakeLists.txt');
  fs.appendFileSync(cmake, `
# Keep a real configure-time dependency object across a missing-header failure.
if(NOT EXISTS "\${CMAKE_CURRENT_BINARY_DIR}/dependency.o")
  execute_process(COMMAND "\${CMAKE_C_COMPILER}" -c "\${CMAKE_CURRENT_SOURCE_DIR}/unit.c"
    -o "\${CMAKE_CURRENT_BINARY_DIR}/dependency.o" COMMAND_ERROR_IS_FATAL ANY)
endif()
if(NOT EXISTS "$ENV{FIXTURE_REQUIRED_HEADER}")
  message(FATAL_ERROR "FIXTURE_MISSING_INSTALLED_HEADER")
endif()
`);
  fs.writeFileSync(cmake, fs.readFileSync(cmake, 'utf8').replace(
    'add_custom_target(cj_entry ALL COMMAND',
    `set(entry_runtime "$ENV{LD_LIBRARY_PATH}")
if(DEFINED ENV{FIXTURE_WRONG_RUNTIME})
  set(entry_runtime "$ENV{FIXTURE_WRONG_RUNTIME}")
endif()
add_custom_target(cj_entry ALL COMMAND`).replace(
    '"LD_LIBRARY_PATH=$ENV{LD_LIBRARY_PATH}" cjc', '"LD_LIBRARY_PATH=\${entry_runtime}" cjc'));
  f.freezeSource();
  const header = path.join(f.sdk, 'include/cangjie/recovery.h');
  const schema = path.join(f.root, 'schema'); fs.mkdirSync(schema);
  const env = {CANGJIE_SCHEMA_DIR:schema, FIXTURE_REQUIRED_HEADER:header};
  const inc = ['--stdx-build-mode', 'incremental'];
  const directory = path.join(f.stdx, 'build_temp/build');
  const graph = path.join(directory, 'build.ninja'), object = path.join(directory, 'dependency.o');
  const failed = f.build([], env);
  assert.equal(failed.status, 1); assert.match(failed.stderr, /FIXTURE_MISSING_INSTALLED_HEADER/);
  assert(fs.existsSync(path.join(directory, 'CMakeCache.txt')));
  assert(!fs.existsSync(graph));
  const before = fs.statSync(object), bytes = fs.readFileSync(object);
  const retained = () => {
    const after = fs.statSync(object);
    assert.equal(after.ino, before.ino); assert.equal(after.mtimeMs, before.mtimeMs);
    assert.deepEqual(fs.readFileSync(object), bytes);
  };
  fs.mkdirSync(path.dirname(header), {recursive:true}); fs.writeFileSync(header, '// installed header\n');
  successful(f.build(inc, env)); retained();
  console.log('STDX_CONFIGURE_RECOVERY_ASSERT_REACHED');
  successful(f.build(inc, env)); retained();
  const originalGraph = fs.readFileSync(graph, 'utf8');
  const hostRuntime = path.join(f.host, 'runtime/lib', tuple);
  const wrongRuntime = path.join(f.sdk, 'runtime/lib', tuple);
  assert(originalGraph.includes(hostRuntime));
  const consumer = path.join(f.root, 'consumer.jsonl');
  const beforeConsumer = fs.readFileSync(consumer, 'utf8');
  fs.writeFileSync(graph, originalGraph.replaceAll(hostRuntime, wrongRuntime));
  try {
    const wrong = f.build(inc, env);
    assert.equal(wrong.status, 1); assert.match(wrong.stderr, /generated cjc command selects wrong runtime/);
    assert.equal(fs.readFileSync(consumer, 'utf8'), beforeConsumer, 'existing bad graph rejected before build.py');
    console.log('STDX_EXISTING_RUNTIME_REJECTION_ASSERT_REACHED');
  } finally {fs.writeFileSync(graph, originalGraph);}
  const generatedWrong = f.build(inc, {...env, FIXTURE_WRONG_RUNTIME:wrongRuntime});
  assert.equal(generatedWrong.status, 1);
  assert.match(generatedWrong.stderr, /generated cjc command selects wrong runtime/);
  assert.notEqual(fs.readFileSync(consumer, 'utf8'), beforeConsumer, 'native reconfigure actually ran');
  assert(!fs.existsSync(path.join(f.sdk, STDX_BUILD_INPUTS)), 'wrong generated graph cannot publish install success');
  console.log('STDX_GENERATED_RUNTIME_REJECTION_ASSERT_REACHED');
  // Restore this controlled graph fault; the normal producer regenerates it.
  fs.writeFileSync(graph, originalGraph);
  successful(f.build(inc, env)); retained();
  assert.equal(read(f.sdk).build.mode, 'incremental');
  console.log('STDX_CACHE_RESTORED_ASSERT_REACHED');
});

test('explicit stdx macro executor reaches first incremental recovery and install children', t => {
  const f = executorFixture(t), inc = ['--stdx-build-mode','incremental'];
  const env = {...f.executorEnv, STDX_HOST_CANGJIE_HOME:f.sdk};
  successful(f.build([], env));
  successful(f.build(inc, env));
  const failed = f.build([], {...env, FIXTURE_EXECUTOR_FAIL_CONFIGURE:'1'});
  assert.equal(failed.status, 1); assert.match(failed.stderr, /EXECUTOR_CONFIGURE_FAILURE/);
  assert(!fs.existsSync(path.join(f.stdx, 'build_temp/build/build.ninja')));
  successful(f.build(inc, env));
  assert.equal(read(f.sdk).build.environment.STDX_HOST_CANGJIE_HOME, f.sdk);
  const selected = f.executorRows().filter(row => ['build','install'].includes(row.phase));
  assert(selected.some(row => row.phase === 'install'));
  for (const row of selected) {
    assert.equal(row.macro, f.sdk); assert.equal(row.baseline, f.host);
    assert.equal(row.home, f.sdk); assert.equal(row.cjc, path.join(f.sdk, 'bin/cjc'));
  }
  assert(fs.readFileSync(f.executorEnv.FIXTURE_EXECUTOR_TRACE,'utf8').includes(path.join(f.sdk,'bin/cjc')));
  console.log('EXPLICIT_EXECUTOR_ATTEMPT_BUILD_INSTALL_ASSERT_REACHED');
  const wrong = f.build(inc, {...env, STDX_HOST_CANGJIE_HOME:f.host});
  assert.equal(wrong.status, 1); assert.match(wrong.stderr, /must provide the public cjc selected on PATH/);
  assert(!fs.existsSync(path.join(f.sdk, STDX_BUILD_INPUTS)));
  const missing = f.build(inc, {...env, STDX_HOST_CANGJIE_HOME:path.join(f.root,'missing-home')});
  assert.equal(missing.status, 1); assert.match(missing.stderr, /host cjc not found/);
  // b107's native contract uses explicit empty HOME to disable host closure.
  successful(f.build(inc, {...env, STDX_HOST_CANGJIE_HOME:''}));
  assert.equal(read(f.sdk).build.environment.STDX_HOST_CANGJIE_HOME, '');
  for (const row of f.executorRows().slice(-2)) assert.equal(row.macro, '');
  successful(f.build(inc, env));
  console.log('EXECUTOR_WRONG_MISSING_EMPTY_RESTORE_ASSERT_REACHED');
});

test('unset stdx macro executor retains official host default when PATH selects that host', t => {
  const f = executorFixture(t);
  // Existing non-explicit consumer layout: H precedes the default compiler output.
  fs.mkdirSync(path.join(f.root,'cangjie_compiler'), {recursive:true});
  fs.symlinkSync(f.sdk, path.join(f.root,'cangjie_compiler/output'));
  const env = {...f.executorEnv, STDX_HOST_CANGJIE_HOME:undefined, CJCJ_SRCBUILD_CONSUMER_SDK:''};
  successful(f.build([], env));
  successful(f.build(['--stdx-build-mode','incremental'], env));
  for (const row of f.executorRows().filter(row => ['build','install'].includes(row.phase))) {
    assert.equal(row.macro, f.host); assert.equal(row.baseline, f.host);
    assert.equal(row.cjc, path.join(f.host,'bin/cjc'));
  }
  assert.equal(read(f.sdk).build.environment.STDX_HOST_CANGJIE_HOME, f.host);
  console.log('UNSET_EXECUTOR_DEFAULT_CONTROL_ASSERT_REACHED');
});
