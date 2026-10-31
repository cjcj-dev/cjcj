#!/usr/bin/env zx
// Consume existing official tuples; shim mode builds only the missing LLVM headers.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import zlib from 'node:zlib';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {targetForHost} from '../../build/lib/targets.mjs';
import {buildCapacity,selectBuildJobs} from '../build-resources.mjs';
import {darwinCommand} from '../release/darwin_commands.mjs';
import {verifyTuplePayloads} from '../release/verify-tuple-payloads.mjs';
import {parseLlvmToolsManifest} from '../llvm-tools-manifest.mjs';
import {verifyInstalledLlvmTuple} from './llvm-tuple.mjs';

export const producer = Object.freeze({repository:'cjcj-dev/cjcj', run:40688530769, attempt:1,
  entry:'126700703a11ba132af79f0cb65692dcc153edd4',
  llvm:'57537222f0b42b9f4e750e57e7684f2574ca0462',
  runtime:'ee395430f52cffe5c3508dfe1ecb98c2ac967f9f',
  compiler:'41b22350b8eb5b0c8244704f906b7b8d3096eb9c',
  flatbuffers:'c3e4d69cbd5950e43f775ba76eadb30750d6e0b7'});
export const tuples = Object.freeze({
  linux_aarch64:{artifact:12820865883, bytes:98454025,
    sums:'e8ea16b8e091161e7df6a525a20379350efbbe2d36ee56c9939602d9a41f93da'},
  darwin_aarch64:{artifact:12820985209, bytes:93795073,
    sums:'62bdf8f0b689d7691ecf15a415ef5b1713a9d9ca9218a0175502781fc12d13f2'},
  darwin_x86_64:{artifact:12820097286, bytes:103694613,
    sums:'c2a1cb19bab257a7aff60108739ca9ffa9da940788a13a7d5a6d077722a3ef45'},
});
// Retained manifests from the SAME completed producer as the tuple/shim object.
export const dylibs = Object.freeze({
  linux_aarch64:{artifact:12817996912,bytes:75589305,sha256:'81592990f4a98b290c37c10485635bf9054ad6b5ca59d736fa53d6cd3bd02261'},
  darwin_x86_64:{artifact:12820698929,bytes:24729471,sha256:'404e09dd3f7cd164cc41dbec397666babf768a820a5e78198c4b540e510f5ead'},
  darwin_aarch64:{artifact:12817737754,bytes:23599401,sha256:'78e1a4bae8ea3646de68329f4898ed2e35c86a0117b6a25bb51b2541674ce2fb'},
});
const GiB = 1024 ** 3;
const repositoryRoot = fileURLToPath(new URL('../..', import.meta.url));
const writeJson = (file, value) => fs.writeFileSync(file, JSON.stringify(value,null,2)+'\n');

export function requireArtifact(platform, run, artifact) {
  const selected = tuples[platform];
  assert.ok(selected, 'NATIVE_TUPLE_PLATFORM');
  assert.equal(run.id, producer.run, 'NATIVE_TUPLE_RUN');
  assert.equal(run.run_attempt, producer.attempt, 'NATIVE_TUPLE_ATTEMPT');
  assert.equal(run.head_sha, producer.entry, 'NATIVE_TUPLE_PRODUCER');
  assert.equal(run.status, 'completed', 'NATIVE_TUPLE_RUN_PENDING');
  assert.equal(run.conclusion, 'success', 'NATIVE_TUPLE_RUN_FAILED');
  assert.equal(artifact.id, selected.artifact, 'NATIVE_TUPLE_ARTIFACT');
  assert.equal(artifact.workflow_run?.id, producer.run, 'NATIVE_TUPLE_ARTIFACT_RUN');
  assert.equal(artifact.workflow_run?.head_sha, producer.entry, 'NATIVE_TUPLE_ARTIFACT_PRODUCER');
  assert.equal(artifact.expired, false, 'NATIVE_TUPLE_EXPIRED');
  assert.equal(artifact.size_in_bytes, selected.bytes, 'NATIVE_TUPLE_ARCHIVE_SIZE');
  assert.equal(artifact.name, 'static-llvm-tuple-'+platform, 'NATIVE_TUPLE_ARTIFACT_NAME');
  return selected;
}

