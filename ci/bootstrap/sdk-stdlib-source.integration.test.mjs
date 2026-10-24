#!/usr/bin/env zx
// Real descriptor/Git inputs through prepare; no compiler, std, N/LLDB or R
// production runs. SOURCE_CHECKOUT/resume use the real build CLI with a small
// script consumer, explicitly not a native SDK qualification.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const entry = fileURLToPath(new URL('./prepare-bootstrap-plans.mjs', import.meta.url));
const build = fileURLToPath(new URL('./sdk-build.mjs', import.meta.url));
const {SDK_STDLIB_TEST_ROOT: parent, SDK_STDLIB_DESCRIPTOR: descriptorFile,
  SDK_STDLIB_REPOSITORY: stdRepository, SDK_STDLIB_COMMIT: stdCommit} = process.env;
assert.ok(parent && descriptorFile && stdRepository && /^[a-f0-9]{40}$/.test(stdCommit || ''),
  'SDK_STDLIB_TEST_ROOT/DESCRIPTOR/REPOSITORY/COMMIT must name real private inputs');
await fs.mkdir(parent, {recursive:true});
const root = await fs.mkdtemp(path.join(parent, 'stdlib-source-'));
const original = JSON.parse(await fs.readFile(descriptorFile, 'utf8'));
assert.notEqual(stdCommit, original.runtimeCommit, 'rejection controls require a different std commit');
let sequence = 0;
const write = async (file, value) => {
  await fs.mkdir(path.dirname(file), {recursive:true});
  await fs.writeFile(file, typeof value === 'string' ? value : JSON.stringify(value, null, 2)+'\n');
};
const read = async file => JSON.parse(await fs.readFile(file, 'utf8'));
async function run(argv, env = {}) {
  const result = spawnSync(argv[0], argv.slice(1), {encoding:'utf8', maxBuffer:4*1024*1024,
    env:{...process.env, CJCJ_NATIVE_INPUTS:'', CJCJ_SDK_INPUTS:'', CJCJ_SDK_TARGETS:'', GITHUB_ENV:'', ...env}});
  const row = {argv, env, rc:result.status, signal:result.signal, error:result.error?.message,
    stdout:result.stdout, stderr:result.stderr};
  await write(path.join(root, `${++sequence}.command.json`), row);
  console.log('STDLIB_ENTRY_RESULT', sequence, row.rc, row.signal);
  return {...row, text:row.stdout+'\n'+row.stderr};
}
async function git(repo, ...args) {
  const r = await run(['git', '-C', repo, ...args]);
  assert.equal(r.rc, 0, r.text);
  return r.stdout.trim();
}
async function prepare(name, explicit) {
  const directory = path.join(root, name), descriptor = structuredClone(original);
  descriptor.work = path.join(directory, 'work');
  descriptor.install = path.join(directory, 'install');
  descriptor.sources.compiler = process.env.SDK_STDLIB_COMPILER_REPOSITORY
    || fileURLToPath(new URL('../../', import.meta.url));
  delete descriptor.stdlibCommit; delete descriptor.sources.stdlib;
  if (explicit) { descriptor.stdlibCommit = stdCommit; descriptor.sources.stdlib = stdRepository; }
  const file = path.join(directory, 'descriptor.json'), workspace = path.join(directory, 'workspace');
  await write(file, descriptor);
  const r = await run([process.execPath, entry], {CJCJ_NATIVE_INPUTS:file, CANGJIE_WORKSPACE:workspace});
  assert.equal(r.rc, 0, r.text);
  const configFile = path.join(workspace, 'build-targets.json'), config = await read(configFile);
  return {directory, descriptor, file, workspace, configFile, config};
}
function assertStdRoute(config, expected) {
  console.log('STDLIB_ROUTE_ASSERTION_REACHED', JSON.stringify({actual:config.repos.std1, expected}));
  assert.deepEqual(config.repos.std1, {...expected, checkout:path.join(config.work, 'sources/std1')});
  const argv = config.stages.find(s => s.id === 'stage3-std').commands[0].argv;
  assert.equal(argv[argv.indexOf('--source')+1], '${repo.std1}');
  assert.equal(argv[argv.indexOf('--commit')+1], expected.commit);
  assert.equal(argv[argv.indexOf('--runtime')+1], config.bootstrapInputs.runtime.install);
}

test('formal descriptor default keeps the runtime source route', async () => {
  const f = await prepare('default', false), input = f.config.bootstrapInputs;
  assert.deepEqual(input.stdlib, input.runtime);
  assert.equal(input.stdlibCommit, undefined);
  assertStdRoute(f.config, {root:input.runtime.repository, commit:input.runtime.commit, tree:input.runtime.tree});
  const r = await run([process.execPath, entry], {CJCJ_SDK_TARGETS:f.configFile});
  assert.equal(r.rc, 0, r.text);
});

