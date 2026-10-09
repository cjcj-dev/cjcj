#!/usr/bin/env zx
// Bounded real parent/child qualification, never a complete native receipt.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {spawn} from 'node:child_process';
import test from 'node:test';
import {buildCjdb} from './sdk-cjdb-producer.mjs';
import {verifyCjdbPythonConfiguration, verifyCjdbPythonInstallation} from './sdk-cjdb-python.mjs';
import {fileDigest, sourceIdentity, readJson, atomicJson} from './sdk-manifest.mjs';
import {CJDB_INPUTS} from './sdk-cjdb-qualification.mjs';

const partial = process.env.CJDB_PYTHON_PARTIAL;
const output = process.env.CJDB_PYTHON_OUTPUT;
const sources = process.env.CJDB_PYTHON_SOURCES;
const configureOnly = process.env.CJDB_PYTHON_CONFIGURE_ONLY === '1';
const repository = path.resolve(import.meta.dirname,'../..');

test('producer root reaches real LLDB Interpreter and Development',
  {skip:!partial || !output || !sources}, async () => {
    await fs.mkdir(output,{recursive:true});
    const commands=[];
    const execute = async (file,args,options={}) => {
      const index=commands.length, started=new Date().toISOString();
      const row={file,args,started,pythonRoot:options.env?.Python3_ROOT_DIR}; commands.push(row);
      const outFile=await fs.open(path.join(output,`${index}.stdout`),'w');
      const errFile=await fs.open(path.join(output,`${index}.stderr`),'w');
      const start=performance.now();
      const result=await new Promise((resolve,reject)=>{
        const child=spawn(file,args,{...options,stdio:['ignore',outFile.fd,errFile.fd]});
        child.once('error',reject); child.once('exit',(rc,signal)=>resolve({rc,signal}));
      });
      await outFile.close(); await errFile.close();
      Object.assign(row,result,{wall:(performance.now()-start)/1000});
      await atomicJson(path.join(output,'commands.json'),commands);
      const stdout=await fs.readFile(path.join(output,`${index}.stdout`),'utf8');
      const stderr=await fs.readFile(path.join(output,`${index}.stderr`),'utf8');
      assert.equal(result.rc,0,`actual command ${index}: ${file} ${args.join(' ')}\n${stderr}`);
      return {stdout,stderr};
    };
    const original=await readJson(path.join(partial,'request.json'));
    const request={...original,directory:path.join(output,'parent')};
    request.component=structuredClone(original.component);
    request.component.producer.repository=repository;
    request.component.producer.version=(await execute('/usr/bin/git',['-C',repository,'rev-parse','HEAD'])).stdout.trim();
    await fs.mkdir(path.join(request.directory,'logs'),{recursive:true});
    const roots={};
    const fetchIdentity=async (input,unused,label)=>{
      const target=label==='cjdb-boundscheck' || label==='cjdb-flatbuffers'
        ? path.join(sources,'compiler/third_party',label.slice(5)) : path.join(sources,label.slice(5));
      const marker=path.join(sources,`${label}.identity.json`);
      try { await fs.access(marker); }
      catch {
        await fs.mkdir(target,{recursive:true});
        await execute('/usr/bin/git',['init',target]);
        // Frozen commits can be unreferenced in a private bare source locator.
        // Fetch that exact commit; clone's advertised refs do not cover it.
        await execute('/usr/bin/git',['-C',target,'fetch','--no-tags',input.repo,input.commit]);
        await execute('/usr/bin/git',['-C',target,'checkout','--detach',input.commit]);
        await sourceIdentity(target,input,label);
        await atomicJson(marker,{commit:input.commit,tree:input.tree});
      }
      assert.equal((await execute('/usr/bin/git',['-C',target,'rev-parse','HEAD'])).stdout.trim(),input.commit);
      assert.equal((await execute('/usr/bin/git',['-C',target,'rev-parse','HEAD^{tree}'])).stdout.trim(),input.tree);
      roots[label.slice(5)]=target;
      return target;
    };
    let childEnv;
    const stop=Symbol('bounded qualification before full native build');
    const run=async (argv,options={})=>{
      if(argv[0]==='cmake' && argv[1]==='--build') { childEnv=options.env; throw stop; }
      const name=argv[0],file=path.isAbsolute(name)?name:request.component.config.tools[name].path;
      return execute(file,argv.slice(1),options);
    };
    try { await buildCjdb(request,{run,tool:name=>request.component.config.tools[name].path,fetchIdentity,execute}); }
    catch(error) { if(error!==stop) throw error; }
    assert.ok(childEnv,'real producer reached its child build launch');
    const parentBuild=path.join(request.directory,'build/compiler');
    const cfgFile=path.join(parentBuild,'third_party/lldb-prefix/tmp/lldb-cfgcmd.txt');
    const cfgText=await fs.readFile(cfgFile,'utf8');
    // Consume ExternalProject's actual generated argv. Only relocate its
    // unbuilt prerequisite references to the declared fixed read-only inputs.
    // No cache, stamp, DONE or timestamp is copied into the new child graph.
    const fixedBuild=path.join(partial,'build/compiler');
    const substitutions={
      LLVM_DIR:path.join(fixedBuild,'third_party/cjnative-prefix/src/cjnative-build/lib/cmake/llvm'),
      LLVM_EXTERNAL_LIT:path.join(fixedBuild,'third_party/cjnative-prefix/src/cjnative-build/bin/llvm-lit'),
      CANGJIE_FRONTEND_LIB:path.join(fixedBuild,'lib/libcangjie-frontend.so'),
      CANGJIE_LSP_LIB:path.join(fixedBuild,'lib/libcangjie-lsp.so'),
    };
    const args=cfgText.trim().slice(5,-1).split(';').filter(arg=>arg!=='<SOURCE_DIR><SOURCE_SUBDIR>');
    for(let i=0;i<args.length;i++){
      args[i]=args[i].replaceAll('|',';');
      for(const [key,value] of Object.entries(substitutions)) if(args[i].startsWith(`-D${key}=`))args[i]=`-D${key}=${value}`;
      args[i]=args[i].replaceAll(path.join(parentBuild,'third_party/xml2'),path.join(fixedBuild,'third_party/xml2'));
    }
    const childBuild=path.join(output,'lldb-build');
    const nativeRoot=path.join(output,'install/third_party/llvm');
    args.push('-S',path.join(roots.llvm,'lldb'),'-B',childBuild,`-DCMAKE_INSTALL_PREFIX=${nativeRoot}`,
      '-DCMAKE_C_COMPILER_LAUNCHER=/usr/bin/ccache','-DCMAKE_CXX_COMPILER_LAUNCHER=/usr/bin/ccache',
      '-DLLVM_PARALLEL_LINK_JOBS=8');
    await atomicJson(path.join(output,'qualification-inputs.json'),{partial,request:original.identity,
      cfgFile,cfgSha256:await fileDigest(cfgFile),substitutions,args,pythonRoot:childEnv.Python3_ROOT_DIR,
      status:'partial qualification; no native output receipt'});
    await execute(args[0],args.slice(1),{env:childEnv});
    const cache=await fs.readFile(path.join(childBuild,'CMakeCache.txt'),'utf8');
    assert.match(cache,/^CMAKE_BUILD_TYPE:STRING=Release$/m);
    assert.match(cache,/^LLDB_ENABLE_PYTHON:STRING=ON$/m);
    console.log('CONTROL_ASSERTIONS_EXECUTED Release Python-enabled fixed-LLVM');
    const configuration=await verifyCjdbPythonConfiguration(request.component.config.options.python.root,childBuild,execute);
    await atomicJson(path.join(output,'python-configuration.json'),configuration);
    console.log('TARGET_ASSERTIONS_EXECUTED CJDB_PYTHON_IDENTITY');
    if(configureOnly)return;
    // The exact five generated native source inputs remain explicit read-only
    // qualification dependencies; their identities are recorded individually.
    const generated={};
    for(const rel of Object.keys(CJDB_INPUTS)){
      const from=path.join(partial,'source-inputs/llvm',rel),to=path.join(roots.llvm,rel);
      await fs.mkdir(path.dirname(to),{recursive:true}); await fs.copyFile(from,to);
      generated[rel]={from,sha256:await fileDigest(from)};
    }
    await atomicJson(path.join(output,'generated-inputs.json'),generated);
    await execute('/usr/bin/ninja',['-C',childBuild,'-t','query','liblldb'],{env:childEnv});
    await execute('/usr/bin/cmake',['--build',childBuild,'-j',String(os.availableParallelism())],{env:childEnv});
    await execute('/usr/bin/cmake',['--install',childBuild],{env:childEnv});
    // Use the product's normal export shape, without sealing or alias repair.
    for(const rel of ['bin','lib','include','share']){
      const from=path.join(request.component.config.options.python.root,rel);
      try { await fs.access(from); } catch(e){if(e.code==='ENOENT')continue;throw e;}
      await fs.cp(from,path.join(nativeRoot,rel),{recursive:true,verbatimSymlinks:true});
    }
    await fs.mkdir(path.join(output,'install/tools/lib'),{recursive:true});
    for(const name of ['libcangjie-frontend.so','libcangjie-lsp.so'])
      await fs.copyFile(path.join(fixedBuild,'lib',name),path.join(output,'install/tools/lib',name));
    const installation=await verifyCjdbPythonInstallation(request.component.config.options.python.root,nativeRoot,execute);
    await atomicJson(path.join(output,'python-installation.json'),installation);
    console.log('TARGET_ASSERTIONS_EXECUTED CJDB_PYTHON_IMPORT debugger-create-valid-destroy');
  });
