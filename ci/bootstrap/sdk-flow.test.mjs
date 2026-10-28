import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {buildFlow, targetOrder, copyOutputs, privateRoot, fileDigest} from './sdk-flow.mjs';

const parent = process.env.SDK_FLOW_TEST_ROOT || (process.env.RELEASE_EVIDENCE_TEST_ROOT && path.join(process.env.RELEASE_EVIDENCE_TEST_ROOT,'sdk-flow'));
if (!parent) throw new Error('SDK_FLOW_TEST_ROOT must name an owned persistent directory');
await fs.mkdir(parent, {recursive: true});
const product = process.env.SDK_FLOW_PRODUCT || fileURLToPath(new URL('./sdk-build.mjs', import.meta.url));
const root = await fs.mkdtemp(path.join(parent, 'native-install-'));
const source = path.join(root, 'source'), native = path.join(root, 'native');
await fs.mkdir(source);
await fs.writeFile(path.join(source, 'CMakeLists.txt'), `cmake_minimum_required(VERSION 3.16)
project(FlowNative C)
add_library(native SHARED value.c)
add_library(bad SHARED bad.c)
add_executable(read-result main.c)
target_link_libraries(read-result PRIVATE native)
add_executable(wrong-result main.c)
target_link_libraries(wrong-result PRIVATE bad)
set_target_properties(read-result wrong-result PROPERTIES INSTALL_RPATH "$ORIGIN/../lib;@loader_path/../lib")
install(TARGETS native bad read-result wrong-result RUNTIME DESTINATION bin LIBRARY DESTINATION lib)
`);
await fs.writeFile(path.join(source, 'value.c'), 'int value(void) { return 42; }\n');
await fs.writeFile(path.join(source, 'bad.c'), 'int value(void) { return 41; }\n');
await fs.writeFile(path.join(source, 'main.c'), '#include <stdio.h>\nextern int value(void); int main(void) { printf("%d\\n",value()); return 0; }\n');
const run = (file, args, options={}) => spawnSync(file, args, {encoding: 'utf8',...options});
if(!process.env.SDK_FLOW_NATIVE_INPUT) for (const argv of [
  ['cmake', '-S', source, '-B', native, '-DCMAKE_BUILD_TYPE=Release'],
  ['cmake', '--build', native, '--parallel', String(os.availableParallelism())],
  ['cmake', '--install', native, '--prefix', path.join(root, 'native-install')],
]) { const result = run(argv[0], argv.slice(1)); assert.equal(result.status, 0, result.stdout+result.stderr); }
const installedSource = process.env.SDK_FLOW_NATIVE_INPUT || path.join(root, 'native-install');
console.log('NATIVE_INPUT_IDENTITY',JSON.stringify(Object.fromEntries(await Promise.all(['bin/read-result','bin/wrong-result','lib/libnative.so','lib/libbad.so'].map(async rel=>[rel,await fileDigest(path.join(installedSource,rel))])))));
const suffix = process.platform === 'win32' ? '.exe' : '';
const check = path.join(root, 'check.mjs');
await fs.writeFile(check, `import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
const r=spawnSync(process.argv[2],[],{encoding:'utf8'});
console.log('NATIVE_INSTALLED_RESULT',JSON.stringify({rc:r.status,stdout:r.stdout,stderr:r.stderr}));
assert.equal(r.status,0,'NATIVE_INSTALLED_CHILD_RC');
console.log('TARGET_ASSERTION_REACHED result='+r.stdout.trim());
assert.equal(r.stdout.trim(),'42','NATIVE_INSTALLED_TARGET_VALUE');
`);
function config(name, binary = 'read-result') {
  const work = path.join(root, name), install = path.join(work, 'install');
  const copies = [{from: path.join(installedSource, 'lib'), to: 'lib'},
    {from: path.join(installedSource, 'bin', binary+suffix), to: 'bin/read-result'+suffix},
    {from: path.join(installedSource, 'bin', 'wrong-result'+suffix), to: 'bin/wrong-result'+suffix}];
  return {work, install, repos: {}, finalStage: 'native', archive: path.join(work, 'sdk.tar.gz'),
    toolchain: {compiler: 'CMake native C compiler'}, stages: [{id: 'native', copies, output: install}],
    test: {required: ['bin/read-result'+suffix], commands: [{argv: [process.execPath, check, '${install}/bin/read-result'+suffix]}]}};
}
async function cli(c, args = []) {
  const input = path.join(root, path.basename(c.work)+'.json'); await fs.writeFile(input, JSON.stringify(c));
  const r = run(process.execPath, [product, '--config', input, ...args]);
  await fs.writeFile(input+'.log', r.stdout+r.stderr);
  console.log('FLOW_CLI_RESULT',path.basename(c.work),r.status);
  return r;
}
test('native targets install tested output and relocated archive preserves the observed value', async () => {
  const c = config('normal'), r = await cli(c);
  assert.equal(r.status, 0, r.stdout+r.stderr);
  assert.equal((r.stdout.match(/TARGET_ASSERTION_REACHED result=42/g)||[]).length, 2, r.stdout);
  const facts=JSON.parse(await fs.readFile(path.join(c.work,'build-result.json')));
  assert.equal(facts.status,'COMPLETE');
  assert.ok(facts.commands.length>0&&facts.commands.every(row=>row.rc===0));
  assert.equal(await fileDigest(path.join(c.install, 'bin/read-result'+suffix)),
    await fileDigest(path.join(c.archive+'.unpacked/install/bin', 'read-result'+suffix)));
});
test('wrong native target reaches and fails the target value assertion', async () => {
  const c = config('wrong-target', 'wrong-result');
  c.stages[0].copies.pop(); // Same destination already contains the wrong native target.
  const r = await cli(c);
  assert.equal(r.status, 1); assert.match(r.stdout, /TARGET_ASSERTION_REACHED result=41/);
  assert.match(r.stderr, /NATIVE_INSTALLED_TARGET_VALUE/);
  assert.equal(await fs.stat(c.archive).then(()=>true,()=>false), false);
});
test('missing necessary native library refuses installation before packaging', async () => {
  const c = config('missing-library'); c.stages[0].copies.shift();
  const r = await cli(c); assert.equal(r.status, 1); assert.match(r.stderr, /NATIVE_INSTALLED_CHILD_RC/);
  assert.equal(await fs.stat(c.archive).then(()=>true,()=>false), false);
});
test('native command exit code propagates and dependent target is not executed', async () => {
  const work = path.join(root,'exit'), c = {work,install:path.join(work,'install'),repos:{},finalStage:'later',
    stages:[{id:'failed',commands:[{argv:[process.execPath,'-e','process.exit(23)']}]},
      {id:'later',depends:['failed'],commands:[{argv:[process.execPath,'-e','process.exit(99)']}]}]};
  const r=await cli(c); assert.equal(r.status,23);
  const record=JSON.parse(await fs.readFile(path.join(work,'build-result.json')));
  assert.equal(record.commands.length,1); assert.equal(record.commands[0].rc,23);
});
test('conflicting producers cannot silently replace installed bytes',async()=>{
  const output=path.join(root,'conflict');
  await assert.rejects(copyOutputs(output,[{from:path.join(source,'value.c'),to:'value.c',owner:'a'},
    {from:path.join(source,'bad.c'),to:'value.c',owner:'b'}]),/INSTALL_CONFLICT/);
  assert.equal(await fs.readFile(path.join(output,'value.c'),'utf8'),'int value(void) { return 42; }\n');
});
test('relative aliases relocate and an external alias is rejected',async()=>{
  const input=path.join(root,'links'); await fs.mkdir(input);
  await fs.writeFile(path.join(input,'original'),'data'); await fs.symlink('original',path.join(input,'alias'));
  const output=path.join(root,'links-install'); await copyOutputs(output,[{from:input,to:''}]);
  assert.equal(await fs.readFile(path.join(output,'alias'),'utf8'),'data');
  await fs.symlink('/etc/passwd',path.join(input,'escape'));
  await assert.rejects(copyOutputs(path.join(root,'links-escape'),[{from:input,to:''}]),/INSTALL_LINK_ESCAPE/);
});
test('shared installation and symlink parent are rejected before writes',async()=>{
  await assert.rejects(privateRoot('/root/sdks/test'),/SHARED_INSTALL/);
  const alias=path.join(root,'linked-root');await fs.symlink(source,alias);
  await assert.rejects(privateRoot(alias+'/child'),/INSTALL_LINK/);
});
test('target dependency order rejects cycles and unknown targets',()=>{
  assert.deepEqual(targetOrder([{id:'c',depends:['b']},{id:'b',depends:['a']},{id:'a'}],'c').map(s=>s.id),['a','b','c']);
  assert.throws(()=>targetOrder([{id:'a',depends:['a']}]),/TARGET_DEPENDENCY/);
  assert.throws(()=>targetOrder([{id:'a'}],'missing'),/TARGET_DEPENDENCY/);
});

