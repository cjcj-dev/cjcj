import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {buildCapacity} from '../../ci/build-resources.mjs';
import {toolsFor} from '../srcbuild/stages/tools.mjs';
import {makeRepos} from '../lib/config.mjs';
import {installEntries} from '../../ci/bootstrap/sdk-install-entries.mjs';
const producers=toolsFor();
const isProducer = (line,verb='') => new RegExp('build\\.(?:py|mjs)'+(verb?' '+verb:'')).test(line);
function assertCommands(lines,verb,selected=producers) {
 const commands=lines.filter(line=>isProducer(line,verb));
 assert.equal(commands.length,selected.length,verb+' count');
 for(const [name,dir]of selected)assert.equal(commands.filter(line=>line.includes('/'+dir)).length,1,verb+' exactly once: '+name);
}
const cli=new URL('../cli.mjs',import.meta.url).pathname;
test('public trace entry selects Cangjie build.mjs and requires its compiler mangle source',async t=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'trace-source-entry-'));t.after(()=>fs.rm(root,{recursive:true,force:true}));
 await fs.mkdir(root+'/cangjie_tools/cjtrace-recover/build',{recursive:true});
 const args=[cli,'--workspace',root,'--tools-phase','build','--tools-build-set','cjtrace-recover','--jobs','1'];
 const env={...process.env,CANGJIE_BUILD_DRY_RUN:'1'};delete env.CANGJIE_MANGLE_SOURCE_DIR;
 const missing=spawnSync(process.execPath,[...args,'build','tools'],{env,encoding:'utf8'});
 assert.equal(missing.status,1);assert.match(missing.stderr,/TOOLS_MANGLE_SOURCE_REQUIRED/);
 const explicit=spawnSync(process.execPath,[...args,'--tools-mangle-source',root+'/mangle','build','tools'],{env,encoding:'utf8'});
 assert.equal(explicit.status,0,explicit.stderr);
 assert.match(explicit.stderr,/build\.mjs build .*--cangjie-sdk .*--mangle-source/);
 assert.doesNotMatch(explicit.stderr,/python3 build\.py|git .*fetch|git .*restore/);
 assert(explicit.stderr.includes(root+'/mangle'));
 assert.match(explicit.stderr,/\$ORIGIN\/\.\.\/lib:\$ORIGIN\/\.\.\/\.\.\/\.\.\/runtime/);
 const invalid=spawnSync(process.execPath,[...args,'--tools-mangle-source','relative','build','tools'],{env,encoding:'utf8'});
 assert.equal(invalid.status,2);assert.match(invalid.stderr,/tools-mangle-source/);
 console.log('TRACE_PUBLIC_SOURCE_AND_SCRIPT_ASSERTION_REACHED');
});
test('public stdx tools profile selects existing producer options without changing the full default',async t=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'sdk-tools-profile-'));t.after(()=>fs.rm(root,{recursive:true,force:true}));
 await fs.mkdir(root+'/cangjie_stdx');
 const invoke=(profile,jobs='1',extra=[],budget=undefined)=>spawnSync(process.execPath,[cli,'--workspace',root,...(profile?['--stdx-profile',profile]:[]),...extra,'build','stdx'],{
  env:{...process.env,CANGJIE_MANGLE_SOURCE_DIR:root+'/mangle',CJCJ_NATIVE_TOOL_DEPENDENCIES:root+'/native-dependencies.json',CANGJIE_BUILD_DRY_RUN:'1',CANGJIE_BUILD_JOBS:jobs??undefined,CMAKE_BUILD_PARALLEL_LEVEL:undefined,KKK2_JOBS:budget},encoding:'utf8'});
 const limited=invoke('sdk-tools');assert.equal(limited.status,0,limited.stderr);
 assert.match(limited.stderr,/--skip-chir --skip-syntax --without-effect-handlers --jobs 1/);
 const full=invoke();assert.equal(full.status,0,full.stderr);assert.doesNotMatch(full.stderr,/--skip-chir|--skip-syntax|--without-effect-handlers/);
 const invalid=invoke('unknown');assert.equal(invalid.status,2);assert.match(invalid.stderr,/invalid stdx profile/);
 const jobs=invoke('sdk-tools','0');assert.equal(jobs.status,1);assert.match(jobs.stderr,/BUILD_JOBS invalid CANGJIE_BUILD_JOBS=0/);
 console.log('STDX_PROFILE_AND_INVALID_JOBS_CONTROL_PASS');
 const explicit=invoke('sdk-tools','16');assert.equal(explicit.status,0,explicit.stderr);
 console.log('STDX_EXPLICIT_JOBS_ASSERT_REACHED');
 assert.match(explicit.stderr,/--jobs 16(?:\s|$)/);
 const argument=invoke(undefined,'1',['--jobs','16']);assert.equal(argument.status,0,argument.stderr);
 assert.match(argument.stderr,/--jobs 16(?:\s|$)/);
 const budget=invoke(undefined,'16',[],'2');assert.equal(budget.status,1);
 assert.match(budget.stderr,/BUILD_JOBS CANGJIE_BUILD_JOBS=16 exceeds declared KKK2_JOBS budget=2/);
 const fallback=invoke(undefined,null);assert.equal(fallback.status,0,fallback.stderr);
 assert.match(fallback.stderr,new RegExp('--jobs '+(await buildCapacity()).cpus+'(?:\\s|$)'));
 const incremental=spawnSync(process.execPath,[cli,'--workspace',root,'--stdx-build-mode','incremental','build','stdx'],{
  env:{...process.env,CANGJIE_MANGLE_SOURCE_DIR:root+'/mangle',CJCJ_NATIVE_TOOL_DEPENDENCIES:root+'/native-dependencies.json',CANGJIE_BUILD_DRY_RUN:'1',CANGJIE_BUILD_JOBS:'2'},encoding:'utf8'});
 assert.equal(incremental.status,0,incremental.stderr);assert.doesNotMatch(incremental.stderr,/build.py clean/);
 assert.match(incremental.stderr,/build.py build/);assert.match(incremental.stderr,/build.py install/);
 console.log('TOOLS_PROFILE_PUBLIC_CONFIG_REACHED limited=1 full=1 invalid-profile=1 invalid-jobs=1; no compilation');
});

