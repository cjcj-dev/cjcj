#!/usr/bin/env zx
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileDigest} from '../bootstrap/sdk-flow.mjs';
import {readToolsPin, readCjpmPin} from '../../build/lib/release-component-provenance.mjs';
import {sourceToolPayloads} from './source-tool-payloads.mjs';
import {releaseSelection} from './native-release-inputs.mjs';
import {retainedToolPath} from '../../build/srcbuild/tool-layout.mjs';
import {toolSdkInputs} from '../cangjie-test/tool-readiness.mjs';
import {allTargets, getTarget, getReleasePlatform, allReleasePlatforms} from '../../build/lib/targets.mjs';
const parent = process.env.RELEASE_EVIDENCE_TEST_ROOT;
if (!parent) throw new Error('RELEASE_EVIDENCE_TEST_ROOT required');
const entry = new URL('./compose-package.mjs', import.meta.url).pathname;
const sourceSha = 'a'.repeat(40), runtimeRef = 'b'.repeat(40);
const tools = ['cjpm', 'cjfmt', 'hle', 'LSPServer', 'cjcov', 'cjtrace-recover', 'cjlint', 'cjprof', 'cjcompat'];
test('default and explicit native release selection preserve every platform mapping', () => {
  for (const platform of allTargets()) {
    const {spec} = getTarget(platform);
    const selected = releaseSelection(platform);
    assert.equal(selected.release.key, spec.packageHost.join('-'));
    assert.equal(selected.release.host, platform);
  }
  for (const key of allReleasePlatforms()) {
    const row = getReleasePlatform(key);
    if (row.excluded || row.crossCompiledHost) assert.throws(() => releaseSelection(row.host, key));
    else assert.equal(releaseSelection(row.host, key).release.key, key);
  }
  assert.throws(() => releaseSelection('linux-x64', 'linux-arm64'), /NATIVE_RELEASE_PLATFORM/);
});
async function fixture() {
  await fs.mkdir(parent, {recursive: true});
  const root = await fs.mkdtemp(path.join(parent, 'native-release-')), sdk = root + '/cangjie';
  const write = async (relative, body) => {
    const file = path.join(sdk, relative); await fs.mkdir(path.dirname(file), {recursive: true}); await fs.writeFile(file, body);
  };
  await fs.mkdir(root + '/artifact');
  const compiler = 'unqualified finite input; never a Cangjie compiler\n';
  await write('libexec/compiler/cjcj-stage1', compiler);
  await write('bin/cjc', compiler);
  const compilerSha256 = await fileDigest(sdk + '/libexec/compiler/cjcj-stage1');
  const metadata = {phase: 'stage3', platform: 'linux_x86_64', compilerCommit: sourceSha, runtimeCommit: runtimeRef,
    compilerFile: 'libexec/compiler/cjcj-stage1', compilerSha256};
  await write('STAGE-INPUTS.json', JSON.stringify(metadata));
  await write('compiler-inputs.json', JSON.stringify({commit: sourceSha, compilerSha256}));
  const pins = {tools: await readToolsPin(new URL('../source_pin.env', import.meta.url)),
    cjpm: await readCjpmPin(new URL('../cjpm_pin.env', import.meta.url))};
  const toolInputs = {files: {}, payloadFiles: {}};
  const components = [];
  for (const tool of tools) {
    const relative = 'tools/bin/' + tool, retained = retainedToolPath({producer:tool,name:tool,to:relative});
    await write(relative, 'finite launcher fixture');
    await write(relative + '.entry', `cjcj-sdk-entry-v1\n../..\n${retained}\nlinux\n1\nruntime/lib/linux_x86_64_cjnative\n`);
    await write(retained, 'finite source tool ' + tool);
    const sha256 = await fileDigest(path.join(sdk, retained));
    // Fixture source is deliberately older than the current selector. Release
    // consumes the original producer record and must not relabel it.
    const source = {...pins[tool === 'cjpm' ? 'cjpm' : 'tools'], status:'resolved', commit:'e'.repeat(40)};
    const build = {rc:0, platform:'linux_x86_64', argv:['finite-producer'], environment:{}, inputs:{stage:{runtimeCommit:runtimeRef}}};
    const artifact = {path:retained,sha256}, entry = {path:relative,sha256:await fileDigest(path.join(sdk,relative)),
      recipe:{path:relative+'.entry',sha256:await fileDigest(path.join(sdk,relative+'.entry'))}};
    toolInputs.files[relative] = {sha256, producer:{source,build,artifact:{path:'/original/build/'+tool,sha256}},artifact,entry};
    components.push(structuredClone({component:tool,source,build,artifact,entry}));
    for (const payload of tool === 'cjpm' ? ['tools/config/cangjie-repo.toml'] : sourceToolPayloads(tool)) {
      if (payload === 'tools/dtsparser') await write(payload + '/analysis.js', 'finite parser');
      else if(payload==='.target-tools/tools/cjlint')await write(payload+'/config/cjlint_rule_list.json','finite lint config');
      else if(payload.endsWith('/config/static'))await write(payload+'/index.html','finite prof config');
      else await write(payload, 'finite payload');
    }
  }
  await write('TOOLS-INPUTS.json', JSON.stringify(toolInputs));
  const archive = root + '/artifact/cangjie-sdk-linux-x64-fixture-cjcj.tar.gz';
  async function pack() {
    await write('BUILD-MANIFEST.json', JSON.stringify({target:'linux-x64', version:'fixture',
      consumption:{status:'EXECUTED',platform:'linux_x86_64'}, components,
      inputs:{'TOOLS-INPUTS.json':{path:'TOOLS-INPUTS.json',sha256:await fileDigest(sdk+'/TOOLS-INPUTS.json')}}}));
    const result=spawnSync('tar',['-czf',archive,'-C',root,'cangjie'],{encoding:'utf8'});
    assert.equal(result.status,0,result.stderr);
    await fs.writeFile(archive+'.sha256',await fileDigest(archive)+'  '+path.basename(archive)+'\n');
  }
  const run = async label => {
    const result = spawnSync(process.execPath, [entry], {encoding:'utf8',env:{...process.env,
      NATIVE_SDK_ARTIFACT_DIR:root+'/artifact',NATIVE_SDK_INSTALL_DIR:root+'/install-'+label,
      RELEASE_PLATFORM:'linux-x64',RELEASE_KEY:'linux-x64',CJCJ_NATIVE_SDK_VERSION:'fixture',
      CJCJ_RELEASE_SOURCE_SHA:sourceSha,CJCJ_NATIVE_RUNTIME_REF:runtimeRef,FINAL_STD_DIR:root+'/std',RELEASE_DIST:root+'/dist-'+label}});
    await fs.writeFile(root+'/'+label+'.stdout',result.stdout);await fs.writeFile(root+'/'+label+'.stderr',result.stderr);
    await fs.writeFile(root+'/'+label+'.rc.json',JSON.stringify({rc:result.status,signal:result.signal}));
    console.log(`NATIVE_RELEASE_CLI label=${label} rc=${result.status} evidence=${root}`);return result;
  };
  return {root,sdk,write,pack,run,metadata,toolInputs,components,archive};
}
function reachedNativeDependencies(result) {
  assert.equal(result.status,1,result.stderr);
  const actual = result.stdout.match(/NATIVE_RELEASE_TOOL_FACTS tools=([^\s]+)/)?.[1].split(',');
  assert.deepEqual(actual?.sort(), [...tools].sort(), result.stdout);
  assert.match(result.stderr,/NATIVE_RELEASE_TOOL_DEPENDENCIES cjpm: target build\/install not recorded/);
  assert.doesNotMatch(result.stdout,/NATIVE_RELEASE_(CONSUMED|ARCHIVE)/);
}
test('release uses current native installation selection without relabelling its old build; CJ pairing stays bound',async()=>{
  const f=await fixture();
  const originals={};
  for(const tool of ['LSPServer']) {
    const build=f.toolInputs.files['tools/bin/'+tool].producer.build;
    build.inputs.stage.runtimeCommit='f'.repeat(40);
    f.components.find(row=>row.component===tool).build=structuredClone(build);
    originals[tool]=structuredClone(build);
  }
  f.toolInputs.installationInputs={stage:f.metadata,artifacts:{}};
  await f.write('TOOLS-INPUTS.json',JSON.stringify(f.toolInputs));await f.pack();
  console.log('RELEASE_INSTALLED_NATIVE_SELECTION_TARGET_BEGIN');
  reachedNativeDependencies(await f.run('current-native-install'));
  for(const tool of ['LSPServer'])assert.deepEqual(f.toolInputs.files['tools/bin/'+tool].producer.build,originals[tool]);
  const cj=f.toolInputs.files['tools/bin/cjpm'].producer.build;
  cj.inputs.stage.runtimeCommit='f'.repeat(40);f.components.find(row=>row.component==='cjpm').build=structuredClone(cj);
  await f.write('TOOLS-INPUTS.json',JSON.stringify(f.toolInputs));await f.pack();
  const rejected=await f.run('wrong-cj-pair');assert.match(rejected.stderr,/NATIVE_RELEASE_TOOL_RUNTIME cjpm/);
});
test('whole SDK CLI reaches real dependency guard, rejects source change, restores; digest is independent',async()=>{
  const f=await fixture();await f.pack();reachedNativeDependencies(await f.run('normal'));
  await f.write('STAGE-INPUTS.json',JSON.stringify({...f.metadata,compilerCommit:'c'.repeat(40)}));await f.pack();
  const wrong=await f.run('wrong-source');assert.equal(wrong.status,1);assert.match(wrong.stderr,/NATIVE_RELEASE_SOURCE_MISMATCH/);
  assert.doesNotMatch(wrong.stdout,/NATIVE_RELEASE_INPUTS/);
  await f.write('STAGE-INPUTS.json',JSON.stringify(f.metadata));await f.pack();reachedNativeDependencies(await f.run('restored'));
  await fs.appendFile(f.archive,'changed transport');const digest=await f.run('wrong-digest');assert.match(digest.stderr,/NATIVE_SDK_ARCHIVE_DIGEST/);
});
for(const tool of tools)test(`whole SDK CLI requires produced ${tool} bytes and source, with restoration`,async()=>{
  const f=await fixture();const retained=retainedToolPath({producer:tool,name:tool,to:'tools/bin/'+tool});
  await fs.rm(path.join(f.sdk,retained));await f.pack();
  const missing=await f.run('missing');assert.equal(missing.status,1);assert.match(missing.stderr,new RegExp('NATIVE_RELEASE_TOOL_MISSING '+tool));
  await f.write(retained,'wrong tool bytes');await f.pack();const wrong=await f.run('wrong-bytes');
  assert.match(wrong.stderr,new RegExp('NATIVE_RELEASE_TOOL_BYTES '+tool));
  await f.write(retained,'finite source tool '+tool);
  const original=f.toolInputs.files['tools/bin/'+tool].producer.source;
  f.toolInputs.files['tools/bin/'+tool].producer.source={...original,commit:'d'.repeat(40)};
  await f.write('TOOLS-INPUTS.json',JSON.stringify(f.toolInputs));await f.pack();
  const identity=await f.run('wrong-source');assert.match(identity.stderr,new RegExp('NATIVE_RELEASE_TOOL_SOURCE '+tool));
  f.toolInputs.files['tools/bin/'+tool].producer.source={status:'unresolved',reason:'original build record missing'};
  await f.write('TOOLS-INPUTS.json',JSON.stringify(f.toolInputs));await f.pack();
  assert.match((await f.run('unresolved-source')).stderr,new RegExp('NATIVE_RELEASE_TOOL_SOURCE '+tool));
  f.toolInputs.files['tools/bin/'+tool].producer.source=original;
  const build=f.toolInputs.files['tools/bin/'+tool].producer.build;
  f.toolInputs.files['tools/bin/'+tool].producer.build={...build,rc:1};
  await f.write('TOOLS-INPUTS.json',JSON.stringify(f.toolInputs));await f.pack();
  assert.match((await f.run('failed-build')).stderr,new RegExp('NATIVE_RELEASE_TOOL_BUILD '+tool));
  const wrongRuntime={...build,inputs:{...build.inputs,stage:{...build.inputs.stage,runtimeCommit:'f'.repeat(40)}}};
  f.toolInputs.files['tools/bin/'+tool].producer.build=wrongRuntime;
  f.components.find(row=>row.component===tool).build=structuredClone(wrongRuntime);
  await f.write('TOOLS-INPUTS.json',JSON.stringify(f.toolInputs));await f.pack();
  const changedRuntime=await f.run('wrong-runtime');
  console.log('RELEASE_RUNTIME_DEPENDENCY_ASSERTION_REACHED '+tool);
  if(toolSdkInputs(tool).includes('runtime'))assert.match(changedRuntime.stderr,new RegExp('NATIVE_RELEASE_TOOL_RUNTIME '+tool));
  else reachedNativeDependencies(changedRuntime); // Native reuse still must reach the real installed-dependency gate.
  f.toolInputs.files['tools/bin/'+tool].producer.build=build;
  f.components.find(row=>row.component===tool).build=structuredClone(build);
  await f.write('TOOLS-INPUTS.json',JSON.stringify(f.toolInputs));await f.pack();reachedNativeDependencies(await f.run('restored'));
});

