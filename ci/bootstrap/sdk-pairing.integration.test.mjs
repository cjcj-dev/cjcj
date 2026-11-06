#!/usr/bin/env zx
// Real completed components traverse the public install CLI. The wrong arm
// names older, existing execution inputs; the installed bytes and ordinary
// compiler consumers must still use the compiler producer's dependencies.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const request=JSON.parse(await fs.readFile(process.env.SDK_PAIRING_INPUTS,'utf8'));
const here=path.dirname(fileURLToPath(import.meta.url)),root=request.work;
await fs.mkdir(root,{recursive:true});
const source=await fs.readFile(request.inputs,'utf8');
const original=JSON.parse(source);
const producer=request.compiler;
const consumer=path.join(root,'assert-dependencies.mjs');
await fs.writeFile(consumer,`import assert from 'node:assert/strict';import fs from 'node:fs/promises';import path from 'node:path';
const [sdk,producer]=process.argv.slice(2);
for(const rel of ['runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so','lib/linux_x86_64_cjnative/libcangjie-std-core.a','third_party/llvm/lib/libLLVM-15.so']){
 const actual=await fs.readFile(path.join(sdk,'.compiler-exec',rel)),expected=await fs.readFile(path.join(producer,'.compiler-exec',rel));
 console.log('SDK_PAIRING_INSTALLED_BYTES_ASSERTION_REACHED '+rel);
 assert.ok(actual.equals(expected),'SDK_PAIRING_INSTALLED_PRODUCER_DEPENDENCY '+rel);
}
`);
const rows=[];
function invoke(name,descriptor){
 const file=path.join(root,name+'.json');
 return fs.writeFile(file,JSON.stringify(descriptor,null,2)).then(async()=>{
  const argv=['bash',path.join(here,'sdk_build.sh'),'--install-inputs',file];
  const result=spawnSync(argv[0],argv.slice(1),{encoding:'utf8',maxBuffer:32*1024*1024});
  await fs.writeFile(path.join(root,name+'.stdout'),result.stdout??'');
  await fs.writeFile(path.join(root,name+'.stderr'),result.stderr??'');
  rows.push({name,argv,rc:result.status,signal:result.signal,error:result.error?.message});
  await fs.writeFile(path.join(root,'results.json'),JSON.stringify(rows,null,2));
  return result;
 });
}
function descriptor(name,wrong){
 const input=structuredClone(original);
 input.work=path.join(root,name+'-work');input.install=path.join(root,name+'-sdk');
 input.selection.targetComponents.compiler={...input.selection.targetComponents.compiler,
  install:producer,product:path.join(producer,request.compilerProduct??'libexec/compiler/cjcj-stage1')};
 input.selection.compilerExecution.compiler={...input.selection.targetComponents.compiler};
 if(wrong)for(const name of ['runtime','std','llvm'])input.selection.compilerExecution[name]=request.old[name];
 else for(const name of ['runtime','std','llvm'])input.selection.compilerExecution[name]={install:producer+'/.compiler-exec',platform:'linux_x86_64'};
 input.test={commands:[{argv:[process.execPath,consumer,'${install}',producer]},
  {argv:[process.execPath,path.join(here,'compiler_identity.mjs'),'${install}']},
  {argv:[process.execPath,path.join(here,'sdk-hello.mjs'),'--sdk','${install}','--work','${work}/hello','--platform','linux_x86_64','--compiler-only',
   '--source',path.resolve(here,'../smoke/01_hello.cj'),'--expected','hello from cjcj']}]};
 if(!wrong&&request.archive!==false)input.archive=path.join(root,'matched-sdk.tar.gz');
 return input;
}
test('matched normal installation runs installed and fresh-unpack consumers',async()=>{
 const matched=await invoke('matched',descriptor('matched',false));
 assert.equal(matched.status,0,matched.stderr);
 console.log('SDK_PAIRING_MATCHED_INSTALL_USE_UNPACK_ASSERTION_REACHED');
});
test('normal installation cannot choose an existing old execution tuple for this compiler',async()=>{
 for(const [name,rel]of Object.entries({runtime:'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so',
  std:'lib/linux_x86_64_cjnative/libcangjie-std-core.a',llvm:'third_party/llvm/lib/libLLVM-15.so'})){
  assert.ok((await fs.stat(path.join(request.old[name].install,rel))).isFile());
  assert.ok(!(await fs.readFile(path.join(request.old[name].install,rel))).equals(await fs.readFile(path.join(producer,'.compiler-exec',rel))),name+' must actually differ');
 }
 console.log('SDK_PAIRING_WRONG_BUT_EXISTING_INPUT_ASSERTION_REACHED');
 const wrong=await invoke('wrong-existing',descriptor('wrong-existing',true));
 console.log('SDK_PAIRING_WRONG_EXISTING_RESULT_ASSERTION_REACHED '+JSON.stringify({rc:wrong.status,signal:wrong.signal}));
 assert.equal(wrong.status,0,wrong.stderr);
 assert.match(wrong.stdout,/SDK_PAIRING_INSTALLED_BYTES_ASSERTION_REACHED/);
 assert.match(wrong.stdout,/SDK_HELLO_TARGET_ASSERTION_REACHED/);
});