test('public nine-tool stage separates the total CPU and heavy package budgets',async t=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'sdk-tool-jobs-'));t.after(()=>fs.rm(root,{recursive:true,force:true}));
 const tools=root+'/cangjie_tools';
 for(const relative of [...producers.map(([,dir])=>dir),'cjpm/dist'])await fs.mkdir(tools+'/'+relative,{recursive:true});
 await fs.writeFile(tools+'/cjpm/build/build.py','# controlled command-generation input\n');
 await fs.writeFile(tools+'/cjpm/dist/cjpm','controlled output existence; no compiled tool\n');
 const env={...process.env,CANGJIE_MANGLE_SOURCE_DIR:root+'/mangle',CJCJ_NATIVE_TOOL_DEPENDENCIES:root+'/native-dependencies.json',CANGJIE_BUILD_DRY_RUN:'1',CANGJIE_BUILD_JOBS:'1'};
 const p=spawnSync(process.execPath,[cli,'--workspace',root,'build','tools'],{env,encoding:'utf8'});
 assert.equal(p.status,0,p.stderr);
 const lines=p.stderr.split('\n').filter(s=>isProducer(s,'build'));
 assertCommands(lines,'build');
 assert(lines.some(s=>s.includes('/cjcompat/build')&&s.includes('--sdk '+root+'/software/cangjie')));
 for(const name of ['cjpm','cjfmt','cangjie-language-server','cjlint','cjprof','cjcompat'])assert(lines.some(s=>s.includes('/'+name+'/build')&&s.includes('--jobs 1')));
 for(const name of ['hyperlangExtension','cjcov','cjtrace-recover'])assert(lines.some(s=>s.includes('/'+name+'/build')&&!s.includes('--jobs')));
 const selectedSdk=root+'/selected-sdk';await fs.mkdir(selectedSdk);
 const selected=spawnSync(process.execPath,[cli,'--workspace',root,'build','tools'],{env:{...env,CJCJ_SRCBUILD_CONSUMER_SDK:selectedSdk},encoding:'utf8'});
 assert.equal(selected.status,0,selected.stderr);
 const selectedCompat=selected.stderr.split('\n').find(s=>s.includes('/cjcompat/build')&&isProducer(s,'build'));
 assert(selectedCompat?.includes('--sdk '+selectedSdk),'explicit SDK reaches actual cjcompat producer');
 const wide=spawnSync(process.execPath,[cli,'--workspace',root,'build','tools'],{env:{...env,CANGJIE_BUILD_JOBS:'64'},encoding:'utf8'});
 assert.equal(wide.status,0,wide.stderr);
 const wideLines=wide.stderr.split('\n').filter(s=>isProducer(s,'build'));
 assertCommands(wideLines,'build');
 const budget=JSON.parse(wide.stderr.split('TOOLS_BUDGET ')[1].split('\n')[0]);
 assert.equal(budget.totalJobs,Math.min(64,os.availableParallelism()));
 assert.equal(budget.heavyProducerLimit,4);
 for(const [name,dir]of [['cjpm','cjpm'],['cjfmt','cjfmt'],['lsp','cangjie-language-server']])assert(wideLines.some(s=>s.includes('/'+dir+'/build')&&s.includes('--jobs '+budget.plan[name].jobs)));
 // All selected producers first get one CPU each; the fixed scheduler then gives
 // cjpm up to three additional CPUs before widening the native tools.
 if(budget.totalJobs>=producers.length+5){assert(budget.plan.lsp.jobs>1);assert(budget.plan.cjfmt.jobs>1);}
 if(budget.totalJobs>=producers.length){
  assert.equal(Object.values(budget.plan).reduce((n,row)=>n+row.jobs,0),budget.totalJobs);
  const cpus=Object.values(budget.plan).flatMap(row=>row.cpuSet.split(','));
  assert.equal(new Set(cpus).size,cpus.length,'concurrent tool CPU allocations must not overlap');
  assert.equal(budget.plan.cjpm.jobs,Math.min(4,budget.totalJobs-(producers.length-1)),'explicit cjpm priority stays bounded');
 }
 const incremental=spawnSync(process.execPath,[cli,'--workspace',root,'--tools-build-mode','incremental','build','tools'],{env,encoding:'utf8'});
 assert.equal(incremental.status,0,incremental.stderr);
 assert.doesNotMatch(incremental.stderr,/build.py clean/);
 const incrementalLines=incremental.stderr.split('\n').filter(s=>isProducer(s));
 assertCommands(incrementalLines,'build');
 assertCommands(incrementalLines,'install');
 const firstInstall=incrementalLines.findIndex(s=>isProducer(s,'install'));
 assert.equal(firstInstall,producers.length,'all selected producers precede installation');
 assert(incrementalLines.slice(firstInstall).every(line=>isProducer(line,'install')),'no late build after shared install begins');
 const invalidMode=spawnSync(process.execPath,[cli,'--workspace',root,'--tools-build-mode','unknown','build','tools'],{env,encoding:'utf8'});
 assert.equal(invalidMode.status,2);assert.match(invalidMode.stderr,/invalid tools build mode/);
 console.log(`NINE_TOOL_JOB_ARGUMENTS_REACHED commands=${producers.length} explicit-interfaces=6; no compilation`);
});


