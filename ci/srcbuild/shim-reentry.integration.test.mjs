import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

// A real complete TU and two normally prepared header trees are required.
// The installed input is a previously compiled shim component, not a full SDK.
if (!process.env.SHIM_REENTRY_INPUT) throw Error('SHIM_REENTRY_INPUT required');
const input=JSON.parse(fs.readFileSync(process.env.SHIM_REENTRY_INPUT));
const root=fs.mkdtempSync(path.join(input.work,'reentry-'));
console.log('SHIM_REENTRY_EVIDENCE='+root);
const consumer=input.consumer||path.join(root,'consumer'),install=path.join(root,'installed');
fs.mkdirSync(consumer,{recursive:true});
assert.equal(spawnSync('tar',['-xf',input.referenceArchive,'-C',consumer]).status,0);
// The fixed successor changes only this script; the complete TU/inc stay fixed.
fs.copyFileSync(path.join(input.source,'runtime_shim/build_shim.mjs'),path.join(consumer,'runtime_shim/build_shim.mjs'));
const object=path.join(consumer,'runtime_shim/cjselfhost_llvmshim.o');
const record=path.join(install,'BUILD-INPUTS.json');
const installed=JSON.parse(fs.readFileSync(input.facts)).facts;
const installedObject=path.join(install,installed.nativeShim.object.path);
fs.mkdirSync(path.dirname(installedObject),{recursive:true});
fs.copyFileSync(path.join(input.installed,installed.nativeShim.object.path),installedObject);
fs.writeFileSync(record,JSON.stringify(installed));
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const commands=[],events=path.join(root,'compiler.jsonl'),capture=path.join(root,'capture.mjs');
fs.writeFileSync(capture,`#!${process.execPath}
import fs from 'node:fs';import crypto from 'node:crypto';import {spawnSync} from 'node:child_process';
const args=process.argv.slice(2),file=process.env.SHIM_CAPTURE_DEPS;
const argv=[...args,'-MD','-MF',file];
const run=process.env.SHIM_USE_CCACHE==='1'?['/usr/bin/ccache',...argv]:argv;
const r=spawnSync(run[0],run.slice(1),{stdio:'inherit'});
const output=args[args.indexOf('-o')+1];
fs.appendFileSync(process.env.SHIM_CAPTURE_EVENTS,JSON.stringify({argv:run,rc:r.status,signal:r.signal,error:r.error?.message??null,dependencyFile:file,object:fs.existsSync(output)?crypto.createHash('sha256').update(fs.readFileSync(output)).digest('hex'):null})+'\\n');
process.exit(r.status??1);
`,{mode:0o755});
const env={...process.env,...input.env,CXX:input.clang,CMAKE_CXX_COMPILER_LAUNCHER:capture,
 SHIM_CAPTURE_EVENTS:events,CPATH:'/invalid-ambient-header',CPLUS_INCLUDE_PATH:'/invalid-ambient-header',CJCJ_SRCBUILD_CONSUMER_SDK:install};
