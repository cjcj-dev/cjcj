#!/usr/bin/env zx
// Script-only CLI wiring: records are produced by sdk-build, installation uses
// real copy/link operations, and gates are explicit script consumers. This does
// not substitute these interfaces for a real bootstrap/native/ABI qualification.
import test from 'node:test';import assert from 'node:assert/strict';
import fs from 'node:fs/promises';import path from 'node:path';import os from 'node:os';
import {spawnSync} from 'node:child_process';import {fileURLToPath} from 'node:url';
import {createBootstrapTargets,FIXED_INPUTS} from './sdk-targets.mjs';
import {readHostToolchainPin} from '../host-toolchain-pin.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url));
const invoke=(entry,args,env={})=>{const r=spawnSync(process.execPath,[path.join(root,entry),...args],{env:{...process.env,...env},encoding:'utf8'});return {...r,text:r.stdout+'\n'+r.stderr};};
const temp=async()=>fs.mkdtemp(path.join(process.env.RELEASE_EVIDENCE_TEST_ROOT||os.tmpdir(),'c2-cli-'));
function input(work){
 const row=(name,commit)=>({repository:path.join(work,name),commit,tree:'a'.repeat(40),install:path.join(work,name),configuration:{fixture:true},buildResult:path.join(work,name+'.json')});
 const runtime=row('R',FIXED_INPUTS.runtime);
 return {work:path.join(work,'flow'),install:path.join(work,'final'),platform:'linux_x86_64',host:{version:readHostToolchainPin('linux_x86_64').replace(/^nightly-/,''),install:path.join(work,'H')},llvm:row('N',FIXED_INPUTS.llvm),ast:row('AST',FIXED_INPUTS.compiler),h1:row('H1',FIXED_INPUTS.h1),runtime,stdlib:runtime,compiler:row('C','c'.repeat(40)),tools:{privateRoot:path.join(work,'tools')}};
}
test('formal prepare CLI keeps default phases and explicit C2 expansion, rejecting a changed recipe',async()=>{
 const work=await temp(),inputs=input(work),file=path.join(work,'inputs.json'),workspace=path.join(work,'workspace');
 const run=()=>invoke('ci/bootstrap/prepare-bootstrap-plans.mjs',[],{CJCJ_SDK_INPUTS:file,CANGJIE_WORKSPACE:workspace,CJCJ_SDK_TARGETS:''});
 await fs.writeFile(file,JSON.stringify(inputs));let r=run();assert.equal(r.status,0,r.text);
 let plan=JSON.parse(await fs.readFile(path.join(workspace,'build-targets.json'),'utf8'));
 assert.ok(plan.stages.some(s=>s.id==='stage0'));
 inputs.runtimeCommit='d'.repeat(40);inputs.runtime={...inputs.runtime,commit:inputs.runtimeCommit};inputs.stdlib=inputs.runtime;
 inputs.stage2={install:path.join(work,'old-C2'),bootstrapStd:path.join(work,'std'),compilerInputs:path.join(work,'old-C2/compiler-inputs.json'),buildResult:path.join(work,'original-result.json'),compilerCommit:'b'.repeat(40),parentCommit:inputs.h1.commit,llvmCommit:inputs.llvm.commit,bootstrapRuntimeCommit:FIXED_INPUTS.runtime};
 await fs.writeFile(file,JSON.stringify(inputs));r=run();assert.equal(r.status,0,r.text);
 plan=JSON.parse(await fs.readFile(path.join(workspace,'build-targets.json'),'utf8'));
 assert.deepEqual(plan.stages.map(s=>s.id),['nativeN','nativeR','nativeAST','stage2','stage3-std','stage2-target-sdk','stage3']);
 assert.equal(plan.stages.find(s=>s.id==='stage2').metadata.compilerCommit,'b'.repeat(40));
 console.log('C2_FORMAL_EXPANSION_ASSERTION_REACHED');
 assert.ok(plan.stages.find(s=>s.id==='stage2').test.commands.some(c=>c.argv.some(a=>a.endsWith('/sdk-verify-install.mjs'))),'C2 imported installation must retain the real installed gate');
 plan.stages.find(s=>s.id==='stage2').test.commands=[];
 const altered=path.join(work,'altered.json');await fs.writeFile(altered,JSON.stringify(plan));
 r=invoke('ci/bootstrap/prepare-bootstrap-plans.mjs',[],{CJCJ_SDK_TARGETS:altered});
 assert.equal(r.status,1,r.text);assert.match(r.text,/BOOTSTRAP_TARGET_INPUT_MISMATCH/);
 inputs.runtimeCommit='HEAD';await fs.writeFile(file,JSON.stringify(inputs));r=run();assert.equal(r.status,1,r.text);assert.match(r.text,/TARGET_SOURCE runtime commit/);
});
test('real sdk-build CLI copies imported inputs and still calls gates on first install and resume',async()=>{
 const work=await temp(),source=path.join(work,'input'),flow=path.join(work,'flow'),install=path.join(work,'install');
 await fs.mkdir(source);await fs.writeFile(path.join(source,'value'),'original C2 input');
 const gate=path.join(work,'gate.mjs'),trace=path.join(work,'trace');
 await fs.writeFile(gate,`import fs from 'node:fs';fs.appendFileSync(process.argv[3],'gate\\n');if(fs.readFileSync(process.argv[2],'utf8')!=='original C2 input')process.exit(43);console.log('C2_INSTALLED_GATE_REACHED');`);
 const config={work:flow,install,repos:{},test:{required:['value']},finalStage:'consume',stages:[{id:'import',reuse:{source},output:path.join(work,'imported'),copies:[{from:path.join(source,'value'),to:'value'}],links:{alias:'value'},metadata:{compilerCommit:'b'.repeat(40)},test:{commands:[{argv:[process.execPath,gate,'${install}/alias',trace]}]}},{id:'consume',depends:['import'],output:install,copies:[{from:'${output.import}/value',to:'value'}]}]};
 const file=path.join(work,'targets.json');await fs.writeFile(file,JSON.stringify(config));
 const call=args=>invoke('ci/bootstrap/sdk-build.mjs',['--config',file,'--no-package',...args]);
 let r=call(['--from','consume']);assert.equal(r.status,1,r.text);assert.match(r.text,/WORK_INPUTS_MISSING/);
 r=call(['--through','import']);assert.equal(r.status,0,r.text);assert.match(r.text,/C2_INSTALLED_GATE_REACHED/);
 const first=await fs.readFile(path.join(flow,'build-result.json'),'utf8');await fs.writeFile(path.join(work,'first-result.json'),first);
 r=call(['--from','consume']);assert.equal(r.status,0,r.text);assert.match(r.text,/C2_INSTALLED_GATE_REACHED/);
 assert.equal(await fs.readFile(trace,'utf8'),'gate\ngate\n');
 config.stages[0].metadata.compilerCommit='e'.repeat(40);await fs.writeFile(file,JSON.stringify(config));
 r=call(['--from','consume']);assert.equal(r.status,1,r.text);assert.match(r.text,/WORK_INPUT_MISMATCH/);
 config.stages[0].metadata.compilerCommit='b'.repeat(40);await fs.writeFile(file,JSON.stringify(config));
 await fs.writeFile(path.join(work,'imported/value'),'changed');
 r=call(['--from','consume']);assert.equal(r.status,43,r.text);
 const failed=JSON.parse(await fs.readFile(path.join(flow,'build-result.json'),'utf8'));assert.equal(failed.status,'FAILED');assert.equal(failed.commands.at(-1).rc,43);
 console.log('C2_REUSE_GATE_REJECTION_ASSERTION_REACHED');
});
