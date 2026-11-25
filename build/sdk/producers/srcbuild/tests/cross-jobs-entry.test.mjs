import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {writeFileSync} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import {crossBuildJobs} from '../lib/cross-build-jobs.mjs';
import {load as yaml} from '../../../../../ci/vendor/js-yaml/js-yaml.mjs';
import {archiveInstall, fileDigest} from '../../../../../ci/bootstrap/sdk-flow.mjs';
import {CROSS_STD_BUILDS, getTarget} from '../../../../lib/targets.mjs';
import {installCompiler} from '../../../../../ci/fixtures/compiler-install.mjs';
const root=process.env.CROSS_JOBS_EVIDENCE;
if(!root||!process.env.ZX)throw Error('CROSS_JOBS_INPUTS');
await fs.mkdir(root,{recursive:true});
const calls=[];
function run(label,argv,options={}){
 const r=spawnSync(argv[0],argv.slice(1),{encoding:'utf8',timeout:60000,maxBuffer:4*1024**2,...options});
 calls.push({label,argv,cwd:options.cwd??process.cwd(),rc:r.status,signal:r.signal,error:r.error?.message});
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
 print('CROSS_STD_CHILD_REACHED',flush=True);sys.exit(0 if os.environ.get('IOS_FINITE_STD') else 37)
if args[0]=='install' and kind=='stdlib' and os.environ.get('IOS_FINITE_STD'):
 root=p(arg('--prefix'));t=os.environ['CROSS_STD_TUPLE']
 for sub,name in [('modules/'+t+'/std','std.core.cjo'),('lib/'+t,'libcangjie-std-core.a'),('runtime/lib/'+t,'libcangjie-std-core.dylib')]:
  (root/sub).mkdir(parents=True);(root/sub/name).write_text('finite std fixture: '+t+'/'+name)
 sys.exit(0)
if kind=='runtime' and (os.environ.get('CROSS_STD_TUPLE') or '').startswith('ios_'):
 tuple=os.environ['CROSS_STD_TUPLE'];arch='x86_64' if 'x86_64' in tuple else 'aarch64'
 def macho(name):
  original=os.environ.get('IOS_REPLAY_INSTALL')
  if original:return (p(original)/'runtime/lib'/tuple/name).read_bytes()
  ident=b'@rpath/'+name.encode()+b'\0';size=(24+len(ident)+7)//8*8
  cmds=struct.pack('<6I',13,size,24,0,0,0)+ident.ljust(size-24,b'\0')+struct.pack('<6I',50,24,7 if 'simulator' in tuple else 2,0,0,0)
  return struct.pack('<8I',0xfeedfacf,0x01000007 if arch=='x86_64' else 0x0100000c,0,6,2,len(cmds),0,0)+cmds
 if args[0]=='build':
  built=p('CMakebuild/runtime-staging/lib')/(arch+'_Release');built.mkdir(parents=True,exist_ok=True)
  for name in ['libboundscheck.dylib','libcangjie-runtime.dylib']:(built/name).write_bytes(macho(name))
  print('CROSS_RUNTIME_CHILD_REACHED',flush=True)
 if args[0]=='install':
  root=p(arg('--prefix'));lib=root/'runtime/lib'/tuple;lib.mkdir(parents=True,exist_ok=True)
  objects=root/'lib'/tuple;objects.mkdir(parents=True,exist_ok=True)
  (lib/'libcangjie-runtime.dylib').write_bytes(macho('libcangjie-runtime.dylib'));(objects/'cjstart.o').write_text('finite object fixture')
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
 const env={...process.env,CANGJIE_WORKSPACE:work,CJCJ_BOOTSTRAP_WORK:work+'/native-bootstrap',CJCJ_NATIVE_RUNTIME_REF:ref,RUNTIME_SRC_URL:repo,RUNTIME_VERSION:'1.3.0-fixture',CJCJ_STAGE3_CANGJIE_VERSION:'1.3.0-fixture',
  ANDROID_NDK_ROOT:ndk,OHOS_SDK_HOME:ohos,CROSS_COMMAND_LOG:work+'/children.jsonl',CANGJIE_BUILD_JOBS:'2',STD_BUILD_JOBS:'1',CMAKE_BUILD_PARALLEL_LEVEL:'4',PYTHONDONTWRITEBYTECODE:'1'};
 if(ios){
  // Explicit platform/command fixture on Linux; no Darwin or iOS execution claim.
  const bin=work+'/fixture-bin';await fs.mkdir(bin,{recursive:true});
  const preload=work+'/darwin-fixture.mjs';
  await fs.writeFile(preload,"Object.defineProperty(process,'platform',{value:'darwin'});Object.defineProperty(process,'arch',{value:'arm64'});\n");
  await fs.writeFile(bin+'/xcrun','#!'+process.execPath+'\nconsole.log(process.argv.includes("--find")?'+JSON.stringify(bin+'/clang')+':'+JSON.stringify(work+'/fixture-sysroot')+');\n',{mode:0o755});
  await fs.writeFile(bin+'/lipo','#!'+process.execPath+'\nconsole.log(process.env.CROSS_STD_TUPLE.includes("x86_64")?"x86_64":"arm64");\n',{mode:0o755});
  Object.assign(env,{NODE_OPTIONS:'--import='+pathToFileURL(preload).href,PATH:bin+path.delimiter+env.PATH});
 }
 const invoke=(name,extra={})=>run(label+'-'+name,[process.env.ZX,path.resolve('build/sdk/producers/srcbuild/steps/build-'+name+'.mjs')],{env:{...env,...extra}});
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
  const f=await fixture(family+'-'+arch);
  if (family === 'android') {
   // The std entry inspects the preceding Android AST archive with the NDK reader.
   const work=f.env.CANGJIE_WORKSPACE, bin=path.join(f.env.ANDROID_NDK_ROOT,'toolchains/llvm/prebuilt/linux-x86_64/bin');
   const lib=path.join(work,'software/android-ast-support/lib/linux_android_aarch64_cjnative');
   await fs.mkdir(bin,{recursive:true});await fs.mkdir(lib,{recursive:true});
   const reader=run('android-ast-reader',['which','llvm-readelf']);assert.equal(reader.status,0,reader.stderr);
   await fs.symlink(reader.stdout.trim(),path.join(bin,'llvm-readelf'));
   const object=path.join(work,'fixture.o');
   const cc=run('android-ast-object',['clang','--target=aarch64-linux-android23','-x','c','-c','-','-o',object],{input:'int fixture;'});
   assert.equal(cc.status,0,cc.stderr);
   const ar=run('android-ast-archive',['ar','rcs',path.join(lib,'libcangjie-ast-support.a'),object]);assert.equal(ar.status,0,ar.stderr);
  }
  const r=f.invoke(family+'-final-std',{CROSS_STD_TUPLE:'linux_'+family+'_'+arch+'_cjnative'});
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

// The stage2 compiler and Xcode commands are finite stand-ins. Production JS
// owns checkout, build/install argv, artifact layout, assembly and reception.
test('source-ios products enter the same SDK that compose receives after relocation', async () => {
  const workflow = async name => yaml(await fs.readFile(new URL('../../../../../.github/workflows/' + name, import.meta.url), 'utf8'));
  const {jobs} = await workflow('sdk-build-target.yml');
  const source = jobs['source-ios'], packaging = jobs.srcbuild;
  const step = (job, match) => job.steps.find(s => s.run?.includes(match));
  const upload = source.steps.find(s => s.uses?.startsWith('actions/upload-artifact@'));
  const download = packaging.steps.find(s => s.with?.pattern === 'final-std-ios-*');
  const installation = step(packaging, 'install-ios-final-std.mjs');
  assert.ok(packaging.needs.includes('source-ios') && packaging.if.includes("needs.source-ios.result == 'success'"));
  assert.equal(installation.if, upload.if);
  assert.equal(download.if, installation.if);
  assert.equal(download.with.path, installation.env.IOS_ARTIFACT_DIR);
  assert.ok(packaging.steps.indexOf(download) < packaging.steps.indexOf(installation));
  assert.ok(packaging.steps.indexOf(installation) < packaging.steps.indexOf(step(packaging, 'steps/package-install.mjs')));
  const caller = (await workflow('release.yml')).jobs.package;
  const recipe = caller.strategy.matrix.include.find(row => row.release_key === 'darwin-arm64-ios');
  const selected = JSON.parse(recipe.cross_std_artifacts);
  const entry = command => path.resolve(command.split(' ').at(-1));
  const f = await fixture('ios product transport', {ios: true});
  const work = f.env.CANGJIE_WORKSPACE;
  const receive = path.join(work, 'runner temp');
  const artifacts = download.with.path.replace('${{ runner.temp }}', receive);
  const sdk = path.join(work, 'software', 'cangjie');
  const runtimeRef = f.env.CJCJ_NATIVE_RUNTIME_REF;
  const sourceSha = 'c'.repeat(40);
  const pack = step(jobs['source-stage3'], 'ios-stage2-handoff.mjs pack');
  const restore = step(source, 'ios-stage2-handoff.mjs restore');
  const stageUpload = jobs['source-stage3'].steps.find(s => s.with?.name?.startsWith('source-ios-stage2-'));
  const stageDownload = source.steps.find(s => s.with?.name === stageUpload.with.name);
  const location = value => value.replace('${{ runner.temp }}', receive);
  const shared = {RUNNER_TEMP:receive,GITHUB_SHA:sourceSha,GITHUB_RUN_ID:'1001',CJCJ_SRCBUILD_TARGET:recipe.platform};
  const handoff = (label, command, env) => run(label,['bash','-eu','-c',command.run],{env:{...f.env,...shared,...env}});
  const packed = handoff('stage2-pack', pack, {SOURCE_SDK_VERSION:f.env.CJCJ_STAGE3_CANGJIE_VERSION});
  assert.equal(packed.status,0,packed.stderr);
  const received = location(stageDownload.with.path);
  await fs.cp(location(stageUpload.with.path),received,{recursive:true});
  const entries = run('stage2-list',['tar','-tzf',path.join(received,'sdk-stage2.tar.gz')]);
  assert.equal(entries.status,0,entries.stderr);
  assert.ok(entries.stdout.split('\n').filter(Boolean).every(name => name.startsWith('sdk-stage2/')));
  assert.doesNotMatch(entries.stdout,/(^|\/)\.git\//m);
  await fs.rename(f.env.CJCJ_BOOTSTRAP_WORK,f.env.CJCJ_BOOTSTRAP_WORK+'-unavailable');
  const moved = path.join(work,'relocated workspace');
  const stageEnv = path.join(receive,'stage-env');
  const restoreEnv = {CANGJIE_WORKSPACE:path.relative(process.cwd(),moved),GITHUB_ENV:stageEnv};
  const wrongRun = handoff('stage2-wrong-run',restore,{...restoreEnv,GITHUB_RUN_ID:'1002'});
  assert.equal(wrongRun.status,1);assert.match(wrongRun.stderr,/IOS_STAGE2_IDENTITY run/);
  const stageArchive = path.join(received,'sdk-stage2.tar.gz');
  await fs.appendFile(stageArchive,'transport changed');
  const broken = handoff('stage2-corrupt',restore,restoreEnv);
  assert.equal(broken.status,1);assert.match(broken.stderr,/IOS_STAGE2_ARCHIVE_BYTES/);
  await assert.rejects(fs.stat(stageEnv),{code:'ENOENT'});
  await fs.copyFile(path.join(location(stageUpload.with.path),'sdk-stage2.tar.gz'),stageArchive);
  const restored = handoff('stage2-restore',restore,restoreEnv);
  assert.equal(restored.status,0,restored.stderr);
  const sdkVersion = (await fs.readFile(stageEnv,'utf8')).trim().split('=')[1];
  assert.equal(sdkVersion,f.env.CJCJ_STAGE3_CANGJIE_VERSION);
  for (const target of CROSS_STD_BUILDS.filter(t => t.family === 'ios')) {
    const original = process.env.IOS_REPLAY_ARTIFACTS;
    const replay = original && path.join(original, target.runtime_target, 'x/ios-source/cangjie_runtime/runtime-install');
    const result = run('produce-'+target.tuple, [process.env.ZX, entry(step(source, 'build-ios-final-std.mjs').run)], {
      env: {...f.env, CANGJIE_WORKSPACE:moved, CJCJ_BOOTSTRAP_WORK:path.join(moved,'native-bootstrap'),
        CJCJ_STAGE3_CANGJIE_VERSION:sdkVersion, CROSS_STD_TUPLE:target.tuple, IOS_FINITE_STD:'1',
        ...(replay && {IOS_REPLAY_INSTALL:replay})}});
    assert.equal(result.status, 0, result.stderr);
    const name = upload.with.name.replace('${{ matrix.artifact }}', target.artifact);
    assert.ok(selected.some(row => row.artifact === name && row.tuple === target.tuple));
    const product = upload.with.path.replace('${{ env.CANGJIE_WORKSPACE }}', moved).replace('${{ matrix.artifact }}', name);
    // Local file transport in place of the two Actions. No source tree is copied.
    await fs.cp(product, path.join(artifacts, name), {recursive: true});
  }
  await fs.mkdir(sdk, {recursive:true});
  const facts = {phase:'stage3',platform:'darwin_aarch64',runtimeCommit:runtimeRef,compilerCommit:sourceSha};
  await fs.writeFile(path.join(sdk,'STAGE-INPUTS.json'), JSON.stringify(facts));
  const host = path.join(sdk, 'modules/darwin_aarch64_cjnative/std/host.cjo');
  await fs.mkdir(path.dirname(host), {recursive:true}); await fs.writeFile(host, 'independent host control');
  const install = label => run(label, [process.execPath,entry(installation.run)], {env:{...process.env,
    CJCJ_SRCBUILD_TARGET:recipe.platform, CANGJIE_WORKSPACE:work, CJCJ_NATIVE_RUNTIME_REF:runtimeRef, IOS_ARTIFACT_DIR:artifacts}});
  const first = install('install-first'); assert.equal(first.status,0,first.stderr);
  const [{tuple,artifact}] = selected;
  const stale = path.join(sdk,'lib',tuple,'obsolete.a');
  await fs.writeFile(stale,'old SDK'); const again = install('install-restored-sdk');
  assert.equal(again.status,0,again.stderr); await assert.rejects(fs.stat(stale), {code:'ENOENT'});
  const bad = path.join(artifacts,artifact,'ios-build.json');
  const good = await fs.readFile(bad,'utf8');
  await fs.writeFile(bad, JSON.stringify({...JSON.parse(good),runtimeRef:'0'.repeat(40)}));
  const rejected = install('install-wrong-std-ref');
  assert.equal(rejected.status,1); assert.match(rejected.stderr,/IOS_FINAL_STD_IDENTITY/);
  await fs.writeFile(bad,good);
  assert.equal(await fs.readFile(host,'utf8'),'independent host control');
  const version='fixture', archiveDir=path.join(work,'sdk artifact');
  const sdkUpload = packaging.steps.find(s => s.with?.name?.startsWith('cjcj-srcbuild-'));
  const uploadPaths = sdkUpload.with.path.trim().split('\n').map(line => line
    .replace('${{ env.CANGJIE_WORKSPACE }}',work)
    .replace('*',getTarget(recipe.platform).spec.sdkName)
    .replace('${{ steps.version.outputs.value }}',version));
  assert.equal(uploadPaths.length,2);
  assert.equal(uploadPaths[1],uploadPaths[0]+'.sha256');
  assert.equal(path.dirname(uploadPaths[0]),path.dirname(sdk));
  const archive = uploadPaths[0];
  // Archive facts are test data; this fixture contains no executable host SDK.
  await fs.writeFile(path.join(sdk,'BUILD-MANIFEST.json'),JSON.stringify({target:recipe.platform,version,
    consumption:{status:'EXECUTED',platform:facts.platform}}));
  await archiveInstall({install:sdk,archive,test:{required:selected.flatMap(({tuple})=>[
    'modules/'+tuple+'/std/std.core.cjo','lib/'+tuple+'/libcangjie-std-core.a','runtime/lib/'+tuple+'/libboundscheck.dylib'])},vars:{}});
  await fs.rename(sdk,sdk+'-unavailable');
  await fs.mkdir(archiveDir);
  for (const file of uploadPaths) await fs.copyFile(file,path.join(archiveDir,path.basename(file)));
  const compose = entry(step((await workflow(path.basename(caller.uses))).jobs.package, 'compose-package.mjs').run);
  const consume = label => run(label,[process.execPath,compose],{env:{...process.env,
    NATIVE_SDK_ARTIFACT_DIR:archiveDir,NATIVE_SDK_INSTALL_DIR:path.join(work,'received '+label),RELEASE_PLATFORM:recipe.platform,
    CJCJ_NATIVE_SDK_VERSION:version,CJCJ_RELEASE_SOURCE_SHA:sourceSha,CJCJ_NATIVE_RUNTIME_REF:runtimeRef,
    FINAL_STD_DIR:path.relative(process.cwd(),path.join(work,'host std')),RELEASE_DIST:path.join(work,'dist '+label),RELEASE_KEY:recipe.release_key,
    CROSS_STD_ARTIFACTS:recipe.cross_std_artifacts,CROSS_STD_DIR:path.relative(process.cwd(),artifacts)}});
  const checkCross = result => {
    assert.equal(result.status,1);
    assert.ok(result.stdout.includes('NATIVE_RELEASE_CROSS_VERIFIED '+selected.map(row=>row.tuple).join(',')),result.stderr);
    assert.match(result.stderr,/ENOENT.*TOOLS-INPUTS.json/);
  };
  checkCross(consume('compose-good'));
  const reference=path.join(artifacts,artifact,'cross-runtime');
  const bounds='runtime/lib/'+tuple+'/libboundscheck.dylib';
  const file=path.join(reference,bounds), manifest=path.join(reference,'CROSS-RUNTIME.json');
  const bytes=await fs.readFile(file), originalManifest=await fs.readFile(manifest);
  // The hash matches the changed payload. Only its dylib identity is wrong.
  await fs.copyFile(path.join(path.dirname(file),'libcangjie-runtime.dylib'),file);
  const record=JSON.parse(originalManifest);record.files.find(row=>row.path===bounds).sha256=await fileDigest(file);
  await fs.writeFile(manifest,JSON.stringify(record));
  const wrong=consume('compose-wrong-id');assert.equal(wrong.status,1);
  assert.match(wrong.stderr,/install name @rpath\/libcangjie-runtime.dylib is not @rpath\/libboundscheck.dylib/);
  const simulator = selected.find(row => row.tuple === 'ios_simulator_aarch64_cjnative');
  await fs.copyFile(path.join(artifacts,simulator.artifact,'cross-runtime/runtime/lib',simulator.tuple,'libboundscheck.dylib'),file);
  record.files.find(row=>row.path===bounds).sha256=await fileDigest(file);
  await fs.writeFile(manifest,JSON.stringify(record));
  const swapped=consume('compose-wrong-platform');assert.equal(swapped.status,1);
  assert.match(swapped.stderr,/targets iossimulator, not ios for/);
  await fs.writeFile(file,bytes); await fs.writeFile(manifest,originalManifest);
  checkCross(consume('compose-restored'));
});
