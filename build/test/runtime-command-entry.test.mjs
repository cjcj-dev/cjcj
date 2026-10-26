import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import {assertHostRuntimeCommands} from '../lib/runtime-split.mjs';
test('generated compiler commands consume their real entry recipe and reject target or wrong execution libraries',t=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'runtime entry '));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 const put=(rel,text='fixture')=>{const f=path.join(root,rel);fs.mkdirSync(path.dirname(f),{recursive:true});fs.writeFileSync(f,text);return f;};
 const tuple='linux_x86_64_cjnative',lib='libcangjie-runtime.so';
 const host=put('host/runtime/lib/'+tuple+'/'+lib),target=put('S/runtime/lib/'+tuple+'/'+lib);
 put('S/.compiler-exec/runtime/lib/'+tuple+'/'+lib);put('S/.compiler-exec/lib/'+tuple+'/.keep');
 put('S/lib/'+tuple+'/.keep');put('S/libexec/compiler/cjcj-stage1');
 fs.symlinkSync('../.compiler-exec/runtime',path.join(root,'S/libexec/runtime'));
 const entry=put('S/bin/cjcj-stage1');fs.chmodSync(entry,0o755);
 fs.symlinkSync('cjcj-stage1',path.join(root,'S/bin/cjc'));
 const recipe=libs=>['cjcj-sdk-entry-v1','1','libexec/compiler/cjcj-stage1','linux','native-target:x64',...libs].join('\n')+'\n';
 const good=['.compiler-exec/runtime/lib/'+tuple,'.compiler-exec/lib/'+tuple];
 fs.writeFileSync(entry+'.entry',recipe(good));
 const graph=put('graph/build.ninja','  COMMAND = /usr/bin/cmake -E env LIBRARY_PATH=/unused cjc -p input\n');
 const options={buildFile:graph,hostRuntime:host,targetRuntime:target,
  environment:{PATH:path.join(root,'S/bin'),LD_LIBRARY_PATH:path.dirname(target)},log:()=>{}};
 assert.equal(assertHostRuntimeCommands(options),1); // The launcher replaces the inherited target loader.
 fs.writeFileSync(graph,`  COMMAND = "${path.join(root,'S/bin/cjc')}" -p input\n`);
 assert.equal(assertHostRuntimeCommands(options),1);
 for(const libraries of [['runtime/lib/'+tuple], [...good,'lib/'+tuple], ['../host/runtime/lib/'+tuple]]) {
  fs.writeFileSync(entry+'.entry',recipe(libraries));
  assert.throws(()=>assertHostRuntimeCommands(options),/target libraries|wrong runtime|invalid installed entry member/);
 }
 fs.writeFileSync(entry+'.entry',recipe(good));assert.equal(assertHostRuntimeCommands(options),1);
 // A normal installed SDK can share its execution and target runtime.
 fs.unlinkSync(path.join(root,'S/libexec/runtime'));fs.symlinkSync('../runtime',path.join(root,'S/libexec/runtime'));
 fs.writeFileSync(entry+'.entry',recipe(['runtime/lib/'+tuple,'lib/'+tuple]));
 assert.equal(assertHostRuntimeCommands(options),1);
 console.log('STDX_NORMAL_ENTRY_INDEPENDENT_CONTROL_PASS');
 put('S/wrong/'+lib);fs.writeFileSync(entry+'.entry',recipe(['wrong','runtime/lib/'+tuple]));
 assert.throws(()=>assertHostRuntimeCommands(options),/wrong runtime/);
 fs.writeFileSync(entry+'.entry',recipe(['runtime/lib/'+tuple,'lib/'+tuple]));
 assert.equal(assertHostRuntimeCommands(options),1);
 const raw=put('host/bin/cjc');fs.chmodSync(raw,0o755);
 fs.writeFileSync(graph,'  COMMAND = cjc -p input\n');
 const plain={...options,environment:{PATH:path.dirname(raw),LD_LIBRARY_PATH:path.dirname(host)}};
 assert.equal(assertHostRuntimeCommands(plain),1);
 assert.throws(()=>assertHostRuntimeCommands({...plain,environment:{...plain.environment,LD_LIBRARY_PATH:path.dirname(target)}}),/wrong runtime/);
 fs.writeFileSync(graph,'  COMMAND = echo no-compiler\n');assert.throws(()=>assertHostRuntimeCommands(options),/no generated cjc command/);
});