test('archive consumer cannot fall back to the old root and the original is restored on rejection',async()=>{
 const c=config('old-root-fallback');
 const check=path.join(root,'old-root-check.mjs');
 await fs.writeFile(check,`import fs from 'node:fs';const old=process.argv[2];const current=process.argv[3];console.log('OLD_ROOT_RELOCATION_ASSERTION_REACHED '+JSON.stringify({old,current,oldExists:fs.existsSync(old)}));if(current.includes('.unpacked/')){if(fs.existsSync(old))process.exit(71);process.exit(72);}`);
 c.test.commands=[{argv:[process.execPath,check,c.install,'${install}']}];
 const r=await cli(c);
 assert.equal(r.status,72,r.stdout+r.stderr);
 assert.match(r.stdout,/"oldExists":false/);
 assert.equal(await fileDigest(path.join(c.install,'bin/read-result')),await fileDigest(path.join(installedSource,'bin/read-result')));
 console.log('ARCHIVE_ORIGINAL_RESTORED_ASSERTION_REACHED');
});

test('public from and repeated packaging publish complete installations and retain old trees',async()=>{
 const c=config('reentry');
 let r=await cli(c);assert.equal(r.status,0,r.stdout+r.stderr);
 const before=await fileDigest(path.join(c.install,'bin/read-result'));
 await fs.writeFile(path.join(c.install,'stale-only'),'retired');
 r=await cli(c,['--from','native']);assert.equal(r.status,0,r.stdout+r.stderr);
 assert.equal(await fs.stat(path.join(c.install,'stale-only')).catch(()=>null),null);
 assert.equal(await fileDigest(path.join(c.install,'bin/read-result')),before);
 const retained=(await fs.readdir(c.work)).filter(n=>n.startsWith('install.previous-'));
 assert.equal(retained.length,1);assert.equal(await fs.readFile(path.join(c.work,retained[0],'stale-only'),'utf8'),'retired');
 assert((await fs.readdir(c.work)).some(n=>n.startsWith('sdk.tar.gz.unpacked.previous-')));
 assert.equal(JSON.parse(await fs.readFile(path.join(c.work,'build-result.json'))).status,'COMPLETE');
});
test('failed assembly leaves the old installation intact and a normal retry can recover',async()=>{
 const c=config('partial-copy');
 const selected=path.join(root,'partial-selected');await fs.copyFile(path.join(installedSource,'bin/read-result'),selected);
 c.stages[0].copies[1].from=selected;
 let r=await cli(c,['--no-package']);assert.equal(r.status,0,r.stdout+r.stderr);
 const before=await fileDigest(path.join(c.install,'bin/read-result'));
 await fs.rename(selected,selected+'.saved');
 r=await cli(c,['--from','native','--no-package']);assert.equal(r.status,1);assert.match(r.stderr,/ENOENT/);
 assert.equal(await fileDigest(path.join(c.install,'bin/read-result')),before);
 await fs.rename(selected+'.saved',selected);
 r=await cli(c,['--from','native','--no-package']);assert.equal(r.status,0,r.stdout+r.stderr);
 assert((await fs.readdir(c.work)).some(n=>n.startsWith('install.pending-')));
});

