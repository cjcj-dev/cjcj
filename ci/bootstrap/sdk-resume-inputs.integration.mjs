#!/usr/bin/env zx
// Finite script-target test through sdk-build's real CLI. The prerequisite
// records are produced by that CLI, never handwritten. This is not N/R native
// ABI/LLDB validation or a complete bootstrap configuration qualification.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const parent = process.env.SDK_RESUME_TEST_ROOT
  || (process.env.RELEASE_EVIDENCE_TEST_ROOT && path.join(process.env.RELEASE_EVIDENCE_TEST_ROOT, 'sdk-resume'));
assert.ok(parent, 'SDK_RESUME_TEST_ROOT must be a private owned directory');
fs.mkdirSync(parent, {recursive:true});
const cli = fileURLToPath(new URL('./sdk-build.mjs', import.meta.url));
const write = (file, value) => {fs.mkdirSync(path.dirname(file), {recursive:true}); fs.writeFileSync(file, value);};
const checker = path.join(parent, 'check-input.mjs');
write(checker, `#!/usr/bin/env zx
import fs from 'node:fs';
const [file,name,trace]=process.argv.slice(2);
const value=fs.readFileSync(file,'utf8');
console.log('RESUMED_INPUT_CHECK_REACHED',name,value);
fs.appendFileSync(trace,name+'\\n');
if(value!=='${'fixed-input'}')process.exit(31);
`);
const producer = path.join(parent, 'produce-input.mjs');
write(producer, `#!/usr/bin/env zx
import fs from 'node:fs';import path from 'node:path';
fs.mkdirSync(process.argv[2],{recursive:true});
fs.writeFileSync(path.join(process.argv[2],'value'),'fixed-input');
`);
const consume = path.join(parent, 'consume.mjs');
write(consume, `#!/usr/bin/env zx
import fs from 'node:fs';import path from 'node:path';
fs.mkdirSync(process.argv[2],{recursive:true});
fs.writeFileSync(path.join(process.argv[2],'consumed'),'consumer ran');
console.log('RESUME_CONSUMER_REACHED');
`);
let sequence = 0;
function call(configFile, args) {
  const argv=[cli,'--config',configFile,'--no-package',...args];
  const p=spawnSync(process.execPath,argv,{encoding:'utf8',maxBuffer:4*1024*1024});
  write(path.join(parent,`${++sequence}.json`),JSON.stringify({argv,status:p.status,signal:p.signal,error:p.error?.message,stdout:p.stdout,stderr:p.stderr},null,2));
  console.log('RESUME_CLI_RESULT',sequence,p.status,p.signal);
  return {...p,text:p.stdout+'\n'+p.stderr};
}
function fixture(name) {
  const work=path.join(parent,name),install=path.join(work,'install'),trace=path.join(work,'checks.log');
  const stages=['nativeN','nativeR'].map((id,index)=>({id,depends:index?['nativeN']:[],
    commands:[{argv:[process.execPath,producer,'${output}']}],
    test:{required:['value'],commands:[{argv:[process.execPath,checker,'${install}/value',id,trace]}]}}));
  stages.push({id:'consumer',depends:['nativeR'],output:install,commands:[{argv:[process.execPath,consume,'${output}']}]});
  const config={work,install,repos:{},stages,finalStage:'consumer',test:{required:['consumed']}};
  const file=path.join(parent,name+'.json');write(file,JSON.stringify(config));
  return {config,file,work,install,trace};
}
function cold(f) {
  const p=call(f.file,['--through','nativeR']);assert.equal(p.status,0,p.text);
  const result=JSON.parse(fs.readFileSync(path.join(f.work,'build-result.json'),'utf8'));
  assert.equal(result.status,'COMPLETE');assert.deepEqual(result.stages.map(s=>s.id),['nativeN','nativeR']);
  assert.equal(result.commands.length,4);assert.ok(result.commands.every(c=>c.rc===0));
  // Preserve the original evidence; never load this copy as a fabricated prior.
  const first=path.join(f.work,'first-production-result.json');
  if(!fs.existsSync(first))write(first,JSON.stringify(result,null,2));
}
const normal=fixture('normal');cold(normal);
const resumed=call(normal.file,['--from','consumer']);
console.log('RESUME_RECHECK_ASSERTION_REACHED');
assert.equal(resumed.status,0,resumed.text);
assert.match(resumed.text,/RESUMED_INPUT_CHECK_REACHED nativeN/);
assert.match(resumed.text,/RESUMED_INPUT_CHECK_REACHED nativeR/);
assert.equal(fs.readFileSync(normal.trace,'utf8'),'nativeN\nnativeR\nnativeN\nnativeR\n');
assert.match(resumed.text,/RESUME_CONSUMER_REACHED/);
for(const id of ['nativeN','nativeR']) {
  const f=fixture('changed-'+id);cold(f);
  write(path.join(f.work,'targets',id,'value'),'changed-installation');
  const failed=call(f.file,['--from','consumer']);
  console.log('RESUME_CHANGED_INPUT_ASSERTION_REACHED',id);
  assert.equal(failed.status,31,failed.text);
  assert.match(failed.text,new RegExp('RESUMED_INPUT_CHECK_REACHED '+id+' changed-installation'));
  assert.equal(fs.existsSync(path.join(f.install,'consumed')),false);
  const result=JSON.parse(fs.readFileSync(path.join(f.work,'build-result.json'),'utf8'));
  assert.equal(result.status,'FAILED');assert.equal(result.commands.at(-1).rc,31);
  // Re-produce the finite prerequisites via the real CLI after restoring their
  // inputs; do not restore or manufacture a previous build-result file.
  cold(f);const restored=call(f.file,['--from','consumer']);assert.equal(restored.status,0,restored.text);
}
const absent=fixture('no-prior');
const noPrior=call(absent.file,['--from','consumer']);
assert.equal(noPrior.status,1,noPrior.text);assert.match(noPrior.text,/WORK_INPUTS_MISSING/);
const alias=fixture('alias');cold(alias);
const output=path.join(alias.work,'targets/nativeN'),moved=path.join(alias.work,'original-nativeN');
fs.renameSync(output,moved);fs.symlinkSync(moved,output);
const linked=call(alias.file,['--from','consumer']);
assert.equal(linked.status,1,linked.text);assert.match(linked.text,/INSTALL_LINK/);
assert.equal(fs.existsSync(path.join(alias.install,'consumed')),false);
console.log('FINITE_RESUME_CLI_PASS');