test('public tool build selection retains a complete install and rejects ambiguous sets',async t=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'sdk-tool-selection-'));t.after(()=>fs.rm(root,{recursive:true,force:true}));
 const tools=root+'/cangjie_tools';
 for(const dir of [...producers.map(([,dir])=>dir),'cjpm/dist'])await fs.mkdir(tools+'/'+dir,{recursive:true});
 await fs.writeFile(tools+'/cjpm/build/build.py','# command generation fixture\n');await fs.writeFile(tools+'/cjpm/dist/cjpm','controlled existence; no compiled tool\n');
 const invoke=(set,phase='all')=>spawnSync(process.execPath,[cli,'--workspace',root,'--tools-build-set',set,'--tools-phase',phase,'--tools-build-mode','incremental','build','tools'],{
  env:{...process.env,CANGJIE_MANGLE_SOURCE_DIR:root+'/mangle',CJCJ_NATIVE_TOOL_DEPENDENCIES:root+'/native-dependencies.json',CANGJIE_BUILD_DRY_RUN:'1',CANGJIE_BUILD_JOBS:'4'},encoding:'utf8'});
 const p=invoke('cjpm,lsp,cjcov,cjtrace-recover');assert.equal(p.status,0,p.stderr);
 const lines=p.stderr.split('\n').filter(s=>isProducer(s));
 const builds=lines.filter(s=>isProducer(s,'build'));assert.equal(builds.length,4);
 assert(!builds.some(s=>s.includes('/cjfmt/')||s.includes('/hyperlangExtension/')));
 assertCommands(lines,'install');
 assert.equal(lines.findIndex(s=>isProducer(s,'install')),4);
 assert(!lines.some(s=>isProducer(s,'clean')));
 const install=invoke('all','install');assert.equal(install.status,0,install.stderr);
 assert.doesNotMatch(install.stderr,/build.py (?:build|clean)/);
 assertCommands(install.stderr.split('\n'),'install');
 for(const invalid of ['hle,hle','all,cjpm','unknown','']) {const r=invoke(invalid);assert.equal(r.status,2,r.stderr);assert.match(r.stderr,/invalid tools build set/);}
});

 test('public independent tool build has no shared install and uses its CPU allocation',async t=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'sdk-tool-independent-'));t.after(()=>fs.rm(root,{recursive:true,force:true}));
 for(const dir of ['cjpm/build','cjcov/build','cjtrace-recover/build','cjlint/build','cjprof/build','cjcompat/build'])await fs.mkdir(root+'/cangjie_tools/'+dir,{recursive:true});
 await fs.writeFile(root+'/cangjie_tools/cjpm/build/build.py','# fixed fixture\n');
 const args=[cli,'--workspace',root,'--tools-build-set','cjcov,cjtrace-recover','--tools-phase','build','--tools-build-mode','incremental','--jobs','63','--tools-package-jobs','3','build','tools'];
 const env={...process.env,CANGJIE_MANGLE_SOURCE_DIR:root+'/mangle',CJCJ_NATIVE_TOOL_DEPENDENCIES:root+'/native-dependencies.json',CANGJIE_BUILD_DRY_RUN:'1',CANGJIE_BUILD_JOBS:'1'};
 const r=spawnSync(process.execPath,args,{env,encoding:'utf8'});assert.equal(r.status,0,r.stderr);
 assert.doesNotMatch(r.stderr,/build.py install|build.py clean/);
 assert.equal(r.stderr.split('\n').filter(s=>isProducer(s,'build')).length,2);
 const budget=JSON.parse(r.stderr.split('TOOLS_BUDGET ')[1].split('\n')[0]);assert.equal(budget.totalJobs,Math.min(63,os.availableParallelism()));
 if(budget.totalJobs>1)assert.equal(budget.plan['cjtrace-recover'].jobs,budget.totalJobs-1);
 for(const [flag,value]of [['--jobs','0'],['--tools-package-jobs','5'],['--tools-phase','bad']]){
  const a=[...args];a[a.indexOf(flag)+1]=value;assert.equal(spawnSync(process.execPath,a,{env,encoding:'utf8'}).status,2);
 }
 });


