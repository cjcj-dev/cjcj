import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {exportBranches, expandEnvironment} from './migration-branches.mjs';
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const evidence = process.env.G2_MIGRATION_EVIDENCE;
assert.ok(evidence && path.isAbsolute(evidence), 'explicit private evidence directory required');
fs.mkdirSync(evidence, {recursive:true});
const cwd = path.join(evidence, 'caller with spaces'); fs.mkdirSync(cwd);
const envBase = {...process.env, LC_ALL:'C', GIT_CONFIG_NOSYSTEM:'1', GIT_AUTHOR_DATE:'2026-10-20T00:00:00+0000', GIT_COMMITTER_DATE:'2026-10-20T00:00:00+0000'};
for (const key of Object.keys(envBase)) if (/^(CJCJ_LLVM_RUNTIME_|CJCJ_SRCBUILD_|TUPLE_|LLVM_|CANGJIE_COMPILER_|FLATBUFFERS_)/.test(key)) delete envBase[key];
delete envBase.NODE_TEST_CONTEXT; delete envBase.RUNTIME_REF; delete envBase.RUNTIME_SRC_URL;
let sequence=0; const results=[];
function run(label, command, env={}, directory=cwd) {
  const dir=path.join(evidence, `${String(sequence++).padStart(3,'0')}-${label}`);fs.mkdirSync(dir);
  fs.writeFileSync(path.join(dir,'command.json'), JSON.stringify({command,cwd:directory,env},null,2)+'\n');
  const result=spawnSync(command[0],command.slice(1),{cwd:directory,env:{...envBase,...env},encoding:'utf8',maxBuffer:16*1024*1024,timeout:120000});
  fs.writeFileSync(path.join(dir,'stdout.log'),result.stdout??'');fs.writeFileSync(path.join(dir,'stderr.log'),result.stderr??'');
  const record={label,dir,rc:result.status,signal:result.signal,error:result.error?.message};results.push(record);
  fs.writeFileSync(path.join(dir,'result.json'),JSON.stringify(record,null,2)+'\n');fs.writeFileSync(path.join(evidence,'results.json'),JSON.stringify(results,null,2)+'\n');
  assert.equal(result.error,undefined); assert.equal(result.signal,null); return result;
}
function setup(command,directory=cwd){const r=run('setup',command,{},directory);assert.equal(r.status,0,r.stderr);return r.stdout.trim();}
function repository(name, files) {
  const dir=path.join(evidence,name);fs.mkdirSync(dir);
  for(const [file,bytes] of Object.entries(files)){fs.mkdirSync(path.dirname(path.join(dir,file)),{recursive:true});fs.writeFileSync(path.join(dir,file),bytes);}
  setup(['git','init','-q',dir]);setup(['git','add','.'],dir);
  setup(['git','-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','finite tuple input'],dir);
  return {dir,sha:setup(['git','rev-parse','HEAD'],dir)};
}
const runtime=repository('runtime remote',{'runtime-marker.txt':'paired real Git consumer\n'});
const other=repository('other remote',{
  'schema/ModuleFormat.fbs':'table Sample { value:int; }\nroot_type Sample;\n',
  'CMakeLists.txt':'cmake_minimum_required(VERSION 3.16)\nproject(flat_fixture NONE)\n',
  'llvm/include/llvm/Transforms/Scalar/ReflectionInfo.h':'enum EnumReflectionType {\n  ERT_FIXTURE\n};\n',
  'llvm/CMakeLists.txt':`cmake_minimum_required(VERSION 3.16)
project(tuple_configure_consumer NONE)
if(NOT LLVM_ENABLE_LIBXML2 STREQUAL "OFF")
  message(FATAL_ERROR "G2_LIBXML2_CONTROL_FAIL")
endif()
message(STATUS "G2_LIBXML2_CONTROL_PASS")
message(STATUS "G2_RUNTIME_TARGET_REACHED")
if(NOT DEFINED CANGJIE_RUNTIME_SOURCE_DIR OR NOT IS_ABSOLUTE "\${CANGJIE_RUNTIME_SOURCE_DIR}")
  message(FATAL_ERROR "G2_RUNTIME_SOURCE_MISSING")
endif()
file(READ "\${CANGJIE_RUNTIME_SOURCE_DIR}/runtime-marker.txt" marker)
if(NOT marker STREQUAL "paired real Git consumer\\n")
  message(FATAL_ERROR "G2_RUNTIME_BYTES_WRONG")
endif()
message(STATUS "G2_RUNTIME_CONSUMER_PASS")
message(FATAL_ERROR "G2_FINITE_CONFIGURE_STOP")
`});
const url='https://github.com/cjcj-dev/cangjie-runtime.git';
fs.writeFileSync(path.join(evidence,'input-identities.json'),JSON.stringify({runtime:runtime.sha,other:other.sha,parser:'shfmt v3.12.0'},null,2)+'\n');
const baseline={TUPLE_ROOT:'tuple relative',TUPLE_PLATFORM:'linux_x86_64',LLVM_TARGETS:'X86',
 CJCJ_LLVM_RUNTIME_MODE:'private',CJCJ_LLVM_RUNTIME_URL:url,CJCJ_LLVM_RUNTIME_SHA:runtime.sha,
 LLVM_URL:'https://fixture.invalid/llvm',LLVM_SHA:other.sha,CANGJIE_COMPILER_URL:'https://fixture.invalid/compiler',CANGJIE_COMPILER_SHA:other.sha,
 FLATBUFFERS_URL:'https://fixture.invalid/flatbuffers',FLATBUFFERS_SHA:other.sha,
 CJCJ_SRCBUILD_REQUIRE_MIRRORS:'1',CJCJ_SRCBUILD_SOURCE_MIRRORS:[`${url}=file://${runtime.dir}`,...['llvm','compiler','flatbuffers'].map(x=>`https://fixture.invalid/${x}=file://${other.dir}`)].join(';')};
