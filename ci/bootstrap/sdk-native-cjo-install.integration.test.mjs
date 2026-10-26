#!/usr/bin/env node
// The compiler kind's real installation path is exercised here: the real
// build_shim.mjs creates the absolute build-tree runtime link and the real
// nativeStage installs the CJO prefix.  The assertion reads what nativeStage
// actually put in share/cjcj/cjo instead of a reimplementation of its copy
// list.  The source tree is a controlled fixture and is not a compiler build.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const stage = fileURLToPath(new URL('./sdk-native-stage.mjs', import.meta.url));
const tuple = 'linux_x86_64_cjnative';

async function writeExecutable(file, body) {
  await fs.mkdir(path.dirname(file), {recursive: true});
  await fs.writeFile(file, body);
  await fs.chmod(file, 0o755);
}

// `produceLink: false` removes the only input the real shim needs to emit the
// link, which makes the same invocation serve as the control arm.
async function runCompilerStage({produceLink = true, explicitHost = false, decoy = false} = {}) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'native-stage-cjo-'));
  const source = path.join(root, 'source'), sdk = path.join(root, 'sdk');
  const runtime = path.join(root, 'runtime'), output = path.join(root, 'output');
  const packageManagerSdk = explicitHost ? path.join(root, 'package-manager-sdk') : path.join(sdk, '.host');
  const target = explicitHost ? path.join(root, 'workspace-target') : path.join(source, 'target');

  await fs.mkdir(path.join(source, 'runtime_shim'), {recursive: true});
  await fs.mkdir(path.join(sdk, 'lib', tuple), {recursive: true});
  await fs.mkdir(path.join(sdk, 'bin'), {recursive: true});
  await fs.mkdir(path.join(sdk, 'tools/bin'), {recursive: true});
  await fs.writeFile(path.join(sdk, 'lib', tuple, 'libcangjie-std-core.a'), 'std archive\n');
  await fs.writeFile(path.join(source, 'cjpm.toml'), 'compile-option = "-O1"\n');
  // The real producer of the build-tree runtime link.
  await fs.copyFile(new URL('../../runtime_shim/build_shim.mjs', import.meta.url),
    path.join(source, 'runtime_shim/build_shim.mjs'));
  // The shim consumes the explicitly installed N object; it still compiles
  // the runtime configuration C source through the normal compiler command.
  await fs.writeFile(path.join(source, 'runtime_shim/cjc_runtime_config.c'),
    'int cjcj_fixture_runtime_config(void) { return 1; }\n');
  await fs.mkdir(path.join(sdk, 'third_party/llvm/fixed-llc'), {recursive:true});
  await fs.writeFile(path.join(sdk, 'third_party/llvm/fixed-llc/cjselfhost_llvmshim.o'),
    'fixture shim object\n');
  // The shim links CANGJIE_HOME/runtime into the build tree, so its absence is
  // what makes the producer silent.
  if (produceLink) {
    await fs.mkdir(path.join(sdk, 'runtime'), {recursive: true});
    await fs.writeFile(path.join(sdk, 'runtime/keep'), 'host runtime\n');
  }

  const packageManager = selected => `#!${process.execPath}
import fs from 'node:fs/promises';
import path from 'node:path';
const args=process.argv.slice(2), target=args.includes('--target-dir')?args[args.indexOf('--target-dir')+1]:'target';
await fs.writeFile('package-manager-observed.json',JSON.stringify({selected:${JSON.stringify(selected)},argv:process.argv.slice(2),sdk:process.env.CANGJIE_HOME,path:process.env.PATH,loader:process.env.LD_LIBRARY_PATH}));
await fs.mkdir(path.join(target,'release/bin'), {recursive: true});
await fs.writeFile(path.join(target,'release/bin/cjcj::cjc'), 'fixture compiler product\\n');
// cjpm also emits the package CJO beside bin; that is the content the CJO
// prefix is supposed to carry.
await fs.mkdir(path.join(target,'release/cjcj'), {recursive: true});
await fs.writeFile(path.join(target,'release/cjcj/parse@cjcj.cjo'), 'fixture cjo payload\\n');
`;
  await writeExecutable(path.join(packageManagerSdk, 'tools/bin/cjpm'),packageManager('selected'));
  if(decoy)await writeExecutable(path.join(sdk, '.host/tools/bin/cjpm'),packageManager('unselected'));
  // stdIdentity reads the std producer's provenance record.
  await fs.writeFile(path.join(sdk, 'PROVENANCE.txt'), 'fixture std provenance\n');
  // ci/test-zx.mjs supplies the actual prepared zx executable through PATH.
  await fs.writeFile(path.join(sdk, 'STAGE-INPUTS.json'), JSON.stringify({compilerFile: 'bin/cjcj-stage1'}));
  await fs.writeFile(path.join(sdk, 'bin/cjcj-stage1'), 'fixture parent compiler identity\n');

  // The native entry verifies the consumed source, for every kind. Give this
  // real shim fixture a real producer revision instead of an invented claim.
  for (const args of [['init', '-q', source], ['-C', source, 'add', '.'],
    ['-C', source, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com',
      'commit', '-qm', 'test: CJO installation source fixture']]) {
    const git = spawnSync('git', args, {encoding: 'utf8'});
    assert.equal(git.status, 0, git.stderr);
  }
  const revision = spawnSync('git', ['-C', source, 'rev-parse', 'HEAD'], {encoding: 'utf8'});
  assert.equal(revision.status, 0, revision.stderr);
  const commit = revision.stdout.trim();
  assert.match(commit, /^[0-9a-f]{40}$/);

  const result = spawnSync(process.execPath, [stage, '--kind', 'compiler', '--source', source, '--sdk', sdk,
    '--runtime', runtime, '--output', output, '--platform', 'linux_x86_64', '--commit', commit,
    '--phase', 'stage2', '--zx', 'zx', '--jobs', '4', '--std-input', sdk,
    ...(explicitHost ? ['--host', packageManagerSdk, '--target-dir', target] : [])],
    {encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
  const sourceRuntime = await fs.lstat(path.join(source, 'target/release/runtime')).catch(() => null);
  const sourceLink = sourceRuntime?.isSymbolicLink()
    ? await fs.readlink(path.join(source, 'target/release/runtime')) : null;
  const cjoRuntime = await fs.lstat(path.join(output, 'share/cjcj/cjo/runtime')).catch(() => null);
  const listing = await fs.readdir(path.join(output, 'share/cjcj/cjo')).catch(() => null);
  const packageCjo = await fs.readdir(path.join(output, 'share/cjcj/cjo/cjcj')).catch(() => null);
  const inputs = await fs.readFile(path.join(output, 'compiler-inputs.json'), 'utf8')
    .then(JSON.parse).catch(error => { if(error.code === 'ENOENT') return null; throw error; });
  const observed=await fs.readFile(path.join(source,'package-manager-observed.json'),'utf8').then(JSON.parse).catch(()=>null);
  return {root, result, listing, packageCjo, sourceLink, cjoRuntime, commit, inputs, observed, sdk, packageManagerSdk, target};
}

async function retainOrRemove(root) {
  console.log('NATIVE_STAGE_CJO_EVIDENCE='+root);
  if(!process.env.SDK_FLOW_TEST_ROOT)await fs.rm(root,{recursive:true,force:true});
}

test('compiler install keeps the build-tree runtime link out of the CJO prefix', async () => {
  const {root, result, listing, packageCjo, sourceLink, cjoRuntime, commit, inputs} = await runCompilerStage();
  try {
    console.log('TARGET_ASSERT_EXECUTED cjo=' + JSON.stringify({
      rc: result.status, listing, packageCjo, sourceLink, cjoRuntime: cjoRuntime?.isSymbolicLink?.() ?? null,
    }));
    // The producer really did link an absolute path into the build tree, so the
    // install assertion below is about the copy, not about an absent producer.
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.equal(inputs.commit, commit, 'installed compiler must record the consumed source');
    console.log('CJO_INSTALL_REACHED commit=' + inputs.commit);
    assert.ok(sourceLink?.startsWith('/'), 'BUILD-TREE RUNTIME LINK WAS NOT PRODUCED');
    assert.equal(cjoRuntime, null, 'INSTALLED CJO MUST NOT CARRY THE BUILD-TREE RUNTIME LINK');
    // The CJO payload itself still has to reach the prefix; excluding it is not
    // an option, so the assertion covers both halves of the same copy entry.
    assert.ok(listing.includes('cjcj'), 'the CJO package did not reach the prefix: ' + listing);
    assert.deepEqual(packageCjo, ['parse@cjcj.cjo'], 'the real CJO payload did not reach the prefix');
  } finally {
    await retainOrRemove(root);
  }
});

test('control: the same install succeeds when the producer emits no link', async () => {
  const {root, result, sourceLink, cjoRuntime, commit, inputs} = await runCompilerStage({produceLink: false});
  try {
    console.log('TARGET_ASSERT_EXECUTED control=' + JSON.stringify({rc: result.status, sourceLink}));
    assert.equal(sourceLink, null, 'the control must not produce the build-tree link');
    assert.equal(cjoRuntime, null);
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.equal(inputs.commit, commit, 'installed compiler must record the consumed source');
    console.log('CJO_INSTALL_REACHED commit=' + inputs.commit);
  } finally {
    await retainOrRemove(root);
  }
});

for(const decoy of [false,true])test('explicit package-manager SDK '+(decoy?'overrides embedded host':'without embedded host'),async()=>{
  const {root,result,observed,sdk,packageManagerSdk,inputs,commit,listing,packageCjo,target}=await runCompilerStage({explicitHost:true,decoy});
  try {
    assert.equal(result.status,0,result.stdout+result.stderr);
    console.log('PACKAGE_MANAGER_SELECTION_TARGET_REACHED '+JSON.stringify(observed));
    assert.equal(observed.selected,'selected','EXPLICIT_PACKAGE_MANAGER_SELECTION');
    assert.deepEqual(observed.argv,['build','--target-dir',target,'-j','4']);
    assert.equal(observed.sdk,sdk,'target compiler/std SDK must remain selected');
    assert.equal(observed.path.split(path.delimiter)[0],sdk+'/bin');
    assert.equal(observed.loader.split(path.delimiter)[0],packageManagerSdk+'/runtime/lib/'+tuple);
    assert.equal(inputs.commit,commit);
    assert.ok(listing.includes('cjcj'));
    assert.deepEqual(packageCjo,['parse@cjcj.cjo']);
  } finally {await retainOrRemove(root);}
});