// Finite public-entry propagation: real Python children, tool installer/native
// launchers, installed hello and supervised regression. The nine bodies and
// regression are controlled interfaces, not cjpm/SDK functional qualification.
let regressionFixture;
async function installedRegressionFixture() {
 if(regressionFixture)return regressionFixture;
 regressionFixture=(async()=>{
  const base=process.env.RELEASE_EVIDENCE_TEST_ROOT||os.tmpdir();
  await fs.mkdir(base,{recursive:true});
  const root=process.env.CJPM_WIRE_FIXTURE||await fs.mkdtemp(path.join(base,'cjpm-install-wire-'));
  const workspace=root+'/workspace',sdk=root+'/sdk',tools=workspace+'/cangjie_tools';
  const write=async(file,body,mode=0o644)=>{await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,body,{mode});};
  const trace=root+'/events.jsonl',commands=root+'/commands.jsonl';
  if(!await fs.stat(root+'/fixture-ready').catch(()=>null)) {
   await fs.mkdir(sdk,{recursive:true});await fs.mkdir(root+'/official',{recursive:true});
   const hello='#!/bin/sh\nprintf "Hello, Cangjie\\n"\n';
   await write(sdk+'/bin/cjcj-stage1','#!'+process.execPath+'\n'+
    `const fs=require('node:fs');const out=process.argv[process.argv.indexOf('-o')+1];fs.writeFileSync(out,${JSON.stringify(hello)},{mode:0o755});\n`,0o755);
   // The real pending-tools consumer copies the installed compiler entry and
   // execution closure. Produce that entry through the existing installer;
   // this compiler body remains an explicitly controlled hello fixture.
   await fs.mkdir(sdk+'/tools/lib',{recursive:true});
   await installEntries({root:sdk,build:root+'/compiler-entry',platform:'linux_x86_64',
    groups:[{directory:'bin',retain:'libexec/compiler',names:['cjcj-stage1'],libraries:['tools/lib']}]});
   await fs.symlink('cjcj-stage1',sdk+'/bin/cjc');
   // Do not copy Node or any SDK; these unrelated HLE inputs are unused markers.
   for(const file of ['tools/bin/node','tools/dtsparser/node_modules/.bin/cjbind','tools/dtsparser/DEPENDENCIES.json'])await write(sdk+'/'+file,'controlled unused HLE boundary');
   const outputs={cjpm:'cjpm/dist/cjpm',cjfmt:'cjfmt/dist/bin/cjfmt',hle:'hyperlangExtension/target/bin/main',lsp:'cangjie-language-server/output/bin/LSPServer',cjcov:'cjcov/dist/cjcov','cjtrace-recover':'cjtrace-recover/dist/bin/cjtrace-recover',cjlint:'cjlint/dist/bin/cjlint',cjprof:'cjprof/dist/bin/cjprof',cjcompat:'cjcompat/dist/bin/cjcompat'};
   const buildProducts={...outputs,cjfmt:'cjfmt/build/build/bin/cjfmt','cjtrace-recover':'cjtrace-recover/cmake-build/cjtrace-recover',cjlint:'cjlint/build/build/bin/cjlint',cjprof:'cjprof/build/build/src/cjprof',cjcompat:'cjcompat/build/cangjie-build/cjcompat'};
   const cjpm='#!'+process.execPath+'\n'+`const fs=require('node:fs');const path=require('node:path');
fs.appendFileSync(${JSON.stringify(trace)},JSON.stringify({event:'installed-cjpm',args:process.argv.slice(2),cwd:process.cwd()})+'\\n');
if(process.argv[2]==='build'){const out=path.resolve('target/release/bin/main');fs.mkdirSync(path.dirname(out),{recursive:true});fs.writeFileSync(out,${JSON.stringify(hello)},{mode:0o755});}
`;
   for(const [name,dir]of producers) {
    const body=name==='cjpm'?cjpm:'#!'+process.execPath+'\nconsole.log("controlled tool");\n';
    const payloads=name==='cjpm'?{'cjpm/dist/cangjie-repo.toml':'fixture repo'}:
     name==='cjfmt'?{'cjfmt/dist/config/cangjie-format.toml':'fixture format'}:
     name==='cjlint'?{'cjlint/dist/lib/libcjlint.so':'unloaded fixture','cjlint/dist/config/rules.json':'{}'}:
     name==='cjprof'?{'cjprof/dist/lib/libcjprof.so':'unloaded fixture','cjprof/dist/lib/libcjprof-jni.so':'unloaded fixture','cjprof/dist/config/static/index.html':'fixture page'}:{};
    if(['cjtrace-recover','cjcompat'].includes(name)) {
     await write(tools+'/'+dir+'/build.mjs',`import fs from 'node:fs';import path from 'node:path';
const verb=process.argv[2];fs.appendFileSync(${JSON.stringify(trace)},JSON.stringify({event:'producer',name:${JSON.stringify(name)},verb})+'\\n');
if(verb==='build'||verb==='install') {const out=path.join(${JSON.stringify(tools)},verb==='build'?${JSON.stringify(buildProducts[name])}:${JSON.stringify(outputs[name])});fs.mkdirSync(path.dirname(out),{recursive:true});fs.writeFileSync(out,${JSON.stringify(body)},{mode:0o755});}
`);
     continue;
    }
    await write(tools+'/'+dir+'/build.py',`import pathlib,sys,json,os
root=pathlib.Path(${JSON.stringify(tools)})
verb=sys.argv[1]
with open(${JSON.stringify(trace)},'a') as f:f.write(json.dumps({'event':'producer','name':${JSON.stringify(name)},'verb':verb})+'\\n')
if verb in ('build','install'):
 out=root/${JSON.stringify(buildProducts[name])} if verb=='build' else root/${JSON.stringify(outputs[name])}
 out.parent.mkdir(parents=True,exist_ok=True);out.write_text(${JSON.stringify(body)});out.chmod(0o755)
 if verb=='install':
  for rel,value in json.loads(${JSON.stringify(JSON.stringify(payloads))}).items():
   p=root/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(value)
`);
   }
   await write(tools+'/cjfmt/dist/config/cangjie-format.toml','fixture format');
   await write(tools+'/cjpm/tests/public/test-cache-errors.mjs',`import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';import {spawnSync} from 'node:child_process';
const [cjpm,out,arm]=process.argv.slice(2);const pending=path.dirname(path.dirname(path.dirname(cjpm)));assert.equal(path.dirname(pending),${JSON.stringify(root)});assert(path.basename(pending).startsWith('sdk.tools-pending-'));assert.equal(cjpm,path.join(pending,'tools/bin/cjpm'));assert(path.isAbsolute(cjpm));assert.equal(arm,'candidate');assert.deepEqual(fs.readdirSync(out),[]);assert.equal(process.env.CJPM_REGRESSION_CASES,undefined);assert.equal(process.env.CJPM_REGRESSION_PRIVATE_SDK,pending);assert.equal(process.env.CANGJIE_HOME,pending);assert(process.env.PATH.startsWith(pending+'/bin:'+pending+'/tools/bin:'));assert(!process.env.LD_LIBRARY_PATH.includes('foreign-sdk'));assert.equal(process.env.CPATH,undefined);
const r=spawnSync(cjpm,['wire-public-consumer'],{encoding:'utf8'});assert.equal(r.status,0,r.stderr);
const row={event:'regression',cjpm,out,arm,cases:process.env.CJPM_REGRESSION_CASES,rc:process.env.CJPM_WIRE_FAIL==='1'?23:0};fs.writeFileSync(path.join(out,'result.json'),JSON.stringify(row));fs.appendFileSync(${JSON.stringify(trace)},JSON.stringify(row)+'\\n');console.log('CJPM_PUBLIC_BODY_REACHED '+JSON.stringify(row));process.exitCode=row.rc;
`);
   // Same module-load boundary technique as runtime-component-source. Keep the
   // tools stage, tools installer, hello, command and supervisor untouched.
   // Outer compiler/runtime/SDK production and qualification are controlled;
   // source pin/network are exercised separately by the actual source gate.
   const boundaries={
    'build/lib/git.mjs':{fetchSource:'return;',assertSourceIdentity:'return;'},
    'ci/bootstrap/sdk-inputs.mjs':{prepareSourceBuildInputs:'return {...arguments[0],installInputs:{install:arguments[0].consumerSdk}};'},
    'ci/bootstrap/sdk-flow.mjs':{installProducts:'return arguments[1].consume(arguments[0].install);'},
    'ci/bootstrap/sdk-verify-install.mjs':{verifyInstall:'return;'},
    'build/srcbuild/native-tool-dependencies.mjs':{prepareNativeToolDependencies:'return;'},
    'build/srcbuild/hle-dependencies.mjs':{installHleDependencies:'return;'},
    'build/srcbuild/tool-build-inputs.mjs':Object.fromEntries(['beginToolBuild','finishToolBuild','toolBuildInputs','finishToolInstall','installedToolBuildInputs'].map(name=>[name,"return {source:{status:'unresolved'},fixture:'production qualification NOT_RUN'};"])),
   };
   for(const file of ['fetch','compiler','runtime','stdlib','stdx','verify'])boundaries['build/srcbuild/stages/'+file+'.mjs']={run:'return;'};
   // Observable boundary for the existing run-all package call. A success
   // control must reach it; a regression failure must never reach it.
   boundaries['build/srcbuild/stages/package.mjs']={run:`recordBoundary(${JSON.stringify(trace)},JSON.stringify({event:'package'})+'\\n');`};
   const repo=new URL('../../',import.meta.url).href;
   await write(root+'/boundaries.json',JSON.stringify(boundaries,null,2));
   await write(root+'/loader.mjs',`import fs from 'node:fs';
const boundaries=${JSON.stringify(Object.fromEntries(Object.entries(boundaries).map(([p,v])=>[new URL(p,repo).href,v])))};
export async function load(url,context,next){const r=await next(url,context);if(!boundaries[url]&&url!==${JSON.stringify(new URL('build/lib/runner.mjs',repo).href)})return r;let source=String(r.source);if(boundaries[url])source+="\\nimport {appendFileSync as recordBoundary} from 'node:fs';\\n";
if(boundaries[url]){for(const [name,body]of Object.entries(boundaries[url])){const re=new RegExp('export (async )?function '+name+'\\\\(');if(!re.test(source))throw Error('BOUNDARY_ANCHOR '+name);source=source.replace(re,(_,a='')=>a+'function CONTROLLED_ORIGINAL_'+name+'(');source+='\\nexport function '+name+'(){'+body+'}\\n';}}
if(url===${JSON.stringify(new URL('build/lib/runner.mjs',repo).href)}){source=source.replace('export async function run(', 'async function originalRun(');source+='\\nexport async function run(argv,options){if(argv[0]==="git"&&argv[1]==="rev-parse")return {exitCode:0,stdout:"${makeRepos().cjpm.tag}\\\\n"};if(argv[0]==="git"&&argv[1]==="restore")return {exitCode:0,stdout:""};return originalRun(argv,options);}\\n';}
return {...r,source};}
`);
   await write(root+'/fixture-ready','finite interface, not a qualified SDK\n');
  }
  const env={...process.env,CANGJIE_MANGLE_SOURCE_DIR:root+'/mangle',NODE_OPTIONS:'--experimental-loader='+root+'/loader.mjs',CJCJ_SRCBUILD_CONSUMER_SDK:sdk,CJCJ_OFFICIAL_SDK_ROOT:root+'/official',CANGJIE_HOME:root+'/foreign-sdk',LD_LIBRARY_PATH:root+'/foreign-sdk/lib',CPATH:root+'/foreign-sdk/include',CJPM_REGRESSION_CASES:'one-case-only',CANGJIE_BUILD_JOBS:'2',CJCJ_SUPERVISOR_WORK:root+'/supervision'};
  delete env.CANGJIE_BUILD_DRY_RUN;delete env.CJCJ_HLE_DEPENDENCIES;
  const readEvents=async()=>{const text=await fs.readFile(trace,'utf8').catch(()=> '');return text.trim()?text.trim().split('\n').map(line=>JSON.parse(line)):[];};
  const invoke=async(label,extra=[],command=['build','tools'],overlay={})=>{
   const before=(await readEvents()).length;
   const argv=[cli,'--workspace',workspace,'--build-root',root+'/buildtools','--host-profile','kkk2','--jobs','2',...extra,...command];
   const out=await fs.open(root+'/'+label+'.stdout','wx'),err=await fs.open(root+'/'+label+'.stderr','wx');
   const r=spawnSync(process.execPath,argv,{env:{...env,...overlay},stdio:['ignore',out.fd,err.fd]});await out.close();await err.close();
   await fs.appendFile(commands,JSON.stringify({label,argv:[process.execPath,...argv],pid:r.pid,rc:r.status,signal:r.signal})+'\n');
   return {...r,stderr:await fs.readFile(root+'/'+label+'.stderr','utf8'),events:(await readEvents()).slice(before)};
  };
  const prefix='attempt-'+Date.now();
  console.log('CJPM_INSTALL_WIRE_FIXTURE '+root);
  return {root,sdk,workspace,trace,env,invoke:(label,...args)=>invoke(prefix+'-'+label,...args)};
 })();return regressionFixture;
}

