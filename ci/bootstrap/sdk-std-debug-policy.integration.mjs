#!/usr/bin/env zx
// Finite producer/configuration/install/resume test: real build.py and CMake,
// existing std payload. No std compilation or Release code-size qualification.
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createBootstrapTargets, FIXED_INPUTS} from './sdk-targets.mjs';
import {stdInstallFiles, sdkPlatform} from './sdk-platform.mjs';
import {prepareRuntimeInputs} from './sdk-native-stage.mjs';
import {readHostToolchainPin} from '../host-toolchain-pin.mjs';
const {SDK_STD_POLICY_WORK:root,SDK_STD_POLICY_SDK:sdk,SDK_STD_BUILD_PY:buildPy,
  SDK_STD_CMAKE_LISTS:cmakeLists}=process.env;
assert.ok(root&&sdk&&buildPy&&cmakeLists,'SDK_STD_POLICY_WORK/SDK/BUILD_PY/CMAKE_LISTS required');
await fs.mkdir(root);const commands=[];
function run(name,argv,expected=0,pattern){
 const r=spawnSync(argv[0],argv.slice(1),{encoding:'utf8',maxBuffer:16*1024*1024});
 commands.push({name,argv,rc:r.status,signal:r.signal,error:r.error?.message});
 return Promise.all([fs.writeFile(root+'/'+name+'.stdout',r.stdout||''),fs.writeFile(root+'/'+name+'.stderr',r.stderr||''),
  fs.writeFile(root+'/commands.json',JSON.stringify(commands,null,2))]).then(()=>{
  assert.equal(r.status,expected,name+': '+r.stdout+'\n'+r.stderr);if(pattern)assert.match(r.stdout+r.stderr,pattern);return r;
 });
}
const native=sdkPlatform('linux_x86_64'),required=stdInstallFiles('linux_x86_64');
const payload=[...required,...['argopt','collection'].map(name=>'lib/'+native.tuple+'/libcangjie-std-'+name+'.a')];
const selection=JSON.parse(await fs.readFile(sdk+'/STAGE-INPUTS.json','utf8')).selection;
const bootstrapHost=selection.bootstrapHost.install,runtimeInput=selection.targetComponents.runtime.install;
const actualCmake=await fs.readFile(cmakeLists,'utf8');
const start=actualCmake.indexOf('string(TOLOWER "${CMAKE_BUILD_TYPE}" runtime_build_mode)');
const end=actualCmake.indexOf('string(TOUPPER "${CMAKE_BUILD_TYPE}" uppercase_CMAKE_BUILD_TYPE)');
assert.ok(start>=0&&end>start);const runtimeLookup=actualCmake.slice(start,end);
const source=root+'/fixture';await fs.mkdir(source+'/stdlib/cmake',{recursive:true});
await fs.copyFile(buildPy,source+'/stdlib/build.py');
await fs.writeFile(source+'/stdlib/cmake/linux_x86_64_toolchain.cmake','# No native compilation in this fixture.\n');
await fs.writeFile(source+'/.gitignore','/stdlib/build/\n/stdlib/output/\n');
await fs.writeFile(source+'/stdlib/CMakeLists.txt',`cmake_minimum_required(VERSION 3.20)
project(StdPolicyFixture NONE)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CJNATIVE_BACKEND cjnative)
${runtimeLookup}
file(WRITE "\${CMAKE_BINARY_DIR}/selected-runtime.txt" "\${RUNTIME_COMMON_LIB_DIR}")
file(WRITE "\${CMAKE_BINARY_DIR}/selected-type.txt" "\${CMAKE_BUILD_TYPE}")
${payload.map(rel=>'install(FILES "'+sdk+'/'+rel+'" DESTINATION "'+path.dirname(rel)+'")').join('\n')}
`);
await run('git-init',['git','init','-q',source]);await run('git-add',['git','-C',source,'add','.']);
await run('git-commit',['git','-C',source,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','test: finite std policy producer']);
const commit=(await run('git-head',['git','-C',source,'rev-parse','HEAD'])).stdout.trim();
const tree=(await run('git-tree',['git','-C',source,'rev-parse','HEAD^{tree}'])).stdout.trim();
function inputs(type,dir){
 const row=(commit,name)=>({commit,tree:'a'.repeat(40),repository:root+'/'+name,install:sdk,configuration:{fixture:true},buildResult:root+'/unused',sourceRoot:root+'/'+name});
 const runtime={...row(FIXED_INPUTS.runtime,'R'),install:runtimeInput};
 return {platform:'linux_x86_64',work:dir+'/unused-work',install:dir+'/unused-install',
  host:{version:readHostToolchainPin('linux_x86_64').replace(/^nightly-/,''),install:bootstrapHost},
  llvm:row(FIXED_INPUTS.llvm,'N'),runtime,ast:row(FIXED_INPUTS.compiler,'AST'),h1:row(FIXED_INPUTS.h1,'H1'),
  compiler:row('b'.repeat(40),'C'),stdlib:{repository:source,commit,tree},stdlibCommit:commit,
  tools:{privateRoot:root},...(type===undefined?{buildType:'release'}:{stdBuildType:type})};
}
const cli=new URL('./sdk-build.mjs',import.meta.url).pathname;
const results=[];
for(const [label,type]of [['release','release'],['debug','debug'],['relwithdebinfo','relwithdebinfo'],['legacy',undefined]]){
 if(process.env.SDK_STD_POLICY_CASES&&!process.env.SDK_STD_POLICY_CASES.split(',').includes(label))continue;
 const dir=root+'/'+label,checkout=dir+'/checkout',output=dir+'/install',work=dir+'/work';
 await fs.mkdir(dir);const generated=createBootstrapTargets(inputs(type,dir));
 const stage=structuredClone(generated.stages.find(s=>s.id==='stage3-std'));stage.output=output;
 const a=stage.commands[0].argv;a.push('--heap','8GB','--jobs','8');
 // Only release needs the actual target String consumer/resume; the other
 // branches test producer arguments and install using the host std contract.
 if(label!=='release'){a[a.indexOf('--compiler-runtime')+1]='host';delete stage.test;}
 const config={work,install:output,platform:'linux_x86_64',repos:{std1:{root:source,checkout,commit,tree}},
  stages:[{id:'stage2',output:sdk,reuse:'fixed-existing-input',test:{commands:[{argv:[process.execPath,'-e',"console.log('POLICY_PREDECESSOR_REACHED')"]}]}},stage],
  finalStage:stage.id,test:{required}};
 const file=dir+'/targets.json';await fs.writeFile(file,JSON.stringify(config,null,2));
 if(label==='release'){
  await run(label+'-clone',['git','clone','--shared',source,checkout]);
  const stale=dir+'/old-runtime';await prepareRuntimeInputs({runtime:runtimeInput,link:stale,native,buildType:'debug'});
  await run(label+'-seed-cache',['cmake','-S',checkout+'/stdlib','-B',checkout+'/stdlib/build/build','-G','Ninja',
   '-DCMAKE_BUILD_TYPE=Debug','-DCANGJIE_TARGET_LIB='+stale,'-DPOLICY_ABI_SENTINEL=retained']);
 }
 await run(label+'-first',[process.execPath,cli,'--config',file,'--no-package']);
 const records=JSON.parse(await fs.readFile(output+'.commands.json','utf8'));
 const build=records.find(r=>r.argv?.includes('build.py')&&r.argv.includes('build'));
 const selected=type??'relwithdebinfo';
 console.log('STD_POLICY_PRODUCER_ASSERTION_REACHED '+label);
 assert.equal(build.argv[build.argv.indexOf('-t')+1],selected);
 const cacheDir=checkout+'/stdlib/build/build',cmakeType={debug:'Debug',release:'Release',relwithdebinfo:'RelWithDebInfo'}[selected];
 assert.equal(await fs.readFile(cacheDir+'/selected-type.txt','utf8'),cmakeType);
 assert.equal(await fs.readFile(cacheDir+'/selected-runtime.txt','utf8'),output+'.runtime-input/common/linux_'+selected+'_x86_64/lib/'+native.tuple);
 for(const rel of payload)assert.deepEqual(await fs.readFile(output+'/'+rel),await fs.readFile(sdk+'/'+rel));
 if(label==='release'){
  assert.match(await fs.readFile(cacheDir+'/CMakeCache.txt','utf8'),/POLICY_ABI_SENTINEL:UNINITIALIZED=retained/);
  assert.ok(records.some(r=>r.argv?.[0]==='cmake'&&r.argv.includes('RUNTIME_COMMON_LIB_DIR')));
  const resume=[process.execPath,cli,'--config',file,'--no-package','--resume-installed',stage.id,'--accept-records',root+'/'+label+'-first.stdout'];
  await run('release-resume',resume,0,/resume-accepted/);
  const cache=await fs.readFile(cacheDir+'/CMakeCache.txt','utf8');
  const stale=cache.replace(/^(CMAKE_BUILD_TYPE:[^=]+=)Release$/m,'$1Debug');assert.notEqual(stale,cache);
  await fs.writeFile(cacheDir+'/CMakeCache.txt',stale);
  try{await run('release-resume-stale',resume,1,/STD_RESUME_BUILD_CONFIGURATION/);}
  finally{await fs.writeFile(cacheDir+'/CMakeCache.txt',cache);}
  await run('release-resume-restored',resume,0,/resume-accepted/);
 }
 results.push({label,selected,build:build.argv,cmakeType,installedExistingBytes:true});
}
await fs.writeFile(root+'/result.json',JSON.stringify({status:'PASS',scope:'finite real entry/configuration/install/resume; existing std bytes; no Release std compilation',results},null,2));
