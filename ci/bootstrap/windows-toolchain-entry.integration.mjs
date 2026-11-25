#!/usr/bin/env zx
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {load} from '../vendor/js-yaml/js-yaml.mjs';
import {createBootstrapTargets,FIXED_INPUTS} from './sdk-targets.mjs';
import {readHostToolchainPin} from '../host-toolchain-pin.mjs';
import {installedInputs} from '../../build/sdk/producers/srcbuild/lib/installed-inputs.mjs';
const root=process.env.WINDOWS_TOOLCHAIN_ENTRY_EVIDENCE;if(!root)throw Error('WINDOWS_TOOLCHAIN_ENTRY_EVIDENCE required');
await fs.mkdir(root,{recursive:true});
const hash=b=>createHash('sha256').update(b).digest('hex');
const put=async(f,s)=>{await fs.mkdir(path.dirname(f),{recursive:true});await fs.writeFile(f,s);};
const json=async(f,s)=>put(f,JSON.stringify(s,null,2));
const entry=new URL('./native-cjdb-job.mjs',import.meta.url).pathname;
const child=new URL('../fixtures/native-windows-job-child.mjs',import.meta.url).pathname;
let seq=0;const records=[];
async function run(label,argv,env=process.env){
 const base=root+'/'+String(++seq).padStart(3,'0')+'-'+label;
 const out=await fs.open(base+'.stdout','wx'),err=await fs.open(base+'.stderr','wx');
 const r=spawnSync(argv[0],argv.slice(1),{env,stdio:['ignore',out.fd,err.fd],timeout:120000});await out.close();await err.close();
 records.push({label,argv,rc:r.status,signal:r.signal,error:r.error?.message});await json(root+'/commands.json',records);
 return{rc:r.status,stdout:await fs.readFile(base+'.stdout','utf8'),stderr:await fs.readFile(base+'.stderr','utf8')};
}
test('formal Windows native action selects the fixed MSVCRT package without replacing other source-stage tools',async()=>{
 const wf=load(await fs.readFile(new URL('../../.github/workflows/sdk-build-target.yml',import.meta.url),'utf8'));
 const action=load(await fs.readFile(new URL('../../.github/actions/native-windows-tools/action.yml',import.meta.url),'utf8'));
 const job=wf.jobs['native-cjdb'],selected=job.steps.find(s=>s.uses==='./.github/actions/native-windows-tools');
 assert.equal(selected.with['native-compiler'],'true');assert.equal(action.inputs['native-compiler'].default,'false');
 assert.match(job.steps.find(s=>s.name==='Materialize native producer inputs').run,/native-cjdb-job.mjs materialize/);
 const install=action.runs.steps.at(-1);assert.equal(install.if,"inputs.native-compiler == 'true'");
 const bad=root+'/bad.zip';await put(bad,'incorrect archive bytes');
 const command=install.run.replace('node ci/bootstrap/install-windows-toolchain.mjs',JSON.stringify(process.execPath)+' '+JSON.stringify(child)+' installer');
 const attempted=await run('action-bad-archive',['bash','-e','-c',command+' '+JSON.stringify(bad)],{...process.env,RUNNER_TEMP:root,GITHUB_ENV:root+'/tool-env',GITHUB_PATH:root+'/tool-path'});
 assert.equal(attempted.rc,1);assert.match(attempted.stderr,/WINDOWS_TOOLCHAIN_ARCHIVE/);
 assert.equal(await fs.stat(root+'/tool-env').then(()=>true,()=>false),false);
 const {WINDOWS_TOOLCHAIN:p}=await import('./install-windows-toolchain.mjs');
 assert.equal(p.url,'https://github.com/mstorsjo/llvm-mingw/releases/download/20261020/llvm-mingw-20261020-msvcrt-x86_64.zip');
 assert.equal(p.sha256,'52a3e3f584a74c3cde8ceb0c6960549683178e03b36818cb02b7ed109a68ff67');
});
test('public raw materialization overlays the actual new source config and preserves original dependency bytes',async()=>{
 const base=root+'/raw',art=root+'/artifact',input=root+'/input';await fs.mkdir(base);await fs.mkdir(art);
 const original={platform:'windows_x86_64',commits:{compiler:'f07c55738c12c154160c313c630a42a73a51025d'},compilerArchive:{file:'old.tar',sha256:hash('old')}};
 await json(base+'/native-cjdb.json',original);await put(base+'/old.tar','old');await put(base+'/dep.tar','unchanged dependency');
 assert.equal((await run('tar',['tar','-cf',art+'/native-build-inputs.tar','-C',base,'.'])).rc,0);
 const next={...original,commits:{compiler:'53da07662223e1dbaa7711f4ef149d6ae7b3afea'},compilerArchive:{file:'compiler-53da.tar',sha256:hash('new controlled source')}};
 await json(art+'/native-cjdb.json',next);await put(art+'/compiler-53da.tar','new controlled source');
 assert.equal((await run('materialize',[process.execPath,entry,'materialize',art,input])).rc,0);
 assert.deepEqual(JSON.parse(await fs.readFile(input+'/native-cjdb.json')),next);
 assert.equal(await fs.readFile(input+'/compiler-53da.tar','utf8'),'new controlled source');
 assert.equal(await fs.readFile(input+'/old.tar','utf8'),'old');assert.equal(await fs.readFile(input+'/dep.tar','utf8'),'unchanged dependency');
 const again=await run('existing-input',[process.execPath,entry,'materialize',art,input]);assert.equal(again.rc,1);assert.match(again.stderr,/EEXIST/);
 await fs.rename(art+'/native-cjdb.json',art+'/next.json');
 assert.equal((await run('original-raw',[process.execPath,entry,'materialize',art,root+'/original-input'])).rc,0);
 assert.deepEqual(JSON.parse(await fs.readFile(root+'/original-input/native-cjdb.json')),original);
 await json(art+'/native-cjdb.json',{...next,compilerArchive:{file:'../escape'}});
 const rejected=await run('escape',[process.execPath,entry,'materialize',art,root+'/escape-input']);assert.equal(rejected.rc,1);assert.match(rejected.stderr,/INSTALL_PATH/);
});
test('public native adapter passes absolute selected compiler and fixed source then refuses non-Windows production',async()=>{
 const input=root+'/job-input',bin=root+'/selected-toolchain/bin';await fs.mkdir(input);await put(bin+'/clang.exe','controlled non-executable placeholder');await put(bin+'/clang++.exe','controlled non-executable placeholder');
 const dep=root+'/dependency';await fs.mkdir(dep);await put(dep+'/input','transport-only');
 assert.equal((await run('dep-tar',['tar','-cf',input+'/dep.tar','-C',dep,'.'])).rc,0);
 const digest=hash(await fs.readFile(input+'/dep.tar')),commit='a'.repeat(40),compiler='53da07662223e1dbaa7711f4ef149d6ae7b3afea';
 const config={platform:'windows_x86_64',commits:{compiler,llvm:commit,runtime:commit,bounds:commit,flatbuffers:commit},compiler:'compiler',tools:{cc:'clang',cxx:'clang++',launcher:'sccache'}};
 for(const name of ['llvm','runtime','bounds','flatbuffers'])config[name+'Archive']={file:'dep.tar',sha256:digest};await json(input+'/native-cjdb.json',config);
 const env={...process.env,CJCJ_WINDOWS_TOOLCHAIN:root+'/selected-toolchain',CJCJ_NATIVE_LLVM_REF:commit,CJCJ_NATIVE_RUNTIME_REF:commit,CJCJ_NATIVE_HOST_VERSION:'1.3.0-alpha.20260925001050'};
 const r=await run('selected',[process.execPath,child,'job','build',input,root+'/job-work'],env);
 assert.equal(r.rc,1);assert.match(r.stderr,/NATIVE_CJDB_RUNNER_REQUIRED/);
 const actual=JSON.parse(await fs.readFile(root+'/job-work/native-cjdb.json'));assert.equal(actual.tools.cc,bin+'/clang.exe');assert.equal(actual.tools.cxx,bin+'/clang++.exe');assert.equal(actual.tools.launcher,'sccache');assert.equal(actual.commits.compiler,compiler);
 const bad=await run('wrong-pair',[process.execPath,child,'job','build',input,root+'/bad-job'],{...env,CJCJ_NATIVE_LLVM_REF:'b'.repeat(40)});
 assert.equal(bad.rc,1);assert.match(bad.stderr,/NATIVE_JOB_SOURCE_PAIR/);
});
function sdkInputs(){const row=(commit,name)=>({commit,tree:'a'.repeat(40),repository:'/fixture/'+name+'.git',install:root+'/'+name,configuration:{fixture:true},buildResult:root+'/'+name+'/result.json',sourceRoot:root+'/'+name+'-producer'});const runtime=row(FIXED_INPUTS.runtime,'R');return{platform:'windows_x86_64',work:root+'/sdk-work',install:root+'/sdk',host:{version:readHostToolchainPin('windows_x86_64').replace(/^nightly-/,''),install:root+'/H'},llvm:row(FIXED_INPUTS.llvm,'N'),runtime,ast:row(FIXED_INPUTS.compiler,'AST'),h1:{...row(FIXED_INPUTS.h1,'H1'),product:root+'/H1/compiler'},compiler:row('b'.repeat(40),'C'),stdlib:{...runtime,install:root+'/std'},tools:{privateRoot:root+'/tools'}};}
test('actual SDK copy recipes and archive retain native runtime bytes and original input at the package reader',async()=>{
 const input=sdkInputs(),dlls=['libc++.dll','libunwind.dll'];
 const originalPath='share/cjcj/build-inputs/windows-toolchain.json',original='{"fixture":"transport only; compiler and Windows were NOT_RUN"}\n';
 const files=[];
 for(const directory of ['bin','third_party/llvm/bin','third_party/flatbuffers/bin'])for(const name of dlls){const rel=directory+'/'+name,bytes='controlled DLL transport '+name;await put(input.llvm.install+'/'+rel,bytes);files.push({path:rel,sha256:hash(bytes)});}
 await put(input.llvm.install+'/'+originalPath,original);
 input.llvm.windowsToolchain={compiler:{fixture:'not executed'},original:{path:originalPath,sha256:hash(original)},installedFiles:files};
 const stage=createBootstrapTargets(input).stages.find(s=>s.id==='stage0-run');
 for(const group of stage.entries.filter(g=>['bin','third_party/llvm/bin'].includes(g.directory)&&!g.names))for(const name of dlls)assert.ok(group.exclude.includes(name),'DLL must not become an executable wrapper');
 const hostCopy=stage.copies.find(c=>c.to===''&&c.owner==='H');assert.ok(dlls.every(n=>hostCopy.exclude.includes('bin/'+n)));
 const copies=stage.copies.filter(c=>c.owner==='native toolchain runtime'||c.owner==='native toolchain input'||c.to==='third_party/llvm'||c.to==='third_party/flatbuffers');
 // N and AST use one native install in production. This bounded transport uses
 // the same physical directory, without pretending to build AST or an SDK.
 for(const c of copies)if(c.to==='third_party/flatbuffers')c.from=input.llvm.install+'/third_party/flatbuffers';
 const flow=root+'/copy.json';await json(flow,{work:root+'/copy-work',install:root+'/copy-sdk',repos:{},stages:[{id:'copy',output:'${install}',copies}],finalStage:'copy',test:{required:[originalPath,...files.map(f=>f.path)]}});
 const r=await run('sdk-copy',[process.execPath,new URL('./sdk-flow.mjs',import.meta.url).pathname,'--config',flow,'--no-package']);assert.equal(r.rc,0,r.stderr);
 const archive=root+'/native-install.tar';assert.equal((await run('package',['tar','-cf',archive,'-C',root+'/copy-sdk','.'])).rc,0);
 // The actual public unpack requires a build record; this is marked as an
 // explicit transport fixture, not native producer success or SDK facts.
 await put(root+'/copy-sdk/BUILD-INPUTS.json','{"fixture":"transport-only"}');
 assert.equal((await run('package-with-record',['tar','-cf',root+'/transport.tar','-C',root+'/copy-sdk','.'])).rc,0);
 const relocated=root+'/relocated';assert.equal((await run('unpack',[process.execPath,entry,'unpack',root+'/transport.tar',relocated])).rc,0);
 await put(relocated+'/libLLVM-marker','finite reader payload');await put(relocated+'/shim-marker','finite reader payload');
 await json(relocated+'/share/cjcj/build-inputs/native-llvm.json',{rc:0,platform:'windows_x86_64',artifacts:[{path:'libLLVM-marker'},{path:'shim-marker'}],windowsToolchain:input.llvm.windowsToolchain});
 const actual=await installedInputs(relocated,'windows_x86_64'),component=actual.components.find(c=>c.component==='llvm-cjdb');
 assert.deepEqual(component.build.windowsToolchain,input.llvm.windowsToolchain);console.log('WINDOWS_RUNTIME_PACKAGE_READER_REACHED');
 await put(relocated+'/bin/libc++.dll','changed');await assert.rejects(installedInputs(relocated,'windows_x86_64'),/INSTALLED_INPUT_BYTES bin\/libc\+\+\.dll/);
 await put(relocated+'/bin/libc++.dll','controlled DLL transport libc++.dll');await put(relocated+'/'+originalPath,'changed');
 await assert.rejects(installedInputs(relocated,'windows_x86_64'),/INSTALLED_INPUT_BYTES share\/cjcj\/build-inputs\/windows-toolchain.json/);
});
test('public installer verifies actual fixed archive then calls system ZIP tool preserving its failure',async()=>{
 const archive=process.env.WINDOWS_TOOLCHAIN_ARCHIVE_INPUT;assert.ok(archive,'read-only fixed platform archive required');
 const system=root+'/system',tar=system+'/System32/tar.exe',work=root+'/installer-call';
 await put(tar,'#!/usr/bin/python3\nimport sys\nprint("SYSTEM_ZIP_TOOL_REACHED",repr(sys.argv))\nsys.exit(31)\n');await fs.chmod(tar,0o755);
 const r=await run('system-zip',[process.execPath,child,'installer',work,archive],{...process.env,SystemRoot:system,GITHUB_ENV:root+'/zip-env',GITHUB_PATH:root+'/zip-path'});
 assert.equal(r.rc,31,r.stderr);assert.match(r.stdout,/SYSTEM_ZIP_TOOL_REACHED/);
 const attempt=(await fs.readdir(work)).find(n=>n.startsWith('install-'));assert.ok(attempt);
 const commands=JSON.parse(await fs.readFile(work+'/'+attempt+'/commands.json'));assert.equal(commands.length,1);
 assert.deepEqual(commands[0].argv,[tar,'-xf',archive,'-C',work+'/'+attempt]);assert.equal(commands[0].rc,31);
 for(const file of ['zip-env','zip-path','installer-call/'+(await import('./install-windows-toolchain.mjs')).WINDOWS_TOOLCHAIN.directory])
  await assert.rejects(fs.lstat(path.join(root,file)),{code:'ENOENT'});
});

