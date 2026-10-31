import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {writeFileSync} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {spawnSync} from 'node:child_process';
import {crossBuildJobs} from '../lib/cross-build-jobs.mjs';
import {CROSS_STD_BUILDS} from '../../../build/lib/targets.mjs';
import {installCompiler} from '../../fixtures/compiler-install.mjs';
const root=process.env.CROSS_JOBS_EVIDENCE;
if(!root||!process.env.ZX)throw Error('CROSS_JOBS_INPUTS');
await fs.mkdir(root,{recursive:true});
const calls=[];
function run(label,argv,options={}){
 const r=spawnSync(argv[0],argv.slice(1),{encoding:'utf8',timeout:60000,maxBuffer:4*1024**2,...options});
 calls.push({label,argv,rc:r.status,signal:r.signal,error:r.error?.message});
 writeFileSync(root+'/'+label+'.stdout',r.stdout||'');writeFileSync(root+'/'+label+'.stderr',r.stderr||'');
 writeFileSync(root+'/commands.json',JSON.stringify(calls,null,2));return r;
}
// This Python command fixture is deliberately not runtime or std production.
// The real public JS CLI, source identity, installer and subprocess argv run.
const python=String.raw`import sys,os,json,pathlib,struct
p=pathlib.Path;args=sys.argv[1:];kind=p.cwd().name
def arg(flag,default=None):
 return args[args.index(flag)+1] if flag in args else default
with open(os.environ['CROSS_COMMAND_LOG'],'a') as f:f.write(json.dumps(dict(kind=kind,args=args,jobs=os.environ.get('CANGJIE_BUILD_JOBS')))+'\n')
if args[0]=='build' and kind=='stdlib':
 print('CROSS_STD_CHILD_REACHED',flush=True);sys.exit(37)
if kind=='runtime' and (os.environ.get('CROSS_STD_TUPLE') or '').startswith('ios_'):
 tuple=os.environ['CROSS_STD_TUPLE'];arch='x86_64' if 'x86_64' in tuple else 'aarch64'
 macho=bytearray(64);struct.pack_into('<I',macho,0,0xfeedfacf);struct.pack_into('<I',macho,4,0x01000007 if arch=='x86_64' else 0x0100000c);struct.pack_into('<I',macho,12,6)
 if args[0]=='build':
  built=p('CMakebuild/runtime-staging/lib')/(arch+'_Release');built.mkdir(parents=True,exist_ok=True)
  (built/'libboundscheck.dylib').write_bytes(macho)
  print('CROSS_RUNTIME_CHILD_REACHED',flush=True)
 if args[0]=='install':
  root=p(arg('--prefix'));lib=root/'runtime/lib'/tuple;lib.mkdir(parents=True,exist_ok=True)
  objects=root/'lib'/tuple;objects.mkdir(parents=True,exist_ok=True)
  (lib/'libcangjie-runtime.dylib').write_bytes(macho);(objects/'cjstart.o').write_text('finite object fixture')
 sys.exit(0)
if kind=='runtime' and args[0]=='build':
 target=arg('--target');family,arch=target.split('-',1);tuple='linux_'+family+'_'+arch+'_cjnative'
 base=p('output/common')/('linux_'+family+'_release_'+arch)
 lib=base/'runtime/lib'/tuple;lib.mkdir(parents=True,exist_ok=True)
 objects=base/'lib'/tuple;objects.mkdir(parents=True,exist_ok=True)
 elf=bytearray(32);elf[:6]=bytes.fromhex('7f454c460201');struct.pack_into('<H',elf,18,183 if arch=='aarch64' else 62)
 (lib/'libcangjie-runtime.so').write_bytes(elf)
 (objects/'cjstart.o').write_text('explicit nonproduction object fixture')
 built=p('CMakebuild/runtime-staging/lib')/(arch+'_Release');built.mkdir(parents=True,exist_ok=True)
 (built/'libboundscheck.so').write_bytes(elf)
 print('CROSS_RUNTIME_CHILD_REACHED',flush=True)
`;
async function fixture(label,{ios=false}={}){
 const work=root+'/'+label,repo=work+'/cangjie_runtime',sdk=work+'/native-bootstrap/sdk-stage2';
 for(const rel of ['runtime','stdlib']){await fs.mkdir(repo+'/'+rel,{recursive:true});await fs.writeFile(repo+'/'+rel+'/build.py',python);}
 for(const [name,args]of [['init',['init','-q']],['add',['add','.']],['commit',['-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','Finite cross entry fixture']]])
  assert.equal(run(label+'-'+name,['git','-C',repo,...args]).status,0);
 const ref=run(label+'-head',['git','-C',repo,'rev-parse','HEAD']).stdout.trim();
 await fs.mkdir(sdk+'/bin',{recursive:true});
 const bytes=ios?Buffer.alloc(64):Buffer.from('explicit nonexecuted compiler fixture\n');
 if(ios){bytes.writeUInt32LE(0xfeedfacf,0);bytes.writeUInt32LE(0x0100000c,4);bytes.writeUInt32LE(2,12);}
 const product=work+'/finite-compiler';
 await fs.writeFile(product,bytes,{mode:0o755});
 const installed=await installCompiler(sdk,product);
 await fs.writeFile(sdk+'/STAGE-INPUTS.json',JSON.stringify({...installed,phase:'stage2',platform:ios?'darwin_aarch64':'linux_x86_64',runtimeCommit:ref}));
 // Finite transport fixture: these required files are not executable SDK products.
 for(const relative of ['lib/'+(ios?'darwin_aarch64':'linux_x86_64')+'_cjnative/libcangjie-ast-support.a','schema/StdAstFormat.fbs','include/flatbuffers/StdAstFormat_generated.h','third_party/flatbuffers/bin/flatc']){
  const file=path.join(sdk,relative);await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,'finite cross argument transport input\n');
 }
 const ndk=work+'/ndk',ohos=work+'/ohos';
 await fs.mkdir(ndk+'/toolchains/llvm/prebuilt',{recursive:true});await fs.mkdir(ohos+'/native/llvm/bin',{recursive:true});
 const env={...process.env,CANGJIE_WORKSPACE:work,CJCJ_BOOTSTRAP_WORK:work+'/native-bootstrap',CJCJ_NATIVE_RUNTIME_REF:ref,RUNTIME_VERSION:'1.3.0-fixture',CJCJ_STAGE3_CANGJIE_VERSION:'1.3.0-fixture',
  ANDROID_NDK_ROOT:ndk,OHOS_SDK_HOME:ohos,CROSS_COMMAND_LOG:work+'/children.jsonl',CANGJIE_BUILD_JOBS:'2',STD_BUILD_JOBS:'1',CMAKE_BUILD_PARALLEL_LEVEL:'4',PYTHONDONTWRITEBYTECODE:'1'};
 if(ios){
  // Explicit platform/command fixture on Linux; no Darwin or iOS execution claim.
  const bin=work+'/fixture-bin';await fs.mkdir(bin,{recursive:true});
  const preload=work+'/darwin-fixture.mjs';
  await fs.writeFile(preload,"Object.defineProperty(process,'platform',{value:'darwin'});Object.defineProperty(process,'arch',{value:'arm64'});\n");
  await fs.writeFile(bin+'/xcrun','#!'+process.execPath+'\nconsole.log(process.argv.includes("--find")?'+JSON.stringify(bin+'/clang')+':'+JSON.stringify(work+'/fixture-sysroot')+');\n',{mode:0o755});
  Object.assign(env,{NODE_OPTIONS:'--import='+preload,PATH:bin+path.delimiter+env.PATH});
 }
 const invoke=(name,extra={})=>run(label+'-'+name,[process.env.ZX,path.resolve('ci/srcbuild/steps/build-'+name+'.mjs')],{env:{...env,...extra}});
 const records=async()=>((await fs.readFile(env.CROSS_COMMAND_LOG,'utf8')).trim().split('\n').map(line=>JSON.parse(line)));
 return {env,invoke,records};
}
test('public Android runtime CLI passes the admitted jobs to the real child process',async()=>{
 const jobs=String(os.availableParallelism()+1);
 const f=await fixture('runtime'),r=f.invoke('android-runtime',{CANGJIE_BUILD_JOBS:undefined,CMAKE_BUILD_PARALLEL_LEVEL:jobs});
 assert.equal(r.status,0,r.stderr);assert.match(r.stdout,/CROSS_RUNTIME_CHILD_REACHED/);
 const row=(await f.records()).find(r=>r.kind==='runtime'&&r.args[0]==='build');
 console.log('CROSS_RUNTIME_JOBS_ASSERTION_REACHED');assert.equal(row.jobs,jobs);
});
test('public Android and both OHOS std entries keep independent runtime and std jobs',async()=>{
 for(const [family,arch]of [['android','aarch64'],['ohos','aarch64'],['ohos','x86_64']]){
  const f=await fixture(family+'-'+arch),r=f.invoke(family+'-final-std',{CROSS_STD_TUPLE:'linux_'+family+'_'+arch+'_cjnative'});
  assert.equal(r.status,1,r.stderr);assert.match(r.stderr,/exit code: 37/);assert.match(r.stdout,/CROSS_STD_CHILD_REACHED/);
  const rows=await f.records();console.log('CROSS_STD_JOBS_ASSERTION_REACHED '+family+' '+arch);
  for(const [kind,jobs]of [['runtime','2'],['stdlib','1']]){
   const row=rows.find(r=>r.kind===kind&&r.args[0]==='build');assert.equal(kind==='runtime'?row.jobs:row.args[row.args.indexOf('-j')+1],jobs);
  }
 }
});
test('resource selection rejects invalid budgets and preserves distinct std selection',()=>{
 assert.equal(crossBuildJobs({CANGJIE_BUILD_JOBS:'99999'}),99999);
 assert.equal(crossBuildJobs({CMAKE_BUILD_PARALLEL_LEVEL:''}),os.availableParallelism());
 assert.equal(crossBuildJobs({CANGJIE_BUILD_JOBS:'2',STD_BUILD_JOBS:'1'},'std'),1);
 assert.equal(crossBuildJobs({CANGJIE_BUILD_JOBS:'2',STD_BUILD_JOBS:'1'}),2);
 for(const value of ['0','-1','1.5','bad','9007199254740992'])assert.throws(()=>crossBuildJobs({CANGJIE_BUILD_JOBS:value}),/CROSS_BUILD_JOBS/);
});
test('public runtime entry still rejects the wrong fixed source before build',async()=>{
 const f=await fixture('wrong-source'),r=f.invoke('android-runtime',{CJCJ_NATIVE_RUNTIME_REF:'a'.repeat(40)});
 assert.notEqual(r.status,0);assert.match(r.stderr,/runtime source mismatch/);
 assert.equal(await fs.stat(f.env.CROSS_COMMAND_LOG).catch(()=>null),null);
});

test('public iOS caller consumes its installed Darwin compiler and AST inputs before std',async()=>{
 for(const target of CROSS_STD_BUILDS.filter(row=>row.family==='ios')){
 const f=await fixture('ios-entry-'+target.tuple,{ios:true});
 const r=f.invoke('ios-final-std',{CROSS_STD_TUPLE:target.tuple});
 assert.equal(r.status,1,r.stderr);assert.match(r.stderr,/exit code: 37/);
 assert.match(r.stdout,/CROSS_STD_CHILD_REACHED/);
 const rows=await f.records(),runtime=rows.find(x=>x.kind==='runtime'&&x.args[0]==='build'),std=rows.find(x=>x.kind==='stdlib'&&x.args[0]==='build');
 console.log('IOS_INSTALLED_INPUT_AND_JOBS_ASSERTION_REACHED '+target.tuple);
 assert.equal(runtime.jobs,'2');assert.equal(std.args[std.args.indexOf('-j')+1],'1');
 assert.equal(std.args[std.args.indexOf('--target')+1],target.runtime_target);
 }
});
