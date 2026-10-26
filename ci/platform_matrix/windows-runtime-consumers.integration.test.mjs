import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {verifiedTool} from '../test-zx.mjs';
const zxTool=verifiedTool();

// Executes the public entries and real child capture/tar. Tool commands and
// Windows platform are explicit fixtures: these results do not qualify PE/OS.
const evidence=process.env.WINDOWS_CONSUMERS_EVIDENCE;
if(!evidence)throw Error('WINDOWS_CONSUMERS_EVIDENCE required');
fs.mkdirSync(evidence,{recursive:true});
function fixture(outputName='output') {
 const root=fs.mkdtempSync(path.join(evidence,"consumer's (literal) "));
 const output=path.join(root,outputName),source=path.join(root,'runtime-source'),runtime=path.join(source,'runtime');
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
 json(path.join(reply,'exception.json'),{name:'Exception',sources:[{path:'src/Exception/WindowsExceptionTransfer.cpp',compileGroupIndex:0}],compileGroups:[{language:'CXX',defines:[{define:'ACTUAL_PRODUCT_CONFIGURATION=1'}],includes:[{path:path.join(runtime,'include')}],compileCommandFragments:[{fragment:'-target x86_64-w64-mingw32 -stdlib=libc++ --rtlib=compiler-rt -fno-exceptions'}]}]});
 for(const name of ['windows_n2c_os_unwind.cpp','windows_exception_return_os.cpp','windows_exception_frames.cpp','gc_unit/test_unwind_regressions.cpp'])put(path.join(runtime,'tests',name),'explicit consumer source command fixture');
 put(path.join(runtime,'tests/windows_exception_imports.mjs'),`import fs from 'node:fs';fs.appendFileSync(process.env.CONSUMER_CALLS,JSON.stringify({kind:'imports',args:process.argv.slice(2)})+'\\n');process.exitCode=Number(process.env.FIXTURE_IMPORTS_RC||0);`);
 const hooks=path.join(root,'host.mjs');
 put(hooks,`import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const {ProcessOutput,$:zx$}=createRequire(${JSON.stringify(zxTool.packageFile)})('zx');
const state=process.env.FIXTURE_VERIFIER_STATE;
// Obtain a real nothrow ProcessOutput from a failed spawn before simulating Windows.
const launch=state==='launch'?await zx$({shell:${JSON.stringify(path.join(root,'missing-shell'))},nothrow:true,quiet:true})\`exit 0\`:null;
Object.defineProperty(process,'platform',{value:'win32'});
globalThis.$=()=>async(strings,...values)=>{
 const states={nonzero:new ProcessOutput(19),signal:new ProcessOutput(null,'SIGTERM'),launch,
  'from-error':ProcessOutput.fromError(Error('explicit public fromError cause')),
  'zero-signal':new ProcessOutput(0,'SIGTERM'),
  'zero-error':new ProcessOutput({code:0,signal:null,error:Error('explicit ProcessOutput cause'),duration:0,from:'public constructor fixture',store:{stdout:[],stderr:[],stdall:[]}})};
 const output=states[state]||new ProcessOutput(0);
 assert(output instanceof ProcessOutput);assert.equal(output.error,undefined);
 if(state==='launch'){assert.equal(output.cause.code,'ENOENT');assert.equal(output.ok,false);}
 fs.appendFileSync(process.env.CONSUMER_CALLS,JSON.stringify({kind:'verifier',values,type:output.constructor.name,ok:output.ok,rc:output.exitCode,signal:output.signal,cause:output.cause?{name:output.cause.name,message:output.cause.message,code:output.cause.code,stack:output.cause.stack}:null})+'\\n');
 return output;
};`);
 const env={...process.env,PLATFORM_CI_ROOT:output,RUNTIME_SOURCE:source,WINDOWS_RUNTIME_EVIDENCE:path.join(output,'windows-native'),CONSUMER_CALLS:calls};
 function run(entry,extra=[],overrides={}) {
  const argv=[process.execPath,zxTool.cli,'--eval',`await import(${JSON.stringify(pathToFileURL(hooks).href)});await import(${JSON.stringify(pathToFileURL(path.resolve('ci/platform_matrix/'+entry)).href)});`,...extra];
  const r=spawnSync(argv[0],argv.slice(1),{env:{...env,...overrides},encoding:'utf8',timeout:30000});
  put(path.join(root,'entry.stdout'),r.stdout||'');put(path.join(root,'entry.stderr'),r.stderr||'');
  json(path.join(root,'entry-command.json'),{argv,rc:r.status,signal:r.signal,error:r.error?.message});return r;
 }
 return {root,output,runtime,build,install,lib,compiler,env,run,events:()=>fs.existsSync(calls)?fs.readFileSync(calls,'utf8').trim().split('\n').map(JSON.parse):[]};
}