test('installed cjpm public regression follows tools installation and blocks package',async()=>{
 const f=await installedRegressionFixture(),outs=[];
 for(const [label,args]of [['first',[]],['incremental',['--tools-build-mode','incremental']],['install',['--tools-phase','install']]]) {
  const r=await f.invoke(label,args);assert.equal(r.status,0,r.stderr);
  const installed=JSON.parse(await fs.readFile(f.sdk+'/TOOLS-INPUTS.json','utf8'));assert.equal(Object.keys(installed.files).length,9);
  assert.equal(JSON.parse(await fs.readFile(f.workspace+'/verify-tools/hello-result.json','utf8')).packaged.rc,0);
  assert.equal(r.events.filter(e=>e.event==='producer'&&e.verb==='install').length,9);
  console.log('CJPM_INSTALL_AND_HELLO_CONTROL_REACHED '+label);
  const rows=r.events.filter(e=>e.event==='regression');
  console.log('CJPM_POST_INSTALL_CALL_ASSERT_REACHED '+label);
  assert.equal(rows.length,1,'installed public regression must be called once after installation');
  const pending=path.dirname(path.dirname(path.dirname(rows[0].cjpm)));assert.equal(path.dirname(pending),f.root);assert(path.basename(pending).startsWith('sdk.tools-pending-'));assert.equal(rows[0].cjpm,path.join(pending,'tools/bin/cjpm'));outs.push(rows[0].out);
  assert(r.events.findIndex(e=>e.event==='regression')>r.events.findLastIndex(e=>e.event==='producer'));
  if(label==='install')assert(!r.events.some(e=>e.event==='producer'&&e.verb==='build'));
 }
 assert.equal(new Set(outs).size,3,'each invocation owns a fresh empty regression directory');
 const buildOnly=await f.invoke('build-only',['--tools-phase','build','--tools-build-set','cjpm']);assert.equal(buildOnly.status,0,buildOnly.stderr);assert(!buildOnly.events.some(e=>e.event==='regression'));
 const dry=await f.invoke('dry',[],['build','tools'],{CANGJIE_BUILD_DRY_RUN:'1'});assert.equal(dry.status,0,dry.stderr);assert.equal(dry.events.length,0);
 const command=['run-all','--skip-system-deps','--skip-install-libs'];
 const failed=await f.invoke('failure',['--tools-phase','install'],command,{CJPM_WIRE_FAIL:'1'});
 assert.equal(failed.status,1,failed.stderr);assert.match(failed.stderr,/TARGET_FAILED rc=23/);
 const rejected=failed.events.find(e=>e.event==='regression');assert.equal(rejected.rc,23);assert(!failed.events.some(e=>e.event==='package'));
 assert.equal(JSON.parse(await fs.readFile(rejected.out+'/result.json','utf8')).rc,23,'failure directory retained');
 const restored=await f.invoke('restored',['--tools-phase','install'],command);assert.equal(restored.status,0,restored.stderr);
 assert.equal(restored.events.filter(e=>e.event==='regression').length,1);assert.equal(restored.events.filter(e=>e.event==='package').length,1);
 console.log('CJPM_FAILURE_BLOCKS_PUBLIC_PACKAGE_AND_RESTORES');
});