test('formal descriptor explicit std preserves R producer and original C2/bootstrapStd', async () => {
  const f = await prepare('explicit', true), input = f.config.bootstrapInputs;
  const tree = await git(stdRepository, 'rev-parse', stdCommit+'^{tree}');
  assertStdRoute(f.config, {root:path.resolve(stdRepository), commit:stdCommit, tree});
  assert.equal(input.runtime.commit, original.runtimeCommit);
  for (const key of ['install','sourceRoot','configuration','buildResult'])
    assert.deepEqual(input.runtime[key], original.installations.runtime[key]);
  const stage2 = f.config.stages.find(s => s.id === 'stage2');
  if (original.installations.stage2) {
    assert.equal(stage2.commands, undefined);
    assert.equal(stage2.reuse.bootstrapStd, original.installations.stage2.bootstrapStd);
    assert.equal(stage2.metadata.stdSource, original.installations.stage2.bootstrapStd);
    assert.equal(stage2.metadata.runtimeCommit, original.runtimeCommit);
    assert.equal(stage2.metadata.compilerCommit, input.stage2.compilerCommit);
    assert.deepEqual(Object.keys(f.config.repos).sort(), ['compiler3','std1']);
  }
  const language = f.config.stages.find(s => s.id === 'stage3').test.commands[0].argv;
  assert.equal(language[language.indexOf('--runtime-source')+1], input.runtime.sourceRoot);
  const repeat = await run([process.execPath, entry], {CJCJ_NATIVE_INPUTS:f.file, CANGJIE_WORKSPACE:f.workspace});
  assert.equal(repeat.rc, 0, repeat.text);
  assert.deepEqual(await read(f.configFile), f.config, 'same descriptor regenerates exactly the same configuration');
  const r = await run([process.execPath, entry], {CJCJ_SDK_INPUTS:path.join(f.descriptor.work,'sdk-inputs.json'), CANGJIE_WORKSPACE:f.workspace});
  assert.equal(r.rc, 0, r.text);
  assert.deepEqual(await read(f.configFile), f.config);
});

test('formal entries reject incomplete selections and a forged resolved std tree before native execution', async () => {
  const f = await prepare('reject', true);
  for (const kind of ['commit-missing','repository-missing','symbolic']) {
    const d = structuredClone(f.descriptor);
    if (kind === 'commit-missing') delete d.stdlibCommit;
    if (kind === 'repository-missing') delete d.sources.stdlib;
    if (kind === 'symbolic') d.stdlibCommit = 'HEAD';
    const file = path.join(f.directory,kind+'.json'); await write(file,d);
    const r = await run([process.execPath,entry],{CJCJ_NATIVE_INPUTS:file,CANGJIE_WORKSPACE:f.workspace});
    assert.equal(r.rc,1,r.text); assert.match(r.text,/NATIVE_STDLIB_SOURCE_REQUIRED/);
  }
  const bad = structuredClone(f.config.bootstrapInputs); bad.stdlib.tree = '0'.repeat(40);
  const inputFile = path.join(f.directory,'wrong-tree.json'); await write(inputFile,bad);
  const prepared = await run([process.execPath,entry],{CJCJ_SDK_INPUTS:inputFile,CANGJIE_WORKSPACE:f.workspace});
  assert.equal(prepared.rc,0,prepared.text); // targets are declarative; build validates their Git objects.
  const refused = await run([process.execPath,build,'--config',f.configFile,'--from','stage3-std','--no-package']);
  assert.equal(refused.rc,1,refused.text); assert.match(refused.text,/NATIVE_SOURCE_TREE stdlib/);
  assert.doesNotMatch(refused.text,/"event":"target-command"/);
});