// R3 keeps runtime/stdlib/verify.run and assertRuntimeSplit untouched. Tiny
// build.py producers and language payloads are explicit finite boundaries;
// installation, complete SDK language checks and native receiving are outside
// this host-selection regression. The real gate readers and native nm run.
import {spawnSync} from 'node:child_process';
import {directSource,directBuild,write} from '../../ci/fixtures/runtime-direct-inputs.mjs';
import {buildConfig} from '../lib/config.mjs';
import {installGcUnitInputs} from '../srcbuild/gc-unit-gate.mjs';
const r3Tuple='linux_x86_64_cjnative';
function r3Fixture(label) {
 const parent=process.env.RELEASE_EVIDENCE_TEST_ROOT||os.tmpdir();fs.mkdirSync(parent,{recursive:true});
 const root=fs.mkdtempSync(path.join(parent,'r3-'+label+'-')),workspace=root+'/workspace',host=root+'/selected-host';
 const compiler=workspace+'/cangjie_compiler',runtime=workspace+'/cangjie_runtime/runtime',stdlib=workspace+'/cangjie_runtime/stdlib',sdk=compiler+'/output';
 const records=[];
 function command(label,file,args,env=process.env,input) {
  const r=spawnSync(file,args,{env,encoding:'utf8',input,maxBuffer:8*1024*1024});
  records.push({label,argv:[file,...args],rc:r.status,signal:r.signal,error:r.error?.message,stdout:r.stdout,stderr:r.stderr});
  write(root+'/commands.json',JSON.stringify(records,null,2));return r;
 }
 function okay(label,file,args,input){const r=command(label,file,args,process.env,input);assert.equal(r.status,0,r.stderr);return r;}
 for(const [base,c]of [[host,'int plain;'],[sdk,'long g_cjLoadBadMask;']]){
  const file=base+'/runtime/lib/'+r3Tuple+'/libcangjie-runtime.so';fs.mkdirSync(path.dirname(file),{recursive:true});
  okay('native-runtime-fixture','cc',['-shared','-fPIC','-x','c','-','-o',file],c);
 }
 write(sdk+'/bin/cjc','#!'+process.execPath+'\nconsole.log("finite compiler boundary");\n',0o755);
 write(sdk+'/runtime/lib/'+r3Tuple+'/libboundscheck.so','finite bounds');write(sdk+'/lib/'+r3Tuple+'/libcangjie-std-core.a','finite std');
 directSource(runtime);directBuild(runtime);
 const config=buildConfig({workspace,officialSdkRoot:host});installGcUnitInputs(config,runtime,sdk);
 const seed=root+'/native-input';fs.cpSync(sdk,seed,{recursive:true});write(seed+'/RUNTIME-INPUTS.json','{}');
 // Only build.py is controlled. Actual runBuildPy environment/command facts,
 // overlay, split/cache checks, provenance and language gate remain active.
 const record=String.raw`import os,sys,pathlib,json,shutil
r=pathlib.Path.cwd(); seed=pathlib.Path(os.environ['R3_SEED'])
with open(os.environ['R3_TRACE'],'a') as f: f.write(json.dumps(dict(cwd=str(r),argv=sys.argv,host=os.environ.get('CJCJ_OFFICIAL_SDK_ROOT'),ld=os.environ.get('LD_LIBRARY_PATH')))+'\n')
if os.environ.get('R3_CHILD_FAIL') and sys.argv[1]=='build': sys.exit(19)
`;
 write(runtime+'/build.py',record+String.raw`
if sys.argv[1]=='build':
 kind=sys.argv[sys.argv.index('-t')+1];out=r/'output/common'/('linux_'+kind+'_x86_64')
 for name in ['lib','runtime']: shutil.copytree(seed/name,out/name,dirs_exist_ok=True)
 p=r/'CMakebuild/gc-unit.status';p.parent.mkdir(parents=True,exist_ok=True)
 p.write_text('GATE=PASS\nGATE_RC=0\nCPP_SUITE=PASS\nLANGUAGE_TESTS=LANGUAGE_DEFERRED\n')
`);
 write(stdlib+'/build.py',record+String.raw`
if sys.argv[1]=='build':
 target=next(a.split('=',1)[1] for a in sys.argv if a.startswith('--target-lib='))
 assert (pathlib.Path(target)/'common/linux_relwithdebinfo_x86_64/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so').is_file(), 'finite runtime predecessor missing'
 p=r/'build/build/CMakeCache.txt';p.parent.mkdir(parents=True,exist_ok=True)
 p.write_text('RUNTIME_COMMON_LIB_DIR:STRING='+target+'\n')
if sys.argv[1]=='install':
 p=r/'output/modules/linux_x86_64_cjnative/std/std.core.cjo';p.parent.mkdir(parents=True,exist_ok=True);p.write_text('finite std artifact')
`);
 const snapshot=runtime+'/target/common/linux_relwithdebinfo_x86_64';
 for(const name of ['lib','runtime'])fs.cpSync(seed+'/'+name,snapshot+'/'+name,{recursive:true});
 const stale=root+'/stale-host/runtime/lib/'+r3Tuple;fs.mkdirSync(stale,{recursive:true});fs.copyFileSync(sdk+'/runtime/lib/'+r3Tuple+'/libcangjie-runtime.so',stale+'/libcangjie-runtime.so');
 const choices={};
 for(const name of ['compiler','runtime','tools','stdx','llvm','cjpm']){
  const repo=workspace+(name==='llvm'?'/cangjie_compiler/third_party/llvm-project':name==='cjpm'?'/cjpm-source':'/cangjie_'+name);
  write(repo+'/tracked','source '+name);write(repo+'/.gitignore','output/\nCMakebuild/\nstdlib/build/\nstdlib/output/\nruntime/target/\nruntime/output/\n');
  okay('git-init','git',['init','-q',repo]);okay('git-add','git',['-C',repo,'add','tracked','.gitignore']);
  okay('git-commit','git',['-C',repo,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','finite stage source']);
  choices[name]={url:'file://'+repo,tag:okay('git-head','git',['-C',repo,'rev-parse','HEAD']).stdout.trim()};
 }
 write(workspace+'/.source-selection.json',JSON.stringify(choices));
 fs.mkdirSync(workspace+'/software',{recursive:true});fs.symlinkSync('../cangjie_compiler/output',workspace+'/software/cangjie');
 const loader=root+'/boundaries.mjs';
 write(loader,`export async function load(url,context,next){const r=await next(url,context);const boundary=url.endsWith('/ci/bootstrap/sdk-flow.mjs')?'installProducts':url.endsWith('/build/lib/package-lineage.mjs')?'assertPackagedLineage':url.endsWith('/ci/bootstrap/sdk-verify-install.mjs')?'verifyInstall':url.endsWith('/ci/bootstrap/native-runtime-input.mjs')?'receiveNativeRuntime':null;if(!boundary)return r;let s=String(r.source);const re=new RegExp('export (async )?function '+boundary+'\\\\(');if(!re.test(s))throw Error('R3_BOUNDARY_SHAPE '+boundary);s=s.replace(re,(_,a='')=>a+'function ORIGINAL_'+boundary+'(');s+='\\nexport async function '+boundary+'(input){console.log("R3_CONTROLLED_BOUNDARY '+boundary+'");if('+JSON.stringify(boundary)+'==="receiveNativeRuntime")return {install:input.root};}';return {...r,source:s};}\n`);
 const base={...process.env,NODE_OPTIONS:'--experimental-loader='+loader,R3_SEED:seed,R3_TRACE:root+'/producer.jsonl',DIRECT_TRACE:root+'/language.jsonl',GC_UNIT_GATE_CONTRACT_SELFTEST:'1',GC_UNIT_GATE_SKIP:'0',MRT_TESTABLE_INTERNALS:'0'};
 for(const key of ['CJCJ_OFFICIAL_SDK_ROOT','CJCJ_SRCBUILD_CONSUMER_SDK','CJCJ_SRCBUILD_VERIFIER_REPORT_ACTIVE','CANGJIE_BUILD_DRY_RUN','CJCJ_NATIVE_RUNTIME_INSTALL','CJCJ_NATIVE_RUNTIME_SOURCE','CJCJ_NATIVE_SOURCE_SELECTION','CJCJ_NATIVE_RUNTIME_REF','CJCJ_NATIVE_LLVM_REF'])delete base[key];
 function invoke(stage,{mode='missing',explicit=true,selected=host,native=false,extra={}}={}) {
  const env={...base,...(mode==='conflict'?{CJCJ_OFFICIAL_SDK_ROOT:root+'/stale-host'}:mode==='same'?{CJCJ_OFFICIAL_SDK_ROOT:host}:{}),...extra};
  if(native)Object.assign(env,{CJCJ_NATIVE_RUNTIME_INSTALL:seed,CJCJ_NATIVE_RUNTIME_REF:choices.runtime.tag,CJCJ_NATIVE_LLVM_REF:choices.llvm.tag,CJCJ_NATIVE_HOST_VERSION:'1.0.0'});
  const args=[new URL('../cli.mjs',import.meta.url).pathname,'--workspace',workspace,'--build-root',root+'/buildtools',...(explicit?['--official-sdk-root',selected]:[]),...(stage==='verify'?['verify']:['build',stage])];
  return command(stage+'-'+mode+(native?'-native':''),process.execPath,args,env);
 }
 return {root,host,sdk,invoke,producer:()=>fs.existsSync(root+'/producer.jsonl')?fs.readFileSync(root+'/producer.jsonl','utf8').trim().split('\n').map(JSON.parse):[],language:()=>fs.existsSync(root+'/language.jsonl')?fs.readFileSync(root+'/language.jsonl','utf8').trim().split('\n').map(JSON.parse):[]};
}
for(const stage of ['runtime','stdlib','verify','native-runtime'])for(const mode of ['missing','conflict'])test('R3 public '+stage+' preserves explicit host with env '+mode,()=>{
 const f=r3Fixture(stage+'-'+mode),r=f.invoke(stage==='native-runtime'?'runtime':stage,{mode,native:stage==='native-runtime'});
 console.log('R3_REAL_STAGE_ASSERTION_REACHED '+stage+' '+mode+' rc='+r.status+' '+f.root);
 assert.equal(r.status,0,r.stdout+'\n'+r.stderr);
 assert.match(r.stdout,/RUNTIME_SPLIT_ASSERT_PASS host=0/);assert.ok(r.stdout.includes('path='+f.host+'/runtime/lib/'));
 for(const row of f.producer()){assert.equal(row.host,f.host);assert.ok(row.ld.includes(f.host+'/runtime/lib/'+r3Tuple));assert.ok(!row.ld.includes('/stale-host/'));}
 if(stage==='stdlib'||stage==='verify'){
  assert.deepEqual(f.language().map(row=>row.kind),['FINALIZER','PHASE']);
  for(const row of f.language())assert.equal(row.env.GC_UNIT_CJC_RUNTIME_LIB_DIR,f.host+'/runtime/lib/'+r3Tuple);
 }
});
test('R3 independent legacy environment entry still runs real split and preserves child failure rc',()=>{
 const f=r3Fixture('legacy-control');let r=f.invoke('stdlib',{mode:'same',explicit:false});assert.equal(r.status,0,r.stderr);assert.match(r.stdout,/RUNTIME_SPLIT_ASSERT_PASS host=0/);
 r=f.invoke('stdlib',{mode:'same',explicit:false,extra:{R3_CHILD_FAIL:'1'}});assert.equal(r.status,1,r.stderr);assert.match(r.stderr,/exit=19/);
 r=f.invoke('stdlib',{mode:'same',explicit:false});assert.equal(r.status,0,r.stderr);
 console.log('R3_LEGACY_CONTROL_AND_CHILD_RC_REACHED');
});
test('R3 selected invalid host remains rejected even when the environment host is valid',()=>{
 const f=r3Fixture('invalid-host'),r=f.invoke('stdlib',{mode:'same',selected:f.sdk});
 assert.equal(r.status,1,r.stderr);assert.match(r.stderr,/host=1.*target=1/);
 console.log('R3_INVALID_SELECTED_HOST_ASSERTION_REACHED '+f.root);
});