test('public re-entry rebuilds prepared inputs and native launcher entries without double wrapping',async()=>{
 const c=config('prepared-entries');
 const prepared=c.work+'/prepared';
 c.stages[0].prepare=[{to:prepared,copies:[{from:installedSource,to:''}]}];
 c.stages[0].commands=[{argv:[process.execPath,check,prepared+'/bin/read-result']}];
 c.stages[0].copies=[{from:prepared+'/lib',to:'lib'},{from:prepared+'/bin/read-result',to:'bin/cjcj-stage1'}];
 c.stages[0].entries=[{directory:'bin',retain:'libexec/compiler',names:['cjcj-stage1'],libraries:['lib']}];
 c.stages[0].links={'bin/cjc':'cjcj-stage1'};
 c.stages[0].metadata={platform:'linux_x86_64',compilerFile:'libexec/compiler/cjcj-stage1'};
 c.platform='linux_x86_64';c.test={required:['bin/cjc'],commands:[{argv:[process.execPath,check,'${install}/bin/cjc']}]};
 let r=await cli(c,['--no-package']);assert.equal(r.status,0,r.stdout+r.stderr);
 const bytes=await fileDigest(c.install+'/libexec/compiler/cjcj-stage1');
 await fs.writeFile(prepared+'/stale','old');
 r=await cli(c,['--from','native','--no-package']);assert.equal(r.status,0,r.stdout+r.stderr);
 assert.equal(await fileDigest(c.install+'/libexec/compiler/cjcj-stage1'),bytes);
 assert.equal(await fs.stat(prepared+'/stale').catch(()=>null),null);
 assert.match(await fs.readFile(c.install+'/bin/cjcj-stage1.entry','utf8'),/libexec\/compiler\/cjcj-stage1/);
});

test('direct native output records traversal facts without authenticating a directory',async()=>{
 const work=path.join(root,'direct-reuse'),install=path.join(work,'installed');
 await fs.mkdir(install,{recursive:true});await fs.writeFile(path.join(install,'payload'),'42');
 const c={work,install,repos:{},finalStage:'existing',stages:[{id:'existing',output:install,reuse:{source:'fixed fixture payload'}}],test:{required:['payload']}};
 for(let i=0;i<2;i++){
  const r=await cli(c,['--no-package']);assert.equal(r.status,0,r.stdout+r.stderr);
  const record=JSON.parse(await fs.readFile(path.join(work,'build-result.json')));
  assert.equal(record.status,'COMPLETE');assert.equal(record.files,undefined);
  assert.equal(await fs.readFile(path.join(install,'payload'),'utf8'),'42');
 }
});

