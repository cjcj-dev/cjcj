import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {test} from 'node:test';
import {producer,tuples,dylibs,requireArtifact,requireDylibArtifact,headerCommands,consumeShim,nativeCommands,consumeProgram,verifyArtifact} from './native_llvm_consumer.mjs';

const platform='linux_aarch64';
function metadata() {
  return {run:{id:producer.run,run_attempt:1,head_sha:producer.entry,status:'completed',conclusion:'success'},
    artifact:{id:tuples[platform].artifact,name:'static-llvm-tuple-'+platform,expired:false,
      size_in_bytes:tuples[platform].bytes,workflow_run:{id:producer.run,head_sha:producer.entry}}};
}
test('exact artifact from successful original attempt is required, with no recent-run fallback',()=>{
  const good=metadata();assert.equal(requireArtifact(platform,good.run,good.artifact),tuples[platform]);
  for(const [object,key,value,target]of [
    ['run','id',1,'RUN'],['run','run_attempt',2,'ATTEMPT'],['run','head_sha','0'.repeat(40),'PRODUCER'],
    ['run','conclusion','failure','RUN_FAILED'],['run','status','in_progress','RUN_PENDING'],
    ['artifact','id',1,'ARTIFACT'],['artifact','expired',true,'EXPIRED'],
    ['artifact','size_in_bytes',1,'ARCHIVE_SIZE'],['artifact','name','old-master','ARTIFACT_NAME'],
  ]) {
    const changed=metadata();changed[object][key]=value;
    assert.throws(()=>requireArtifact(platform,changed.run,changed.artifact),new RegExp('NATIVE_TUPLE_'+target));
  }
  for(const [key,value,target]of [['id',1,'ARTIFACT_RUN'],['head_sha','0'.repeat(40),'ARTIFACT_PRODUCER']]) {
    const changed=metadata();changed.artifact.workflow_run[key]=value;
    assert.throws(()=>requireArtifact(platform,changed.run,changed.artifact),new RegExp(target));
  }
  assert.equal(requireArtifact(platform,good.run,good.artifact),tuples[platform]);
});

for(const selected of Object.keys(tuples))test(selected+' uses installed LLVM tools and actual native linker inputs',()=>{
  const root=path.resolve('/native consumer'), bin=path.join(root,'install/bin'),work=path.join(root,'evidence');
  const sdk={root:'/Applications/SDK with spaces',version:'15.5'};
  const commands=nativeCommands(selected,bin,work,'/usr/bin/clang',sdk);
  assert.equal(commands[0][1],path.join(bin,'opt'));assert.equal(commands[1][1],path.join(bin,'llc'));
  assert.ok(commands[0][2].includes('-verify-each'));
  const link=commands[3];
  if(selected.startsWith('darwin_')) {
    assert.equal(link[1],path.join(bin,'ld64.lld'));
    assert.deepEqual(link[2].slice(0,8),['-arch',selected.endsWith('aarch64')?'arm64':'x86_64','-platform_version','macos','13.0','15.5','-syslibroot',sdk.root]);
    assert.ok(link[2].includes('-lSystem'));
    assert.throws(()=>nativeCommands(selected,bin,work,'/usr/bin/clang',{root:'relative',version:'15.5'}),/APPLE_SDK/);
  }else assert.ok(link[2].includes('--ld-path='+path.join(bin,'ld.lld')));
});

