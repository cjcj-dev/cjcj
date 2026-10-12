#!/usr/bin/env zx
// Bounded qualification against an already completed CMake installation.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn} from 'node:child_process';
import test from 'node:test';
import {cjdbPythonClosureSources,exportCjdbPythonClosure} from './sdk-cjdb-python-closure.mjs';
import {verifyCjdbPythonInstallation} from './sdk-cjdb-python.mjs';
import {readJson,fileDigest,atomicJson} from './sdk-manifest.mjs';

const previous = process.env.CJDB_CLOSURE_PREVIOUS;
const output = process.env.CJDB_CLOSURE_OUTPUT;
const arm = process.env.CJDB_CLOSURE_ARM || 'normal';
test(`real qualification closure ${arm}`,{skip:!previous || !output},async()=>{
  await fs.mkdir(output,{recursive:true});
  const commands=[];
  const execute=async(file,args,options={})=>{
    const index=commands.length,row={file,args,started:new Date().toISOString()}; commands.push(row);
    const out=await fs.open(path.join(output,`${index}.stdout`),'w'),err=await fs.open(path.join(output,`${index}.stderr`),'w');
    const start=performance.now();
    const result=await new Promise((resolve,reject)=>{
      const child=spawn(file,args,{...options,env:{...process.env,...options.env,LC_ALL:'C'},stdio:['ignore',out.fd,err.fd]});
      child.once('error',reject); child.once('exit',(rc,signal)=>resolve({rc,signal}));
    });
    await out.close();await err.close();Object.assign(row,result,{wall:(performance.now()-start)/1000});
    await atomicJson(path.join(output,'commands.json'),commands);
    const stdout=await fs.readFile(path.join(output,`${index}.stdout`),'utf8'),stderr=await fs.readFile(path.join(output,`${index}.stderr`),'utf8');
    assert.equal(result.rc,0,`actual command ${index} ${file}: ${stderr}`);
    return {stdout,stderr};
  };
  const configuration=await readJson(path.join(previous,'normal-config/qualification-inputs.json'));
  const request=await readJson(path.join(configuration.partial,'request.json'));
  const pythonRoot=request.component.config.options.python.root;
  const oldNative=path.join(previous,'normal-config/install/third_party/llvm');
  const install=path.join(output,'install'),nativeRoot=path.join(install,'third_party/llvm');
  const sourcesFile=path.resolve(output,'../sources.json');
  let sources;
  try {sources=await readJson(sourcesFile);} catch(error) {
    if(error.code!=='ENOENT')throw error;
    sources=await cjdbPythonClosureSources(oldNative,path.join(previous,'normal-config/lldb-build/install_manifest.txt'),pythonRoot);
    const recorded=await readJson(path.join(previous,'import-artifacts.json'));
    for(const [rel,digest] of Object.entries(recorded)) {
      const row=sources.lldb.files[rel] || sources.python.files[rel];
      assert.equal(row?.sha256,digest,`original installed identity ${rel}`);
    }
    await atomicJson(sourcesFile,sources);
  }
  const exportClosure=()=>exportCjdbPythonClosure(configuration.partial,install,execute,sources);
  if(arm==='normal') {
    const closure=await exportClosure();
    assert.ok(closure.edges.some(edge=>edge.role==='sealed'));
    assert.ok(closure.edges.some(edge=>edge.role==='python'));
    assert.ok(closure.system.length && closure.system.every(row=>row.real && row.sha256));
    await atomicJson(path.join(output,'closure.json'),closure);
    console.log('TARGET_ASSERTIONS_EXECUTED CLOSURE_NORMAL authenticated roles and resolved system edges');
    const installation=await verifyCjdbPythonInstallation(pythonRoot,nativeRoot,execute);
    await atomicJson(path.join(output,'installation.json'),installation);
    console.log('TARGET_ASSERTIONS_EXECUTED CJDB_PYTHON_IMPORT debugger-valid-destroy');
    return;
  }
  // Other arms reuse the completed export in this owner's directory, never the
  // previous owner's files. Each mutation is restored before the next target.
  const normal=path.resolve(output,'../normal/install');
  await fs.cp(normal,install,{recursive:true,verbatimSymlinks:true});
  if(arm==='import') {
    const control=await execute(path.join(nativeRoot,'bin/python3.11'),['-B','-c','import json,sys; print(json.dumps(dict(control="interpreter-started",version=sys.version_info[:2])))'],
      {env:{...process.env,PYTHONHOME:nativeRoot,LD_LIBRARY_PATH:path.join(nativeRoot,'lib')}});
    assert.deepEqual(JSON.parse(control.stdout).version,[3,11]);
    console.log('CONTROL_ASSERTIONS_EXECUTED interpreter-started Python311');
    const installation=await verifyCjdbPythonInstallation(pythonRoot,nativeRoot,execute);
    await atomicJson(path.join(output,'installation.json'),installation);
    console.log('TARGET_ASSERTIONS_EXECUTED CJDB_PYTHON_IMPORT debugger-valid-destroy');
    return;
  }
  assert.equal(arm,'refuse');
  const checks=[];
  async function refuse(name,mutate,restore,pattern) {
    await mutate();
    try {
      console.log(`TARGET_ASSERTION_REACHED CLOSURE_REJECT ${name}`);
      await assert.rejects(exportClosure,pattern,`CLOSURE_REJECT ${name}`);
      checks.push({name,rejected:true});
      console.log(`TARGET_ASSERTIONS_EXECUTED CLOSURE_REJECT ${name}`);
    } finally {await restore();await atomicJson(path.join(output,'checks.json'),checks);}
  }
  const sealed='third_party/llvm/lib/libboundscheck.so';
  const physical=await fs.realpath(path.join(install,sealed));
  const backup=path.join(output,'boundscheck.backup');
  await fs.copyFile(physical,backup);
  await refuse('existing sealed bytes',()=>fs.appendFile(physical,'wrong identity'),()=>fs.copyFile(backup,physical),/DEPENDENCY_DIGEST.*bytes/);
  const library=path.join(nativeRoot,'lib/liblldb.so.15.0.4'),libraryBackup=path.join(output,'lldb.backup');
  await fs.copyFile(library,libraryBackup);
  const oldLldb=path.join(configuration.partial,'artifacts/third_party/llvm/lib/liblldb.so');
  await refuse('old LLDB bytes',()=>fs.copyFile(oldLldb,library),()=>fs.copyFile(libraryBackup,library),/DEPENDENCY_DIGEST/);
  const binding=path.join(nativeRoot,'lib/python3.11/site-packages/lldb/_lldb.cpython-311-x86_64-linux-gnu.so');
  const bindingTarget=await fs.readlink(binding);
  await refuse('binding alias escape',async()=>{await fs.unlink(binding);await fs.symlink(path.join(oldNative,'lib/liblldb.so'),binding);},
    async()=>{await fs.unlink(binding);await fs.symlink(bindingTarget,binding);},/LINK_ESCAPE/);
  const pythonLibrary=path.join(nativeRoot,'lib/libpython3.11.so.1.0'),pythonBackup=path.join(output,'python.backup');
  await fs.copyFile(pythonLibrary,pythonBackup);
  await refuse('different Python bytes',()=>fs.appendFile(pythonLibrary,'wrong Python'),()=>fs.copyFile(pythonBackup,pythonLibrary),/DEPENDENCY_DIGEST/);
  const foreign=path.join(nativeRoot,'lib/libpython3.10.so.1.0');
  await refuse('unowned Python',()=>fs.copyFile(pythonLibrary,foreign),()=>fs.unlink(foreign),/DEPENDENCY_SOURCE/);
  const tools=path.join(install,'tools'),toolsBackup=path.join(output,'tools.backup');
  await refuse('parent alias escape',async()=>{await fs.rename(tools,toolsBackup);await fs.symlink(path.join(normal,'tools'),tools);},
    async()=>{await fs.unlink(tools);await fs.rename(toolsBackup,tools);},/LINK_ESCAPE|DEPENDENCY_SOURCE/);
  const alias=path.join(nativeRoot,'lib/liblldb.so'),aliasTarget=await fs.readlink(alias);
  await refuse('alias cycle',async()=>{await fs.unlink(alias);await fs.symlink('liblldb.so',alias);},
    async()=>{await fs.unlink(alias);await fs.symlink(aliasTarget,alias);},/LINK_ESCAPE|ELOOP/);
  // Real readelf commands are run first; only their observed NEEDED result is
  // mutated, to exercise absent and deep missing edges without rebuilding ELF.
  async function injected(name,transform,pattern) {
    console.log(`TARGET_ASSERTION_REACHED CLOSURE_REJECT ${name}`);
    await assert.rejects(()=>exportCjdbPythonClosure(configuration.partial,install,async(file,args,options)=>{
      const result=await execute(file,args,options);return file==='/usr/bin/readelf'?{...result,stdout:transform(result.stdout,args[1])}:result;
    },sources),pattern);
    checks.push({name,rejected:true});console.log(`TARGET_ASSERTIONS_EXECUTED CLOSURE_REJECT ${name}`);
  }
  await injected('missing system edge',text=>text.replace('[libc.so.6]','[lib931-absent.so]'),/DEPENDENCY_MISSING/);
  await injected('deep missing edge',(text,file)=>file.startsWith('/usr/lib/')?text.replace('[libc.so.6]','[lib931-deep-absent.so]'):text,/DEPENDENCY_MISSING/);
  await injected('parse error',()=> 'invalid dynamic result',/DEPENDENCY_PARSE/);
  await assert.rejects(()=>exportCjdbPythonClosure(configuration.partial,install,async(file,args,options)=>{
    if(file==='/sbin/ldconfig')throw Object.assign(new Error('controlled resolver ENOENT'),{code:'ENOENT'});
    return execute(file,args,options);
  },sources),/controlled resolver ENOENT/);
  checks.push({name:'resolver error propagation',rejected:true});
  await atomicJson(path.join(output,'checks.json'),checks);
  const restored=await exportClosure();await atomicJson(path.join(output,'restored-closure.json'),restored);
  const installation=await verifyCjdbPythonInstallation(pythonRoot,nativeRoot,execute);
  await atomicJson(path.join(output,'installation.json'),installation);
  console.log(`TARGET_ASSERTIONS_EXECUTED CLOSURE_RESTORED ${checks.length} precise refusals, import restored`);
});
