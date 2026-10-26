import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

// Executes the public entries and real child capture/tar. Tool commands and
// Windows platform are explicit fixtures: these results do not qualify PE/OS.
const evidence=process.env.WINDOWS_CONSUMERS_EVIDENCE;
if(!evidence)throw Error('WINDOWS_CONSUMERS_EVIDENCE required');
fs.mkdirSync(evidence,{recursive:true});
function fixture() {
 const root=fs.mkdtempSync(path.join(evidence,"consumer's (literal) "));
 const output=path.join(root,'output'),source=path.join(root,'runtime-source'),runtime=path.join(source,'runtime');
 const install=path.join(output,'runtime-install'),lib=path.join(install,'windows_release_x86_64/runtime/lib/windows_x86_64_cjnative');
 const build=path.join(runtime,'CMakebuild'),reply=path.join(build,'.cmake/api/v1/reply');
 const put=(f,s)=>{fs.mkdirSync(path.dirname(f),{recursive:true});fs.writeFileSync(f,s);};
 const json=(f,x)=>put(f,JSON.stringify(x));
 const exe=(f,s)=>{put(f,'#!'+process.execPath+'\n'+s);fs.chmodSync(f,0o755);};
 for(const name of ['libcangjie-runtime.dll','libboundscheck.dll','libcangjie-runtime.dll.a','libboundscheck.dll.a','windows_x86_64_exports.def'])put(path.join(lib,name),'explicit non-PE command fixture');
 const calls=path.join(root,'calls.jsonl');
 const compiler=path.join(root,'toolchain/bin/clang++.exe');
 const compiledExe=`const fs=require('node:fs');fs.appendFileSync(process.env.CONSUMER_CALLS,JSON.stringify({kind:'run',argv:process.argv.slice(2),exe:process.argv[1],cwd:process.cwd(),path:process.env.PATH})+'\\n');process.exitCode=Number(process.env.FIXTURE_RUN_RC||0);`;
 exe(compiler,`const fs=require('node:fs');const args=process.argv.slice(2);fs.appendFileSync(process.env.CONSUMER_CALLS,JSON.stringify({kind:'compiler',args,cwd:process.cwd()})+'\\n');if(args.includes('--version')){console.log('explicit compiler command fixture');process.exit(0);}if(process.env.FIXTURE_COMPILE_RC&&args.includes('-c'))process.exit(Number(process.env.FIXTURE_COMPILE_RC));const dest=args[args.indexOf('-o')+1];if(args.includes('-c'))fs.writeFileSync(dest,'non-COFF command fixture');else {fs.writeFileSync(dest,${JSON.stringify('#!'+process.execPath+'\n'+compiledExe)});fs.chmodSync(dest,0o755);}`);
 put(path.join(build,'CMakeCache.txt'),'CMAKE_CXX_COMPILER:FILEPATH='+compiler+'\n');
 json(path.join(reply,'index-fixture.json'),{reply:{'client-runtime-exports':{'codemodel-v2':{jsonFile:'model.json'}}}});
 json(path.join(reply,'model.json'),{paths:{build,source:runtime},configurations:[{targets:[{jsonFile:'exception.json'}]}]});
 json(path.join(reply,'exception.json'),{name:'Exception',sources:[{path:'src/Exception/WindowsExceptionTransfer.cpp',compileGroupIndex:0}],compileGroups:[{language:'CXX',defines:[{define:'ACTUAL_PRODUCT_CONFIGURATION=1'}],includes:[{path:path.join(runtime,'include')}],compileCommandFragments:[{fragment:'-target x86_64-w64-mingw32 -stdlib=libc++ -fno-exceptions'}]}]});
 for(const name of ['windows_n2c_os_unwind.cpp','windows_exception_return_os.cpp','windows_exception_frames.cpp','gc_unit/test_unwind_regressions.cpp'])put(path.join(runtime,'tests',name),'explicit consumer source command fixture');
 put(path.join(runtime,'tests/windows_exception_imports.mjs'),`import fs from 'node:fs';fs.appendFileSync(process.env.CONSUMER_CALLS,JSON.stringify({kind:'imports',args:process.argv.slice(2)})+'\\n');process.exitCode=Number(process.env.FIXTURE_IMPORTS_RC||0);`);
 const hooks=path.join(root,'host.mjs');
 put(hooks,`import fs from 'node:fs';Object.defineProperty(process,'platform',{value:'win32'});globalThis.$=()=>async(strings,...values)=>{fs.appendFileSync(process.env.CONSUMER_CALLS,JSON.stringify({kind:'verifier',values})+'\\n');return {exitCode:0,signal:null};};`);
 const env={...process.env,PLATFORM_CI_ROOT:output,RUNTIME_SOURCE:source,WINDOWS_RUNTIME_EVIDENCE:path.join(output,'windows-native'),CONSUMER_CALLS:calls};
 function run(entry,extra=[],overrides={}) {
  const argv=[process.execPath,'--import',hooks,path.resolve('ci/platform_matrix/'+entry),...extra];
  const r=spawnSync(argv[0],argv.slice(1),{env:{...env,...overrides},encoding:'utf8',timeout:30000});
  put(path.join(root,'entry.stdout'),r.stdout||'');put(path.join(root,'entry.stderr'),r.stderr||'');
  json(path.join(root,'entry-command.json'),{argv,rc:r.status,signal:r.signal,error:r.error?.message});return r;
 }
 return {root,output,runtime,build,install,lib,compiler,env,run,events:()=>fs.existsSync(calls)?fs.readFileSync(calls,'utf8').trim().split('\n').map(JSON.parse):[]};
}

