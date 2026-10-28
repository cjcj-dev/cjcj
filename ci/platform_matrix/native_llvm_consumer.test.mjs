import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {test} from 'node:test';
import {producer,tuples,requireArtifact,nativeCommands,consumeProgram,verifyArtifact} from './native_llvm_consumer.mjs';

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
test('official consumption selects only remaining Darwin ARM on standard macos-26',()=>{
  const workflow=fs.readFileSync(new URL('../../.github/workflows/consume-native-llvm-tuple.yml',import.meta.url),'utf8');
  const cells=[...workflow.matchAll(/- platform: ([^\s]+)\n\s+runner: ([^\s]+)/g)].map(match=>({platform:match[1],runner:match[2]}));
  assert.deepEqual(cells,[{platform:'darwin_aarch64',runner:'macos-26'}],
    'only the unconsumed ARM host on the selected standard runner may execute');
  assert.equal((workflow.match(/- platform:/g)||[]).length,1);
  assert.match(workflow,/timeout-minutes: 20/);assert.match(workflow,/max-parallel: 1/);
  assert.match(workflow,/artifact-ids: \$\{\{ steps.select.outputs.artifact_id \}\}/);
  assert.match(workflow,/run-id: \$\{\{ steps.select.outputs.run_id \}\}/);
  assert.doesNotMatch(workflow,/build_cjcj|build-fixed-llc|build-llvm-tools|workflow_run:|schedule:/);
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
