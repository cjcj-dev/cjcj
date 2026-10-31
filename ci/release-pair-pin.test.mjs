import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {load as loadYaml} from './vendor/js-yaml/js-yaml.mjs';

const root = new URL('../', import.meta.url);
const read = file => fs.readFileSync(new URL(file, root), 'utf8');
const pins = file => Object.fromEntries(read(file).trim().split('\n').map(line => {
  const i = line.indexOf('=');
  return [line.slice(0, i), line.slice(i + 1)];
}));
const runtime = pins('ci/runtime_pin.env');
const llvm = pins('ci/llvm_pin.env');
const input = JSON.parse(read('ci/bootstrap_inputs_pin.json'));

test('workflow pin producers export the canonical pair consumed by checkout and cache', t => {
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'workflow-runtime-pair-'));
  t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
  const base={...process.env,RUNNER_TEMP:dir,PLATFORM:'darwin_aarch64'};
  for(const key of ['CJCJ_NATIVE_LLVM_REF','CJCJ_NATIVE_RUNTIME_REF','CJCJ_NATIVE_RUNTIME_ARTIFACT',
    'CJCJ_NATIVE_HOST_VERSION','CJCJ_RUNTIME_REF_OVERRIDE','CJCJ_ALLOW_RUNTIME_OVERRIDE',
    'CJCJ_BOOTSTRAP_RUNTIME_PIN','RUNTIME_SRC_URL'])delete base[key];
  let invocation=0;
  const execute=(command,extra={})=>{
    const output=path.join(dir,'env-'+invocation++);
    const result=spawnSync('bash',['-e','-c',command],{cwd:fileURLToPath(root),env:{...base,...extra,GITHUB_ENV:output},encoding:'utf8'});
    const exported=fs.existsSync(output)?Object.fromEntries(fs.readFileSync(output,'utf8').trim().split('\n').map(line=>{
      const i=line.indexOf('=');assert.ok(i>0,'valid GITHUB_ENV assignment');return [line.slice(0,i),line.slice(i+1)];
    })):{};
    return {result,exported};
  };
  const assertPair=(row,expected={llvm:llvm.LLVM_SHA,runtime:runtime.RUNTIME_REF})=>{
    assert.equal(row.result.status,0,row.result.stderr);
    assert.equal(row.exported.CJCJ_NATIVE_LLVM_REF,expected.llvm);
    assert.equal(row.exported.CJCJ_NATIVE_RUNTIME_REF,expected.runtime);
    assert.equal(row.exported.RUNTIME_REF,undefined,'retired environment alias is not exported');
    assert.equal(row.exported.RUNTIME_VERSION,runtime.RUNTIME_VERSION);
  };
  const workflows=['platform-matrix','darwin-input-consumers','ci','objc-darwin-e2e','verify-darwin-runtime','std-input-evidence'];
  let callers=0;
  for(const name of workflows)for(const [jobName,job]of Object.entries(loadYaml(read('.github/workflows/'+name+'.yml')).jobs)) {
    const steps=job.steps??[],index=steps.findIndex(step=>step.run?.includes('node ci/load_runtime_pin.mjs'));
    if(index<0)continue;
    const loaded=execute(steps[index].run);assertPair(loaded);callers++;
    for(const step of steps)for(const [key,value]of Object.entries(step.with??{})) {
      if(typeof value!=='string'||!value.includes('${{ env.CJCJ_NATIVE_RUNTIME_REF }}'))continue;
      assert.ok(steps.indexOf(step)>index,'export must precede '+key);
      const resolved=value.replace('${{ env.CJCJ_NATIVE_RUNTIME_REF }}',loaded.exported.CJCJ_NATIVE_RUNTIME_REF);
      if(['ref','pin'].includes(key))assert.equal(resolved,runtime.RUNTIME_REF);
      else assert.ok(resolved.includes(runtime.RUNTIME_REF),'cache key carries the selected runtime');
    }
    console.log('CANONICAL_WORKFLOW_TARGET',name,jobName,loaded.exported.CJCJ_NATIVE_RUNTIME_REF);
  }
  assert.equal(callers,9,'all migrated raw-pin callers are exercised');
  const command=loadYaml(read('.github/workflows/platform-matrix.yml')).jobs['darwin-runtime'].steps.find(step=>step.name==='Load runtime pin').run;
  const explicit={CJCJ_NATIVE_LLVM_REF:'a'.repeat(40),CJCJ_NATIVE_RUNTIME_REF:'b'.repeat(40)};
  assertPair(execute(command,explicit),{llvm:explicit.CJCJ_NATIVE_LLVM_REF,runtime:explicit.CJCJ_NATIVE_RUNTIME_REF});
  const half=execute(command,{CJCJ_NATIVE_RUNTIME_REF:explicit.CJCJ_NATIVE_RUNTIME_REF});
  assert.equal(half.result.status,1);assert.match(half.result.stderr,/NATIVE_RUNTIME_EXPLICIT_PAIR_REQUIRED/);
  const conflict=execute(command,{...explicit,CJCJ_RUNTIME_REF_OVERRIDE:'c'.repeat(40),CJCJ_ALLOW_RUNTIME_OVERRIDE:'true'});
  assert.equal(conflict.result.status,1);assert.match(conflict.result.stderr,/NATIVE_RUNTIME_OVERRIDE_CONFLICT/);
  assert.throws(()=>assertPair(execute('cat ci/runtime_pin.env >> "$GITHUB_ENV"')),/undefined/,'old producer does not establish canonical checkout input');
  assertPair(execute(command));
});