const old=path.join(evidence,'old repo');
for(const [source,target] of [
 ['ci/fixtures/g2/fetch_sources.bash.txt','ci/platform_tuples/fetch_sources.sh'],['ci/fixtures/g2/build_tuple.bash.txt','ci/platform_tuples/build_tuple.sh'],
 ['build/lib/srcbuild_git.sh','build/lib/srcbuild_git.sh'],['ci/fetch-llvm-runtime.mjs','ci/fetch-llvm-runtime.mjs'],['ci/runtime_pin.env','ci/runtime_pin.env']]){
 const dest=path.join(old,target);fs.mkdirSync(path.dirname(dest),{recursive:true});fs.copyFileSync(path.join(repo,source),dest);
}
const commands=(entry,arm)=>arm==='old'?['bash',path.join(old,`ci/platform_tuples/${entry}.sh`)]:['npx','--yes','zx@8',path.join(repo,`ci/platform_tuples/${entry}.mjs`)];
const allRows=[];
for(const entry of ['fetch_sources','build_tuple']){
 const parsed=exportBranches(fs.readFileSync(path.join(repo,`ci/fixtures/g2/${entry}.bash.txt`),'utf8'));
 fs.writeFileSync(path.join(evidence,`${entry}.ast.json`),JSON.stringify(parsed.ast,null,2)+'\n');allRows.push(...parsed.rows.map(row=>({...row,entry})));
}
const expanded=expandEnvironment(allRows,{fetch_sources:baseline,build_tuple:baseline});
fs.writeFileSync(path.join(evidence,'ast-branches.json'),JSON.stringify(allRows,null,2)+'\n');
fs.writeFileSync(path.join(evidence,'ast-expanded.json'),JSON.stringify(expanded,null,2)+'\n');
function invoke(entry,arm,label,env){return run(`${label}-${arm}`,commands(entry,arm),env);}
function pair(entry,label,env,check){for(const arm of ['old','new']){const r=invoke(entry,arm,label,env);check(r,arm);}}
let count=0;
test('AST required environment expands into actual CLI rejections',()=>{
 assert.throws(()=>exportBranches('if then'), /Bash AST parser/);
 assert.ok(allRows.some(row=>row.variable==='LLVM_URL' && row.kind==='required' && row.operator===':?'));

 for(const item of expanded.filter(x=>x.status==='READY'&&x.outcome!=='set')){
  const env={...item.env,TUPLE_ROOT:`required-${count++}`};
  if(item.variable==='TUPLE_ROOT'){if(item.outcome==='unset')delete env.TUPLE_ROOT;else env.TUPLE_ROOT='';}
  // Omitted values must not be reintroduced by the ambient environment.
  pair(item.entry,`${item.entry}-${item.variable}-${item.outcome}`,env,r=>{assert.equal(r.status,1,r.stdout+r.stderr);assert.ok((r.stdout+r.stderr).includes(`: line ${item.line}: ${item.variable}:`),r.stdout+r.stderr);});
 }
});
test('fetch real first checkout and cached checkout preserve pinned identities',()=>{
 for(const arm of ['old','new']){
  const env={...baseline,TUPLE_ROOT:`${arm} tuple`};
  for(const phase of ['first','cached']){
   const r=invoke('fetch_sources',arm,phase,env);assert.equal(r.status,0,r.stdout+r.stderr);
   for(const [dir,sha] of [['llvm-project',other.sha],['paired-runtime',runtime.sha],['cangjie-compiler',other.sha],['flatbuffers',other.sha]])
    assert.equal(setup(['git','-C',path.resolve(cwd,env.TUPLE_ROOT,dir),'rev-parse','HEAD']),sha);
   assert.ok(fs.existsSync(path.resolve(cwd,env.TUPLE_ROOT,'cangjie-compiler/schema/ModuleFormat.fbs')));
   assert.ok(fs.readFileSync(path.resolve(cwd,env.TUPLE_ROOT,'logs/source-fetch.log'),'utf8').includes('LLVM_RUNTIME_IDENTITY'));
  }
  fs.writeFileSync(path.resolve(cwd,env.TUPLE_ROOT,'paired-runtime/dirty'),'dirty');
  const rejected=invoke('fetch_sources',arm,'dirty-runtime',env);assert.equal(rejected.status,1);assert.match(rejected.stdout,/private runtime checkout is dirty/);
 }
});
test('absolute root reaches the selected checkout from another caller directory',()=>{
 pair('fetch_sources','absolute-root',{...baseline,TUPLE_ROOT:path.join(cwd,'absolute tuple')},r=>assert.equal(r.status,0,r.stdout+r.stderr));
 assert.equal(setup(['git','-C',path.join(cwd,'absolute tuple/paired-runtime'),'rev-parse','HEAD']),runtime.sha);
});
test('invalid private input stops before any LLVM checkout',()=>{
 for(const arm of ['old','new']){
  const env={...baseline,TUPLE_ROOT:`bad-private-${arm}`,CJCJ_LLVM_RUNTIME_SHA:'bad'};
  const r=invoke('fetch_sources',arm,'bad-private',env);assert.equal(r.status,1);assert.match(r.stdout,/complete lowercase 40-digit SHA/);
  assert.equal(fs.existsSync(path.join(cwd,env.TUPLE_ROOT,'llvm-project')),false);
 }
});
test('mirror policy rejects malformed, duplicate and required missing transport',()=>{
 for(const [label,mappings] of [['invalid','broken'],['duplicate','x=a;x=b'],['missing','x=a']])
  pair('fetch_sources',label,{...baseline,TUPLE_ROOT:`mirror-${label}`,CJCJ_SRCBUILD_SOURCE_MIRRORS:mappings},r=>{assert.equal(r.status,1);assert.match(r.stdout,/invalid CJCJ_SRCBUILD_SOURCE_MIRRORS|duplicate CJCJ_SRCBUILD_SOURCE_MIRRORS|source mirror required/);});
});
let buildResults;
function builds(){
 if(buildResults)return buildResults;
 buildResults=[];
 for(const arm of ['old','new']){
  const env={...baseline,TUPLE_ROOT:`build ${arm}`};
  assert.equal(invoke('fetch_sources',arm,'build-input',env).status,0);
  const r=invoke('build_tuple',arm,'actual-cmake',env);buildResults.push({arm,r,env});
 }
 return buildResults;
}
test('tuple CMake runtime consumption reaches the actual pinned bytes',()=>{
 for(const {arm,r} of builds()){
  console.log(`G2_TARGET_ASSERT_REACHED arm=${arm} rc=${r.status}`);
  assert.equal(r.status,1);assert.match(r.stdout,/G2_RUNTIME_TARGET_REACHED/);
  assert.match(r.stdout,/G2_RUNTIME_CONSUMER_PASS/,`G2_PRODUCT_RUNTIME_WIRING ${arm}`);
  assert.match(r.stdout,/G2_FINITE_CONFIGURE_STOP/);
 }
});
test('tuple CMake independent explicit libxml2 flag remains OFF',()=>{
 for(const {arm,r} of builds()){console.log(`G2_CONTROL_ASSERT_REACHED arm=${arm}`);assert.match(r.stdout,/G2_LIBXML2_CONTROL_PASS/);}
});