test('real build CLI checks generated std checkout HEAD/tree/dirt and same-configuration resume', async () => {
  const f = await prepare('checkout',true);
  // Sparse Git checkout keeps this configuration test within a text-only budget.
  // Git still retains the complete immutable commit/tree; no native build is run.
  const selected = f.config.repos.std1, checkout = selected.checkout;
  await fs.mkdir(path.dirname(checkout),{recursive:true});
  let r = await run(['git','clone','--shared','--no-checkout',selected.root,checkout]);
  assert.equal(r.rc,0,r.text);
  await git(checkout,'sparse-checkout','set','--no-cone','/stdlib/build.py');
  await git(checkout,'checkout','--detach',selected.commit);
  const expectedText = await git(checkout,'show',selected.commit+':stdlib/build.py');
  const consumer = path.join(f.directory,'consume.mjs');
  await write(consumer,`#!/usr/bin/env zx
import fs from 'node:fs'; import path from 'node:path'; import assert from 'node:assert/strict';
const [source,output]=process.argv.slice(2); console.log('STDLIB_CHECKOUT_CONSUMER_REACHED');
assert.equal(fs.readFileSync(path.join(source,'stdlib/build.py'),'utf8').trim(),${JSON.stringify(expectedText)});
fs.mkdirSync(output,{recursive:true}); fs.writeFileSync(path.join(output,'consumed'),'selected std source');
`);
  const finite = {work:path.join(f.directory,'finite-work'),install:path.join(f.directory,'finite-install'),
    repos:{std1:selected},finalStage:'consume',test:{required:['consumed']},
    stages:[{id:'consume',output:'${install}',commands:[{argv:[process.execPath,consumer,'${repo.std1}','${output}']}]}]};
  const originalWork=finite.work;
  const file = path.join(f.directory,'finite-targets.json'); await write(file,finite);
  const invoke = from => run([process.execPath,build,'--config',file,'--no-package',...(from?['--from','consume']:[])]);
  r = await invoke(false); assert.equal(r.rc,0,r.text); assert.match(r.text,/STDLIB_CHECKOUT_CONSUMER_REACHED/);
  await write(path.join(f.directory,'first-build-result.json'),await read(path.join(finite.work,'build-result.json')));
  r = await invoke(true); assert.equal(r.rc,0,r.text);
  for (const mode of ['head','tree','dirty']) {
    if (mode === 'head') await git(checkout,'checkout','--detach',original.runtimeCommit);
    if (mode === 'tree') {
      finite.repos.std1.tree='0'.repeat(40);
      // Fresh work avoids an earlier configuration-mismatch masking SOURCE_CHECKOUT.
      finite.work=path.join(f.directory,'wrong-tree-work'); await write(file,finite);
    }
    if (mode === 'dirty') await fs.appendFile(path.join(checkout,'stdlib/build.py'),'\n# controlled dirty source\n');
    r=await invoke(false); assert.equal(r.rc,1,r.text); assert.match(r.text,/SOURCE_CHECKOUT std1/);
    assert.doesNotMatch(r.text,/STDLIB_CHECKOUT_CONSUMER_REACHED/);
    if (mode === 'head') await git(checkout,'checkout','--detach',selected.commit);
    if (mode === 'tree') { finite.repos.std1.tree=f.config.bootstrapInputs.stdlib.tree; finite.work=originalWork; await write(file,finite); }
    if (mode === 'dirty') await git(checkout,'restore','--','stdlib/build.py');
    r=await invoke(false); assert.equal(r.rc,0,r.text); assert.match(r.text,/STDLIB_CHECKOUT_CONSUMER_REACHED/);
  }
  assert.equal(await git(checkout,'status','--porcelain','--untracked-files=no'),'');
  finite.repos.std1.commit=original.runtimeCommit; await write(file,finite);
  r=await invoke(true); assert.equal(r.rc,1,r.text); assert.match(r.text,/WORK_INPUT_MISMATCH/);
});


test('public bootstrap and both stage3 wrappers consume real full or C2 phase contracts', async () => {
  for (const reused of [false, true]) {
    const f = await prepare('phase-'+(reused?'C2':'full'), true);
    const input = structuredClone(f.config.bootstrapInputs);
    if (!reused) delete input.stage2;
    const inputs = path.join(f.directory, 'phase-inputs.json');
    await write(inputs, input);
    let r = await run([process.execPath, entry], {CJCJ_SDK_INPUTS:inputs,CANGJIE_WORKSPACE:f.workspace});
    assert.equal(r.rc, 0, r.text);
    const bootstrap = fileURLToPath(new URL('./bootstrap.mjs', import.meta.url));
    r = await run([process.execPath,bootstrap,'--config',f.configFile,'--stage','all','--dry-run']);
    console.log('F6_PUBLIC_PHASE_ASSERTION',reused?'C2':'full',r.rc);
    assert.equal(r.rc,0,r.text);
    const order=JSON.parse(r.stdout.trim());assert.equal(order.some(s=>s.id==='stage0'),!reused);assert.ok(order.some(s=>s.id==='stage2'));
    for(const [entryName,args] of [['../srcbuild/steps/build-stage3.mjs',[]],['./gha-run.mjs',['all']]]) {
      r=await run([process.execPath,fileURLToPath(new URL(entryName,import.meta.url)),...args],{CJCJ_SDK_TARGETS:f.configFile,CJCJ_SDK_FROM:'stage3-std'});
      assert.equal(r.rc,1,r.text);assert.match(r.text,/WORK_INPUTS_MISSING/);assert.doesNotMatch(r.text,/BOOTSTRAP_PHASE_MISSING|target-command/);
    }
    const plan=await read(f.configFile);plan.stages=plan.stages.filter(s=>s.id!=='stage2');await write(f.configFile,plan);
    r=await run([process.execPath,bootstrap,'--config',f.configFile,'--stage','all','--dry-run']);assert.equal(r.rc,1,r.text);assert.match(r.text,/BOOTSTRAP_PHASE_MISSING stage2/);
  }
});
