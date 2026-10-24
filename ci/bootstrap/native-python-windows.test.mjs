import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {windowsPythonEnvironment,windowsPythonBuildArgs,windowsPythonLayoutArgs,windowsPythonInstallation,windowsPythonJobs} from './native-python-windows.mjs';
import {fileDigest} from './sdk-flow.mjs';
const execute=promisify(execFile);
const upstream=process.env.WINDOWS_PYTHON_LAYOUT;
if(!upstream)throw Error('FIXED_CPYTHON_LAYOUT_REQUIRED');
const root=await fs.mkdtemp(path.join(process.env.PYTHON_LAYOUT_EVIDENCE||os.tmpdir(),'python-layout-fixture-'));
test.after(async()=>{if(!process.env.PYTHON_LAYOUT_EVIDENCE)await fs.rm(root,{recursive:true});});
test('jobs on the actual CPU domain reach native MSBuild arguments without a minimum core gate',()=>{
  const available=os.availableParallelism();
  console.log('WINDOWS_PYTHON_JOBS_ASSERTION_REACHED '+JSON.stringify({available}));
  assert.equal(windowsPythonJobs(),available);
  for(const requested of new Set([1,Math.min(4,available),available]))
    assert.ok(windowsPythonBuildArgs(windowsPythonJobs(requested)).includes('/m:'+requested));
});
test('jobs reject invalid values',()=>{
  for(const jobs of [0,-1,1.5,'4',NaN,Infinity])
    assert.throws(()=>windowsPythonJobs(jobs),/WINDOWS_PYTHON_NATIVE_CAPACITY/);
});
async function fixture(name,producerArgs=true,dev=true) {
  const dir=path.join(root,name),source=path.join(dir,'source'),build=path.join(dir,'build'),install=path.join(dir,'install'),temp=path.join(dir,'temp');
  await fs.mkdir(path.join(source,'PC'),{recursive:true});
  await fs.cp(upstream,path.join(source,'PC/layout'),{recursive:true});
  // Explicit copy fixtures: none is a Windows executable, header implementation
  // or native module. The verified upstream layout copies them without running.
  for(const rel of ['Include/Python.h','PC/pyconfig.h','Lib/os.py','Lib/ssl.py','Lib/ctypes/__init__.py']) {
    await fs.mkdir(path.dirname(path.join(source,rel)),{recursive:true});
    await fs.writeFile(path.join(source,rel),'Explicit upstream layout fixture: '+rel+'\n');
  }
  await fs.mkdir(build,{recursive:true});
  for(const rel of ['python.exe','pythonw.exe','python311.dll','python311.lib','python3.dll','python3.lib',
    'vcruntime140.dll','_ssl.pyd','_ctypes.pyd','libssl-3.dll','libcrypto-3.dll','libffi-8.dll','LICENSE.txt'])
    await fs.writeFile(path.join(build,rel),'Explicit non-executable layout fixture: '+rel+'\n');
  const args=producerArgs?windowsPythonLayoutArgs({source,build,install,temp}):
    ['-B',path.join(source,'PC/layout'),'--source',source,'--build',build,'--arch','amd64','--copy',install,'--temp',temp,'--include-stable',...(dev?['--include-dev']:[])];
  const argv=[process.env.PYTHON_LAYOUT_HOST||'/usr/bin/python3',...args];
  const started=new Date().toISOString();
  let result;
  try{result=await execute(argv[0],argv.slice(1),{env:{...process.env,PYTHON_HEXVERSION:'0x030B11F0',PYTHONDONTWRITEBYTECODE:'1'},maxBuffer:4*1024**2});}
  catch(error){await fs.writeFile(path.join(dir,'layout-failure.json'),JSON.stringify({argv,rc:error.code,stdout:error.stdout,stderr:error.stderr}));throw error;}
  await fs.writeFile(path.join(dir,'layout.stdout'),result.stdout);
  await fs.writeFile(path.join(dir,'layout.stderr'),result.stderr);
  await fs.writeFile(path.join(dir,'command.json'),JSON.stringify({argv,started,ended:new Date().toISOString(),rc:0,host:process.platform,
    versionSelector:'official PC/layout PYTHON_HEXVERSION fixture option; Windows binaries never executed'}));
  return {source,build,install,dir};
}
test('producer layout arguments reach actual upstream development install and preserve bytes',async()=>{
  const f=await fixture('product');
  console.log('PYTHON_DEVELOPMENT_INSTALL_ASSERTION_REACHED');
  const result=await windowsPythonInstallation(f.install);
  assert.equal(result.files['include/Python.h'].sha256,await fileDigest(path.join(f.source,'Include/Python.h')));
  assert.equal(result.files['libs/python311.lib'].sha256,await fileDigest(path.join(f.build,'python311.lib')));
  assert.ok(result.entries.includes('python3.dll'));assert.ok(result.entries.includes('vcruntime140.dll'));
  assert.ok(result.files['DLLs/libcrypto-3.dll']);assert.ok(result.files['DLLs/libffi-8.dll']);
});
test('runtime-only upstream layout is rejected as a development installation',async()=>{
  const f=await fixture('runtime-only',false,false);
  await assert.rejects(windowsPythonInstallation(f.install),/PYTHON_DEVELOPMENT_INSTALL include\/Python.h/);
});
test('relocated upstream layout retains relative files and rejects missing loader DLL',async()=>{
  const f=await fixture('relocation',false,true),moved=f.install+'-relocated';
  await fs.rename(f.install,moved);
  const result=await windowsPythonInstallation(moved);
  assert.ok(result.files['include/Python.h']);assert.ok(result.files['libs/python311.lib']);
  const file=path.join(moved,'vcruntime140.dll'),bytes=await fs.readFile(file);await fs.unlink(file);
  try{await assert.rejects(windowsPythonInstallation(moved),/PYTHON_DEVELOPMENT_INSTALL vcruntime/);}
  finally{await fs.writeFile(file,bytes);}
});
test('native build arguments and actual child environment keep the selected configuration',async()=>{
  const args=windowsPythonBuildArgs(64);
  assert.ok(args.includes('-M'));assert.ok(args.includes('/m:64'));assert.ok(args.includes('/p:KillPython=false'));
  assert.ok(args.includes('-e'));assert.ok(!args.includes('-E'));assert.ok(!args.includes('--no-ssl'));assert.ok(!args.includes('--no-ctypes'));
  assert.throws(()=>windowsPythonBuildArgs(0),/PYTHON_JOBS/);
  const inherited={...process.env,PYTHON_HEXVERSION:'wrong',ORG:'wrong',PythonHome:'wrong',INCLUDESSL:'false',IncludeSSL:'false',Regen:'true'};
  const env={...inherited,...windowsPythonEnvironment(inherited,{bootstrapPython:'explicit-python',msbuild:'explicit-msbuild'})};
  const child=await execute(process.execPath,['-e','console.log(JSON.stringify(process.env))'],{env});
  const observed=JSON.parse(child.stdout);
  assert.equal(observed.PYTHON_HEXVERSION,undefined);assert.equal(observed.ORG,undefined);
  assert.equal(observed.PythonHome,undefined);assert.equal(observed.Regen,undefined);
  assert.equal(observed.INCLUDESSL,'true');assert.equal(observed.IncludeSSL,'true');assert.equal(observed.IncludeCTypes,'true');
  assert.equal(observed.PYTHON,'explicit-python');assert.equal(observed.MSBUILD,'explicit-msbuild');
});
test('public producer rejects a non-Windows host before creating a work tree',async()=>{
  assert.notEqual(process.platform,'win32','this limited entry rejection arm runs on Linux');
  const work=path.join(root,'must-not-exist'),config=path.join(root,'foreign.json');
  await fs.writeFile(config,JSON.stringify({work}));
  await assert.rejects(execute(process.execPath,['ci/bootstrap/native-python-windows.mjs',config]),error=>
    error.code===1&&error.stderr.includes('WINDOWS_PYTHON_NATIVE_HOST_REQUIRED'));
  assert.equal(await fs.stat(work).catch(()=>null),null);
});