function fixture(context) {
  const parent=process.env.RELEASE_EVIDENCE_TEST_ROOT||os.tmpdir();fs.mkdirSync(parent,{recursive:true});
  const root=fs.mkdtempSync(path.join(parent,'native-tuple-consumer-'));
  if(!process.env.RELEASE_EVIDENCE_TEST_ROOT)context.after(()=>fs.rmSync(root,{recursive:true,force:true}));
  return root;
}
test('consumer runs all three numeric assertions; command failure stops subsequent execution',context=>{
  const root=fixture(context),seen=[];
  const run=(label,tool,args)=>{seen.push({label,tool,args});return {stdout:label.startsWith('execute-')?`input=${args[0]} got=${args[1]} expected=${args[1]}\n`:''};};
  consumeProgram(platform,root,root,'/usr/bin/clang',null,run);
  assert.deepEqual(seen.filter(row=>row.label.startsWith('execute-')).map(row=>row.args),[['0','0'],['1','1'],['10000','50005000']]);
  const cut=[];
  assert.throws(()=>consumeProgram(platform,root,root,'/usr/bin/clang',null,(label,tool,args)=>{
    cut.push(label);if(label==='link')throw Object.assign(Error('actual linker rc'),{exitCode:7});return run(label,tool,args);
  }),error=>error.exitCode===7);
  assert.deepEqual(cut,['opt','llc','driver','link']);
  assert.throws(()=>consumeProgram(platform,root,root,'/usr/bin/clang',null,()=>({stdout:'version only'})),/NATIVE_TUPLE_RESULT/);
  consumeProgram(platform,root,root,'/usr/bin/clang',null,run);
});
test('empty, extra, and symlink artifact members fail before fetch can select a fallback',context=>{
  const root=fixture(context);
  assert.throws(()=>verifyArtifact(root,platform),/NATIVE_TUPLE_MEMBERS/);
  fs.writeFileSync(path.join(root,'old-master'),'unqualified payload');
  assert.throws(()=>verifyArtifact(root,platform),/NATIVE_TUPLE_MEMBERS/);
  fs.symlinkSync('old-master',path.join(root,'bin'));
  assert.throws(()=>verifyArtifact(root,platform),/NATIVE_TUPLE_SYMLINK/);
});
test('official shim consumption selects the three hosts with missing headers only',()=>{
  const workflow=fs.readFileSync(new URL('../../.github/workflows/consume-native-llvm-tuple.yml',import.meta.url),'utf8');
  const cells=[...workflow.matchAll(/- platform: ([^\s]+)\n\s+runner: ([^\s]+)/g)].map(match=>({platform:match[1],runner:match[2]}));
  assert.deepEqual(cells,[{platform:'linux_aarch64',runner:'ubuntu-22.04-arm'},
    {platform:'darwin_x86_64',runner:'macos-15-intel'},{platform:'darwin_aarch64',runner:'macos-26'}]);
  assert.equal((workflow.match(/- platform:/g)||[]).length,3);
  assert.match(workflow,/timeout-minutes: 90/);assert.match(workflow,/max-parallel: 3/);
  assert.match(workflow,/native_llvm_consumer\.mjs prepare-shim/);
  assert.match(workflow,/native_llvm_consumer\.mjs consume-shim/);
  assert.doesNotMatch(workflow,/native_llvm_consumer\.mjs consume\s/);
  assert.match(workflow,/artifact-ids: \$\{\{ steps.select.outputs.dylib_id \}\}/);
  assert.match(workflow,/llvm-headers-\*\.tar\.gz/);
  assert.match(workflow,/component: llvm-headers/);
  assert.match(workflow,/artifact-ids: \$\{\{ steps.select.outputs.artifact_id \}\}/);
  assert.match(workflow,/run-id: \$\{\{ steps.select.outputs.run_id \}\}/);
  assert.doesNotMatch(workflow,/build_cjcj|build-fixed-llc|build-llvm-tools|workflow_run:|schedule:/);
});

test('dylib selection binds exact old platform/run/artifact rather than a recent build',()=>{
  for(const selected of Object.keys(dylibs)) {
    const item=dylibs[selected];
    const artifact={id:item.artifact,size_in_bytes:item.bytes,name:'llvm-dylib-'+selected,expired:false,
      workflow_run:{id:producer.run,head_sha:producer.entry}};
    requireDylibArtifact(selected,artifact);
    assert.throws(()=>requireDylibArtifact(selected,{...artifact,id:item.artifact+1}),/ARTIFACT_id/);
    assert.throws(()=>requireDylibArtifact(selected,{...artifact,workflow_run:{id:1,head_sha:producer.entry}}),/ARTIFACT_RUN/);
    requireDylibArtifact(selected,artifact);
  }
});

test('normal header graph keeps original ABI options and installs only its component',()=>{
  for(const selected of Object.keys(tuples)) {
    const root='/new native headers', commands=headerCommands(root,selected,1,
      {c:'/usr/bin/clang',cxx:'/usr/bin/clang++'},'/cache/sccache',selected.startsWith('darwin_')?{root:'/actual SDK'}:null);
    const configure=commands[0][2];
    for(const option of ['-DLLVM_ENABLE_ASSERTIONS=OFF','-DLLVM_ENABLE_RTTI=OFF',
      '-DBUILD_SHARED_LIBS=OFF','-DLLVM_BUILD_LLVM_DYLIB=OFF','-DLLVM_LINK_LLVM_DYLIB=OFF',
      '-DCANGJIE_RUNTIME_SOURCE_DIR='+root+'/runtime-source'])assert.ok(configure.includes(option),option);
    assert.ok(configure.includes('-DLLVM_TARGETS_TO_BUILD='+(selected.endsWith('aarch64')?'AArch64':'X86')));
    assert.deepEqual(commands[1].slice(1),['cmake',['--build',root+'/header-build','--parallel','1','--target','llvm-headers']]);
    assert.deepEqual(commands[2].slice(1),['cmake',['--install',root+'/header-build','--prefix',root+'/headers','--component','llvm-headers']]);
  }
});

