import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {validateSourceInputs, installedFinalStd} from './sdk-inputs.mjs';
import {buildFlow} from './sdk-flow.mjs';

const gitEnv = {...process.env, GIT_AUTHOR_NAME: 'Zxilly', GIT_AUTHOR_EMAIL: 'zxilly@outlook.com',
  GIT_COMMITTER_NAME: 'Zxilly', GIT_COMMITTER_EMAIL: 'zxilly@outlook.com'};
function git(cwd, args) {
  const result = spawnSync('git', args, {cwd, env: gitEnv, encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}

test('explicit inputs reject a macro source that is not this paired tree', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'sdk-pair-'));
  const repo = path.join(root, 'source');
  await fs.mkdir(path.join(repo, 'packages/macro/src'), {recursive: true});
  const expected = await fs.readFile(new URL('../../packages/macro/src/InvokeUtil.cj', import.meta.url));
  await fs.writeFile(path.join(repo, 'packages/macro/src/InvokeUtil.cj'), expected);
  git(repo, ['init', '-q']);
  git(repo, ['add', 'packages/macro/src/InvokeUtil.cj']);
  git(repo, ['commit', '-qm', 'test: paired macro source']);
  const commit = git(repo, ['rev-parse', 'HEAD']);
  const tree = git(repo, ['rev-parse', 'HEAD^{tree}']);
  const row = {repository: repo, commit, tree};
  await validateSourceInputs({llvm: row, runtime: row, ast: row, h1: row, compiler: row});
  await assert.rejects(validateSourceInputs({llvm: row, runtime: row, ast: row, h1: row,
    compiler: row, stdlib: {...row, tree: '0'.repeat(40)}}), /NATIVE_SOURCE_TREE stdlib/);
  await fs.writeFile(path.join(repo, 'packages/macro/src/InvokeUtil.cj'), expected + '\n');
  git(repo, ['add', 'packages/macro/src/InvokeUtil.cj']);
  git(repo, ['commit', '-qm', 'test: unpaired macro source']);
  const other = git(repo, ['rev-parse', 'HEAD']);
  const otherTree = git(repo, ['rev-parse', 'HEAD^{tree}']);
  await assert.rejects(validateSourceInputs({llvm: row, runtime: row, ast: row,
    h1: {...row, commit: other, tree: otherTree}, compiler: row}), /NATIVE_MACRO_SOURCE h1/);
});

test('resume without a recorded result is refused before the later command', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'sdk-resume-missing-'));
  const config = {work: path.join(root, 'work'), install: path.join(root, 'install'), repos: {}, finalStage: 'b',
    stages: [{id: 'a', commands: [{argv: [process.execPath, '-e', 'process.exit(99)']}]},
      {id: 'b', depends: ['a'], commands: [{argv: [process.execPath, '-e', 'process.exit(98)']}]}]};
  await assert.rejects(buildFlow(config, {from: 'b', through: 'b', packageOutput: false}), /WORK_INPUTS_MISSING/);
  assert.equal(await fs.stat(path.join(root, 'work', 'build-result.json')).then(() => true, () => false), false);
});


test('explicit final std reuse must retain the actual producer build type',async()=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'std-policy-reuse-'));
 const install=root+'/install',commands=root+'/commands.json';
 for(const rel of ['modules/linux_x86_64_cjnative/std/std.core.cjo','lib/linux_x86_64_cjnative/libcangjie-std-core.a']){
  await fs.mkdir(path.dirname(install+'/'+rel),{recursive:true});await fs.writeFile(install+'/'+rel,'fixture');
 }
 const commit='a'.repeat(40),compiler='b'.repeat(40);
 await fs.writeFile(install+'/PROVENANCE.txt',`STD_SOURCE_COMMIT = ${commit}\nBUILT_BY_CJC = ${compiler}\nCOLOURED = true\n`);
 const input={platform:'linux_x86_64',stdlib:{commit},stage2:{compilerCommit:compiler}};
 for(const type of ['debug','release','relwithdebinfo']){
  await fs.writeFile(commands,JSON.stringify([
   {cwd:root,argv:['python3','-I','build.py','build','-t',type],rc:0},
   {cwd:root,argv:['python3','-I','build.py','install','--prefix',install],rc:0}]));
  assert.deepEqual(await installedFinalStd({install,commands},{...input,stdBuildType:type}),{install,commands});
  await assert.rejects(installedFinalStd({install,commands},{...input,stdBuildType:type==='debug'?'release':'debug'}),/FINAL_STD_REUSE_BUILD_TYPE/);
  if(type==='relwithdebinfo')await installedFinalStd({install,commands},input);
  else await assert.rejects(installedFinalStd({install,commands},input),/FINAL_STD_REUSE_BUILD_TYPE/);
 }
});