// Public compose/verify consumer: text fixtures stop at the real installed-dependency guard.
// Different build/install bytes model an allowed native install transformation;
// this does not claim that these fixture files are executable tools.
test('public release consumes install bytes, retains raw facts, and rejects incomplete install',async()=>{
  const f=await fixture(),row=f.toolInputs.files['tools/bin/cjcompat'];
  const raw=f.root+'/raw-cjcompat';await fs.writeFile(raw,'finite raw input before native install transformation');
  row.producer.artifact={path:raw,sha256:await fileDigest(raw)};
  row.producer.install={rc:0,argv:['build.py','install','--prefix','dist'],artifact:structuredClone(row.artifact)};
  assert.notEqual(row.producer.artifact.sha256,row.producer.install.artifact.sha256);
  const install=structuredClone(row.producer.install);
  const save=async()=>{await f.write('TOOLS-INPUTS.json',JSON.stringify(f.toolInputs));await f.pack();};
  await save();reachedNativeDependencies(await f.run('install-transformed'));
  for(const [label,change]of [
    ['wrong-installed-bytes',()=>{row.producer.install.artifact=structuredClone(row.producer.artifact);}],
    ['failed-install',()=>{row.producer.install.rc=1;}],
    ['missing-install-artifact',()=>{delete row.producer.install.artifact;}],
  ]) {
    row.producer.install=structuredClone(install);change();await save();
    const result=await f.run(label);assert.equal(result.status,1);
    assert.match(result.stderr,/NATIVE_RELEASE_TOOL_INSTALL cjcompat/);
    assert.doesNotMatch(result.stdout,/NATIVE_RELEASE_INPUTS/);
  }
  row.producer.install=structuredClone(install);await save();reachedNativeDependencies(await f.run('install-restored'));
  // Existing records with no separate install remain valid only with unchanged
  // bytes. Partial/failed new records must never silently use this legacy arm.
  row.producer.artifact=structuredClone(row.artifact);delete row.producer.install;
  await save();reachedNativeDependencies(await f.run('legacy-unchanged-control'));
  row.producer.install={rc:0};await save();
  assert.match((await f.run('partial-cannot-fallback')).stderr,/NATIVE_RELEASE_TOOL_INSTALL cjcompat/);
  delete row.producer.install;await save();reachedNativeDependencies(await f.run('legacy-restored'));
});