export function requireDylibArtifact(platform, artifact) {
  const selected=dylibs[platform];assert.ok(selected,'NATIVE_SHIM_PLATFORM');
  for(const [key,value]of Object.entries({id:selected.artifact,size_in_bytes:selected.bytes,
    name:'llvm-dylib-'+platform,expired:false}))assert.equal(artifact[key],value,'NATIVE_SHIM_ARTIFACT_'+key);
  assert.equal(artifact.workflow_run?.id,producer.run,'NATIVE_SHIM_ARTIFACT_RUN');
  assert.equal(artifact.workflow_run?.head_sha,producer.entry,'NATIVE_SHIM_ARTIFACT_PRODUCER');
}

export function headerCommands(root,platform,jobs,compilers,launcher,sdk) {
  assert.ok(tuples[platform],'NATIVE_SHIM_PLATFORM');
  assert.ok(Number.isSafeInteger(jobs)&&jobs>0,'NATIVE_SHIM_JOBS');
  for(const tool of [compilers.c,compilers.cxx,launcher])assert.ok(path.isAbsolute(tool),'NATIVE_SHIM_TOOL_PATH');
  const build=path.join(root,'header-build'),prefix=path.join(root,'headers');
  // Same public-header configuration as E126700's llc-build. Only the requested
  // build/install targets change; lld stays configured but is never built.
  return [
    ['headers-configure','cmake',['-G','Ninja','-S',path.join(root,'llvm-source/llvm'),'-B',build,
      '-DCANGJIE_RUNTIME_SOURCE_DIR='+path.join(root,'runtime-source'),'-DCMAKE_BUILD_TYPE=Release',
      '-DLLVM_ENABLE_ASSERTIONS=OFF','-DBUILD_SHARED_LIBS=OFF','-DLLVM_LINK_LLVM_DYLIB=OFF',
      '-DLLVM_BUILD_LLVM_DYLIB=OFF','-DLLVM_ENABLE_RTTI=OFF','-DLLVM_ENABLE_LIBXML2=OFF',
      '-DLLVM_TARGETS_TO_BUILD='+(platform.endsWith('aarch64')?'AArch64':'X86'),'-DLLVM_ENABLE_PROJECTS=lld',
      '-DCMAKE_C_COMPILER='+compilers.c,'-DCMAKE_CXX_COMPILER='+compilers.cxx,
      '-DCMAKE_C_COMPILER_LAUNCHER='+launcher,'-DCMAKE_CXX_COMPILER_LAUNCHER='+launcher,
      '-DLLVM_PARALLEL_COMPILE_JOBS='+jobs,'-DLLVM_PARALLEL_LINK_JOBS=1',
      '-DCMAKE_CXX_FLAGS=-gline-tables-only -include cstdint -include unordered_map -include map -include vector -include string',
      ...(sdk?['-DCMAKE_OSX_SYSROOT='+sdk.root]:[])]],
    ['headers-build','cmake',['--build',build,'--parallel',String(jobs),'--target','llvm-headers']],
    ['headers-install','cmake',['--install',build,'--prefix',prefix,'--component','llvm-headers']],
  ];
}

export function consumeShim(platform,root,compiler,sdk,launcher,run,env) {
  const darwin=platform.startsWith('darwin_'),work=path.join(root,'evidence');
  const library=path.join(root,'dylib',darwin?'libLLVM.dylib':'libLLVM-15.so');
  const executable=path.join(work,'shim-gap-test');
  run('shim-compile-link',launcher,[compiler,'-std=c++17','-O2','-fno-rtti','-fno-exceptions',
    ...(darwin?['-arch',platform.endsWith('aarch64')?'arm64':'x86_64','-isysroot',sdk.root]:[]),
    '-I'+path.join(root,'headers/include'),path.join(repositoryRoot,'runtime_shim/llvm15_c_api_gap_test.cpp'),
    path.join(root,'runtime_shim/cjselfhost_llvmshim.o'),library,'-Wl,-rpath,'+path.dirname(library),
    '-Wl,-t','-o',executable]);
  const loader=run('shim-loader',darwin?'otool':'ldd',darwin?['-L',executable]:[executable]);
  assert.ok(!loader.stdout.includes('not found'),'NATIVE_SHIM_DEPENDENCY');
  const result=run('shim-three-apis',executable,[],{env:{...env,
    ...(darwin?{DYLD_PRINT_LIBRARIES:'1'}:{LD_DEBUG:'libs'})}});
  for(const api of ['LLVMGetValueContext','LLVMCanValueUseFastMathFlags','LLVMSetFastMathFlags'])
    assert.ok(result.stdout.split(/\r?\n/).includes('CHECK '+api+' PASS'),'NATIVE_SHIM_API_'+api);
  assert.ok(result.stdout.split(/\r?\n/).includes('FAILS=0'),'NATIVE_SHIM_FAILURES');
  assert.ok(result.stderr.includes(library),'NATIVE_SHIM_LOADED_LIBRARY');
}

