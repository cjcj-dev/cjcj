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
import {execute} from './host_tools.mjs';
import {tuplePayloads} from './native_libraries.mjs';
const here=path.dirname(fileURLToPath(import.meta.url)),repo=path.resolve(here,'../..');
const product=process.env.BOOTSTRAP_PRODUCT || here+'/bootstrap.sh';
const sdkProduct=process.env.SDK_BUILD_PRODUCT || here+'/sdk_build.sh';
const {Bootstrap}=await import(pathToFileURL(product.replace(/\.sh$/,'.mjs')));
const out=fs.mkdtempSync(path.join(process.env.TMPDIR||os.tmpdir(),'bootstrap-contract-'));
let f;
let invocation=0;
const invoke=(entry,args,env={})=>{
  const result=spawnSync(entry.endsWith('.sh')?'bash':process.execPath,[entry,...args],{env:{...process.env,...env},encoding:'utf8',maxBuffer:16*1024*1024});
  if(process.env.BOOTSTRAP_TEST_EVIDENCE) {
    const evidence=path.resolve(process.env.BOOTSTRAP_TEST_EVIDENCE);fs.mkdirSync(evidence,{recursive:true});const label=String(++invocation).padStart(3,'0');
    fs.writeFileSync(evidence+'/'+label+'.log',(result.stdout||'')+(result.stderr||''));
    fs.writeFileSync(evidence+'/'+label+'.json',JSON.stringify({entry,args,rc:result.status,error:result.error?.message||null},null,2)+'\n');
  }
  assert.equal(result.error,undefined);assert.notEqual(result.status,null);return {...result,text:result.stdout+result.stderr};
};
const count=(text,regexp,n,label)=>{const found=text.split('\n').filter(line=>regexp.test(line)).length;assert.equal(found,n,`${label} count=${found} expected=${n}`);};
function dry(stage='all',extra=[],env={}) {return invoke(product,[...f.args,'--stage',stage,'--dry-run',...extra],env);}
function checkDry(result,stage='all') {
  assert.equal(result.status,0,result.text);assert.match(result.stdout,new RegExp(`BOOTSTRAP-OK 到 ${stage} `));assert.match(result.stdout,/DRY-RUN: no compilation performed/);
  if(stage!=='all')return;
  const text=result.stdout;
  count(text,/tools\/bin\/cjpm/,4,'CJPM-tool');
  count(text,/CMD cjpm build bin=/,1,'CJPM-stage0');
  count(text,/compile-option = "-O1"/,1,'O1-rewrite');
  count(text,/shape=planned Int64.ti>1 FFI-archives>0/,2,'A1');count(text,/FFI-set-equals=/,1,'A1-FFI');
  for (const phase of ['stage1','stage2']) count(text,new RegExp(`CMD env -i .*cjcj-${phase} --version`),1,'A2-'+phase);
  count(text,/ASSERT stage1-compiler executable=planned/,2,'A3');
  count(text,/ISOLATE cjcj-src from=/,2,'CJPM-isolation');count(text,/ASSERT compile-option-o1 planned/,1,'O1');
  count(text,/CMD cjpm build/,2,'CJPM');count(text,new RegExp(`CMD cjpm build -j ${process.env.CJ_JOBS||os.availableParallelism?.()||os.cpus().length} bin=`),1,'CJPM-JOBS');
  const expensive=text.split('\n').filter(line=>/^CMD env -i /.test(line)&&(/python3 build.py build/.test(line)||/tools\/bin\/cjpm build/.test(line)));
  assert.equal(expensive.length,4,'A4 exactly four expensive recipes');
  for (const line of expensive) {assert.match(line,/HOME=/);assert.match(line,/TMPDIR=/);assert.match(line,/CANGJIE_HOME=/);assert.match(line,/cjHeapSize=/);assert.match(line,new RegExp(`${f.native.loader}=`));}
  const jobs=process.env.CJ_JOBS||String(os.availableParallelism?.()||os.cpus().length);
  const compilerCommands=expensive.filter(line=>line.includes('/tools/bin/cjpm build'));
  assert.equal(compilerCommands.length,2,'two actual compiler execution commands');
  assert.ok(compilerCommands.some(line=>line.includes('/tools/bin/cjpm build -j '+jobs+' ')),'stage1 execution receives configured jobs');
  const resources=Object.fromEntries(execute('bash',[f.out+'/src/ci/build_resources.sh',process.env.STAGE1_HEAP||'20GB']).stdout.trim().split('\n').map(line=>line.split('=')));
  assert.ok(compilerCommands.some(line=>line.includes('cjHeapSize='+resources.STD_BUILD_HEAP+' ')&&line.includes('/tools/bin/cjpm build -j '+jobs+' ')),'stage1 execution receives configured heap');
  for (const line of expensive) {
    const quote=value=>/^[\w/@+=:.,-]+$/.test(value)?value:"'"+value.replaceAll("'","'\\''")+"'";
    assert.ok(line.includes('HOME='+quote(process.env.HOME||'/root')+' '),'isolated command preserves caller/default HOME');
    assert.ok(line.includes('TMPDIR='+quote(process.env.TMPDIR||f.out+'/work/tmp-private')+' '),'isolated command preserves caller/default TMPDIR');
  }
  count(text,/BUILD-ENV planned HOME=/,4,'A4');
  count(text,/CMD rm -rf .*stdsrc\/build\/build/,2,'STD-clean');
  count(text,/python3 build.py build .*--target-lib=/,2,'STD-target-lib');
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
  const firstAssembly=text.indexOf('--std '+f.out+'/work/stdlib-stage1'),secondAssembly=text.indexOf('--std '+f.out+'/work/stdlib-stage2');
  assert.ok(firstStd>=0&&firstAssembly>firstStd&&secondStd>firstAssembly&&secondAssembly>secondStd,'STD precedes its consuming compiler assembly');
  const order=text.split('\n').flatMap(line=>{
    if (/^\[stage[01]\]/.test(line))return [line.startsWith('[stage0]')?'stage0':'stage1'];
    if (/^ASSERT stdlib-stage1 shape=planned/.test(line))return ['initial-std-built'];
    if (/^CMD rm -rf -- .*\/sdk-std-bootstrap$/.test(line))return ['bootstrap-sdk-removed'];
    if (/^CMD rm -rf -- .*\/std-runtime-link$/.test(line))return ['runtime-link-cleared'];
    if (/^CMD .*sdk_build\.sh .*--to .*\/sdk-stage1 --target /.test(line))return [line.includes('--std '+f.out+'/work/stdlib-stage1 ')?'assemble-old':line.includes('--std '+f.out+'/work/stdlib-stage2 ')?'assemble-new':'assemble-unexpected'];
    if (/^ASSERT stage1-compiler executable=planned/.test(line))return ['executable'];
    if (/^ASSERT stdlib-stage2 shape=planned/.test(line))return ['stdlib-built'];
    return [];
  });
  assert.deepEqual(order,['stage0','stage1','runtime-link-cleared','initial-std-built','bootstrap-sdk-removed','runtime-link-cleared','assemble-old','executable','stdlib-built','assemble-new','executable'],'stage1 SDK assembly sequence');
  assert.doesNotMatch(text,/cjcj-stage2-forensic|target\/debug\/bin|cjpm build -j .* -g/);
  console.log('PASS bootstrap dry contracts A1 A2 A3 A4 CJPM SHIM LLVM STD-order');
}
function shape(prefix=f.base,compare=prefix) {const b=new Bootstrap([]);b.STAGE='test-A1';b.host_tuple_init();b.assertStdShape(prefix,compare,'stdlib-stage2');}
function expectFailure(body,pattern) {let error;try{body();}catch(e){error=e;}assert.ok(error,'product guard must fail');if(pattern)assert.match(error.message,pattern);console.log('PASS precise-red '+pattern);}
// Mutate a real carrier in a private source copy. Imports and all other product
// files are copied intact; the same CLI and assertions consume its output.
function cutProduct(relative,transform) {
  const carrier=path.join(here,relative),dest=out+'/product';
  if(!fs.existsSync(dest))for(const dir of ['ci','build'])fs.cpSync(repo+'/'+dir,dest+'/'+dir,{recursive:true});
  const original=fs.readFileSync(carrier,'utf8'),changed=transform(original);
  assert.notEqual(changed,original,'cut must alter its real carrier');
  fs.writeFileSync(dest+'/ci/bootstrap/'+relative,changed);
  return dest+'/ci/bootstrap/'+relative;
}
function sdk(args,extra=[]) {return invoke(sdkProduct,['--from',f.base,'--to',out+'/sdk-test',...args,'--colour-runtime',f.colour,'--host-runtime',f.host,...extra]);}
function checkSdk(args,extra=[]) {const result=sdk(args,extra);assert.equal(result.status,0,result.text);assert.match(result.stdout,/SDK-BUILD-OK/);return out+'/sdk-test';}
function prepareStdBuild() {
  const program=`import os, pathlib, shutil, sys\nexpected_sdk = ${JSON.stringify(f.base)}\nif os.environ.get('LEAK_ME'): raise SystemExit(44)\nif os.environ.get('CANGJIE_HOME') != expected_sdk: raise SystemExit(45)\nif len(sys.argv)>1 and sys.argv[1]=='build':\n    target = next((x.split('=',1)[1] for x in sys.argv if x.startswith('--target-lib=')), '')\n    if target != expected_sdk+'/runtime/lib/${f.native.tuple}': raise SystemExit(46)\nif len(sys.argv)>1 and sys.argv[1]=='install':\n    prefix=pathlib.Path(sys.argv[sys.argv.index('--prefix')+1])\n    for rel in ['lib/${f.native.tuple}/libcangjie-std-core.a','runtime/lib/${f.native.tuple}/libcangjie-std-core${f.native.librarySuffix}','lib/${f.native.tuple}/libfixtureFFI.a','lib/libstdFFI${f.native.librarySuffix}']:\n        dest=prefix/rel; dest.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(pathlib.Path(expected_sdk)/rel,dest)\n`;
  fs.writeFileSync(f.out+'/stdsrc/build.py',program);
  // Real native files replace the old fake nm executable.
  fs.mkdirSync(f.base+'/third_party/flatbuffers/bin',{recursive:true});
  fs.copyFileSync(f.officialTool,f.base+'/third_party/flatbuffers/bin/flatc');
  fs.copyFileSync(f.ast,f.base+'/libcangjie-ast-support.a');
  for(const dir of ['include','schema']) {fs.mkdirSync(f.base+'/'+dir);fs.writeFileSync(f.base+'/'+dir+'/fixture','fixture');}
  fs.writeFileSync(f.base+'/SHA256SUMS',['libcangjie-ast-support.a','third_party/flatbuffers/bin/flatc'].map(rel=>sha256File(f.base+'/'+rel)+'  '+rel+'\n').join(''));
  return Object.assign(new Bootstrap([]),{STAGE:'test-A4',WORK:f.out+'/work',SRC:f.out+'/src',STDSRC:f.out+'/stdsrc',AST_SUPPORT:f.base+'/libcangjie-ast-support.a'});
}
function checkForensic(result) {
  assert.equal(result.status,0,result.text);const text=result.stdout,jobs=process.env.CJ_JOBS||String(os.availableParallelism?.()||os.cpus().length);
  const assertions=[['forensic-output',1,/OUTPUT cjcj-stage2-forensic=/],['forensic-g',1,new RegExp('CMD cjpm build -j '+jobs+' -g bin=')],['forensic-debug-trimpath',1,/CMD node .*trimpath.mjs .*cjcj-src-stage1-forensic --debug$/],['release-stage0-trimpath',1,/CMD node .*trimpath.mjs .*cjcj-src-stage0$/],['release-stage1-trimpath',1,/CMD node .*trimpath.mjs .*cjcj-src-stage1$/],['forensic-isolation',1,/ISOLATE cjcj-src from=.* dest=.*cjcj-src-stage1-forensic /],['forensic-debug',2,/target\/debug\/bin/],['forensic-pickup',1,/product=planned dir=.*cjcj-src-stage1-forensic\/target\/debug\/bin/],['forensic-stamp',1,/INPUT cjcj-stage2-forensic path=.* sha256=planned/],['forensic-source-stamp',1,/INPUT cjcj-stage2-forensic-src path=.*cjpm.toml sha256=planned/],['release-pickup',1,/product=planned dir=.*cjcj-src-stage1\/target\/release\/bin/],['release-command',1,new RegExp('CMD cjpm build -j '+jobs+' bin=.* cwd=.*cjcj-src-stage1 heap=')]];
  let failed=0;for(const [label,n,pattern] of assertions){try{count(text,pattern,n,label);console.log('PASS '+label);}catch(error){failed++;console.error(error.message);}}
  console.log('ASSERTIONS total=12 failed='+failed);assert.equal(failed,0,'forensic and release assertions all executed');
}
async function mode(name,args=[]) {
  if(name==='check-exit-receipts') {
    for(const script of args.length?args:['run.sh','exceptions/run.sh','library/run.sh','library/execute.sh','unload/run.sh']) {
      const receipts=out+'/receipts/'+script;fs.mkdirSync(receipts,{recursive:true});
      const result=invoke(repo+'/test/heap_string_literals/'+script,[],{LITERAL_OUT:receipts,CANGJIE_HOME:out+'/missing-sdk',LITERAL_HOST:out+'/missing-host',LITERAL_RUNTIME:out+'/missing-runtime',LITERAL_RUNTIME_HEADERS:out+'/missing-headers',LITERAL_ARTIFACTS:out+'/missing-artifacts',LITERAL_CORES:'0'});
      assert.notEqual(result.status,0,'missing inputs must fail');assert.equal(fs.readFileSync(receipts+'/run.rc','utf8').trim(),String(result.status));assert.match(fs.readFileSync(receipts+'/wall.txt','utf8'),/^wall=[0-9]+\n?$/);assert.ok(fs.statSync(receipts+'/uptime-after.txt').size>0);console.log('PASS EXIT-RECEIPT '+script);
    }return;
  }
  if(name==='check-tuple-with-so') {
    const target=checkSdk(['--host','--llvm-tuple',f.tuple,'--llvm-so',f.colourLlvm]);
    assert.deepEqual(fs.readFileSync(target+'/third_party/llvm/'+f.native.library.replace(/^/,'lib/')),fs.readFileSync(f.colourLlvm));
    for(const rel of tuplePayloads(f.native))assert.deepEqual(fs.readFileSync(target+'/third_party/llvm/'+rel),fs.readFileSync(f.tuple+'/'+rel));return;
  }
  if(name==='check-sdk-literal-prefix') {
    const prefix=out+'/std [literal]';fs.cpSync(f.base,prefix,{recursive:true});
    const target=checkSdk(['--host','--std',prefix]);
    for(const rel of ['lib/'+f.native.tuple+'/libcangjie-std-core.a','runtime/lib/'+f.native.tuple+'/libcangjie-std-core'+f.native.librarySuffix,'lib/libstdFFI'+f.native.librarySuffix,'modules/'+f.native.tuple+'/std.core.cjo'])assert.deepEqual(fs.readFileSync(target+'/'+rel),fs.readFileSync(prefix+'/'+rel));return;
  }
  if(['positive-a4','positive-build-env','check-build-env','check-std-compiler-identity','fault-a4'].includes(name)) {
    let b=prepareStdBuild();
    process.env.LEAK_ME='must-not-cross';
    if(name==='fault-a4') {
      const entry=cutProduct('bootstrap.mjs',s=>s.replace('return {...compilerCacheEnvironment(),HOME:', 'return {...process.env,...compilerCacheEnvironment(),HOME:'));
      const {Bootstrap:CutBootstrap}=await import(pathToFileURL(entry));b=Object.assign(new CutBootstrap([]),b);
    }
    b.host_tuple_init();
    for(const layout of name==='check-std-compiler-identity'?['direct','runner']:['direct']) {
      if(layout==='runner') {fs.copyFileSync(f.officialTool,f.base+'/bin/cjcj-stage1');fs.writeFileSync(f.base+'/bin/cjc','#!/usr/bin/env node\nprocess.exit(0);\n');fs.chmodSync(f.base+'/bin/cjc',0o755);}
      await b.stdlibBuild('stdlib-stage1',f.base,f.out+'/host-rt',out+'/installed-std');
      const producer=JSON.parse(fs.readFileSync(out+'/installed-std/std-producer.json')).compiler_sha256;
      assert.equal(producer,sha256File(f.officialTool),'real compiler identity, independent of wrapper bytes');
      console.log('PASS STD_CJC '+layout);
    }return;
  }
  if(name==='dry-run'){const result=dry(args[0]||'all');process.stdout.write(result.text);process.exitCode=result.status;return;}
  if(['check-dry-contract','check-dry-build-env','check-shim-wiring'].includes(name)){
    checkDry(dry());
    if(name==='check-dry-build-env') for(const stage of ['stage1-initial-std','stage1-std','stage1-compiler']) {const result=dry(stage);checkDry(result,stage);const lines=result.stdout.split('\n').filter(line=>/^CMD env -i /.test(line)&&(/python3 build.py build/.test(line)||/tools\/bin\/cjpm build/.test(line)));assert.equal(lines.length,1);assert.match(lines[0],stage==='stage1-initial-std'?/stdlib-stage1/:stage==='stage1-std'?/stdlib-stage2/:/cjcj-src-stage1/);}
    return;
  }
  if(name==='check-forensic-dry'){
    checkForensic(dry('all',[],{CJCJ_FORENSIC_STAGE2:'1'}));return;
  }
  if(name==='ruler-control'){const b=new Bootstrap([]);b.host_tuple_init();b.assertOfficialOpt(args[0]);b.assertColourTuple(args[1],args[2]);return;}
  if(name==='positive-a1'){shape();return;}
  if(name.startsWith('fault-a1')){
    const suffix=name.slice('fault-a1'.length);
    const target=suffix==='-missing-core-archive'?`${f.base}/lib/${f.native.tuple}/libcangjie-std-core.a`:suffix==='-missing-core-shared'?`${f.base}/runtime/lib/${f.native.tuple}/libcangjie-std-core${f.native.librarySuffix}`:suffix==='-missing-ffi-shared'?`${f.base}/lib/libstdFFI${f.native.librarySuffix}`:'';
    if(target)fs.rmSync(target);else fs.copyFileSync(f.host,`${f.base}/runtime/lib/${f.native.tuple}/libcangjie-std-core${f.native.librarySuffix}`);
    shape();return;
  }
  if(name==='fault-a2'){const p=out+'/exit23.c';fs.writeFileSync(p,'int main(void){return 23;}');execute('cc',[p,'-o',out+'/exit23']);const b=new Bootstrap([]);b.STAGE='test-A2';b.host_tuple_init();await b.assertVersion('cjcj-stage2',out+'/exit23',f.base,f.out+'/host-rt');return;}
  if(name==='fault-a3'){const b=new Bootstrap([]);b.assertExecutable('stage1-compiler',f.out+'/missing-cjc');return;}
  if(['positive-compile-option-o1','fault-compile-option'].includes(name)){
    const toml=f.out+'/src/cjpm.toml';fs.writeFileSync(toml,name.startsWith('positive')?'compile-option = "-O1"\n':'compile-option = "-O0"\n');const b=new Bootstrap([]);b.STAGE='test-O1';b.rewriteO1(toml);assert.match(fs.readFileSync(toml,'utf8'),/"-O1"/);return;
  }
  if(name==='fault-product-missing'){const b=new Bootstrap([]);b.STAGE='test-product';b.product(f.out+'/missing','cjcj-stage1');return;}
  const cuts={
    'fault-build-env':s=>s.replace("...(this.BUILD_TMPDIR ? {TMPDIR:this.BUILD_TMPDIR} : {}),",''),
    'fault-dry-stage1-missing':s=>s.replace("this.hostRunner(sdk,compiler); this.assertExecutable('stage1-compiler',sdk+'/bin/cjc');","this.hostRunner(sdk,compiler);"),
    'fault-dry-stage1-duplicate':s=>s.replace("this.assertExecutable('stage1-compiler',sdk+'/bin/cjc');","this.assertExecutable('stage1-compiler',sdk+'/bin/cjc'); this.assertExecutable('stage1-compiler',sdk+'/bin/cjc');"),
    'fault-dry-stage1-serial':s=>s.replace("['-j',this.JOBS],this.STAGE1_HEAP","['-j','1'],this.STAGE1_HEAP"),
    'fault-dry-stage1-drop-jobs':s=>s.replace("this.cmd(sdk+'/tools/bin/cjpm',['build',...extra]","this.cmd(sdk+'/tools/bin/cjpm',['build']"),
    'fault-dry-stage1-stale-stdlib':s=>s.replace('this.assembleStage1(sdk,compiler,std);','this.assembleStage1(sdk,compiler,this.phase.previousStd);'),
    'fault-shim-wiring':s=>s.replace("await this.shimBuild('stage0',sdk,this.HRT,copy);",''),
    'fault-forensic-drop-g':s=>s.replace("['-j',this.JOBS,'-g']","['-j',this.JOBS]"),
  };
  if(cuts[name]) {
    const entry=cutProduct('bootstrap.mjs',cuts[name]);
    const result=invoke(entry,[...f.args,'--stage','all','--dry-run'],name==='fault-forensic-drop-g'?{CJCJ_FORENSIC_STAGE2:'1'}:{});
    if(name==='fault-forensic-drop-g')checkForensic(result);
    else checkDry(result);return;
  }
  if(name==='fault-llvm-so-location') {
    fs.appendFileSync(f.hostLlvm,'changed input bytes');
    const entry=cutProduct('sdk_build.mjs',s=>s.replace("path.join(to,'third_party/llvm/lib',name)","path.join(to,'third_party/llvm/bin',name)"));
    const result=invoke(entry,['--from',f.base,'--to',out+'/sdk-wrong-so','--host','--llvm-so',f.hostLlvm,'--colour-runtime',f.colour,'--host-runtime',f.host]);
    assert.equal(result.status,0,result.text);assert.deepEqual(fs.readFileSync(out+'/sdk-wrong-so/third_party/llvm/lib/'+f.native.library),fs.readFileSync(f.hostLlvm));return;
  }
  if(name==='fault-cjpm-toml')fs.rmSync(f.out+'/src/cjpm.toml');
  else if(name==='fault-src-file'){f.args[f.args.indexOf('--src')+1]=f.out+'/src/main.cj';}
  else if(name==='fault-host-sha')f.args[f.args.indexOf('--host-llvm-sha256')+1]='0'.repeat(64);
  else if(name==='fault-ast-sha')f.args[f.args.indexOf('--ast-support-sha256')+1]='0'.repeat(64);
  else if(name==='fault-ast-bytes')fs.appendFileSync(f.ast,'changed');
  else if(name==='fault-host-colour'){
    const src=out+'/host-colour.cpp';fs.writeFileSync(src,'namespace llvm { bool isCJTypedReadHelperCandidate(void*) { return true; } }');
    execute('c++',[src,'-o',f.hostLlvm,...(f.native.os==='darwin'?['-dynamiclib']:['-shared','-fPIC'])]);f.args[f.args.indexOf('--host-llvm-sha256')+1]=sha256File(f.hostLlvm);
  }
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