test('public source preparation failure preserves predecessors for subsequent normal from',async()=>{
 const work=path.join(root,'source-recovery'),install=work+'/installed',source=work+'/source';
 await fs.mkdir(source,{recursive:true});await fs.writeFile(source+'/tracked','fixed');
 for(const args of [['init','-q',source],['-C',source,'add','.'],['-C',source,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','test: source recovery fixture']]){const r=run('git',args);assert.equal(r.status,0,r.stderr);}
 const commit=run('git',['-C',source,'rev-parse','HEAD']).stdout.trim(),tree=run('git',['-C',source,'rev-parse','HEAD^{tree}']).stdout.trim();
 const c={work,install,repos:{input:{root:source,commit,tree}},stages:[{id:'pre',output:installedSource,reuse:'fixed native C fixture',test:{commands:[{argv:[process.execPath,check,installedSource+'/bin/read-result']}] }},{id:'next',depends:['pre'],output:install,commands:[{argv:[process.execPath,'-e','const fs=require("fs");console.log("RECOVERY_NATIVE_COMMAND_REACHED");if(process.env.SDK_FLOW_FIXTURE_FAIL)process.exit(7);fs.mkdirSync(process.argv[1],{recursive:true});fs.writeFileSync(process.argv[1]+"/marker","42")','${output}','${repo.input}']}]}],finalStage:'next',test:{required:['marker']}};
 let r=await cli(c,['--no-package']);assert.equal(r.status,0,r.stdout+r.stderr);
 assert.equal(run('git',['-C',source,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','--allow-empty','-qm','different source HEAD']).status,0);
 try{r=await cli(c,['--from','next','--no-package']);assert.equal(r.status,1);assert.match(r.stderr,/SOURCE_CHECKOUT input/);}
 finally{assert.equal(run('git',['-C',source,'checkout','--detach',commit]).status,0);}
 process.env.SDK_FLOW_FIXTURE_FAIL='1';
 try{r=await cli(c,['--from','next','--no-package']);}
 finally{delete process.env.SDK_FLOW_FIXTURE_FAIL;}
 console.log('SOURCE_REENTRY_EXIT_ASSERTION_REACHED rc='+r.status);
 assert.equal(r.status,7,r.stderr);assert.match(r.stdout,/RECOVERY_NATIVE_COMMAND_REACHED/);
 r=await cli(c,['--from','next','--no-package']);assert.equal(r.status,0,r.stdout+r.stderr);
 const state=JSON.parse(await fs.readFile(work+'/build-result.json'));
 assert.deepEqual(state.stages.map(s=>s.id),['pre','next']);
});

// The registered flow gate includes the public archive-source branch.
await import('./sdk-archive-source-cases.mjs');

await import('./sdk-source-cases.mjs');

test('public final consumer rejection preserves the previous usable install',async()=>{
 const c=config('consumer-rollback');
 let r=await cli(c,['--no-package']);assert.equal(r.status,0,r.stdout+r.stderr);
 const old=await fileDigest(c.install+'/bin/read-result');
 const bad=config('consumer-rollback','wrong-result');bad.stages[0].copies.pop();
 // Input change is a fresh invocation, preserving the old public destination.
 bad.work=c.work+'-candidate';
 r=await cli(bad,['--no-package']);
 assert.equal(r.status,1);assert.match(r.stdout,/TARGET_ASSERTION_REACHED result=41/);
 assert.equal(await fileDigest(c.install+'/bin/read-result'),old);
 console.log('FAILED_CONSUMER_OLD_INSTALL_ASSERTION_REACHED');
});

test('public second publish rename failure restores the old install and retry recovers',async()=>{
 const c=config('rename-rollback');
 let r=await cli(c,['--no-package']);assert.equal(r.status,0,r.stdout+r.stderr);
 await fs.writeFile(c.install+'/old-marker','usable old install');
 const injected=path.join(root,'rename-eio.mjs');
 await fs.writeFile(injected,`import fs from 'node:fs/promises';const rename=fs.rename;fs.rename=async(from,to)=>{if(to===process.env.INSTALL_RENAME_TARGET&&String(from).startsWith(process.env.INSTALL_RENAME_TARGET+'.pending-')){console.log('SECOND_PUBLISH_RENAME_ASSERTION_REACHED');throw Object.assign(Error('injected publish EIO'),{code:'EIO'});}return rename(from,to);};`);
 const options=process.env.NODE_OPTIONS;
 process.env.NODE_OPTIONS=[options,'--import',injected].filter(Boolean).join(' ');
 process.env.INSTALL_RENAME_TARGET=c.install;
 try{r=await cli(c,['--from','native','--no-package']);}
 finally{if(options===undefined)delete process.env.NODE_OPTIONS;else process.env.NODE_OPTIONS=options;delete process.env.INSTALL_RENAME_TARGET;}
 assert.equal(r.status,1,r.stdout+r.stderr);assert.match(r.stdout,/SECOND_PUBLISH_RENAME_ASSERTION_REACHED/);
 assert.equal(await fs.readFile(c.install+'/old-marker','utf8'),'usable old install');
 const control=await cli(config('rename-independent-control'),['--no-package']);assert.equal(control.status,0,control.stderr);
 r=await cli(c,['--from','native','--no-package']);assert.equal(r.status,0,r.stdout+r.stderr);
 assert.equal(await fs.stat(c.install+'/old-marker').catch(()=>null),null);
 console.log('SECOND_PUBLISH_RENAME_RECOVERED');
});

test('failed archive consumption retains the prior archive and restores the install',async()=>{
 const c=config('archive-preservation');let r=await cli(c);assert.equal(r.status,0,r.stdout+r.stderr);
 const oldArchive=await fileDigest(c.archive),oldInstall=await fileDigest(c.install+'/bin/read-result');
 const checkRelocated=path.join(root,'reject-relocated.mjs');
 await fs.writeFile(checkRelocated,`import fs from 'node:fs';const install=process.argv[2];console.log('ARCHIVE_REJECTION_TARGET_REACHED '+install);if(install.includes('.unpacked/'))process.exit(73);`);
 c.test.commands.push({argv:[process.execPath,checkRelocated,'${install}']});c.work+='-candidate';
 r=await cli(c);assert.equal(r.status,73,r.stdout+r.stderr);
 assert.equal(await fileDigest(c.archive),oldArchive);assert.equal(await fileDigest(c.install+'/bin/read-result'),oldInstall);
 const files=(await fs.readdir(path.dirname(c.archive))).filter(name=>name.endsWith('.commands.json'));
 const facts=await Promise.all(files.map(name=>fs.readFile(path.join(path.dirname(c.archive),name),'utf8').then(JSON.parse)));
 const rejected=facts.find(row=>row.status==='FAILED');assert.ok(rejected);
 assert.equal(rejected.commands.at(-1).rc,73);assert.deepEqual(rejected.commands.filter(row=>row.argv[0]==='tar').map(row=>row.rc),[0,0]);
 console.log('ARCHIVE_FAILURE_PREVIOUS_PRESERVED');
});

test('public run-all uses one pending install and rolls back when a later producer fails',async()=>{
 const work=path.join(root,'run-all-public'),workspace=work+'/workspace',sdk=workspace+'/software/cangjie';
 const put=async(file,text,mode=0o644)=>{await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,text,{mode});};
 // Native build.py/Cangjie semantics are controlled here. The public CLI,
 // source resolution, entity copies, compiled launcher, hello subprocess and
 // publication remain the real product implementations.
 const selection={};
 for(const name of ['compiler','runtime','tools','stdx','llvm','cjpm']){
  const repo=workspace+(name==='llvm'?'/cangjie_compiler/third_party/llvm-project':name==='cjpm'?'/cjpm-source':'/cangjie_'+name);
  await put(repo+'/tracked','fixed source '+name);
  for(const args of [['init','-q',repo],['-C',repo,'add','tracked'],['-C',repo,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','test: controlled run-all native source']])assert.equal(run('git',args).status,0);
  selection[name]={url:'file://'+repo,tag:run('git',['-C',repo,'rev-parse','HEAD']).stdout.trim()};
 }
 await put(workspace+'/.source-selection.json',JSON.stringify(selection));
 const native=workspace+'/cangjie_compiler/output',tuple='linux_x86_64_cjnative';
 await put(native+'/bin/cjc',`#!/usr/bin/env node
const fs=require('node:fs'),cp=require('node:child_process'),path=require('node:path');
const args=process.argv.slice(2),output=args[args.indexOf('-o')+1];
if(!output)process.exit(0);
const c=output+'.c';fs.writeFileSync(c,'#include <stdio.h>\\nint main(void){puts("hello from cjcj");return 0;}\\n');
const r=cp.spawnSync('cc',[c,'-o',output],{stdio:'inherit'});process.exit(r.status??1);
`,0o755);
 for(const relative of ['modules/'+tuple+'/std/std.core.cjo','lib/'+tuple+'/libcangjie-std-core.a',
  'runtime/lib/'+tuple+'/libcangjie-runtime.so','third_party/llvm/bin/llc','third_party/llvm/lib/libLLVM-15.so'])await put(native+'/'+relative,'controlled native dependency');
 await fs.mkdir(native+'/tools/bin',{recursive:true});
 await put(work+'/host/runtime/lib/'+tuple+'/libcangjie-runtime.so','controlled host runtime');
 await put(sdk+'/old-success','previous SDK');
 const loader=work+'/boundaries.mjs',trace=work+'/trace.jsonl';
 await put(loader,`export async function load(url,context,next){const result=await next(url,context);
const stage=/\\/build\\/srcbuild\\/stages\\/(fetch|compiler|runtime|stdlib|stdx|tools|package|verify)\\.mjs$/.exec(url)?.[1];
const verify=url.endsWith('/ci/bootstrap/sdk-verify-install.mjs');if(!stage&&!verify)return result;
const name=verify?'verifyInstall':'run';let source=String(result.source);source=source.replace('export async function '+name+'(','async function ORIGINAL_'+name+'(');
source+='\\nexport async function '+name+'(config){const fs=await import("node:fs");const name='+JSON.stringify(stage??'installed-consumer')+';fs.appendFileSync(process.env.RUN_ALL_TRACE,JSON.stringify({name,sdk:config.consumerSdk??config.sdk,selection:config.selection})+"\\\\n");if(name===process.env.RUN_ALL_FAIL)throw Error("RUN_ALL_LATE_PRODUCER_FAILURE");}';return {...result,source};}
`);
 const cliPath=new URL('../../build/cli.mjs',import.meta.url).pathname;
 const argv=[cliPath,'--workspace',workspace,'--build-root',work+'/buildtools','--official-sdk-root',work+'/host',
  'run-all','--skip-system-deps','--skip-install-libs'];
 const env={...process.env,NODE_OPTIONS:'--experimental-loader='+loader,RUN_ALL_TRACE:trace};
 const commands=[];
 async function invoke(label,extra={},flags=[]){
  const actualArgv=[...argv,...flags];const r=run(process.execPath,actualArgv,{env:{...env,...extra}});commands.push({label,argv:actualArgv,rc:r.status,signal:r.signal,stdout:r.stdout,stderr:r.stderr});
  await put(work+'/commands.json',JSON.stringify(commands,null,2));return r;
 }
 let dry=await invoke('dry-run',{},['--dry-run']);assert.equal(dry.status,0,dry.stderr);
 assert.equal(await fs.stat(trace).catch(()=>null),null);assert.match(dry.stdout,/NOT_INSTALLED/);
 let build=await invoke('build-only',{},['--build-only']);assert.equal(build.status,0,build.stdout+build.stderr);
 assert.match(build.stdout,/NOT_INSTALLED/);assert.equal(await fs.readFile(sdk+'/old-success','utf8'),'previous SDK');
 const built=(await fs.readFile(trace,'utf8')).trim().split('\n').map(JSON.parse);
 assert.deepEqual(built.map(row=>row.name),['fetch','compiler','runtime','stdlib','stdx','tools']);
 await fs.rename(trace,trace+'.build-only');
 let r=await invoke('late-failure',{RUN_ALL_FAIL:'tools'});assert.equal(r.status,1,r.stdout+r.stderr);
 assert.match(r.stderr,/RUN_ALL_LATE_PRODUCER_FAILURE/);assert.match(r.stdout,/SDK_HELLO_TARGET_ASSERTION_REACHED/);
 assert.equal(await fs.readFile(sdk+'/old-success','utf8'),'previous SDK');
 let rows=(await fs.readFile(trace,'utf8')).trim().split('\n').map(JSON.parse);
 assert.equal(rows.some(row=>row.name==='package'),false);
 assert.ok(rows.find(row=>row.name==='stdx').sdk.startsWith(sdk+'.pending-'));
 r=await invoke('restored');assert.equal(r.status,0,r.stdout+r.stderr);
 assert.equal(await fs.stat(sdk+'/old-success').catch(()=>null),null);
 rows=(await fs.readFile(trace,'utf8')).trim().split('\n').map(JSON.parse);
 assert.equal(rows.findLast(row=>row.name==='package').sdk,sdk);
 assert.deepEqual(rows.findLast(row=>row.name==='compiler').selection,rows.findLast(row=>row.name==='stdlib').selection);
 console.log('RUN_ALL_PENDING_CONSUMER_ROLLBACK_RECOVERED '+work);
});

 test('public default and explicit source choices resolve to the same dry-run tuple',async()=>{
 const workspace=path.join(root,'default-source-choice'),cliPath=new URL('../../build/cli.mjs',import.meta.url).pathname;
 const argv=[cliPath,'--workspace',workspace,'run-all','--dry-run'];
 const first=run(process.execPath,argv);assert.equal(first.status,0,first.stderr);
 const defaults=JSON.parse(first.stdout.trim());assert.equal(defaults.status,'NOT_INSTALLED');
 assert.equal(await fs.stat(workspace).catch(()=>null),null);
 await fs.mkdir(workspace);await fs.writeFile(workspace+'/.source-selection.json',JSON.stringify(Object.fromEntries(
  Object.entries(defaults.sources).map(([name,row])=>[name,{url:row.repository,tag:row.commit}]))));
 const second=run(process.execPath,argv);assert.equal(second.status,0,second.stderr);
 assert.deepEqual(JSON.parse(second.stdout.trim()).sources,defaults.sources);
 assert.deepEqual((await fs.readdir(workspace)),['.source-selection.json']);
 console.log('DEFAULT_EXPLICIT_SOURCE_TUPLE_ASSERTION_REACHED '+JSON.stringify(defaults.sources));
 });

// R1/R2: independent CLI processes, with the real native command writer,
// installer, installedInputs and package/archive implementation. Only the
// heavyweight producer and full language/ABI gates are controlled boundaries.
async function stagedFixture(label) {
 const work=path.join(root,label),workspace=work+'/workspace',sdk=workspace+'/software/cangjie';
 const put=async(file,text,mode=0o644)=>{await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,text,{mode});};
 const selected={};
 for(const name of ['compiler','runtime','tools','stdx','llvm','cjpm']) {
  const repo=workspace+(name==='llvm'?'/cangjie_compiler/third_party/llvm-project':name==='cjpm'?'/cjpm-source':'/cangjie_'+name);
  await put(repo+'/tracked','fixed '+name);
  await put(repo+'/build.py','import os, sys\nprint("FINITE_NATIVE_COMMAND", os.environ.get("FINITE_PRODUCER"), sys.argv)\nsys.exit(17 if os.environ.get("STAGED_FAIL")==os.environ.get("FINITE_PRODUCER") and sys.argv[1]=="install" else 0)\n');
  for(const args of [['init','-q',repo],['-C',repo,'add','tracked','build.py'],['-C',repo,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','test: finite native producer']])assert.equal(run('git',args).status,0);
  selected[name]={url:'file://'+repo,tag:run('git',['-C',repo,'rev-parse','HEAD']).stdout.trim()};
 }
 await put(workspace+'/.source-selection.json',JSON.stringify(selected));
 const output=workspace+'/cangjie_compiler/output',tuple='linux_x86_64_cjnative';
 await put(output+'/bin/cjc',`#!/usr/bin/env node
const fs=require('node:fs'),cp=require('node:child_process');const args=process.argv.slice(2),out=args[args.indexOf('-o')+1];if(!out)process.exit(0);
fs.writeFileSync(out+'.c','#include <stdio.h>\\nint main(void){puts("hello from cjcj");return 0;}\\n');process.exit(cp.spawnSync('cc',[out+'.c','-o',out],{stdio:'inherit'}).status??1);
`,0o755);
 for(const rel of ['modules/'+tuple+'/std/std.core.cjo','lib/'+tuple+'/libcangjie-std-core.a',
  'lib/'+tuple+'/libcangjie-ast-support.a','runtime/lib/'+tuple+'/libcangjie-runtime.so',
  'third_party/llvm/lib/libLLVM-15.so','schema/StdAstFormat.fbs','include/flatbuffers/StdAstFormat_generated.h',
  'third_party/flatbuffers/bin/flatc','stdx/'+tuple+'/fixture',
  ...['llc','llvm-as','llvm-dis','opt'].map(name=>'third_party/llvm/bin/'+name),
  ...['cjpm','cjfmt','hle','LSPServer','cjcov','cjtrace-recover','cjlint','cjprof','cjcompat','cjhead'].flatMap(name=>{
    const privateDir={LSPServer:'lsp',cjlint:'cjlint',cjhead:'cjhead'}[name];
    return ['tools/bin/'+name,'tools/bin/'+name+'.entry','.target-tools/tools/'+(privateDir?privateDir+'/':'')+'bin/'+name];
  }),
  'tools/config/cangjie-format.toml','tools/config/cangjie-repo.toml','tools/dtsparser/analysis.js','tools/bin/node'])await put(output+'/'+rel,'finite native artifact');
 for(const name of ['llc','llvm-as','llvm-dis','opt'])await fs.chmod(output+'/third_party/llvm/bin/'+name,0o755);
 await put(output+'/tools/dtsparser/DEPENDENCIES.json','{}');
 await put(work+'/host/runtime/lib/'+tuple+'/libcangjie-runtime.so','finite host runtime');
 for(const name of ['check_sdk_usable.mjs','verifier_artifact_gate.mjs'])assert.equal(await fs.stat(output+'/tools/'+name).catch(()=>null),null);
 const loader=work+'/boundaries.mjs';
 await put(loader,`export async function load(url,context,next){const result=await next(url,context);if(result.source==null)return result;let source=String(result.source);
const stage=/\\/build\\/srcbuild\\/stages\\/(compiler|runtime|stdlib|stdx|tools|fetch|verify)\\.mjs$/.exec(url)?.[1];
if(stage){source=source.replace('export async function run(','async function ORIGINAL_run(');source+='\\nexport async function run(config){const name='+JSON.stringify(stage)+';if(!["compiler","runtime","stdlib"].includes(name))return;const {runBuildPy}=await import("./common.mjs");for(const step of ["build","install"])await runBuildPy(config,config.repoPath(name==="stdlib"?"runtime":name),[step],{stageName:name+"."+step,extraEnv:{FINITE_PRODUCER:name}});}';}
else if(url.endsWith('/sdk-verify-install.mjs')) {source=source.replace('export async function verifyInstall(','async function ORIGINAL_verifyInstall(');source+='\\nexport async function verifyInstall(){console.log("FINITE_LANGUAGE_BOUNDARY");}';}
else for(const [file,name]of [['runtime-split.mjs','assertSdkCompilerRuntimeAbi'],['sdk-path-parity.mjs','assertSdkPathParity']])if(url.endsWith('/'+file)){source=source.replace('function '+name+'(','function ORIGINAL_'+name+'(');source+='\\nexport function '+name+'(){console.log("FINITE_ABI_PATH_BOUNDARY");}';}
return {...result,source};}
`);
 const cliPath=fileURLToPath(new URL('../../build/cli.mjs',import.meta.url));
 const base=[cliPath,'--workspace',workspace,'--build-root',work+'/buildtools','--official-sdk-root',work+'/host'];
 const env={...process.env,NODE_OPTIONS:'--experimental-loader='+loader};
 const commands=[];
 async function invoke(label,args,extra={}) {
  const argv=[...base,...args],r=run(process.execPath,argv,{env:{...env,...extra}});
  commands.push({label,argv,rc:r.status,signal:r.signal,error:r.error?.message,stdout:r.stdout,stderr:r.stderr});
  await put(work+'/commands.json',JSON.stringify(commands,null,2));return r;
 }
 const facts=async()=>JSON.parse(await fs.readFile(workspace+'/build/native-build.json','utf8'));
 return {work,workspace,sdk,output,put,selected,invoke,facts};
}

test('public staged build preserves predecessor commands through package and recovery',async()=>{
 const f=await stagedFixture('staged-public');
 for(const name of ['compiler','runtime','stdlib','stdx','tools']) {
  const r=await f.invoke(name,['build',name]);assert.equal(r.status,0,r.stdout+r.stderr);
  if(name==='compiler')await f.put(f.work+'/compiler-original.json',JSON.stringify(await f.facts()));
 }
 const packaged=await f.invoke('package',['package']);
 console.log('STAGED_PACKAGE_ASSERTION_REACHED rc='+packaged.status);
 assert.equal(packaged.status,0,packaged.stdout+packaged.stderr);
 const original=JSON.parse(await fs.readFile(f.work+'/compiler-original.json','utf8')).commands;
 const installed=JSON.parse(await fs.readFile(f.sdk+'/STAGE-INPUTS.json','utf8'));
 assert.deepEqual(installed.production.commands.filter(row=>row.stage.startsWith('compiler.')),original);
 const archives=(await fs.readdir(path.dirname(f.sdk))).filter(n=>n.startsWith('cangjie-sdk-')&&n.endsWith('.tar.gz'));
 assert.equal(archives.length,1);
 const unpacked=path.join(path.dirname(f.sdk),archives[0]+'.unpacked/cangjie');
 assert.deepEqual(JSON.parse(await fs.readFile(unpacked+'/STAGE-INPUTS.json','utf8')).production.commands,installed.production.commands);
 let r=await f.invoke('stdlib-cached',['build','stdlib']);assert.equal(r.status,0,r.stderr);
 assert.deepEqual((await f.facts()).commands.filter(row=>row.stage.startsWith('compiler.')),original);
 r=await f.invoke('compiler-failure',['build','compiler'],{STAGED_FAIL:'compiler'});assert.equal(r.status,1,r.stderr);
 assert.equal((await f.facts()).commands.at(-1).exitCode,17);
 await f.put(f.work+'/failed-original.json',JSON.stringify(await f.facts()));
 r=await f.invoke('compiler-recovered',['build','compiler']);assert.equal(r.status,0,r.stderr);
 for(const name of ['runtime','stdlib']){r=await f.invoke('recover-'+name,['build',name]);assert.equal(r.status,0,r.stderr);}
 r=await f.invoke('package-recovered',['package']);assert.equal(r.status,0,r.stderr);
 const previous=await fs.readdir(f.workspace+'/build');
 const attempts=await Promise.all(previous.filter(name=>name.startsWith('native-build.json.previous-')).map(name=>fs.readFile(f.workspace+'/build/'+name,'utf8').then(JSON.parse)));
 assert.ok(attempts.some(row=>row.commands.some(cmd=>cmd.stage==='compiler.install'&&cmd.exitCode===17)));
 console.log('STAGED_PREDECESSOR_RECOVERY_REACHED '+f.work);
});

test('first public install and same-install package receive repository scripts without preseed',async()=>{
 const f=await stagedFixture('scripts-first-public');
 const r=await f.invoke('run-all',['run-all','--skip-system-deps','--skip-install-libs']);assert.equal(r.status,0,r.stdout+r.stderr);
 console.log('INSTALLED_SCRIPTS_ASSERTION_REACHED');
 const archive=(await fs.readdir(path.dirname(f.sdk))).find(n=>n.startsWith('cangjie-sdk-')&&n.endsWith('.tar.gz'));
 for(const name of ['check_sdk_usable.mjs','verifier_artifact_gate.mjs']) {
  const actual=await fs.readFile(f.sdk+'/tools/'+name,'utf8');
  assert.equal(actual,await fs.readFile(new URL('../../scripts/'+name,import.meta.url),'utf8'));
  assert.equal(await fs.readFile(path.join(path.dirname(f.sdk),archive+'.unpacked/cangjie/tools/'+name),'utf8'),actual);
  assert.equal(await fs.stat(f.output+'/tools/'+name).catch(()=>null),null);
 }
 console.log('FIRST_INSTALL_PACKAGE_SCRIPTS_REACHED '+f.work);
});

test('public staged build does not inherit commands across source or configuration changes',async()=>{
 for(const change of ['source','configuration','toolchain']) {
  const f=await stagedFixture('changed-'+change);
  let r=await f.invoke('compiler',['build','compiler']);assert.equal(r.status,0,r.stderr);
  if(change==='source') {
   const repo=f.workspace+'/cangjie_compiler';await f.put(repo+'/tracked','changed compiler source');
   for(const args of [['-C',repo,'add','tracked'],['-C',repo,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','test: changed source']])assert.equal(run('git',args).status,0);
   f.selected.compiler.tag=run('git',['-C',repo,'rev-parse','HEAD']).stdout.trim();await f.put(f.workspace+'/.source-selection.json',JSON.stringify(f.selected));
  }
  const flags=change==='configuration'?['--build-type','debug']:[],overlay=change==='toolchain'?{CXX:'c++'}:{};
  r=await f.invoke('runtime-after-change',[...flags,'build','runtime'],overlay);assert.equal(r.status,0,r.stderr);
  console.log('CHANGED_INPUT_FACTS_ASSERTION_REACHED '+change);
  assert.equal((await f.facts()).commands.some(row=>row.stage.startsWith('compiler.')),false);
  r=await f.invoke('stdlib-after-change',[...flags,'build','stdlib'],overlay);assert.equal(r.status,0,r.stderr);
  r=await f.invoke('package-after-change',[...flags,'package'],overlay);assert.equal(r.status,1,r.stderr);assert.match(r.stderr,/INSTALLED_NATIVE_PRODUCTION/);
 }
});