// Size/accounting only, no inventory certification; do not follow source symlinks.
function footprint(directory) {
  if(!directory||!fs.existsSync(directory))return {bytes:0,allocated:0};
  const stat=fs.lstatSync(directory);
  const total={bytes:stat.size,allocated:stat.blocks*512};
  if(stat.isDirectory())for(const name of fs.readdirSync(directory)) {
    const child=footprint(path.join(directory,name));total.bytes+=child.bytes;total.allocated+=child.allocated;
  }
  return total;
}

async function shimMain(mode,platform,root,work,run,env) {
  const limit=12*GiB,reserve=2*GiB;
  const admission=async(phase,reserveClosure=false)=>{
    const capacity=await buildCapacity(),disk=fs.statfsSync(root),usage=footprint(root),cache=footprint(env.SCCACHE_DIR);
    const remaining=reserveClosure?Math.max(0,limit-usage.bytes-cache.bytes):0;
    let available=process.availableMemory();
    if(platform.startsWith('darwin_')) {
      // os.freemem alone omits reclaimable inactive pages on these hosted Macs.
      // Record the native counters and count each category once, not total RAM.
      const vm=run('vm-'+phase,'vm_stat',[]).stdout;
      const page=Number(vm.match(/page size of (\d+) bytes/)?.[1]);
      const counts=['free','inactive','speculative'].map(name=>Number(vm.match(new RegExp('Pages '+name+':\\s+(\\d+)'))?.[1]));
      assert.ok(page>0&&counts.every(Number.isFinite),'NATIVE_SHIM_VM_STAT');
      available=page*counts.reduce((sum,value)=>sum+value,0);
    }
    const memory=Math.min(capacity.memory,available);
    const record={phase,at:new Date().toISOString(),...capacity,availableMemory:memory,
      freeDisk:disk.bavail*disk.bsize,usage,cache,limit,reserve,remaining,
      runner:env.RUNNER_NAME,image:env.ImageVersion,os:os.release(),arch:os.arch()};
    writeJson(path.join(work,'capacity-'+phase+'.json'),record);
    assert.ok(usage.bytes+cache.bytes<=limit&&record.freeDisk>=reserve+remaining,'NATIVE_SHIM_DISK_CAPACITY');
    assert.ok(memory>=2*GiB,'NATIVE_SHIM_MEMORY_CAPACITY');
    return record;
  };
  if(mode==='prepare-shim') {
    fs.mkdirSync(path.dirname(root),{recursive:true});fs.mkdirSync(root);fs.mkdirSync(work);
    await admission('before-download',true);
    const original=JSON.parse(run('producer-run','gh',['api',`repos/${producer.repository}/actions/runs/${producer.run}/attempts/${producer.attempt}`]).stdout);
    const tuple=JSON.parse(run('artifact-metadata','gh',['api',`repos/${producer.repository}/actions/artifacts/${tuples[platform].artifact}`]).stdout);
    const dylib=JSON.parse(run('dylib-metadata','gh',['api',`repos/${producer.repository}/actions/artifacts/${dylibs[platform].artifact}`]).stdout);
    requireArtifact(platform,original,tuple);requireDylibArtifact(platform,dylib);
    assert.ok(env.GITHUB_OUTPUT,'GITHUB_OUTPUT is required');
    fs.appendFileSync(env.GITHUB_OUTPUT,`artifact_id=${tuple.id}\ndylib_id=${dylib.id}\nrun_id=${producer.run}\n`);
    return;
  }
  assert.equal(mode,'consume-shim');assert.ok(fs.existsSync(work),'NATIVE_SHIM_PREPARE_REQUIRED');
  const summary={platform,producer,headersProducer:{entry:env.GITHUB_SHA,run:env.GITHUB_RUN_ID,attempt:env.GITHUB_RUN_ATTEMPT},
    fetch:'NOT_RUN',headers:'NOT_RUN',shim:'NOT_RUN',tools:'NOT_RUN (already consumed)',rc:null};
  try {
    await admission('before-source',true);
    verifyArtifact(path.join(root,'artifact'),platform);
    const library=platform.startsWith('darwin_')?'libLLVM.dylib':'libLLVM-15.so';
    const manifest=JSON.parse(fs.readFileSync(path.join(root,'dylib/manifest.json'),'utf8'));
    for(const [key,value]of Object.entries({llvm_sha:producer.llvm,runtime_sha:producer.runtime,platform,library,
      sha256:dylibs[platform].sha256,run_id:String(producer.run),run_attempt:String(producer.attempt)}))
      assert.equal(manifest[key],value,'NATIVE_SHIM_DYLIB_'+key);
    assert.deepEqual(manifest.targets,['X86','ARM','AArch64'],'NATIVE_SHIM_DYLIB_TARGETS');
    assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(root,'dylib',library))).digest('hex'),
      dylibs[platform].sha256,'NATIVE_SHIM_DYLIB_DIGEST');
    fs.mkdirSync(path.join(root,'runtime_shim'));
    run('fetch','npx',['--yes','zx@8',path.join(repositoryRoot,'ci/platform_matrix/fetch_llvm_tuple.mjs')],
      {env:{...env,TUPLE_ARTIFACT_DIR:path.join(root,'artifact'),PLATFORM_CI_ROOT:root,GITHUB_ENV:path.join(root,'selected.env')}});
    summary.fetch=0;
    for(const [name,repository,sha,paths]of [
      ['llvm-source','cjcj-llvm',producer.llvm,['llvm','lld','cmake','third-party']],
      ['runtime-source','cangjie-runtime',producer.runtime,['runtime']],
    ]) {
      const source=path.join(root,name);
      run(name+'-init','git',['init',source]);
      run(name+'-remote','git',['-C',source,'remote','add','origin',`https://github.com/cjcj-dev/${repository}.git`]);
      run(name+'-sparse','git',['-C',source,'sparse-checkout','set',...paths]);
      run(name+'-fetch','git',['-C',source,'fetch','--depth=1','--filter=blob:none','origin',sha],{timeout:600000});
      run(name+'-checkout','git',['-C',source,'checkout','--detach','FETCH_HEAD'],{timeout:600000});
      assert.equal(run(name+'-identity','git',['-C',source,'rev-parse','HEAD']).stdout.trim(),sha,'NATIVE_SHIM_SOURCE');
    }
    const darwin=platform.startsWith('darwin_');
    const locate=name=>run(name+'-path',darwin?'xcrun':'which',darwin?['--find',name]:[name]).stdout.trim();
    const compilers={c:locate('clang'),cxx:locate('clang++')};
    const sdk=darwin?{root:run('sdk-root','xcrun',['--sdk','macosx','--show-sdk-path']).stdout.trim(),
      version:run('sdk-version','xcrun',['--sdk','macosx','--show-sdk-version']).stdout.trim()}:null;
    run('compiler-version',compilers.cxx,['--version']);run('cmake-version','cmake',['--version']);
    const capacity=await admission('before-configure',true);
    const jobs=await selectBuildJobs(Math.max(1,Math.min(4,capacity.cpus,Math.floor((capacity.availableMemory-GiB)/(1.5*GiB)))),env);
    summary.configuration={compilers,sdk,jobs,launcher:env.SCCACHE_PATH};
    for(const [label,command,args]of headerCommands(root,platform,jobs,compilers,env.SCCACHE_PATH,sdk)) {
      // Native time records the normal command's RSS and propagated status. Its
      // wrapper status remains separately recorded by darwinCommand.
      run(label,'/usr/bin/time',[darwin?'-l':'-v',command,...args],{timeout:label==='headers-build'?3600000:600000});
      if(label==='headers-configure') {
        run('headers-dependencies','ninja',['-C',path.join(root,'header-build'),'-t','query','llvm-headers']);
        run('headers-commands','ninja',['-C',path.join(root,'header-build'),'-t','commands','llvm-headers']);
      }
      await admission('after-'+label,true);
    }
    summary.headers=0;
    run('headers-package','tar',['-czf',path.join(root,'llvm-headers-'+platform+'.tar.gz'),'-C',path.join(root,'headers'),'.']);
    summary.headersOutput={...footprint(path.join(root,'headers')),
      archiveBytes:fs.statSync(path.join(root,'llvm-headers-'+platform+'.tar.gz')).size};
    consumeShim(platform,root,compilers.cxx,sdk,env.SCCACHE_PATH,run,env);summary.shim=0;
    await admission('complete');summary.rc=0;
  }catch(error){summary.rc=error.exitCode||1;summary.error=error.message;throw error;}
  finally{writeJson(path.join(work,'summary.json'),summary);}
}