for(const name of ['CANGJIE_CPP_SRC','CJCJ_BOOTSTRAP_CPP_SRC','CJCJ_LLVM_SHIM_O','CANGJIE_HOME','CMAKE_C_COMPILER_LAUNCHER'])delete env[name];
const entry=[process.execPath,path.join(input.source,'ci/srcbuild/steps/build-shim.mjs')];
const ordinary=[process.execPath,input.zx,path.join(consumer,'runtime_shim/build_shim.mjs')];
const captured=()=>fs.existsSync(events)?fs.readFileSync(events,'utf8').trim().split('\n').filter(Boolean).map(JSON.parse).filter(row=>row.argv.some(arg=>arg.endsWith('/cjselfhost_llvmshim.cpp'))):[];
let serial=0;
function run(label,extra={},rc=0,argv=entry) {
 const name=String(++serial).padStart(2,'0')+'-'+label,deps=path.join(root,name+'.d');
 for(const file of ['shim-build.log','shim-build-command.json']) {
  const prior=path.join(consumer,'.srcbuild',file);
  if(fs.existsSync(prior))fs.renameSync(prior,path.join(root,name+'.previous-'+file));
 }
 const r=spawnSync(argv[0],argv.slice(1),{cwd:consumer,env:{...env,SHIM_CAPTURE_DEPS:deps,...extra},encoding:'utf8',maxBuffer:16*1024*1024});
 fs.writeFileSync(path.join(root,name+'.log'),(r.stdout||'')+(r.stderr||''));
 const row={label,argv,cwd:consumer,rc:r.status,signal:r.signal,headers:extra.CJCJ_BOOTSTRAP_CPP_SRC||extra.CANGJIE_CPP_SRC||null,deps,
  object:fs.existsSync(object)?{sha256:hash(object),bytes:fs.statSync(object).size}:null};
 commands.push(row);fs.writeFileSync(path.join(root,'commands.json'),JSON.stringify(commands,null,2));
 if(row.object)fs.copyFileSync(object,path.join(root,name+'.o'));
 let productLog='';
 for(const file of ['shim-build.log','shim-build-command.json']) {
  const current=path.join(consumer,'.srcbuild',file);
  if(fs.existsSync(current)){fs.copyFileSync(current,path.join(root,name+'.product-'+file));if(file==='shim-build.log')productLog=fs.readFileSync(current,'utf8');}
 }
 assert.equal(r.status,rc,label+': '+r.stderr);return {...row,log:(r.stdout||'')+(r.stderr||'')+productLog};
}
function compiled(label,headers,extra={}) {
 const before=captured().length,row=run(label,{CJCJ_BOOTSTRAP_CPP_SRC:headers,...extra});
 console.log('SELECTED_HEADERS_COMPILE_ASSERT_REACHED '+label);
 assert.equal(captured().length,before+1,'selected headers must reach the real compiler/launcher');
 const actual=captured().at(-1);assert.equal(actual.rc,0);assert.equal(actual.object,row.object.sha256);
 const deps=fs.readFileSync(row.deps,'utf8');
 for(const suffix of ['/build/build/schema/flatbuffers/CjoFormat_generated.h','/build/build/third_party/llvm/include/llvm/Config/llvm-config.h','/third_party/llvm-project/llvm/include/llvm/IR/Module.h'])
  assert.ok(deps.includes(headers+suffix),'actual dependency missing: '+headers+suffix);
 assert.ok(deps.includes(consumer+'/runtime_shim/cjo_read_surface_official.inc'));
 assert.ok(row.object.bytes>100000,'complete real shim object required');
 return row;
}
test('public shim selects usable bytes or genuinely compiles the selected complete TU',()=>{
 run('installed-before-headers');assert.equal(hash(object),installed.nativeShim.object.sha256);
 run('explicit-object',{CJCJ_LLVM_SHIM_O:installedObject});assert.equal(hash(object),installed.nativeShim.object.sha256);
 const a=compiled('headers-A',input.headersA,{SHIM_USE_CCACHE:'1'});
 assert.notEqual(a.object.sha256,installed.nativeShim.object.sha256,'native DNDEBUG object must not survive ordinary source compilation');
 compiled('headers-B',input.headersB,{SHIM_USE_CCACHE:'1'});
 compiled('same-source-reentry',input.headersB,{SHIM_USE_CCACHE:'1'});
 compiled('unavailable-explicit-object',input.headersA,{CJCJ_LLVM_SHIM_O:root+'/absent.o',SHIM_USE_CCACHE:'1'});
 const inc=path.join(consumer,'runtime_shim/cjo_read_surface_official.inc'),incBytes=fs.readFileSync(inc);
 try {
  fs.appendFileSync(inc,'\n#error R13_OFFICIAL_INC_CONSUMPTION\n');
  fs.writeFileSync(path.join(root,'inc-cut.diff'),'--- '+inc+'\n+++ '+inc+'\n@@ -'+(incBytes.toString().split('\n').length-1)+',0 +'+incBytes.toString().split('\n').length+',2 @@\n+\n+#error R13_OFFICIAL_INC_CONSUMPTION\n');
  assert.match(run('inc-cut',{CJCJ_BOOTSTRAP_CPP_SRC:input.headersA},1).log,/R13_OFFICIAL_INC_CONSUMPTION/);
  assert.equal(captured().at(-1).rc,1);
  run('inc-independent-installed');assert.equal(hash(object),installed.nativeShim.object.sha256);
 } finally {fs.writeFileSync(inc,incBytes);}
 compiled('inc-restored',input.headersA,{SHIM_USE_CCACHE:'1'});
 const config=path.join(input.headersB,'build/build/third_party/llvm/include/llvm/Config/llvm-config.h'),configBytes=fs.readFileSync(config);
 try {
  fs.appendFileSync(config,'\n#error R13_LLVM_CONFIG_CONSUMPTION\n');
  fs.writeFileSync(path.join(root,'config-cut.diff'),'--- '+config+'\n+++ '+config+'\n@@ -'+(configBytes.toString().split('\n').length-1)+',0 +'+configBytes.toString().split('\n').length+',2 @@\n+\n+#error R13_LLVM_CONFIG_CONSUMPTION\n');
  assert.match(run('config-public-compile',{CJCJ_BOOTSTRAP_CPP_SRC:input.headersB},1).log,/R13_LLVM_CONFIG_CONSUMPTION/);
  assert.equal(captured().at(-1).rc,1);run('config-independent-installed');
 } finally {fs.writeFileSync(config,configBytes);}
 compiled('config-restored',input.headersB,{SHIM_USE_CCACHE:'1'});
 assert.match(run('missing-selected-headers',{CJCJ_BOOTSTRAP_CPP_SRC:root+'/absent'},1).log,/selected shim header directory missing/);
 run('missing-explicit-compiler',{CJCJ_BOOTSTRAP_CPP_SRC:input.headersA,CXX:root+'/absent-clang'},1);
 assert.notEqual(captured().at(-1).rc,0);
 const bytes=fs.readFileSync(installedObject),before=captured().length;
 try {
  fs.appendFileSync(installedObject,'wrong bytes');
  const explicit=compiled('explicit-bad-bytes-source-fallback',input.headersA,{CJCJ_LLVM_SHIM_O:installedObject,SHIM_USE_CCACHE:'1'});
  assert.match(explicit.log,/SHIM_OBJECT_UNAVAILABLE NATIVE_SHIM_INSTALLED_BYTES/);
  const fallback=run('installed-bad-bytes-source-fallback',{SHIM_USE_CCACHE:'1'});
  assert.match(fallback.log,/SHIM_OBJECT_UNAVAILABLE NATIVE_SHIM_INSTALLED_BYTES/);
  assert.equal(captured().length,before+2);
  assert.ok(fs.readFileSync(fallback.deps,'utf8').includes(consumer+'/.srcbuild/cpp/build/build/schema/flatbuffers/CjoFormat_generated.h'));
  assert.notEqual(fallback.object.sha256,hash(installedObject));
 } finally {fs.writeFileSync(installedObject,bytes);}
 run('installed-bytes-restored');assert.equal(hash(object),installed.nativeShim.object.sha256);
 assert.deepEqual(fs.readFileSync(inc),incBytes);assert.deepEqual(fs.readFileSync(config),configBytes);
 fs.writeFileSync(path.join(root,'restored.json'),JSON.stringify({inc:true,configuration:true,installedObject:hash(installedObject)===installed.nativeShim.object.sha256}));
 const stats=spawnSync('/usr/bin/ccache',['--show-stats'],{env,encoding:'utf8'});
 fs.writeFileSync(path.join(root,'ccache-stats.txt'),stats.stdout+stats.stderr);assert.equal(stats.status,0);
});