for(const [packaged,outputName] of [[false,'output'],[true,'output'],[true,'D: archive root']])test(packaged?'same-install package selects unpacked DLL and imports: '+outputName:'installed consumers preserve compiler inputs and IAT checks',()=>{
 const f=fixture(outputName);const r=f.run(packaged?'windows_runtime_package.mjs':'windows_runtime_consumers.mjs');
 if(outputName.includes(':')) {
  const archiveDir=fs.readdirSync(f.env.WINDOWS_RUNTIME_EVIDENCE).find(x=>x.startsWith('package-'));
  assert.ok(archiveDir,'the real tar command must have been started');
  const command=JSON.parse(fs.readFileSync(path.join(f.env.WINDOWS_RUNTIME_EVIDENCE,archiveDir,'command.json')));
  console.log('PACKAGE_TAR_LOCAL_TARGET_REACHED');
  assert.equal(command.rc,0,'real tar must create the local archive in a colon-containing root');
 }
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
 console.log('CONSUMER_UNWINDER_TARGET_REACHED');
 for(const link of links) {
  assert.ok(link.args.includes('-static'),'consumer must not borrow toolchain runtime DLLs');
  assert.ok(link.args.includes('--unwindlib=libunwind'),'C++ exception consumers must link their unwinder');
 }
 for(const name of ['libcangjie-runtime.dll.a','libboundscheck.dll.a'])assert.ok(links[2].args.includes(path.join(selected,path.relative(f.install,f.lib),name)));
 const captures=fs.readdirSync(f.env.WINDOWS_RUNTIME_EVIDENCE).filter(x=>x.startsWith('consumer-')).map(x=>JSON.parse(fs.readFileSync(path.join(f.env.WINDOWS_RUNTIME_EVIDENCE,x,'command.json'))));
 assert.equal(captures.length,13);assert.ok(captures.every(c=>c.rc===0&&c.signal===null));
 if(packaged){
  const verifier=events.find(e=>e.kind==='verifier'),command=verifier.values[0];
  console.log('PACKAGE_VERIFIER_ARGV_TARGET_REACHED');
  assert.deepEqual(command,[process.execPath,zxTool.cli,path.resolve('ci/platform_matrix/verify_windows_runtime_exports.mjs'),selected,'--expected-def',path.join(selected,path.relative(f.install,f.lib),'windows_x86_64_exports.def'),'--reference-services'],'verifier must receive the unpacked input through the actual Node/zx CLI');
  const archiveCommands=fs.readdirSync(f.env.WINDOWS_RUNTIME_EVIDENCE).filter(x=>/^(package|unpack)-/.test(x)).map(x=>JSON.parse(fs.readFileSync(path.join(f.env.WINDOWS_RUNTIME_EVIDENCE,x,'command.json'))));
  console.log('PACKAGE_LOCAL_ARCHIVE_TARGET_REACHED');
  assert.equal(archiveCommands.length,2);assert.ok(archiveCommands.every(c=>c.rc===0&&c.cwd===f.output));
  assert.ok(archiveCommands.every(c=>c.argv[2]==='./runtime-install.tar'),'tar must receive a local archive operand');
  for(const name of fs.readdirSync(f.lib))assert.deepEqual(fs.readFileSync(path.join(selected,path.relative(f.install,f.lib),name)),fs.readFileSync(path.join(f.lib,name)),'same-install member bytes must survive tar/unpack');
  assert.equal(events.filter(e=>e.kind==='verifier').length,1);assert.ok(fs.existsSync(path.join(f.output,'runtime-install.tar')));
  const summary=JSON.parse(fs.readFileSync(path.join(f.output,'unpacked-consumer.json')));
  assert.equal(summary.verifier.rc,0);assert.equal(summary.native.rc,0);assert.equal(summary.rc,0);
 }
});
test('package verifier uses the real zx child with literal path arguments',()=>{
 const f=fixture(String.raw`D:\a\native package's (literal)`);
 const symbols=['CJ_MCC_SetReferenceMethods','CJ_MCC_ReferenceInvokeFinalize','CJ_MCC_ReferenceWaitPending','CJ_MCC_ReferenceRuntimeRunning','CJ_MCC_ReferenceNanoTime'];
 fs.writeFileSync(path.join(f.lib,'windows_x86_64_exports.def'),'EXPORTS\n'+symbols.map((s,i)=>` ${s} @${i+1}`).join('\n')+'\n');
 const packaged=f.run('windows_runtime_package.mjs');assert.equal(packaged.status,0,packaged.stderr);
 const command=f.events().find(e=>e.kind==='verifier').values[0];
 const dump=path.join(f.root,'objdump-fixture.mjs');
 const table=['dbghelp.dll','kernel32.dll','libboundscheck.dll','msvcrt.dll','ws2_32.dll'].map(s=>'DLL Name: '+s).join('\n')+'\n\n[Ordinal/Name Pointer] Table\n'+symbols.map((s,i)=>` [${i}] ${s}`).join('\n')+'\n\n';
 fs.writeFileSync(dump,'#!'+process.execPath+'\nconsole.log('+JSON.stringify(table)+');\n',{mode:0o755});
 const driver=path.join(f.root,'verifier-child.mjs');
 fs.writeFileSync(driver,'const command='+JSON.stringify(command)+';const result=await $({nothrow:true})`${command}`;console.log(JSON.stringify({rc:result.exitCode,signal:result.signal,ok:result.ok,cause:result.cause?.message,stdout:result.stdout,stderr:result.stderr}));');
 const argv=[process.execPath,zxTool.cli,driver],r=spawnSync(argv[0],argv.slice(1),{encoding:'utf8',env:{...f.env,OBJDUMP:dump},timeout:30000});
 fs.writeFileSync(path.join(f.root,'verifier-child.stdout'),r.stdout||'');fs.writeFileSync(path.join(f.root,'verifier-child.stderr'),r.stderr||'');
 fs.writeFileSync(path.join(f.root,'verifier-child-command.json'),JSON.stringify({argv,rc:r.status,signal:r.signal,verifierArgv:command}));
 assert.equal(r.status,0,r.stderr);const actual=JSON.parse(r.stdout.trim());
 console.log('PACKAGE_REAL_VERIFIER_TARGET_REACHED');
 assert.equal(actual.rc,0,actual.stderr);assert.equal(actual.ok,true);assert.equal(actual.signal,null);
 assert.ok(actual.stdout.includes('dll='+path.join(f.output,'runtime-unpacked',path.relative(f.install,f.lib),'libcangjie-runtime.dll')),'real verifier must consume the exact unpacked literal path');
 assert.ok(actual.stdout.includes('missing=0'));
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
for(const state of ['nonzero','signal','launch','from-error','zero-signal','zero-error'])test('verifier failure stops native consumers: '+state,()=>{
 const f=fixture(),r=f.run('windows_runtime_package.mjs',[],{FIXTURE_VERIFIER_STATE:state});
 const events=f.events();
 assert.equal(events.filter(e=>e.kind==='verifier').length,1,'verifier must actually be invoked');
 console.log('VERIFIER_STOP_TARGET_REACHED '+state);
 assert.equal(events.filter(e=>['compiler','imports','run'].includes(e.kind)).length,0,
  'failed or abnormal verifier must not start native consumers');
 assert.equal(r.status,state==='nonzero'?19:1,'abnormal verifier must terminate package nonzero');
 const summary=JSON.parse(fs.readFileSync(path.join(f.output,'unpacked-consumer.json')));
 assert.equal(summary.rc,r.status);assert.equal(summary.native.status,'NOT_RUN');
 const actual=events.find(e=>e.kind==='verifier');
 assert.equal(summary.verifier.rc,actual.rc,'preserve the actual zx exitCode, including spawn errno');
 if(state==='launch')assert.ok(Number.isInteger(actual.rc)&&actual.rc<0,'real Linux ENOENT spawn reports a negative errno');
 else assert.equal(actual.rc,state==='nonzero'?19:state.startsWith('zero-')?0:null);
 assert.equal(summary.verifier.signal,state.includes('signal')?'SIGTERM':null);
 assert.equal(summary.verifier.ok,events.find(e=>e.kind==='verifier').ok);
 if(['launch','from-error','zero-error'].includes(state)){
  console.log('VERIFIER_CAUSE_TARGET_REACHED '+state);
  const actual=events.find(e=>e.kind==='verifier');
  assert.equal(actual.ok,false);assert.ok(actual.cause?.message);
  assert.deepEqual(summary.verifier.cause,actual.cause,'preserve the real ProcessOutput cause');
  if(state==='launch')assert.equal(summary.verifier.cause.code,'ENOENT');
 }else assert.equal(summary.verifier.cause,null);
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