function files(directory, relative='') {
  return fs.readdirSync(path.join(directory,relative)).flatMap(name => {
    const member=path.join(relative,name), stat=fs.lstatSync(path.join(directory,member));
    assert.ok(!stat.isSymbolicLink(), 'NATIVE_TUPLE_SYMLINK');
    if(stat.isDirectory())return files(directory,member);
    assert.ok(stat.isFile(), 'NATIVE_TUPLE_REGULAR_FILE');
    return [{name:member.split(path.sep).join('/'), bytes:stat.size}];
  });
}
export function verifyArtifact(directory, platform) {
  const selected=tuples[platform];assert.ok(selected,'NATIVE_TUPLE_PLATFORM');
  const linker=platform.startsWith('darwin_')?'ld64.lld':'ld.lld';
  const expected=['MANIFEST','SHA256SUMS','lib/STATIC_LLVM.txt',
    ...['llc','opt',linker].map(tool=>'bin/'+tool),
    ...['llc.gz','opt.gz',linker+'.gz','llvm-tools.manifest','cjselfhost_llvmshim.o'].map(tool=>'fixed-llc/'+tool)];
  assert.deepEqual(files(directory).map(row=>row.name).sort(),expected.sort(),'NATIVE_TUPLE_MEMBERS');
  assert.equal(verifyTuplePayloads(directory),selected.sums,'NATIVE_TUPLE_SUMS');
  const manifest=parseLlvmToolsManifest(fs.readFileSync(path.join(directory,'fixed-llc/llvm-tools.manifest'),'utf8')).values;
  for(const [key,value]of [['PLATFORM',platform],['LLVM_SHA',producer.llvm],
    ['CANGJIE_COMPILER_SHA',producer.compiler],['FLATBUFFERS_SHA',producer.flatbuffers],['LLD_TOOL',linker]])
    assert.equal(manifest.get(key),value,'NATIVE_TUPLE_'+key);
  const metadata=fs.readFileSync(path.join(directory,'MANIFEST'),'utf8');
  for(const [key,value]of [['PLATFORM',platform],['LLVM_SHA',producer.llvm],
    ['CANGJIE_COMPILER_SHA',producer.compiler],['RECIPE_CJCJ_SHA',producer.entry],['RUNTIME_REF',producer.runtime]])
    assert.ok(metadata.split('\n').includes(key+'='+value),'NATIVE_TUPLE_METADATA_'+key);
  return manifest;
}

