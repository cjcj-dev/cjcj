#!/usr/bin/env zx
// Finite Linux worker entry contract, using the pinned real jq executable.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {exportBranches, expandInputs} from './g3-entry-branches.mjs';
const repo=path.resolve(import.meta.dirname,'..');
const evidence=process.env.WORKER_MIGRATION_EVIDENCE;
const entity=process.env.WORKER_JQ_ENTITY;
assert.ok(evidence && path.isAbsolute(evidence),'WORKER_MIGRATION_EVIDENCE required');
assert.ok(entity && path.isAbsolute(entity),'WORKER_JQ_ENTITY required');
fs.mkdirSync(evidence,{recursive:true});
const expected='5942c9b0934e510ee61eb3e30273f1b3fe2590df93933a93d7c58b81d19c8ff5';
assert.equal(crypto.createHash('sha256').update(fs.readFileSync(entity)).digest('hex'),expected);
const old=path.join(repo,'ci/fixtures/g3/release-evidence-worker.bash.txt');
const candidate=path.join(repo,'ci/release-evidence-worker.mjs');
const caller=path.join(evidence,'caller with spaces');fs.mkdirSync(path.join(caller,'ci'),{recursive:true});
const consumer=path.join(caller,'consumer.mjs');
fs.writeFileSync(consumer,`import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
test('worker actual private jq and evidence consumer',()=>{
  console.log('WORKER_CONSUMER_REACHED');
  const root=process.env.EXPECT_WORKER_ROOT;
  assert.equal(process.env.RELEASE_EVIDENCE_TEST_ROOT,root+'/release-evidence-tests','WORKER_EVIDENCE_ENV');
  assert.equal(process.env.PATH.split(':')[0],root+'/bin','WORKER_PRIVATE_PATH');
  assert.equal(execFileSync('jq',['--version'],{encoding:'utf8'}),'jq-1.7.1\\n');
  fs.writeFileSync(path.join(process.env.RELEASE_EVIDENCE_TEST_ROOT,'consumer.json'),JSON.stringify({cwd:process.cwd(),jq:execFileSync('jq',['-n','{actual: true}'],{encoding:'utf8'}),core:fs.readFileSync('/proc/self/limits','utf8').split('\\n').find(s=>s.startsWith('Max core file size'))}));
});
test('worker independent core limit',()=>{
  assert.match(fs.readFileSync('/proc/self/limits','utf8'),/Max core file size\\s+0\\s+0/);
  console.log('WORKER_CORE_CONTROL_REACHED');
});
`);
fs.writeFileSync(path.join(caller,'ci/test-manifest.mjs'),`if(process.argv[2]!=='list')process.exit(9);console.log('consumer.mjs');\n`);
fs.writeFileSync(path.join(caller,'reject.mjs'),`import {test} from 'node:test';import assert from 'node:assert/strict';test('real consumer expected rejection',()=>assert.fail('WORKER_TEST_FAILURE_PROPAGATED'));\n`);
fs.copyFileSync(entity,path.join(caller,'jq entity'));
fs.writeFileSync(path.join(caller,'wrong-jq'),'wrong checksum\n');
let index=0;const results=[];
function execute(label,variant,args,root){
 const command=variant==='old'?['bash',old,...args]:['npx','--yes','zx@8',candidate,...args];
 const directory=path.join(evidence,`${String(index++).padStart(3,'0')}-${label}-${variant}`);fs.mkdirSync(directory);
 const env={...process.env,LC_ALL:'C',EXPECT_WORKER_ROOT:root};delete env.NODE_TEST_CONTEXT;
 const r=spawnSync(command[0],command.slice(1),{cwd:caller,env,encoding:'utf8',timeout:120000,maxBuffer:4*1024*1024});
 const record={label,variant,command,cwd:caller,rc:r.status,signal:r.signal,error:r.error?.message};
 fs.writeFileSync(path.join(directory,'command.json'),JSON.stringify(record,null,2)+'\n');
 fs.writeFileSync(path.join(directory,'stdout.log'),r.stdout??'');fs.writeFileSync(path.join(directory,'stderr.log'),r.stderr??'');
 results.push({...record,directory});fs.writeFileSync(path.join(evidence,'results.json'),JSON.stringify(results,null,2)+'\n');
 assert.equal(r.signal,null,JSON.stringify(record));assert.equal(r.error,undefined,JSON.stringify(record));
 return {...r,directory};
}
function pair(label,makeArgs,expectedRc,check=()=>{}){
 for(const variant of ['old','candidate']){
  const root=path.join(evidence,`${label} ${variant}`);const r=execute(label,variant,makeArgs(root),root);
  assert.equal(r.status,expectedRc,`${label}/${variant}\n${r.stdout}\n${r.stderr}`);check(r,root,variant);
 }
}
const inventory=exportBranches(fs.readFileSync(old,'utf8'));
fs.writeFileSync(path.join(evidence,'ast-full.json'),JSON.stringify(inventory.ast,null,2)+'\n');
const branchRows=inventory.rows.map(r=>({...r,entry:'ci/release-evidence-worker.mjs'}));
fs.writeFileSync(path.join(evidence,'ast-branches.json'),JSON.stringify(branchRows,null,2)+'\n');
const expanded=expandInputs(branchRows,{'ci/release-evidence-worker.mjs':{args:[path.join(evidence,'ast prepared root'),entity,consumer],env:{}}});
fs.writeFileSync(path.join(evidence,'ast-expanded.json'),JSON.stringify(expanded,null,2)+'\n');

