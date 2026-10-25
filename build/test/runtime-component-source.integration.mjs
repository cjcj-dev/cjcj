#!/usr/bin/env zx
// Actual fixed source -> native C pair -> public build/install/archive -> public
// configure/receive/reuse. CPP, H1/AST/LLVM payloads are explicit finite boundaries.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {hostToolchainFromCjcVersion} from '../../ci/host-toolchain-pin.mjs';
import {buildConfig} from '../lib/config.mjs';
const repo=new URL('../../',import.meta.url).pathname;
const base=process.env.RELEASE_EVIDENCE_TEST_ROOT,generator=process.env.CJCJ_TEST_RUNTIME_GENERATOR,host=process.env.CJCJ_SRCBUILD_HOST_SDK;
if(!base||!generator||!host)throw Error('runtime component test requires evidence root, original generator and complete private host');
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const write=async(file,data)=>{await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,data);};
const hostVersion=spawnSync(path.join(host,'bin/cjc'),['--version'],{encoding:'utf8'});
assert.equal(hostVersion.status,0,hostVersion.stderr);
const platform='linux_x86_64',tuple=platform+'_cjnative',version=hostToolchainFromCjcVersion(hostVersion.stdout).replace(/^nightly-/,'');
const shared='runtime/lib/'+tuple+'/libcangjie-runtime.so',archive='lib/'+tuple+'/libcangjie-runtime.a';
for(const mode of ['archive','clean','archive-wrapper'])test(`formal native ${mode} producer facts survive unavailable source and configure/receive relocation`,async()=>{
 await fs.mkdir(base,{recursive:true});const root=await fs.mkdtemp(path.join(base,'runtime-formal-'+mode+'-'));
 const objects=root+'/objects',materialized=root+'/materialized',records=[];
 const run=async(label,argv,env={},expected=0)=>{
  const p=spawnSync(argv[0],argv.slice(1),{cwd:repo,env:{...process.env,...env},encoding:'utf8',maxBuffer:16*1024*1024});
  records.push({label,argv,env,rc:p.status,signal:p.signal,stdout:p.stdout,stderr:p.stderr});
  await write(root+'/commands.json',JSON.stringify(records,null,2));
  assert.equal(p.status,expected,label+' '+p.stdout+'\n'+p.stderr);return p;
 };
 await write(objects+'/runtime/src/mask.c','unsigned long g_cjLoadBadMask = 42;\n');
 await write(objects+'/runtime/src/bounds.c','int fixture_bounds(void) { return 42; }\n');
 await write(objects+'/runtime/build/cmake/GenerateRuntimeProvenance.cmake',await fs.readFile(generator));
 await write(objects+'/runtime/CMakeLists.txt','# finite native pair, not the real runtime CPP suite\n');
 await write(objects+'/packages/macro/src/InvokeUtil.cj',await fs.readFile(repo+'packages/macro/src/InvokeUtil.cj'));
 await write(objects+'/runtime/build.py',String.raw`import os,sys,pathlib,subprocess,shutil
r=pathlib.Path.cwd(); b=r/'CMakebuild'; b.mkdir(exist_ok=True)
def run(args): subprocess.run([str(x) for x in args],check=True)
if sys.argv[1]=='build':
 run(['cmake','-DREPOSITORY_DIR='+str(r.parent),'-DSOURCE_DIR='+str(r),'-DOUTPUT_FILE='+str(b/'RuntimeProvenance.cpp'),'-DCOMMIT_OVERRIDE=','-P',r/'build/cmake/GenerateRuntimeProvenance.cmake'])
 run(['c++','-fPIC','-c',b/'RuntimeProvenance.cpp','-o',b/'provenance.o'])
 run(['cc','-fPIC','-c',r/'src/mask.c','-o',b/'mask.o'])
 run(['c++','-shared',b/'provenance.o',b/'mask.o','-o',b/'libcangjie-runtime.so'])
 run(['ar','rcs',b/'libcangjie-runtime.a',b/'provenance.o',b/'mask.o'])
 d=b/'runtime-staging/lib/x86_64_Release';d.mkdir(parents=True,exist_ok=True)
 run(['cc','-shared','-fPIC',r/'src/bounds.c','-o',d/'libboundscheck.so'])
 cache=['CANGJIE_COMPILER_CACHE:STRING='+os.environ['SCCACHE_PATH']]
 if os.environ.get('FINITE_CACHE_WRAPPER'):
  for language,name in [('C','clang'),('CXX','clang++')]:
   wrapper=b/name;wrapper.symlink_to(os.environ['SCCACHE_PATH'])
   cache.append('CMAKE_'+language+'_COMPILER:FILEPATH='+str(wrapper))
 else:
  cache += [k+':STRING='+os.environ['SCCACHE_PATH'] for k in ['CMAKE_C_COMPILER_LAUNCHER','CMAKE_CXX_COMPILER_LAUNCHER']]
 (b/'CMakeCache.txt').write_text('\n'.join(cache)+'\n')
else:
 p=pathlib.Path(sys.argv[sys.argv.index('--prefix')+1]);t='linux_x86_64_cjnative'
 for src,dst in [(b/'libcangjie-runtime.so',p/'runtime/lib'/t/'libcangjie-runtime.so'),(b/'libcangjie-runtime.a',p/'lib'/t/'libcangjie-runtime.a')]:
  dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
`);
 // Explicit C consumer for the legacy stdlib invocation; not Cangjie std.
 await write(objects+'/stdlib/build.py',String.raw`import os,sys,pathlib,subprocess
r=pathlib.Path.cwd()
if sys.argv[1]=='build':
 target=pathlib.Path(next(x.split('=',1)[1] for x in sys.argv if x.startswith('--target-lib=')))
 kind=sys.argv[sys.argv.index('-t')+1];t='linux_x86_64_cjnative';lib=target/('common/linux_'+kind+'_x86_64')/'runtime/lib'/t
 assert (lib/'libcangjie-runtime.so').is_file(), 'LEGACY_RUNTIME_SNAPSHOT_REQUIRED'
 b=r/'build/build';b.mkdir(parents=True,exist_ok=True)
 (b/'CMakeCache.txt').write_text('RUNTIME_COMMON_LIB_DIR:STRING='+str(lib)+'\n')
 (b/'consumer.c').write_text('#include <stdio.h>\nextern unsigned long g_cjLoadBadMask;int main(void){printf("LEGACY_NATIVE_VALUE=%lu\\n",g_cjLoadBadMask);return g_cjLoadBadMask!=42;}\n')
 subprocess.run(['cc',str(b/'consumer.c'),'-L'+str(lib),'-lcangjie-runtime','-Wl,-rpath,'+str(lib),'-o',str(b/'consumer')],check=True)
 subprocess.run([str(b/'consumer')],env={**os.environ,'LD_LIBRARY_PATH':str(lib)},check=True)
if sys.argv[1]=='install':
 (r/'output').mkdir(exist_ok=True)
`);
 await run('git-init',['git','init',objects]);await run('git-add',['git','-C',objects,'add','.']);
 await run('git-commit',['git','-C',objects,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-m','finite native runtime formal producer'],{GIT_AUTHOR_DATE:'2026-10-18T00:00:00Z',GIT_COMMITTER_DATE:'2026-10-18T00:00:00Z'});
 const commit=(await run('git-head',['git','-C',objects,'rev-parse','HEAD'])).stdout.trim();
 const origin='https://github.com/cjcj-dev/cangjie-runtime.git';
 await run('git-origin',['git','-C',objects,'remote','add','origin',origin]);
 await run('fixed-archive',['git','-C',objects,'archive','--output='+root+'/source.tar',commit]);
 await fs.mkdir(materialized);await run('source-extract',['tar','-xf',root+'/source.tar','-C',materialized]);
 const source=mode.startsWith('archive')?materialized:objects;
 // Explicit unavailable functionality, never a fabricated CPP PASS file.
 const boundaries={
  'ci/platform_matrix/native_runtime.mjs':{installNativeRuntimeInputs:'const root=arguments[0].installRoot;controlledDirectSource(path.join(root,"share/runtime-build/runtime"));for(const f of ["share/runtime-build/runtime/CMakebuild/compile_commands.json","share/runtime-build/runtime/CMakebuild/gc-unit.status","runtime/include/schedule.h"]){fs.mkdirSync(path.dirname(path.join(root,f)),{recursive:true});fs.writeFileSync(path.join(root,f),"CONTROLLED_CPP_NOT_RUN");}console.log("CONTROLLED_CPP_DIRECT_INPUT_NOT_RUN");'},
  'build/srcbuild/gc-unit-gate.mjs':{
   assertLanguageState:'console.log("CONTROLLED_CPP_GATE_NOT_RUN");return new Map([["CPP_SUITE","PASS"]]);',
  },
 };
 await write(root+'/boundaries.json',JSON.stringify({functions:boundaries,otherSourcePins:'H1/AST/LLVM use actual finite Git object; no native qualification',commands:['sudo apt-get preparation','npx qualify_teardown_tools'],host:'actual complete private H925'},null,2));
 await write(root+'/loader.mjs',String.raw`const boundaries=${JSON.stringify(Object.fromEntries(Object.entries(boundaries).map(([p,v])=>[new URL(p,'file://'+repo).href,v])))};
export async function load(url,context,next){const r=await next(url,context);if(!boundaries[url]&&!url.endsWith('/ci/bootstrap/sdk-targets.mjs'))return r;let source=String(r.source);
if(url.endsWith('/ci/platform_matrix/native_runtime.mjs'))source+='\nimport {directSource as controlledDirectSource} from '+JSON.stringify(${JSON.stringify(new URL('ci/fixtures/runtime-direct-inputs.mjs','file://'+repo).href)})+';\n';
if(boundaries[url])for(const [name,body]of Object.entries(boundaries[url])){const re=new RegExp('export (async )?function '+name+'\\(');if(!re.test(source))throw Error('BOUNDARY_ANCHOR '+name);source=source.replace(re,(_,a='')=>a+'function CONTROLLED_ORIGINAL_'+name+'(');source+='\nexport function '+name+'(){'+body+'}\n';}
if(url.endsWith('/ci/bootstrap/sdk-targets.mjs')){const anchor='compiler:pins.source.COMPILER_REF';if(!source.includes(anchor))throw Error('BOUNDARY_COMPILER_PIN_ANCHOR');source=source.replace(anchor,"compiler:'${commit}'").replace(/h1:'[0-9a-f]{40}'/,"h1:'${commit}'");}
return {...r,source};}
`);
 const bin=root+'/bin';await fs.mkdir(bin);
 for(const name of ['sudo','npx','sccache']){const file=bin+'/'+name;await write(file,`#!${process.execPath}\nconsole.log('CONTROLLED_EXTERNAL_PREPARATION',${JSON.stringify(name)},process.argv.slice(2));\n`);await fs.chmod(file,0o755);}
 const loader='--experimental-loader='+root+'/loader.mjs';
 const env={NODE_OPTIONS:loader,PATH:bin+path.delimiter+process.env.PATH,PLATFORM_CI_ROOT:root+'/producer',
  RUNTIME_SOURCE:source,RUNTIME_GIT_REPOSITORY:objects,RUNTIME_TARGET:'native',RUNTIME_TOOLCHAIN:'',RUNTIME_NATIVE_PAIR:'1',
  RUNTIME_REF:commit,CJCJ_NATIVE_RUNTIME_REF:commit,LLVM_SHA:commit,NATIVE_RUNTIME_PLATFORM:platform,
  RUNTIME_VERSION:version,RUNTIME_BUILD_TYPE:'release',CJCJ_NATIVE_HOST_VERSION:version,
  FINITE_CACHE_WRAPPER:mode==='archive-wrapper'?'1':'',SCCACHE_PATH:bin+'/sccache',CMAKE_TOOLCHAIN_FILE:'',CJ_RUNTIME_COMMIT:'',GC_UNIT_GATE_LANGUAGE_TESTS:'defer',GITHUB_STEP_SUMMARY:'',RUNNER_TEMP:root+'/preinstall'};
 await run('formal-producer',[process.env.ZX||'zx',repo+'ci/platform_matrix/build_runtime.mjs'],env);
 const installed=root+'/producer/runtime-install',carried=root+'/received';await fs.mkdir(carried);
 if(mode==='archive-wrapper'){const m=JSON.parse(await fs.readFile(installed+'/NATIVE-INPUTS.json'));for(const k of ['C','CXX'])assert.equal(m.compiler_cache_configuration[k].mode,'compiler-wrapper');console.log('NATIVE_WRAPPER_RECORD_TO_RECEIVE_REACHED');}
 console.log('RUNTIME_PRODUCER_INSTALLED_RECORD_ASSERT_REACHED '+mode);
 const original=await fs.readFile(installed+'/RUNTIME-INPUTS.json').catch(error=>{if(error.code==='ENOENT')return null;throw error;});
 assert.ok(original,'RUNTIME_PRODUCER_INSTALLED_SOURCE_RECORD');const facts=JSON.parse(original);
 assert.equal(facts.source.repository,origin);assert.equal(facts.source.commit,commit);
 assert.match(facts.embedded_stamp,mode.startsWith('archive')?/^CJRT-COMMIT:src-[0-9a-f]{64}$/:/^CJRT-COMMIT:[0-9a-f]{40}$/);
 await run('archive-install',['tar','-cf',root+'/runtime.tar','-C',installed,'.']);
 await run('receive-install',['tar','-xf',root+'/runtime.tar','-C',carried]);
 // Keep Git transport independent from the retired producer path.
 await run('consumer-object-mirror',['git','clone','--bare',objects,root+'/transport.git']);
 await fs.rename(objects,objects+'.unavailable');await fs.rename(materialized,materialized+'.unavailable');await fs.rename(installed,installed+'.unavailable');
 const inputs=root+'/inputs';await fs.mkdir(inputs);
 await fs.symlink(host,inputs+'/host');await write(inputs+'/host-archive','controlled host archive location; host execute is actual');
 for(const file of ['node','cjbind'])await write(inputs+'/hle/'+file,'unrelated HLE boundary');await fs.mkdir(inputs+'/hle/modules');
 await write(inputs+'/hle/dependencies.json',JSON.stringify({platform,...Object.fromEntries(['node','modules','cjbind'].map(name=>[name,{path:name,source:'finite unrelated input',version:'fixture'}]))}));
 for(const file of ['cjcj-stage1.mjs','stage1-transform.mjs'])await write(inputs+'/private/ts/src/sharedbuild/'+file,'// unavailable stage producer\n');
 const shapes={llvm:['third_party/llvm/bin/llc','third_party/llvm/bin/llvm-as','third_party/llvm/bin/llvm-dis','third_party/llvm/lib/libLLVM-15.so','third_party/llvm/fixed-llc/cjselfhost_llvmshim.o','tools/bin/cjdb'],
 ast:['libcangjie-ast-support.a','schema/StdAstFormat.fbs','include/flatbuffers/StdAstFormat_generated.h','third_party/flatbuffers/bin/flatc']};
 for(const [name,files]of Object.entries(shapes)){for(const file of files)await write(inputs+'/'+name+'/'+file,'unrelated native component shape; NOT_RUN');await write(inputs+'/'+name+'/result.json',JSON.stringify({controlledUnavailableNativeComponent:name}));}
 const locations={platform,hleDependencies:'hle/dependencies.json',host:{install:'host',archive:'host-archive',version},tools:{privateRoot:'private'},
 installations:Object.fromEntries(Object.keys(shapes).map(name=>[name,{install:name,buildResult:name+'/result.json',configuration:{finiteBoundary:name}}]))};
 await write(inputs+'/locations.json',JSON.stringify(locations));
 const gitConfig=root+'/gitconfig';
 await write(gitConfig,'[url "file://'+root+'/transport.git"]\n'+['https://github.com/cjcj-dev/cangjie-runtime.git','https://github.com/cjcj-dev/cjcj-llvm.git','https://github.com/cjcj-dev/cjcj.git','https://gitcode.com/Cangjie/cangjie_compiler.git'].map(url=>' insteadOf = '+url).join('\n')+'\n');
 const consumer={NODE_OPTIONS:loader,GIT_CONFIG_GLOBAL:gitConfig,GIT_CONFIG_NOSYSTEM:'1',GIT_ALLOW_PROTOCOL:'file:https',
  CANGJIE_WORKSPACE:root+'/consumer',GITHUB_WORKSPACE:root+'/transport.git',CJCJ_NATIVE_INPUT_ROOT:inputs,CJCJ_BOOTSTRAP_BASE:inputs+'/host',CJCJ_BOOTSTRAP_BASE_ARCHIVE:inputs+'/host-archive',
  CJCJ_NATIVE_RUNTIME_INSTALL:carried,CJCJ_NATIVE_RUNTIME_SOURCE:carried+'/share/runtime-build',CJCJ_NATIVE_LLVM_REF:commit,CJCJ_NATIVE_RUNTIME_REF:commit,CJCJ_NATIVE_HOST_VERSION:version,GITHUB_ENV:''};
 const configure=()=>[process.execPath,repo+'ci/bootstrap/configure-gha-inputs.mjs'];
 await run('formal-configure',configure(),consumer);
 const inputFile=consumer.CANGJIE_WORKSPACE+'/native-bootstrap/sdk-inputs.json';
 const configured=JSON.parse(await fs.readFile(inputFile));
 assert.equal(configured.runtime.sourceRepository,origin);
 assert.deepEqual(await fs.readFile(carried+'/RUNTIME-INPUTS.json'),original);
 await run('formal-configure-reuse',configure(),consumer);
 const plan=await run('formal-plan',[process.execPath,repo+'ci/bootstrap/prepare-bootstrap-plans.mjs'],{...consumer,CJCJ_SDK_INPUTS:inputFile});
 assert.match(plan.stdout,/build-targets.json/);
 const build=[process.execPath,repo+'ci/bootstrap/sdk-build.mjs','--config',consumer.CANGJIE_WORKSPACE+'/build-targets.json','--through','nativeR','--no-package'];
 await run('formal-native-target',build,consumer);
 await run('formal-native-target-resume',[...build,'--from','nativeR'],consumer);
 await fs.rename(carried,carried+'.parked');await fs.mkdir(carried);await run('second-receive',['tar','-xf',root+'/runtime.tar','-C',carried]);
 await run('formal-received-again',configure(),consumer);
 if(mode==='archive') {
  const native=JSON.parse(await fs.readFile(carried+'/NATIVE-INPUTS.json'));
  const save=async()=>{await write(carried+'/NATIVE-INPUTS.json',JSON.stringify(native));};
  const expectedReject=async(label,pattern)=>{console.log('RUNTIME_FORMAL_TARGET_REACHED '+label);const r=await run(label,configure(),consumer,1);assert.match(r.stderr,pattern);};
  // Recompute transport inventory deliberately: downstream source/pair assertions
  // must reject even when the transport digest is self-consistent.
  const mutateRecord=async(change)=>{const value=JSON.parse(original);change(value);const bytes=JSON.stringify(value);await write(carried+'/RUNTIME-INPUTS.json',bytes);native.files['RUNTIME-INPUTS.json']=hash(bytes);await save();};
  await fs.unlink(carried+'/RUNTIME-INPUTS.json');delete native.files['RUNTIME-INPUTS.json'];await save();
  await expectedReject('missing-original-record',/RUNTIME_SOURCE_RECORD_REQUIRED/);
  await mutateRecord(x=>x.source.repository='https://invalid.example/runtime');await expectedReject('wrong-source',/RUNTIME_SOURCE_INPUT_BINDING/);
  await mutateRecord(x=>x.source.commit='c'.repeat(40));await expectedReject('wrong-source-commit',/RUNTIME_SOURCE_INPUT_BINDING/);
  await mutateRecord(x=>x.build.configuration.pairedLlvmCommit='c'.repeat(40));await expectedReject('wrong-configuration',/RUNTIME_SOURCE_INPUT_BINDING/);
  await write(carried+'/RUNTIME-INPUTS.json',original);native.files['RUNTIME-INPUTS.json']=hash(original);await save();
  const bytes=await fs.readFile(carried+'/'+archive);await fs.appendFile(carried+'/'+archive,'changed');native.files[archive]=hash(await fs.readFile(carried+'/'+archive));await save();
  await expectedReject('wrong-pair-bytes',/RUNTIME_SOURCE_PAIR_BYTES/);
  await write(carried+'/'+archive,bytes);native.files[archive]=hash(bytes);await save();
  const changed=Buffer.from(bytes),stamp=Buffer.from(facts.embedded_stamp),at=changed.indexOf(stamp);assert.ok(at>=0);changed[at+stamp.length-1]=changed[at+stamp.length-1]===97?98:97;
  await write(carried+'/'+archive,changed);native.files[archive]=hash(changed);
  await mutateRecord(x=>x.artifacts.find(row=>row.path===archive).sha256=hash(changed));
  await expectedReject('wrong-pair-stamp',/RUNTIME_SOURCE_PAIR_STAMP/);
  await write(carried+'/'+archive,bytes);native.files[archive]=hash(bytes);await write(carried+'/RUNTIME-INPUTS.json',original);native.files['RUNTIME-INPUTS.json']=hash(original);await save();
  await run('formal-restored',configure(),consumer);
 }
 // Exercise the original public API after the native SDK receive/restore.
 // Empty publication directory is explicitly unavailable CPP, not a status file.
 await fs.mkdir(carried+'/share/runtime-build',{recursive:true});
 const legacy=root+'/legacy';await fs.mkdir(legacy);
 await run('legacy-source-clone',['git','clone',origin,legacy+'/cangjie_runtime'],consumer);
 // The public CLI resolves every selected source before entering runtime/std.
 // Materialize finite Git inputs for those unchanged boundaries as well.
 const legacyConfig=buildConfig({workspace:legacy,targetKey:'linux-x64'}),choices={};
 for(const name of ['compiler','runtime','tools','stdx','llvm','cjpm']) {
  const url=name==='llvm'?'https://github.com/cjcj-dev/cjcj-llvm.git':origin;
  if(name!=='runtime')await run('legacy-'+name+'-clone',['git','clone',url,legacyConfig.repoPath(name)],consumer);
  choices[name]={url,tag:commit};
 }
 await write(legacy+'/.source-selection.json',JSON.stringify(choices));
 const legacyBoundary={...boundaries,
  'build/lib/provenance.mjs':{writeStdProvenance:'console.log("CONTROLLED_CANGJIE_STD_PROVENANCE_NOT_RUN");'},
  'build/srcbuild/gc-unit-gate.mjs':{...boundaries['build/srcbuild/gc-unit-gate.mjs'],
   runGcUnitLanguageTests:'console.log("LEGACY_LANGUAGE_PRODUCER_ASSERT_REACHED");if(arguments[2]?.source!==process.env.CJCJ_NATIVE_RUNTIME_SOURCE)throw Error("LEGACY_LANGUAGE_PRODUCER_REQUIRED");console.log("CONTROLLED_LEGACY_LANGUAGE_SOURCE_SELECTED "+arguments[2].source);'}};
 let legacyLoader=await fs.readFile(root+'/loader.mjs','utf8');
 const oldLiteral=JSON.stringify(Object.fromEntries(Object.entries(boundaries).map(([p,v])=>[new URL(p,'file://'+repo).href,v])));
 const newLiteral=JSON.stringify(Object.fromEntries(Object.entries(legacyBoundary).map(([p,v])=>[new URL(p,'file://'+repo).href,v])));
 assert.ok(legacyLoader.includes(oldLiteral));legacyLoader=legacyLoader.replace(oldLiteral,newLiteral);
 // Preserve arguments passed by the actual public stages at controlled boundaries.
 legacyLoader=legacyLoader.replace("+'(){'+body", "+'(...args){'+body");
 await write(root+'/legacy-loader.mjs',legacyLoader);
 await write(root+'/legacy-boundaries.json',JSON.stringify({functions:legacyBoundary,CPP:'NOT_RUN',CANGJIE_STD:'NOT_RUN',LANGUAGE:'NOT_RUN'}));
 const legacyEnv={...consumer,NODE_OPTIONS:'--experimental-loader='+root+'/legacy-loader.mjs',CJCJ_SRCBUILD_HOST_SDK:host};
 for(const buildType of ['release','relwithdebinfo']){
  const cli=[process.execPath,repo+'build/cli.mjs','--workspace',legacy,'--build-root',root+'/legacy-build','--build-type',buildType];
  await run('legacy-runtime-'+buildType,[...cli,'build','runtime'],legacyEnv);
  const snapshot=legacy+'/cangjie_runtime/runtime/target/common/linux_'+buildType+'_x86_64/';
  console.log('LEGACY_RUNTIME_SNAPSHOT_ASSERT_REACHED '+buildType);
  const actual=await fs.readFile(snapshot+shared).catch(error=>{if(error.code==='ENOENT')return null;throw error;});
  assert.ok(actual,'LEGACY_RUNTIME_SNAPSHOT_REQUIRED');
  assert.equal(hash(actual),hash(await fs.readFile(carried+'/'+shared)));
  assert.equal(hash(await fs.readFile(snapshot+archive)),hash(await fs.readFile(carried+'/'+archive)));
  const std=await run('legacy-stdlib-'+buildType,[...cli,'build','stdlib'],legacyEnv);
  assert.match(std.stdout+std.stderr,/LEGACY_NATIVE_VALUE=42/);
  assert.match(std.stdout+std.stderr,/CONTROLLED_LEGACY_LANGUAGE_SOURCE_SELECTED/);
  await run('legacy-runtime-repeat-'+buildType,[...cli,'build','runtime'],legacyEnv);
 }
 console.log('RUNTIME_FORMAL_FINITE_PASS '+JSON.stringify({mode,root,commit,stamp:facts.embedded_stamp,commands:records.length,CPP:'NOT_RUN'}));
});