// Same IR, C driver, and three results as native575/validate-native-tools.mjs.
export const consumerIR=`define i64 @sum_to(i64 %n) {
entry: br label %loop
loop:
 %i = phi i64 [ 0, %entry ], [ %next, %body ]
 %sum = phi i64 [ 0, %entry ], [ %added, %body ]
 %more = icmp ult i64 %i, %n
 br i1 %more, label %body, label %exit
body:
 %next = add i64 %i, 1
 %added = add i64 %sum, %next
 br label %loop
exit: ret i64 %sum
}
`;
export const consumerDriver='#include <stdint.h>\n#include <stdio.h>\n#include <stdlib.h>\nextern uint64_t sum_to(uint64_t);\nint main(int argc,char **argv){if(argc!=3)return 2;uint64_t n=strtoull(argv[1],0,10),expected=strtoull(argv[2],0,10),got=sum_to(n);printf("input=%llu got=%llu expected=%llu\\n",(unsigned long long)n,(unsigned long long)got,(unsigned long long)expected);return got!=expected;}\n';

export function nativeCommands(platform,bin,work,compiler,sdk) {
  assert.ok(tuples[platform],'NATIVE_TUPLE_PLATFORM');
  assert.ok(path.isAbsolute(compiler),'NATIVE_TUPLE_COMPILER_PATH');
  const darwin=platform.startsWith('darwin_'), arch=platform.endsWith('aarch64')?'arm64':'x86_64';
  const triple=darwin?`${arch}-apple-macosx13.0.0`:'aarch64-unknown-linux-gnu';
  if(darwin)assert.ok(path.isAbsolute(sdk?.root||'')&&/^\d+(?:\.\d+){0,2}$/.test(sdk.version),'NATIVE_TUPLE_APPLE_SDK');
  return [
    ['opt',path.join(bin,'opt'),['-passes=default<O2>','-verify-each','-S',path.join(work,'consumer.ll'),'-o',path.join(work,'optimized.ll')]],
    ['llc',path.join(bin,'llc'),['-mtriple='+triple,'-relocation-model=pic','-filetype=obj',path.join(work,'optimized.ll'),'-o',path.join(work,'consumer.o')]],
    ['driver',compiler,[...(darwin?['-arch',arch,'-isysroot',sdk.root,'-mmacosx-version-min=13.0']:[]),'-c',path.join(work,'driver.c'),'-o',path.join(work,'driver.o')]],
    darwin?['link',path.join(bin,'ld64.lld'),['-arch',arch,'-platform_version','macos','13.0',sdk.version,
      '-syslibroot',sdk.root,'-lSystem',path.join(work,'driver.o'),path.join(work,'consumer.o'),'-o',path.join(work,'consumer')]]
      :['link',compiler,['--ld-path='+path.join(bin,'ld.lld'),'-Wl,-t',path.join(work,'driver.o'),path.join(work,'consumer.o'),'-o',path.join(work,'consumer')]],
  ];
}
export function consumeProgram(platform,bin,work,compiler,sdk,run) {
  fs.writeFileSync(path.join(work,'consumer.ll'),consumerIR);
  fs.writeFileSync(path.join(work,'driver.c'),consumerDriver);
  for(const [label,tool,args]of nativeCommands(platform,bin,work,compiler,sdk))run(label,tool,args);
  const executable=path.join(work,'consumer');
  const loader=run('program-loader',platform.startsWith('darwin_')?'otool':'ldd',platform.startsWith('darwin_')?['-L',executable]:[executable]);
  assert.ok(!loader.stdout.includes('not found'),'NATIVE_TUPLE_PROGRAM_DEPENDENCY');
  for(const [input,expected]of [['0','0'],['1','1'],['10000','50005000']]) {
    const result=run('execute-'+input,executable,[input,expected]);
    assert.ok(result.stdout.includes(`input=${input} got=${expected} expected=${expected}`),'NATIVE_TUPLE_RESULT');
  }
}