test('release runtime loader selects the stack-slot-root runtime paired with LLVM', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'release-pair-'));
  try {
    const output = path.join(dir, 'github-env');
    const env = {...process.env, GITHUB_ENV: output};
    for (const key of ['CJCJ_NATIVE_LLVM_REF', 'CJCJ_NATIVE_RUNTIME_REF', 'RUNTIME_SRC_URL', 'CJCJ_RUNTIME_REF_OVERRIDE', 'CJCJ_ALLOW_RUNTIME_OVERRIDE']) delete env[key];
    const result = spawnSync(process.execPath, [fileURLToPath(new URL('ci/load_runtime_pin.mjs', root))], {env, encoding: 'utf8'});
    assert.equal(result.status, 0, result.stderr);
    const selected = /^CJCJ_NATIVE_RUNTIME_REF=(.*)$/m.exec(fs.readFileSync(output, 'utf8'))?.[1];
    assert.equal(selected, runtime.RUNTIME_REF, 'release runtime must provide the paired ordinary-statepoint register-root contract');
    console.log(`ASSERT release-runtime-selected=${selected}`);
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
});

test('release LLVM source and both dylib provenance pins use the stack-slot-root and RawData safepoint producer', () => {
  assert.match(llvm.LLVM_SHA, /^[0-9a-f]{40}$/, 'LLVM source identity comes from ci/llvm_pin.env');
  for (const platform of ['linux_x86_64', 'linux_aarch64']) {
    const dylib = pins(`ci/llvm-dylib/${platform}.env`);
    assert.equal(dylib.LLVM_DYLIB_SOURCE_SHA, llvm.LLVM_SHA, platform);
    assert.equal(dylib.LLVM_DYLIB_RUN_ID, llvm.LLVM_TUPLE_RUN_ID, platform);
    assert.equal(dylib.LLVM_DYLIB_RUN_ATTEMPT, llvm.LLVM_TUPLE_RUN_ATTEMPT, platform);
  }
  console.log('ASSERT release-llvm-dylib-pair executed');
});

test('every platform dylib pin names the paired prerelease that published it', () => {
  const release = JSON.parse(read('ci/llvm-dylib/release.json'));
  assert.equal(release.llvm_sha, llvm.LLVM_SHA);
  assert.equal(release.run_id, llvm.LLVM_TUPLE_RUN_ID);
  assert.equal(release.run_attempt, llvm.LLVM_TUPLE_RUN_ATTEMPT);
  assert.equal(release.prerelease, true, 'the tuple must ship as a prerelease, never a full release');
  for (const platform of ['linux_x86_64', 'linux_aarch64', 'darwin_x86_64', 'darwin_aarch64']) {
    const dylib = pins(`ci/llvm-dylib/${platform}.env`);
    assert.equal(dylib.LLVM_DYLIB_SOURCE_SHA, llvm.LLVM_SHA, platform);
    assert.equal(String(release.platforms[platform].artifact_id), dylib.LLVM_DYLIB_ARTIFACT_ID, platform);
    assert.equal(release.platforms[platform].library_sha256, dylib.LLVM_DYLIB_SHA256, platform);
  }
  console.log(`ASSERT release-dylib-prerelease-pair run=${release.run_id} prerelease=${release.prerelease}`);
});

test('release tuple sums digest equals the reviewed LLVM pin and immutable input', () => {
  const digest = createHash('sha256').update(read('ci/llvm_tuple_SHA256SUMS')).digest('hex');
  assert.equal(llvm.LLVM_TUPLE_SUMS_SHA, digest, 'reviewed tuple checksum pin');
  const sums = input.files.find(file => file.path === 'SHA256SUMS');
  assert.equal(sums.artifact_sha256, digest);
  assert.equal(sums.release_sha256, digest);
  console.log(`ASSERT release-tuple-digest=${digest}`);
});

test('release immutable bootstrap files belong to the selected tuple', () => {
  assert.equal(String(input.run), llvm.LLVM_TUPLE_RUN_ID);
  assert.equal(String(input.attempt), llvm.LLVM_TUPLE_RUN_ATTEMPT);
  assert.equal(String(input.artifact), llvm.LLVM_TUPLE_ARTIFACT_ID);
  const sums = new Map(read('ci/llvm_tuple_SHA256SUMS').trim().split('\n').map(line => {
    const [, digest, file] = /^(\w{64})\s+\*?(.+)$/.exec(line);
    return [file.replace(/^\.\//, ''), digest];
  }));
  for (const file of input.files.filter(file => file.path !== 'SHA256SUMS')) {
    assert.equal(file.artifact_sha256, sums.get(file.path), file.path);
    assert.equal(file.release_sha256, file.artifact_sha256, file.path);
  }
  console.log('ASSERT release-bootstrap-input-pair executed');
});