test('shim consumer uses installed headers and original object/library; API and loader failures reject',()=>{
  for(const selected of Object.keys(tuples)) {
    const root='/native shim',library=root+'/dylib/'+(selected.startsWith('darwin_')?'libLLVM.dylib':'libLLVM-15.so');
    const good=['LLVMGetValueContext','LLVMCanValueUseFastMathFlags','LLVMSetFastMathFlags'].map(api=>'CHECK '+api+' PASS').join('\n')+'\nFAILS=0\n';
    const calls=[],run=(label,tool,args)=>{calls.push({label,tool,args});return {stdout:label==='shim-three-apis'?good:library,stderr:library};};
    const consume=executor=>consumeShim(selected,root,'/usr/bin/clang++',{root:'/actual SDK'},'/cache/sccache',executor,{});
    consume(run);
    assert.ok(calls[0].args.includes('-I'+root+'/headers/include'));
    assert.ok(calls[0].args.includes(root+'/runtime_shim/cjselfhost_llvmshim.o'));
    assert.ok(calls[0].args.includes(library));
    assert.deepEqual(calls.map(row=>row.label),['shim-compile-link','shim-loader','shim-three-apis']);
    assert.throws(()=>consume((label,tool,args)=>({...run(label,tool,args),stdout:label==='shim-three-apis'?good.replace('CHECK LLVMSetFastMathFlags PASS','CHECK LLVMSetFastMathFlags FAIL'):library})),/NATIVE_SHIM_API_LLVMSetFastMathFlags/);
    assert.throws(()=>consume((label,tool,args)=>({...run(label,tool,args),stderr:'/system/libLLVM'})),/NATIVE_SHIM_LOADED_LIBRARY/);
    const stopped=[];
    assert.throws(()=>consume(label=>{stopped.push(label);throw Object.assign(Error('link failure'),{exitCode:7});}),error=>error.exitCode===7);
    assert.deepEqual(stopped,['shim-compile-link']);
    consume(run);
  }
});

test('registered LLVM entry selects consumption exclusively and preserves normal production selection',()=>{
  const entry=fs.readFileSync(new URL('../../.github/workflows/build-fixed-llc.yml',import.meta.url),'utf8');
  const consumer=fs.readFileSync(new URL('../../.github/workflows/consume-native-llvm-tuple.yml',import.meta.url),'utf8');
  assert.match(entry,/consume_native_only:\n[\s\S]*?type: boolean\n        default: false/);
  assert.match(consumer,/on:\n  workflow_call:/);
  assert.doesNotMatch(consumer,/workflow_dispatch:/);
  const jobs=Object.fromEntries([...entry.slice(entry.indexOf('\njobs:')).matchAll(/^  ([\w-]+):\n([\s\S]*?)(?=^  [\w-]+:\n|$(?![\s\S]))/gm)].map(match=>[match[1],match[2]]));
  assert.deepEqual(Object.keys(jobs),['native-consume','native-runtime','host','tuple','persist']);
  assert.match(jobs['native-consume'],/uses: \.\/\.github\/workflows\/consume-native-llvm-tuple.yml/);
  assert.match(jobs['native-consume'],/permissions:\n      contents: read\n      actions: read/);
  assert.doesNotMatch(jobs['native-consume'],/needs:|secrets:|with:/);
  // These workflow conditions are plain boolean expressions. Execute their actual
  // input/needs expressions; actionlint separately checks GitHub expression syntax.
  const selected=(inputs,platforms='["linux_aarch64"]')=>Object.entries(jobs).filter(([name,body])=>{
    const expression=body.match(/^    if: \$\{\{ (.+) \}\}$/m)?.[1];
    assert.ok(expression,'missing job condition: '+name);
    return Function('inputs','needs',`return (${expression})`)(inputs,{tuple:{outputs:{tuple_platforms:platforms}}});
  }).map(([name])=>name);
  for(let bits=0;bits<32;bits++) {
    const input=Object.fromEntries(['build_runtime','publish_host','publish_tuple','publish_dylib','persist_tuple'].map((key,i)=>[key,Boolean(bits&(1<<i))]));
    for(const platforms of ['[]','["linux_aarch64"]']) {
      assert.deepEqual(selected({...input,consume_native_only:true},platforms),['native-consume'],'consume mode must exclude every production/publication job');
      const expected=[...(input.build_runtime?['native-runtime']:[]),...(input.publish_host?['host']:[]),
        ...(!input.publish_host||input.publish_tuple||input.publish_dylib?['tuple']:[]),
        ...(input.persist_tuple&&input.publish_tuple&&platforms!=='[]'?['persist']:[])];
      assert.deepEqual(selected({...input,consume_native_only:false},platforms),expected);
      assert.deepEqual(selected(input,platforms),expected);
    }
  }
  assert.deepEqual(selected({}),['tuple']); // Existing push/default behavior.
  assert.deepEqual(selected({consume_native_only:true}),['native-consume']);
});