async function main(mode) {
  const platform=targetForHost()?.spec.llvmPlatform;
  assert.ok(tuples[platform],'NATIVE_TUPLE_NATIVE_HOST');
  if(process.env.NATIVE_CONSUMER_PLATFORM)assert.equal(platform,process.env.NATIVE_CONSUMER_PLATFORM,'NATIVE_TUPLE_RUNNER_PLATFORM');
  const root=path.resolve(process.env.PLATFORM_CI_ROOT||'.platform-ci/tuple-consumer');
  const work=path.join(root,'evidence');
  const env={...process.env};
  for(const key of ['LD_LIBRARY_PATH','LD_PRELOAD','DYLD_LIBRARY_PATH','DYLD_INSERT_LIBRARIES','NODE_OPTIONS','TUPLE_DRY_RUN'])delete env[key];
  const run=(label,tool,args,options={})=>darwinCommand(work,label,tool,args,{cwd:root,env,timeout:180000,...options});
  if(mode==='prepare-shim'||mode==='consume-shim')return shimMain(mode,platform,root,work,run,env);
  const admission=async phase=>{
    const disk=fs.statfsSync(root), bytes=files(root).reduce((total,row)=>total+row.bytes,0);
    const capacity={phase,at:new Date().toISOString(),...await buildCapacity(),freeMemory:os.freemem(),
      freeDisk:disk.bavail*disk.bsize,outputBytes:bytes,outputLimit:2*GiB,reserveBytes:2*GiB};
    writeJson(path.join(work,'capacity-'+phase+'.json'),capacity);
    assert.ok(bytes<=2*GiB && capacity.freeDisk>=2*GiB+(mode==='prepare'?2*GiB:0),'NATIVE_TUPLE_CAPACITY');
  };
  if(mode==='prepare') {
    fs.mkdirSync(path.dirname(root),{recursive:true});
    fs.mkdirSync(root);fs.mkdirSync(work);
    await admission('before-download');
    const runMetadata=JSON.parse(run('producer-run','gh',['api',`repos/${producer.repository}/actions/runs/${producer.run}/attempts/${producer.attempt}`]).stdout);
    const metadata=JSON.parse(run('artifact-metadata','gh',['api',`repos/${producer.repository}/actions/artifacts/${tuples[platform].artifact}`]).stdout);
    requireArtifact(platform,runMetadata,metadata);
    assert.ok(process.env.GITHUB_OUTPUT,'GITHUB_OUTPUT is required');
    fs.appendFileSync(process.env.GITHUB_OUTPUT,`artifact_id=${tuples[platform].artifact}\nrun_id=${producer.run}\n`);
    return;
  }
  assert.equal(mode,'consume','NATIVE_TUPLE_MODE');
  assert.ok(fs.existsSync(work),'NATIVE_TUPLE_PREPARE_REQUIRED');
  const summary={platform,producer,artifact:tuples[platform].artifact,fetch:'NOT_RUN',install:'NOT_RUN',consumer:'NOT_RUN',
    shim:{status:'NOT_RUN',reason:'No matching platform LLVM header input supplied; tuple tools consumption only'},rc:null};
  try {
    await admission('before-consume');
    const artifact=path.join(root,'artifact'), manifest=verifyArtifact(artifact,platform);
    const selectedEnv=path.join(root,'selected.env');assert.ok(!fs.existsSync(selectedEnv),'NATIVE_TUPLE_FRESH_ENV');
    fs.mkdirSync(path.join(root,'runtime_shim'));
    run('fetch','npx',['--yes','zx@8',path.join(repositoryRoot,'ci/platform_matrix/fetch_llvm_tuple.mjs')],
      {env:{...env,TUPLE_ARTIFACT_DIR:artifact,PLATFORM_CI_ROOT:root,GITHUB_ENV:selectedEnv}});
    summary.fetch=0;
    const selected=new Map(fs.readFileSync(selectedEnv,'utf8').trim().split('\n').map(line=>{const at=line.indexOf('=');return[line.slice(0,at),line.slice(at+1)];}));
    assert.equal(selected.get('PLATFORM_TUPLE'),platform,'NATIVE_TUPLE_FETCH_PLATFORM');
    const bin=path.join(root,'install/bin');fs.mkdirSync(bin,{recursive:true});
    const tools=[['llc','LLC'],['opt','OPT'],[manifest.get('LLD_TOOL'),'LLD']].map(([name,key])=>{
      const archive=selected.get('FIXED_'+key+'_GZ');
      assert.equal(archive,path.join(root,'fixed-toolchain',platform,name+'.gz'),'NATIVE_TUPLE_FETCH_PATH');
      fs.writeFileSync(path.join(bin,name),zlib.gunzipSync(fs.readFileSync(archive)),{mode:0o755});
      return {name,archive,manifestKey:key+'_SHA256',versionKey:key+'_VERSION'};
    });
    await verifyInstalledLlvmTuple(tools,{sdk:path.join(root,'install'),sdkToolPath:async name=>path.join(bin,name),manifest,env});
    summary.install=0;
    const darwin=platform.startsWith('darwin_');
    for(const tool of tools){const probe=run('loader-'+tool.name,darwin?'otool':'ldd',darwin?['-L',path.join(bin,tool.name)]:[path.join(bin,tool.name)]);assert.ok(!probe.stdout.includes('not found'),'NATIVE_TUPLE_TOOL_DEPENDENCY');}
    const compiler=run('compiler-path',darwin?'xcrun':'which',darwin?['--find','clang']:['clang']).stdout.trim();
    const sdk=darwin?{root:run('sdk-root','xcrun',['--sdk','macosx','--show-sdk-path']).stdout.trim(),
      version:run('sdk-version','xcrun',['--sdk','macosx','--show-sdk-version']).stdout.trim()}:null;
    run('compiler-version',compiler,['--version']);
    consumeProgram(platform,bin,work,compiler,sdk,run);summary.consumer=0;
    await admission('complete');summary.rc=0;
  }catch(error){summary.rc=error.exitCode||1;summary.error=error.message;throw error;}
  finally{writeJson(path.join(work,'summary.json'),summary);}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try{await main(process.argv[2]);}catch(error){console.error(error.stack);process.exitCode=error.exitCode||1;}
}