test('installed cjpm hello remains independent of the full regression call',async()=>{
 const f=await installedRegressionFixture();
 const installed=await f.invoke('independent-hello-preparation');
 assert.equal(installed.status,0,installed.stderr);
 const {helloInstall}=await import('../../ci/bootstrap/sdk-hello.mjs');
 await helloInstall({sdk:f.sdk,work:f.root+'/independent-hello-'+Date.now(),platform:'linux_x86_64'});
 console.log('CJPM_INDEPENDENT_INSTALLED_HELLO_PASS');
});

// Keep the public tools/installation/hello path real. Only the compiler and
// nine producer bodies are the existing controlled fixture, not official H.
test('public tools install accepts direct compiler SDKs and retains the staged recipe requirement',async()=>{
 const f=await installedRegressionFixture(),entry=f.sdk+'/bin/cjcj-stage1.entry';
 const saved=await fs.readFile(entry),raw=await fs.readFile(f.sdk+'/libexec/compiler/cjcj-stage1');
 await fs.rename(f.sdk+'/bin',f.sdk+'/bin-staged-control');
 await fs.mkdir(f.sdk+'/bin');await fs.writeFile(f.sdk+'/bin/cjc',raw,{mode:0o755});
 try {
  const normal=await f.invoke('direct-compiler');assert.equal(normal.status,0,normal.stderr);
  console.log('TOOLS_DIRECT_COMPILER_CONSUMER_REACHED');
  assert.equal(normal.events.filter(e=>e.event==='regression').length,1);
  assert.equal(JSON.parse(await fs.readFile(f.workspace+'/verify-tools/hello-result.json')).packaged.rc,0);
  assert.equal(await fs.stat(f.sdk+'/STAGE-INPUTS.json').catch(()=>null),null);
  assert.equal(await fs.stat(entry).catch(()=>null),null);
  // A staged SDK with a lost recipe must reject before its compiler consumer.
  await fs.writeFile(f.sdk+'/STAGE-INPUTS.json','{"fixture":"staged SDK marker"}');
  const missing=await f.invoke('missing-staged-recipe',['--tools-phase','install']);
  assert.equal(missing.status,1,missing.stderr);
  assert.match(missing.stderr,/TOOL_CONSUMER_COMPILER_ENTRY missing staged launcher recipe/);
  assert(!missing.events.some(e=>e.event==='regression'));
  console.log('TOOLS_STAGED_MISSING_RECIPE_REJECTED');
  await fs.unlink(f.sdk+'/STAGE-INPUTS.json');
 }finally {
  await fs.rm(f.sdk+'/STAGE-INPUTS.json',{force:true});
  await fs.rename(f.sdk+'/bin',f.sdk+'/bin-direct-evidence');
  await fs.rename(f.sdk+'/bin-staged-control',f.sdk+'/bin');
 }
 assert.deepEqual(await fs.readFile(entry),saved);
 const restored=await f.invoke('staged-recipe-restored',['--tools-phase','install']);
 assert.equal(restored.status,0,restored.stderr);
 assert.equal(restored.events.filter(e=>e.event==='regression').length,1);
 console.log('TOOLS_STAGED_RECIPE_CONTROL_RESTORED');
});