for(const packaged of [false,true])test(packaged?'same-install package selects unpacked DLL and imports':'installed consumers preserve compiler inputs and IAT checks',()=>{
 const f=fixture();const r=f.run(packaged?'windows_runtime_package.mjs':'windows_runtime_consumers.mjs');
 assert.equal(r.status,0,r.stderr);
 const selected=packaged?path.join(f.output,'runtime-unpacked'):f.install;
 const events=f.events(),runs=events.filter(e=>e.kind==='run'),checks=events.filter(e=>e.kind==='imports');
 console.log('CONSUMER_IAT_TARGET_REACHED');
 assert.deepEqual(checks.map(c=>c.args[1]),['entry','gc'],'both actual compiled frame objects must reach IAT checks before linking');
 assert.ok(checks.every(c=>fs.existsSync(c.args[0])));
 console.log('CONSUMER_ORIGIN_TARGET_REACHED');
 assert.equal(runs.length,3,'all three native groups must execute');
 for(const run of runs) {
  assert.equal(run.argv.length,1);
  assert.equal(run.argv[0],path.join(selected,path.relative(f.install,f.lib),'libcangjie-runtime.dll'),'consumer must receive the matching installed/unpacked DLL');
  assert.equal(run.path.split(';')[0],path.dirname(run.argv[0]));
  assert.ok(!run.path.includes('toolchain'),'runtime PATH must not borrow compiler DLLs');
  assert.ok(run.cwd.startsWith(path.join(f.output,'windows-consumers')));
 }
 const compiles=events.filter(e=>e.kind==='compiler'&&e.args.includes('-c'));
 assert.equal(compiles.length,4);
 for(const c of compiles) {
  assert.ok(c.args.includes('-DACTUAL_PRODUCT_CONFIGURATION=1'));
  assert.ok(c.args.includes(path.join(f.runtime,'include')));
  assert.ok(c.args.includes('-fexceptions'));assert.ok(c.args.includes('-fno-rtti'));
  assert.match(fs.readFileSync(c.args[0].slice(1),'utf8'),/-stdlib=libc\+\+/);
 }
 const links=events.filter(e=>e.kind==='compiler'&&e.args.includes('-lntdll'));
 assert.equal(links.length,3);
 for(const name of ['libcangjie-runtime.dll.a','libboundscheck.dll.a'])assert.ok(links[2].args.includes(path.join(selected,path.relative(f.install,f.lib),name)));
 const captures=fs.readdirSync(f.env.WINDOWS_RUNTIME_EVIDENCE).filter(x=>x.startsWith('consumer-')).map(x=>JSON.parse(fs.readFileSync(path.join(f.env.WINDOWS_RUNTIME_EVIDENCE,x,'command.json'))));
 assert.equal(captures.length,13);assert.ok(captures.every(c=>c.rc===0&&c.signal===null));
 if(packaged){
  assert.equal(events.filter(e=>e.kind==='verifier').length,1);assert.ok(fs.existsSync(path.join(f.output,'runtime-install.tar')));
  const summary=JSON.parse(fs.readFileSync(path.join(f.output,'unpacked-consumer.json')));
  assert.equal(summary.verifier.rc,0);assert.equal(summary.native.rc,0);assert.equal(summary.rc,0);
 }
});
test('package summary preserves native failure after successful verifier',()=>{
 const f=fixture(),r=f.run('windows_runtime_package.mjs',[],{FIXTURE_RUN_RC:'33'});
 assert.equal(r.status,33,r.stderr);
 const summary=JSON.parse(fs.readFileSync(path.join(f.output,'unpacked-consumer.json')));
 console.log('PACKAGE_NATIVE_RC_TARGET_REACHED');
 assert.equal(summary.verifier.rc,0);assert.equal(summary.native.rc,33);
 assert.equal(summary.rc,33,'package summary must include native consumer failure');
 assert.equal(f.events().filter(e=>e.kind==='run').length,1);
});
for(const [key,code,stoppedKind]of [['FIXTURE_COMPILE_RC',31,'run'],['FIXTURE_IMPORTS_RC',32,'frames-link'],['FIXTURE_RUN_RC',33,'second-compile']])test('consumer failure preserves '+key,()=>{
 const f=fixture(),r=f.run('windows_runtime_consumers.mjs',[],{[key]:String(code)});
 assert.equal(r.status,code,r.stderr);
 const events=f.events();
 if(stoppedKind==='run')assert.equal(events.filter(e=>e.kind==='run').length,0);
 if(stoppedKind==='frames-link')assert.equal(events.filter(e=>e.kind==='compiler'&&e.args.includes('-lntdll')).length,2);
 if(stoppedKind==='second-compile')assert.equal(events.filter(e=>e.kind==='compiler'&&e.args.includes('-c')).length,1);
 const captures=fs.readdirSync(f.env.WINDOWS_RUNTIME_EVIDENCE).map(x=>JSON.parse(fs.readFileSync(path.join(f.env.WINDOWS_RUNTIME_EVIDENCE,x,'command.json'))));
 assert.equal(captures.filter(c=>c.rc===code).length,1);
});