test('worker required arguments follow the mature AST expansion',()=>{
 assert.throws(()=>exportBranches('if true; then\n'),SyntaxError);
 assert.ok(branchRows.some(row=>row.kind==='condition'&&row.source.includes('/*')));
 const seen=new Set();for(const row of expanded.filter(r=>r.kind==='required'&&r.status==='READY')){
  const key=JSON.stringify(row.args);if(seen.has(key))continue;seen.add(key);
  if(row.outcome==='set')continue;
  pair(`required-${row.start}-${row.outcome}`,()=>row.args,1,r=>assert.match(r.stderr,/(private worker root required|jq-linux-amd64 entity required)/));
 }
 assert.equal(seen.size,5); // one valid argument list plus four missing/empty states
});
test('worker rejects each explicit forbidden root before copying',()=>{
 for(const [i,root]of ['relative','/','/tmp','/tmp/nested'].entries())pair(`root-${i}`,()=>[root,entity,consumer],2,r=>assert.match(r.stderr,/private worker root must be absolute and outside \/tmp/));
});
test('worker actual explicit consumer and independent core control',()=>{
 pair('explicit',root=>[root,'jq entity','--test-concurrency=1','consumer.mjs'],0,(r,root)=>{
  assert.match(r.stdout,/WORKER_CONSUMER_REACHED/);assert.match(r.stdout,/WORKER_CORE_CONTROL_REACHED/);
  assert.match(r.stdout,/# pass 2\n/);assert.match(r.stdout,/# fail 0\n/);
  assert.equal(fs.statSync(path.join(root,'bin/jq')).mode&0o777,0o755);
  assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(root,'bin/jq'))).digest('hex'),expected);
  const product=JSON.parse(fs.readFileSync(path.join(root,'release-evidence-tests/consumer.json'),'utf8'));
  assert.equal(product.cwd,caller);assert.deepEqual(JSON.parse(product.jq),{actual:true});
 });
});
test('worker default list executes the caller manifest and real Node consumer',()=>{
 pair('default',root=>[root,entity],0,r=>{assert.match(r.stdout,/# tests 2\n/);assert.match(r.stdout,/WORKER_CONSUMER_REACHED/);});
});
test('worker real checksum, filesystem and downstream failures propagate',()=>{
 pair('checksum',root=>[root,'wrong-jq',consumer],1,(r,root)=>assert.equal(fs.existsSync(root),false));
 pair('missing-entity',root=>[root,'missing entity',consumer],1,(r,root)=>assert.equal(fs.existsSync(root),false));
 pair('occupied-root',root=>{fs.writeFileSync(root,'occupied');return [root,entity,consumer];},1,r=>assert.match(r.stderr,/mkdir:/));
 pair('consumer-fail',root=>[root,entity,'reject.mjs'],1,r=>assert.match(r.stdout,/WORKER_TEST_FAILURE_PROPAGATED/));
 pair('bad-node-option',root=>[root,entity,'--definitely-invalid-worker-option'],9,r=>assert.match(r.stderr,/bad option:/));
});