// Limit writes on the two real runner files in the installer child. The
// second write to ENV fails only after the first chunk has reached disk.
const exportIoFixture=`
import fs from 'node:fs/promises';
import {constants} from 'node:fs';
import assert from 'node:assert/strict';
const {GITHUB_PATH,GITHUB_ENV,EXPORT_IO}=process.env,open=fs.open;
fs.open=async(file,flags,...args)=>{
 const handle=await open(file,flags,...args);
 if(file!==GITHUB_PATH&&file!==GITHUB_ENV)return handle;
 assert.equal(flags,constants.O_WRONLY,'runner files need truncatable write handles');
 const write=handle.write.bind(handle);
 let written=0;
 handle.write=async(buffer,offset,length,position)=>{
  if(file===GITHUB_ENV&&written&&EXPORT_IO!=='short-write')
   throw Object.assign(Error('SECOND_EXPORT_WRITE_FAILED'),{rc:73});
  const result=await write(buffer,offset,Math.min(7,length),position);
  written+=result.bytesWritten;
  return result;
 };
 if(file===GITHUB_PATH&&EXPORT_IO==='truncate-error')
  handle.truncate=async()=>{throw Error('FIRST_EXPORT_TRUNCATE_FAILED');};
 return handle;
};`;

for(const mode of ['success','short-write','write-error','truncate-error','layout','missing-env','missing-path','missing-command-file','existing'])
 test('public installer deterministic publication: '+mode,async()=>{
 const {WINDOWS_TOOLCHAIN:p}=await import('./install-windows-toolchain.mjs');
 const archive=process.env.WINDOWS_TOOLCHAIN_ARCHIVE_INPUT;assert.ok(archive,'read-only fixed platform archive required');
 const system=root+'/extract-system-'+mode,tar=system+'/System32/tar.exe';
 // The public Linux transport fixture substitutes only tar.exe. Extract the
 // five checked members from the pinned archive with the host ZIP reader.
 await put(tar,`#!/usr/bin/python3
import os, sys, zipfile
with zipfile.ZipFile(sys.argv[2]) as z:
 for rel in ['bin/clang.exe','bin/clang++.exe','bin/llvm-readobj.exe','x86_64-w64-mingw32/bin/libc++.dll','x86_64-w64-mingw32/bin/libunwind.dll']:
  if os.environ.get('OMIT_MEMBER') != rel: z.extract('${p.directory}/'+rel, sys.argv[4])
`);await fs.chmod(tar,0o755);
  const work=path.join(root,'publish-'+mode),fixed=path.join(work,p.directory),jobEnv=work+'/env',jobPath=work+'/path';
  const envBefore='BEFORE=一\r\n',pathBefore='précédent\r\n',bin=path.join(fixed,'bin');
  await put(jobEnv,envBefore);await put(jobPath,pathBefore);
  if(mode==='existing')await fs.mkdir(fixed); // even an empty directory is owned
  const env={...process.env,SystemRoot:system,GITHUB_ENV:jobEnv,GITHUB_PATH:jobPath};
  if(mode==='layout')env.OMIT_MEMBER='bin/clang++.exe';
  if(mode==='missing-env')delete env.GITHUB_ENV;
  if(mode==='missing-path')delete env.GITHUB_PATH;
  if(mode==='missing-command-file')env.GITHUB_ENV=work+'/absent';
  const nodeArgs=[];
  if(['short-write','write-error','truncate-error'].includes(mode)){
   const preload=path.join(work,'export-io.mjs');
   await put(preload,exportIoFixture);nodeArgs.push('--import',preload);env.EXPORT_IO=mode;
  }
  const r=await run('publish-'+mode,[process.execPath,...nodeArgs,child,'installer',work,archive],env);
  const attempts=(await fs.readdir(work)).filter(name=>name.startsWith('install-'));
  assert.equal(attempts.length,1);
  const commands=JSON.parse(await fs.readFile(path.join(work,attempts[0],'commands.json')));
  assert.equal(commands.length,1);assert.equal(commands[0].rc,0);
  if(mode==='success'||mode==='short-write'){
   assert.equal(r.rc,0,r.stderr);
   assert.deepEqual(await fs.readFile(jobEnv),Buffer.from(envBefore+'CJCJ_WINDOWS_TOOLCHAIN='+fixed+'\n'),'stable toolchain export');
   assert.deepEqual(await fs.readFile(jobPath),Buffer.from(pathBefore+bin+'\n'));
   assert.ok((await fs.stat(path.join(fixed,'bin/clang.exe'))).size>0);
   assert.deepEqual(await fs.readdir(path.join(work,attempts[0])),['commands.json']);
  }else if(mode==='write-error'||mode==='truncate-error'){
   assert.equal(r.rc,73,r.stderr);assert.match(r.stderr,/SECOND_EXPORT_WRITE_FAILED/);
   if(mode==='truncate-error')assert.match(r.stderr,/FIRST_EXPORT_TRUNCATE_FAILED/);
   assert.deepEqual(await fs.readFile(jobPath),Buffer.from(mode==='write-error'?pathBefore:pathBefore+bin+'\n'));
   assert.deepEqual(await fs.readFile(jobEnv),Buffer.from(envBefore));
   await assert.rejects(fs.lstat(fixed),{code:'ENOENT'});
   assert.ok((await fs.stat(path.join(work,attempts[0],p.directory,'bin/clang.exe'))).size>0);
  }else{
   assert.equal(r.rc,1,r.stderr);
   assert.match(r.stderr,{layout:/clang\+\+\.exe/,existing:/WINDOWS_TOOLCHAIN_EXISTS/,'missing-env':/WINDOWS_TOOLCHAIN_JOB_ENV_REQUIRED/,
    'missing-path':/WINDOWS_TOOLCHAIN_JOB_ENV_REQUIRED/,'missing-command-file':/ENOENT/}[mode]);
   assert.deepEqual(await fs.readFile(jobEnv),Buffer.from(envBefore));assert.deepEqual(await fs.readFile(jobPath),Buffer.from(pathBefore));
   if(mode==='existing')assert.deepEqual(await fs.readdir(fixed),[]);
   else await assert.rejects(fs.lstat(fixed),{code:'ENOENT'});
  }
});