test('original layout crosses N copy and installedInputs with null CONFIG_ARGS; full DLL/original bytes stay required',async()=>{
 const {copyWindowsPythonInstallation}=await import('./native-python-install.mjs');
 const {pythonSourceInputs}=await import('./sdk-cjdb-python.mjs');
 const {installedInputs}=await import('../srcbuild/lib/installed-inputs.mjs');
 const f=process.env.WINDOWS_PYTHON_COPY_INPUT?{install:process.env.WINDOWS_PYTHON_COPY_INPUT}:await fixture('native-copy');
 const sdk=path.join(root,'sdk'),nativeRoot=path.join(sdk,'third_party/llvm');
 const record=path.join(f.install,'PYTHON-BUILD-INPUTS.json');
 if(!process.env.WINDOWS_PYTHON_COPY_INPUT){
 const layout=await windowsPythonInstallation(f.install);
 // This ordinary record describes only the observed upstream layout fixture.
 // Windows build/import/LLDB remain NOT_RUN, never a production claim.
 const log='share/cjcj/build-inputs/python/layout-command.json';
 await fs.mkdir(path.dirname(path.join(f.install,log)),{recursive:true});
 await fs.copyFile(path.join(path.dirname(f.install),'command.json'),path.join(f.install,log));
 const facts={rc:0,host:'windows_x86_64',target:'windows_x86_64',
  source:{url:'https://example.invalid/fixed-layout-fixture.tar.xz',version:'3.11.17',sha256:'a'.repeat(64)},
  producer:{repository:'explicit-upstream-layout-fixture',commit:'b'.repeat(40)},
  files:layout.files,installation:{entries:layout.entries},commands:[JSON.parse(await fs.readFile(path.join(path.dirname(f.install),'command.json'),'utf8'))],
  originals:{layout:{path:log,sha256:await fileDigest(path.join(f.install,log))}},
  notRun:['Windows PCbuild','Python execution','LLDB']};
 await fs.writeFile(record,JSON.stringify(facts));
 }
 const input={record,sha256:await fileDigest(record)};
 const carried=await copyWindowsPythonInstallation({root:f.install,nativeRoot,inputs:input});
 console.log('WINDOWS_PYTHON_COPY_CONSUMER_ASSERT_REACHED');
 assert.deepEqual(await fs.readFile(path.join(sdk,carried.record)),await fs.readFile(record));
 assert.deepEqual(await fs.readFile(path.join(nativeRoot,'python3.dll')),await fs.readFile(path.join(f.install,'python3.dll')));
 assert.deepEqual(await fs.readFile(path.join(nativeRoot,'share/cjcj/build-inputs/python/layout-command.json')),await fs.readFile(path.join(f.install,'share/cjcj/build-inputs/python/layout-command.json')));
 const selected={version:'3.11.17 (layout fixture)',configure:null,executable:path.join(f.install,'python.exe'),
  include:path.join(f.install,'include'),library:path.join(f.install,'libs/python311.lib')};
 const pythonSource=await pythonSourceInputs({...input,root:f.install,nativeRoot,platform:'windows_x86_64',selected});
 const artifacts=[];
 for(const rel of ['third_party/llvm/bin/libLLVM-15.dll','tools/bin/cjdb.exe']){
  const file=path.join(sdk,rel.startsWith('tools/bin/')?'.native-tools/'+rel:rel);await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,'explicit nonexecutable N fixture');
  artifacts.push({path:rel,sha256:await fileDigest(file)});
 }
 const nativeFacts={rc:0,platform:'windows_x86_64',install:sdk,artifacts,pythonSource,
  pythonConfiguration:{selected},pythonInstallation:{observed:{version:selected.version},loaded:{}}};
 await fs.mkdir(path.join(sdk,'share/cjcj/build-inputs'),{recursive:true});
 await fs.writeFile(path.join(sdk,'share/cjcj/build-inputs/native-llvm.json'),JSON.stringify(nativeFacts));
 await fs.rename(f.install,f.install+'.unavailable');
 try{
 const moved=sdk+'.relocated';await fs.rename(sdk,moved);
 const got=(await installedInputs(moved,'windows_x86_64')).components.find(row=>row.component==='python');
 assert.equal(got.build.configuration.configure,null);assert.equal(got.installation.entries.includes('python3.dll'),true);
 assert.equal(got.installation.record.sha256,input.sha256);
 const dll=path.join(moved,'third_party/llvm/python3.dll'),bytes=await fs.readFile(dll);await fs.appendFile(dll,'changed');
 console.log('WINDOWS_PYTHON_RELOCATED_DLL_ASSERT_REACHED');
 await assert.rejects(installedInputs(moved,'windows_x86_64'),/PYTHON_INSTALL_BYTES/);await fs.writeFile(dll,bytes);
 const original=path.join(moved,'third_party/llvm/share/cjcj/build-inputs/python/layout-command.json'),originalBytes=await fs.readFile(original);await fs.appendFile(original,'changed');
 await assert.rejects(installedInputs(moved,'windows_x86_64'),/PYTHON_INSTALL_BYTES/);await fs.writeFile(original,originalBytes);
 assert.equal((await installedInputs(moved,'windows_x86_64')).components.find(row=>row.component==='python').source.status,'resolved');
 }finally{await fs.rename(f.install+'.unavailable',f.install);}
});