test('public independent install selects native upstream prefixes without HLE or SDK publication',async t=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'native-tool-prefix-'));
 t.after(()=>fs.rm(root,{recursive:true,force:true}));
 for(const name of ['cjfmt','cangjie-language-server','cjlint','cjprof','cjcompat'])await fs.mkdir(root+'/cangjie_tools/'+name+'/build',{recursive:true});
 const env={...process.env,CANGJIE_MANGLE_SOURCE_DIR:root+'/mangle',CANGJIE_BUILD_DRY_RUN:'1',CANGJIE_BUILD_JOBS:'1'};
 const invoke=(extra=[])=>spawnSync(process.execPath,[cli,'--workspace',root,
  '--tools-phase','install','--tools-build-set','cjfmt,lsp,cjlint,cjprof,cjcompat',
  '--tools-install-prefix',root+'/installed',...extra,'build','tools'],{env,encoding:'utf8'});
 const r=invoke();assert.equal(r.status,0,r.stderr);
 assertCommands(r.stderr.split('\n'),'install',producers.filter(([name])=>['cjfmt','lsp','cjlint','cjprof','cjcompat'].includes(name)));
 assert.doesNotMatch(r.stderr,/build.py (?:build|clean)|cjpm.checkout|hle.dependencies/);
 for(const name of ['cjfmt','cjlint','cjprof','cjcompat'])assert(r.stderr.includes('--prefix '+root+'/installed/'+name));
 assert(r.stderr.includes('--prefix '+root+'/installed/lsp/bin'));
 for(const args of [['--tools-phase','build'],['--tools-build-set','all'],['--tools-install-prefix','relative']]) {
  const invalid=invoke(args);assert.equal(invalid.status,2,invalid.stderr);assert.match(invalid.stderr,/tools-install-prefix requires/);
 }
 const hle=invoke(['--tools-build-set','hle']);assert.equal(hle.status,1,hle.stderr);assert.match(hle.stderr,/independent install requires native tools/);
});

test('public Cangjie cjcompat receives the selected shared frontend inputs',async t=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'compat-source-entry-'));t.after(()=>fs.rm(root,{recursive:true,force:true}));
 await fs.mkdir(root+'/cangjie_tools/cjcompat/build',{recursive:true});
 const options=['--tools-compiler-libs',root+'/selected-libs','--tools-runtime-config',root+'/config.o','--tools-llvm-shim',root+'/shim.o','--tools-llvm-library',root+'/libLLVM.so'];
 const r=spawnSync(process.execPath,[cli,'--workspace',root,'--tools-phase','build','--tools-build-set','cjcompat','--jobs','1',...options,'build','tools'],{encoding:'utf8',env:{...process.env,CANGJIE_BUILD_DRY_RUN:'1'}});
 assert.equal(r.status,0,r.stderr);
 for(const [flag,file]of [['--compiler-libs','selected-libs'],['--runtime-config','config.o'],['--shim','shim.o'],['--llvm','libLLVM.so']])assert(r.stderr.includes(flag+' '+root+'/'+file));
 assert.match(r.stderr,/build\.mjs build --type release/);
 assert.doesNotMatch(r.stderr,/build\.py|build\.mjs clean/);
});
