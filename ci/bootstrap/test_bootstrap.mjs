#!/usr/bin/env zx
// ESM successor of the Bash bootstrap contract tests; inspect real CLI plans
// and real native object consumers. A plan is never reported as a product build.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import {prepareNativeTestInputs} from './native_test_inputs.mjs';
import {sha256File} from './sdk_verify.mjs';
const here=path.dirname(fileURLToPath(import.meta.url)),repo=path.resolve(here,'../..');
const product=process.env.BOOTSTRAP_PRODUCT || here+'/bootstrap.sh';
const sdkProduct=process.env.SDK_BUILD_PRODUCT || here+'/sdk_build.sh';
const {Bootstrap}=await import(pathToFileURL(product.replace(/\.sh$/,'.mjs')));
const out=fs.mkdtempSync(path.join(process.env.TMPDIR||os.tmpdir(),'bootstrap-contract-'));
let f;
const invoke=(entry,args,env={})=>{
  const result=spawnSync(entry.endsWith('.sh')?'bash':process.execPath,[entry,...args],{env:{...process.env,...env},encoding:'utf8',maxBuffer:16*1024*1024});
  assert.equal(result.error,undefined);assert.notEqual(result.status,null);return {...result,text:result.stdout+result.stderr};
};
const count=(text,regexp,n,label)=>{const found=text.split('\n').filter(line=>regexp.test(line)).length;assert.equal(found,n,`${label} count=${found} expected=${n}`);};
function dry(stage='all',extra=[],env={}) {return invoke(product,[...f.args,'--stage',stage,'--dry-run',...extra],env);}
function checkDry(result,stage='all') {
  assert.equal(result.status,0,result.text);assert.match(result.stdout,new RegExp(`BOOTSTRAP-OK 到 ${stage} `));assert.match(result.stdout,/DRY-RUN: no compilation performed/);
  if(stage!=='all')return;
  const text=result.stdout;
  count(text,/shape=planned Int64.ti>1 FFI-archives>0/,2,'A1');count(text,/FFI-set-equals=/,1,'A1-FFI');
  for (const phase of ['stage1','stage2']) count(text,new RegExp(`CMD env -i .*cjcj-${phase} --version`),1,'A2-'+phase);
  count(text,/ASSERT stage1-compiler executable=planned/,2,'A3');
  count(text,/ISOLATE cjcj-src from=/,2,'CJPM-isolation');count(text,/ASSERT compile-option-o1 planned/,1,'O1');
  count(text,/CMD cjpm build/,2,'CJPM');count(text,new RegExp(`CMD cjpm build -j ${process.env.CJ_JOBS||os.availableParallelism?.()||os.cpus().length} bin=`),1,'CJPM-JOBS');
  const expensive=text.split('\n').filter(line=>/^CMD env -i /.test(line)&&(/python3 build.py build/.test(line)||/tools\/bin\/cjpm build/.test(line)));
  assert.equal(expensive.length,4,'A4 exactly four expensive recipes');
  for (const line of expensive) {assert.match(line,/HOME=/);assert.match(line,/TMPDIR=/);assert.match(line,/CANGJIE_HOME=/);assert.match(line,/cjHeapSize=/);assert.match(line,new RegExp(`${f.native.loader}=`));}
  count(text,/BUILD-ENV planned HOME=/,4,'A4');
  count(text,/CMD shim build label=/,2,'SHIM');
  assert.match(text,/label=stage0 .*source-object=source .*sdk=.*sdk-stage0 .*runtime=.*host-rt/);
  assert.match(text,/label=stage1 .*source-object=.*sdk-stage1\/third_party\/llvm\/fixed-llc\/cjselfhost_llvmshim.o .*runtime=.*colour-rt/);
  count(text,/CJCJ_COMMIT=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/,2,'SHIM-commit');
  count(text,/CJCJ_LLVM_SHIM_O=/,1,'SHIM-source');count(text,/OUTPUT stage[01]-shim-cpp .*sha256=planned/,2,'SHIM-cpp');count(text,/OUTPUT stage[01]-shim-config .*sha256=planned/,2,'SHIM-config');
  count(text,/CMD node .*trimpath.mjs .*cjcj-src-stage[01]$/,2,'TRIMPATH');
  count(text,/ASSERT installed-host-llvm-so sha256=planned/,1,'LLVM-SO');count(text,/ASSERT installed-colour-tuple sha256=planned/,30,'LLVM-TUPLE');
  count(text,/ASSERT host-llvm-zero .*hits=0/,2,'LLVM-RULER');count(text,/ASSERT official-opt-zero .*hits=0/,1,'LLVM-OFFICIAL');count(text,/ASSERT colour-opt-stamp .*hits=1/,2,'LLVM-STAMP');
  count(text,/--verify-host-rt /,2,'HOST-RT');count(text,/stage1_host_runner.sh .*sdk-stage1 .*sdk-stage0 .*host-rt/,2,'HOST-RUNNER');
  assert.match(text,/sdk_build.sh .*--to .*sdk-std-bootstrap --host --llvm-tuple/);assert.match(text,/std_runtime_colour.mjs --colour-runtime .* --std .*stdlib-stage1/);
  const firstStd=text.indexOf('ASSERT stdlib-stage1 shape=planned'),secondStd=text.indexOf('ASSERT stdlib-stage2 shape=planned');
  const firstAssembly=text.indexOf('--std '+f.out+'/stdlib-stage1'),secondAssembly=text.indexOf('--std '+f.out+'/stdlib-stage2');
  assert.ok(firstStd>=0&&firstAssembly>firstStd&&secondStd>firstAssembly&&secondAssembly>secondStd,'STD precedes its consuming compiler assembly');
  assert.doesNotMatch(text,/cjcj-stage2-forensic|target\/debug\/bin|cjpm build -j .* -g/);
  console.log('PASS bootstrap dry contracts A1 A2 A3 A4 CJPM SHIM LLVM STD-order');
}
function shape(prefix=f.base,compare=prefix) {const b=new Bootstrap([]);b.STAGE='test-A1';b.host_tuple_init();b.assertStdShape(prefix,compare,'stdlib-stage2');}
function expectFailure(body,pattern) {let error;try{body();}catch(e){error=e;}assert.ok(error,'product guard must fail');if(pattern)assert.match(error.message,pattern);console.log('PASS precise-red '+pattern);}
async function mode(name,args=[]) {
  if(name==='dry-run'){const result=dry(args[0]||'all');process.stdout.write(result.text);process.exitCode=result.status;return;}
  if(['check-dry-contract','check-dry-build-env','check-shim-wiring','check-build-env','positive-build-env'].includes(name)){
    checkDry(dry());
    if(name==='check-dry-build-env') for(const stage of ['stage1-initial-std','stage1-std','stage1-compiler']) {const result=dry(stage);checkDry(result,stage);const lines=result.stdout.split('\n').filter(line=>/^CMD env -i /.test(line)&&(/python3 build.py build/.test(line)||/tools\/bin\/cjpm build/.test(line)));assert.equal(lines.length,1);assert.match(lines[0],stage==='stage1-initial-std'?/stdlib-stage1/:stage==='stage1-std'?/stdlib-stage2/:/cjcj-src-stage1/);}
    return;
  }
  if(name==='check-forensic-dry'){
    const result=dry('all',[],{CJCJ_FORENSIC_STAGE2:'1'});assert.equal(result.status,0,result.text);count(result.stdout,/CMD cjpm build -j .* -g bin=/,1,'FORENSIC');count(result.stdout,/target\/debug\/bin/,2,'FORENSIC-product');assert.match(result.stdout,/INPUT cjcj-stage2-forensic-src path=.*cjpm.toml sha256=planned/);return;
  }
  if(name==='ruler-control'){const b=new Bootstrap([]);b.host_tuple_init();b.assertOfficialOpt(args[0]);b.assertColourTuple(args[1],args[2]);return;}
  if(name==='positive-a1'){shape();return;}
  if(name.startsWith('fault-a1')){
    const suffix=name.slice('fault-a1'.length);
    const target=suffix==='-missing-core-archive'?`${f.base}/lib/${f.native.tuple}/libcangjie-std-core.a`:suffix==='-missing-core-shared'?`${f.base}/runtime/lib/${f.native.tuple}/libcangjie-std-core${f.native.librarySuffix}`:suffix==='-missing-ffi-shared'?`${f.base}/lib/libstdFFI${f.native.librarySuffix}`:'';
    if(target)fs.rmSync(target);else fs.copyFileSync(f.host,`${f.base}/runtime/lib/${f.native.tuple}/libcangjie-std-core${f.native.librarySuffix}`);
    shape();return;
  }
  if(name==='fault-a2'){const b=new Bootstrap([]);b.host_tuple_init();await b.assertVersion('cjcj-stage2','/usr/bin/false',f.base,f.out+'/host-rt');return;}
  if(name==='fault-a3'){const b=new Bootstrap([]);b.assertExecutable('stage1-compiler',f.out+'/missing-cjc');return;}
  if(['positive-compile-option-o1','fault-compile-option'].includes(name)){
    const toml=f.out+'/src/cjpm.toml';fs.writeFileSync(toml,name.startsWith('positive')?'compile-option = "-O1"\n':'compile-option = "-O0"\n');const b=new Bootstrap([]);b.STAGE='test-O1';b.rewriteO1(toml);assert.match(fs.readFileSync(toml,'utf8'),/"-O1"/);return;
  }
  if(name==='fault-product-missing'){const b=new Bootstrap([]);b.STAGE='test-product';b.product(f.out+'/missing','cjcj-stage1');return;}
  if(name==='fault-cjpm-toml')fs.rmSync(f.out+'/src/cjpm.toml');
  else if(name==='fault-src-file'){f.args[f.args.indexOf('--src')+1]=f.out+'/src/main.cj';}
  else if(name==='fault-host-sha')f.args[f.args.indexOf('--host-llvm-sha256')+1]='0'.repeat(64);
  else if(name==='fault-ast-sha')f.args[f.args.indexOf('--ast-support-sha256')+1]='0'.repeat(64);
  else if(name==='fault-ast-bytes')fs.appendFileSync(f.ast,'changed');
  else if(name==='fault-colour-ruler'){fs.copyFileSync(f.officialTool,f.tuple+'/bin/opt');f.sums();}
  else if(name==='fault-colour-stamp-duplicate'){fs.appendFileSync(f.tuple+'/bin/opt','CJLLVM-COMMIT:'+f.llvmSha);f.sums();}
  else if(name==='fault-colour-stamp-mismatch'){const p=f.tuple+'/bin/opt';fs.writeFileSync(p,fs.readFileSync(p).toString('latin1').replace('CJLLVM-COMMIT:'+f.llvmSha,'CJLLVM-COMMIT:'+'2'.repeat(40)),'latin1');f.sums();}
  else if(name==='fault-colour-sha')f.args[f.args.indexOf('--colour-llvm-sha')+1]='2'.repeat(40);
  else if(name==='fault-tuple-missing-opt')fs.rmSync(f.tuple+'/bin/opt');
  else if(name==='fault-tuple-sums')fs.appendFileSync(f.tuple+'/bin/llc','changed');
  else if(name==='fault-tuple-extra-entry')fs.appendFileSync(f.tuple+'/SHA256SUMS','0'.repeat(64)+'  ./EXTRA\n');
  else if(name==='fault-old-host-llvm'||name==='fault-old-colour-llc'){const result=invoke(product,[name==='fault-old-host-llvm'?'--host-llvm':'--colour-llc','obsolete']);process.stdout.write(result.text);process.exitCode=result.status;return;}
  else if(name==='test'){
    checkDry(dry());shape();
    const toml=f.out+'/src/cjpm.toml',b=new Bootstrap([]);b.rewriteO1(toml);b.rewriteO1(toml);assert.match(fs.readFileSync(toml,'utf8'),/"-O1"/);
    for(const [kind,pattern] of [['fault-host-sha',/host-llvm sha256 不匹配/],['fault-ast-sha',/ast-support sha256 不匹配/],['fault-colour-ruler',/章计数不是 1/],['fault-colour-stamp-duplicate',/章计数不是 1/],['fault-colour-stamp-mismatch',/章与 MANIFEST/],['fault-colour-sha',/MANIFEST LLVM_SHA/],['fault-tuple-missing-opt',/缺或未登记 bin\/opt/],['fault-tuple-sums',/SHA256SUMS strict/],['fault-tuple-extra-entry',/10 个 payload/],['fault-cjpm-toml',/--src 缺少 cjpm.toml/],['fault-src-file',/--src 缺少 cjpm.toml/],['fault-compile-option',/compile-option 不是 -O1/],['fault-product-missing',/产物缺失/]]){
      const result=invoke(here+'/test_bootstrap.mjs',[kind]);assert.equal(result.status,1,result.text);assert.match(result.text,pattern);console.log('PASS precise-red '+kind);
    }
    for(const entry of ['test_stage0_cache.mjs','test_sdk_verify.py','test_sdk_symlinks.py','test_sdk_runtime.py','test_sdk_shared_pair.py','test_sdk_std.py','test_sdk_exe_symlink.py','test_sdk_cjc_swap.py']){
      const executor=entry.endsWith('.py')?'python3':process.execPath;
      const result=spawnSync(executor,[here+'/'+entry],{encoding:'utf8',env:process.env,maxBuffer:16*1024*1024});assert.equal(result.status,0,result.stdout+result.stderr);process.stdout.write(result.stdout);
    }
    console.log('PASS bootstrap native plan and SDK rejection controls');return;
  } else if(!name.startsWith('fault-'))throw new Error('unknown bootstrap contract mode: '+name);
  else throw new Error('unmigrated legacy fault mode: '+name);
  const result=dry();process.stdout.write(result.text);process.exitCode=result.status;
}
try {f=prepareNativeTestInputs(out,repo);await mode(process.argv[2]||'test',process.argv.slice(3));}
catch(error){console.error(error.message);process.exitCode=1;}
finally{fs.rmSync(out,{recursive:true,force:true});}
