import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import yaml from '../vendor/js-yaml/js-yaml.mjs';
const entry = path.resolve('ci/platform_matrix/build_runtime.mjs');
const llvm = 'db51a4c7ebb6903e9f997d3b35d52f3577810385';
const platform = `${process.platform}_${{x64:'x86_64',arm64:'aarch64'}[process.arch]}`;
const toolchain = path.resolve('ci/platform_matrix/native_runtime_toolchain.cmake');
import {directSource} from '../fixtures/runtime-direct-inputs.mjs';
const directHelper=new URL('../fixtures/runtime-direct-inputs.mjs',import.meta.url).href;
// External native compilation is a command fixture here. The real product CLI,
// checkout check, CMake toolchain script, installation and manifest path execute.
function fixture(check,{legacy=false}={}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'native-runtime-'));
  try {
    const source = path.join(root, 'runtime-source'), bin = path.join(root, 'bin');
    fs.mkdirSync(path.join(source, 'runtime'), {recursive:true});
    fs.mkdirSync(bin);
    fs.writeFileSync(path.join(source, 'runtime/build.py'), '# producer fixture, see command log\n');
    directSource(path.join(source,'runtime'),{legacy});
    const git = args => {
      const r = spawnSync('git', ['-C',source,...args], {encoding:'utf8'});
      assert.equal(r.status,0,r.stderr); return r.stdout.trim();
    };
    git(['init','-q']); git(['add','.']);
    git(['-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-qm','runtime fixture']);
    const runtime = git(['rev-parse','HEAD']);
    const command = `#!${process.execPath}\nimport {directBuild} from ${JSON.stringify(directHelper)};\n` + String.raw`
import fs from 'node:fs'; import path from 'node:path'; import crypto from 'node:crypto'; import {spawnSync} from 'node:child_process';
const name=path.basename(process.argv[1]), args=process.argv.slice(2), e=process.env;
fs.appendFileSync(e.FIXTURE_LOG,JSON.stringify({name,args,cwd:process.cwd(),toolchain:e.CMAKE_TOOLCHAIN_FILE})+'\n');
if(name==='python3' && args[0]==='build.py') {
 if(args[1]==='build') {
  if(e.FIXTURE_FAIL_BUILD) process.exit(19);
  const r=spawnSync('cmake',['-P',e.FIXTURE_CMAKE],{encoding:'utf8',env:e});
  process.stdout.write(r.stdout||'');process.stderr.write(r.stderr||'');if(r.status!==0)process.exit(r.status||1);
  fs.mkdirSync('CMakebuild',{recursive:true});
  const arch=e.NATIVE_RUNTIME_PLATFORM.split('_').slice(1).join('_'),suffix=process.platform==='darwin'?'dylib':'so';
  const bounds=path.resolve('CMakebuild/runtime-staging/lib/'+arch+'_Release/libboundscheck.'+suffix);
  if(!e.FIXTURE_NO_BOUNDS){fs.mkdirSync(path.dirname(bounds),{recursive:true});fs.writeFileSync(bounds,'this native build bounds');}
  const links=['boundscheck','cangjie-runtime'].map(name=>path.resolve('CMakebuild/src/CMakeFiles/'+name+'.dir/link.txt'));
  for(const file of links)fs.mkdirSync(path.dirname(file),{recursive:true});
  fs.writeFileSync(links[0],'clang -shared -o '+bounds);
  fs.writeFileSync(links[1],e.FIXTURE_BAD_LINK?'clang -shared unrelated.so':'clang -shared '+bounds);
  fs.writeFileSync('CMakebuild/runtime-link-inputs.txt',links.join('\n'));

  const tuple=e.NATIVE_RUNTIME_PLATFORM+'_cjnative',preinstall=path.resolve('CMakebuild/cjthread-installed');
  fs.mkdirSync('CMakebuild/cjthread-build',{recursive:true});
  fs.writeFileSync('CMakebuild/cjthread-build/CMakeCache.txt',
    'CMAKE_HOME_DIRECTORY:INTERNAL='+path.resolve('src/CJThread')+'\nCMAKE_INSTALL_PREFIX:PATH='+preinstall+'\nTARGET_ARCH:STRING='+tuple+'\nCMAKE_BUILD_TYPE:STRING='+(e.FIXTURE_BAD_MODE?'Debug':'Release')+'\n');
  fs.mkdirSync(path.join(preinstall,'lib',tuple),{recursive:true});
  for(const name of ['thread','aio'])if(!(e.FIXTURE_NO_AIO && name==='aio'))
    fs.writeFileSync(path.join(preinstall,'lib',tuple,'libcangjie-'+name+'.a'),'installed CJThread '+name);
  fs.writeFileSync('CMakebuild/cjthread-build/install_manifest.txt',['thread','aio'].filter(name=>!(e.FIXTURE_BAD_MANIFEST&&name==='aio')).map(name=>path.join(preinstall,'lib',tuple,'libcangjie-'+name+'.a')).join('\n'));
  const cache=['CANGJIE_COMPILER_CACHE:FILEPATH='+e.SCCACHE_PATH,
    'CMAKE_HOME_DIRECTORY:INTERNAL='+process.cwd(),'CMAKE_INSTALL_PREFIX:PATH='+preinstall,'CMAKE_BUILD_TYPE:STRING=Release'];
  if(e.FIXTURE_WRAPPER) {
    const wrappers=path.resolve('CMakebuild/wrappers');fs.mkdirSync(wrappers,{recursive:true});
    for(const [language,name] of [['C','clang'],['CXX','clang++']]) {
      const wrapper=path.join(wrappers,name);
      fs.symlinkSync(e.FIXTURE_BAD_WRAPPER && language==='CXX'?process.execPath:e.SCCACHE_PATH,wrapper);
      cache.push('CMAKE_'+language+'_COMPILER:FILEPATH='+wrapper);
      if(e.FIXTURE_WRAPPER_LAUNCHER)cache.push('CMAKE_'+language+'_COMPILER_LAUNCHER:STRING=wrong-launcher');
    }
  } else cache.push('CMAKE_C_COMPILER_LAUNCHER:STRING='+e.SCCACHE_PATH,
    'CMAKE_CXX_COMPILER_LAUNCHER:STRING='+(e.FIXTURE_BAD_CACHE?'ccache':e.SCCACHE_PATH));
  fs.writeFileSync('CMakebuild/CMakeCache.txt',cache.join('\n')+'\n');
  if(process.platform==='linux') {
    directBuild(process.cwd(),{noStatus:Boolean(e.FIXTURE_NO_STATUS),cppFail:Boolean(e.FIXTURE_CPP_FAIL)});
  }
 } else if(args[1]==='install') {
  const prefix=args[args.indexOf('--prefix')+1],tuple=e.NATIVE_RUNTIME_PLATFORM+'_cjnative';
  const suffix=process.platform==='darwin'?'dylib':'so';
  const files=['runtime/lib/'+tuple+'/libcangjie-runtime.'+suffix,'lib/'+tuple+'/libcangjie-runtime.a'];
  if(process.platform==='darwin' && !e.FIXTURE_NO_BOUNDS)files.push('runtime/lib/'+tuple+'/libboundscheck.'+suffix);
  for(const file of files){const dst=path.join(prefix,file);fs.mkdirSync(path.dirname(dst),{recursive:true});fs.writeFileSync(dst,'fixture bytes '+file+'\0CJRT-COMMIT:'+e.CJCJ_NATIVE_RUNTIME_REF+'\0');}
  if(e.FIXTURE_ELF) {
    const cpp=path.resolve('CMakebuild/finite.c'),obj=path.resolve('CMakebuild/finite.o');
    fs.writeFileSync(cpp,'unsigned long g_cjLoadBadMask=42; const char stamp[]="CJRT-COMMIT:'+e.CJCJ_NATIVE_RUNTIME_REF+'";\n');
    for(const argv of [['cc','-fPIC','-c',cpp,'-o',obj],['cc','-shared',obj,'-o',path.join(prefix,files[0])],['ar','rcs',path.join(prefix,files[1]),obj]]) {
      if(argv[0]==='ar')fs.rmSync(path.join(prefix,files[1]));
      const r=spawnSync(argv[0],argv.slice(1),{stdio:'inherit'});if(r.status!==0)process.exit(r.status||1);
    }
  }

 }
}
`;
    for (const name of ['sudo','npx','python3','sccache']) {
      fs.writeFileSync(path.join(bin,name),command,{mode:0o755});
    }
    const cmake = path.join(root,'verify-cache.cmake');
    fs.writeFileSync(cmake,`include("${toolchain}")\nforeach(key CANGJIE_COMPILER_CACHE CMAKE_C_COMPILER_LAUNCHER CMAKE_CXX_COMPILER_LAUNCHER)\n  if(NOT "\${\${key}}" STREQUAL "$ENV{SCCACHE_PATH}")\n    message(FATAL_ERROR "NATIVE_CACHE_SELECTION_FAILED: \${key}")\n  endif()\nendforeach()\n`);
    const log=path.join(root,'commands.jsonl'), install=path.join(root,'work/runtime-install');
    const env={...process.env,PATH:bin+path.delimiter+process.env.PATH,
      PLATFORM_CI_ROOT:path.join(root,'work'),RUNTIME_SOURCE:source,RUNTIME_TARGET:'native',RUNTIME_TOOLCHAIN:'',
      RUNTIME_NATIVE_PAIR:'1',
      NATIVE_RUNTIME_PLATFORM:platform,RUNTIME_VERSION:'1.3.0-fixture',RUNTIME_BUILD_TYPE:'release',
      CMAKE_TOOLCHAIN_FILE:'',SCCACHE_PATH:path.join(bin,'sccache'),FIXTURE_LOG:log,FIXTURE_CMAKE:cmake,
      FIXTURE_BAD_LINK:'',FIXTURE_BAD_MODE:'',FIXTURE_BAD_MANIFEST:'',FIXTURE_NO_AIO:'',FIXTURE_BAD_CACHE:'',FIXTURE_NO_BOUNDS:'',FIXTURE_FAIL_BUILD:'',FIXTURE_NO_STATUS:'',FIXTURE_CPP_FAIL:'',
      GC_UNIT_GATE_LANGUAGE_TESTS:'defer',GITHUB_STEP_SUMMARY:'',RUNNER_TEMP:path.join(root,'preinstall')};
    // Consume the workflow's real GITHUB_ENV producer instead of hand-filling
    // the pair that the installed-language input consumer needs on Linux.
    for (const key of ['CJCJ_NATIVE_RUNTIME_REF','CJCJ_NATIVE_LLVM_REF','LLVM_SHA']) delete env[key];
    const workflow=yaml.load(fs.readFileSync('.github/workflows/build-native-runtime.yml','utf8'));
    const load=workflow.jobs.runtime.steps.find(step=>step.id==='pin');
    assert.equal(load.run,'node ci/native-llvm-inputs.mjs');
    const selection=path.join(root,'github-env');
    const selected=spawnSync(process.execPath,[load.run.slice('node '.length)],{encoding:'utf8',env:{...env,
      CJCJ_NATIVE_LLVM_REF:llvm,CJCJ_NATIVE_RUNTIME_REF:runtime,GITHUB_ENV:selection,GITHUB_OUTPUT:path.join(root,'github-output')}});
    assert.equal(selected.status,0,selected.stderr);
    Object.assign(env,Object.fromEntries(fs.readFileSync(selection,'utf8').trim().split('\n').map(line=>{
      const at=line.indexOf('=');return [line.slice(0,at),line.slice(at+1)];
    })));
    const run = extra => spawnSync(process.env.ZX || 'zx',[entry],{encoding:'utf8',env:{...env,...extra},timeout:20000});
    const manifest=()=>JSON.parse(fs.readFileSync(path.join(install,'NATIVE-INPUTS.json'),'utf8'));
    check({run,manifest,runtime,install,log,env,source,root});
  } finally {if(!process.env.RELEASE_EVIDENCE_TEST_ROOT)fs.rmSync(root,{recursive:true,force:true});}
}

test('native runtime public entry builds then installs and records the actual pair and payload',()=>fixture(({run,manifest,runtime,install,log})=>{
  const r=run();
  const phases=fs.readFileSync(log,'utf8').trim().split('\n').map(JSON.parse)
    .filter(x=>x.name==='python3'&&x.args[0]==='build.py').map(x=>x.args[1]);
  assert.deepEqual(phases,['build','install']);
  console.log('NATIVE_PAIR_INSTALL_TARGET_REACHED');
  assert.equal(r.status,0,r.stdout+r.stderr);
  if(process.platform==='linux') assert.equal(fs.readFileSync(path.join(install,'runtime/lib',platform+'_cjnative/libboundscheck.so'),'utf8'),'this native build bounds');
  console.log('CJTHREAD_INSTALLED_ARCHIVE_TARGET_REACHED');
  for(const name of ['thread','aio'])assert.equal(fs.readFileSync(path.join(install,'lib',platform+'_cjnative','libcangjie-'+name+'.a'),'utf8'),'installed CJThread '+name);
  const m=manifest(); assert.equal(m.runtime_sha,runtime);assert.equal(m.paired_llvm_sha,llvm);assert.equal(m.platform,platform);
  for(const [relative,digest] of Object.entries(m.files))assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(install,relative))).digest('hex'),digest);
  const commands=fs.readFileSync(log,'utf8').trim().split('\n').map(JSON.parse).filter(x=>x.name==='python3'&&x.args[0]==='build.py');
  assert.deepEqual(commands.map(x=>x.args),m.commands.map(x=>x.slice(1)));
  assert.deepEqual(commands.map(x=>x.toolchain),[toolchain,toolchain]);
}));
test('native public entry carries direct scripts and generated headers through archive relocation', {skip:process.platform!=='linux'},()=>fixture(({run,install,source,root})=>{
 const r=run();assert.equal(r.status,0,r.stdout+r.stderr);
 const text=fs.readFileSync(path.join(source,'runtime/CMakebuild/gc-unit.status'),'utf8');
 const archive=path.join(root,'runtime.tar'),moved=path.join(root,'moved');fs.mkdirSync(moved);
 for(const args of [['-cf',archive,'-C',install,'.'],['-xf',archive,'-C',moved]])assert.equal(spawnSync('tar',args).status,0);
 fs.renameSync(source,source+'.unreachable');fs.renameSync(install,install+'.unreachable');
 const carried=path.join(moved,'share/runtime-build/runtime');
 assert.equal(fs.readFileSync(path.join(carried,'CMakebuild/gc-unit.status'),'utf8'),text);
 assert.ok(fs.existsSync(path.join(carried,'tests/gc_unit/language_toolchain.mjs')));
 assert.ok(fs.existsSync(path.join(moved,'runtime/include/schedule.h')));
 assert.equal(fs.existsSync(path.join(carried,'build/resolve_runtime_output.sh')),false);
 assert.equal(fs.existsSync(path.join(carried,'output/temp')),false);
 console.log('NATIVE_DIRECT_INPUT_INSTALL_ASSERT_REACHED');
}));
for(const [name,extra,reason] of [
  ['missing CPP status',{FIXTURE_NO_STATUS:'1'},'gc-unit.status'],
  ['failed CPP record',{FIXTURE_CPP_FAIL:'1'},'current native gate did not complete'],
])test(`native public entry rejects ${name}`,{skip:process.platform!=='linux'},()=>fixture(({run,install})=>{
  const r=run(extra);assert.notEqual(r.status,0);assert.ok((r.stdout+r.stderr).includes(reason),r.stdout+r.stderr);
  assert.equal(fs.existsSync(path.join(install,'NATIVE-INPUTS.json')),false);
}));
for(const [name,extra,reason] of [
  ['missing explicit LLVM pair',{CJCJ_NATIVE_LLVM_REF:''},'NATIVE_RUNTIME_EXPLICIT_PAIR_REQUIRED'],
  ['mismatched source pair',{CJCJ_NATIVE_RUNTIME_REF:'f'.repeat(40)},'expected fffff'],
  ['wrong checkout',{CJCJ_NATIVE_RUNTIME_REF:'e'.repeat(40)},'expected eeeee'],
  ['wrong native platform',{NATIVE_RUNTIME_PLATFORM:'darwin_invalid'},'NATIVE_RUNTIME_PLATFORM_MISMATCH'],
  ['missing bounds',{FIXTURE_NO_BOUNDS:'1'},'NATIVE_RUNTIME_BUILD_MISSING'],
  ['missing aio manifest member',{FIXTURE_BAD_MANIFEST:'1'},'NATIVE_CJTHREAD_INSTALL_MANIFEST'],
  ['wrong CJThread configuration',{FIXTURE_BAD_MODE:'1'},'NATIVE_CJTHREAD_INSTALL_CONFIGURATION'],
  ['unlinked bounds target',{FIXTURE_BAD_LINK:'1'},'NATIVE_BOUNDS_RUNTIME_LINK'],
  ['missing installed aio',{FIXTURE_NO_AIO:'1'},'NATIVE_CJTHREAD_INSTALL_MISSING'],
  ['wrong C++ cache',{FIXTURE_BAD_CACHE:'1'},'NATIVE_RUNTIME_CACHE_MISMATCH: CMAKE_CXX_COMPILER_LAUNCHER'],
]) test(`native runtime public entry rejects ${name}`,()=>fixture(({run,install})=>{
  const r=run(extra); assert.notEqual(r.status,0);assert.ok((r.stdout+r.stderr).includes(reason),r.stdout+r.stderr);
  assert.equal(fs.existsSync(path.join(install,'NATIVE-INPUTS.json')),false);
}));
test('native producer failure stops before install and preserves its command exit',()=>fixture(({run,install,log})=>{
  const r=run({FIXTURE_FAIL_BUILD:'1'});assert.notEqual(r.status,0);assert.match(r.stdout+r.stderr,/19/);
  const commands=fs.readFileSync(log,'utf8').trim().split('\n').map(JSON.parse);
  assert.equal(commands.some(x=>x.args[0]==='build.py'&&x.args[1]==='install'),false);
  assert.equal(fs.existsSync(path.join(install,'NATIVE-INPUTS.json')),false);
}));
test('formal workflow carries selected sources through checkout, original producer and whole install upload',()=>{
  const entry=yaml.load(fs.readFileSync('.github/workflows/build-fixed-llc.yml','utf8'));
  const native=yaml.load(fs.readFileSync('.github/workflows/build-native-runtime.yml','utf8'));
  for(const key of ['llvm_ref','runtime_ref'])assert.equal(native.on.workflow_dispatch.inputs[key].required,false);
  assert.equal(native.on.workflow_dispatch.inputs.platforms.default,'darwin_aarch64,darwin_x86_64');
  assert.equal(entry.on.workflow_dispatch.inputs.build_runtime.default,false);
  assert.equal(entry.jobs['native-runtime'].uses,'./.github/workflows/build-native-runtime.yml');
  for(const key of ['llvm_ref','runtime_ref'])assert.equal(entry.jobs['native-runtime'].with[key],`\${{ inputs.${key} }}`);
  const steps=native.jobs.runtime.steps;
  assert.equal(steps.find(x=>x.with?.repository==='cjcj-dev/cangjie-runtime').with.ref,'${{ steps.pin.outputs.runtime_sha }}');
  const build=steps.find(x=>x.env?.RUNTIME_NATIVE_PAIR==='1');
  assert.equal(build.env.CJCJ_NATIVE_RUNTIME_REF,'${{ steps.pin.outputs.runtime_sha }}');
  assert.equal(build.env.GC_UNIT_GATE_LANGUAGE_TESTS,"${{ runner.os == 'Linux' && 'defer' || 'all' }}");
  assert.doesNotMatch(JSON.stringify(native),/GC_UNIT_GATE_SKIP/);
  assert.match(build.run,/zx@8 ci\/platform_matrix\/build_runtime.mjs/);
  assert.match(build.run,/ci\/build-resources.mjs --jobs-only/);
  const consumer=steps.find(x=>x.run==='node ci/platform_matrix/native_runtime_package.mjs');
  assert.ok(steps.indexOf(consumer)>steps.indexOf(build));
  assert.equal(consumer.env.NATIVE_RUNTIME_PLATFORM,'${{ matrix.platform }}');
  assert.equal(steps.find(x=>x.with?.name==='native-runtime-install-${{ matrix.platform }}').with.path,'.platform-ci/runtime-install');
  assert.equal(native.jobs.runtime['runs-on'],'${{ matrix.runner }}');
  assert.equal(native.permissions.contents,'read');
  assert.doesNotMatch(JSON.stringify(native),/h48|language_tuple|build_colour_std|release create/);
});

test('public native producer records compiler-name cache wrappers', {skip:process.platform==='win32'},()=>fixture(({run,manifest})=>{
  const r=run({FIXTURE_WRAPPER:'1'});assert.equal(r.status,0,r.stdout+r.stderr);
  const m=manifest();for(const language of ['C','CXX'])assert.equal(m.compiler_cache_configuration[language].mode,'compiler-wrapper');
  console.log('NATIVE_WRAPPER_RECORD_ASSERT_REACHED');
}));
for(const [name,extra] of [
  ['unrelated executable under a compiler name',{FIXTURE_BAD_WRAPPER:'1'}],
  ['wrong explicit launcher despite valid wrapper',{FIXTURE_WRAPPER_LAUNCHER:'1'}],
])test('public native producer rejects '+name,{skip:process.platform==='win32'},()=>fixture(({run,install})=>{
  const r=run({FIXTURE_WRAPPER:'1',...extra});assert.notEqual(r.status,0);
  assert.match(r.stdout+r.stderr,/NATIVE_RUNTIME_CACHE_MISMATCH/);
  assert.equal(fs.existsSync(path.join(install,'NATIVE-INPUTS.json')),false);
}));

// Same normal install/dependency/input/record/receive API sequence handed to the
// SDK private driver. Only build.py's native payload is the bounded C fixture.
for(const scenario of ['reentry','bad-inputs'])test('normal existing native install and direct receive '+scenario,{skip:process.platform!=='linux'},()=>fixture(({run,runtime,install,source,root,env})=>{
 const first=run({FIXTURE_ELF:'1'});assert.equal(first.status,0,first.stdout+first.stderr);
 const original=path.join(source,'runtime/CMakebuild/gc-unit.status');
 const current=path.join(root,'actual-producer.status');fs.renameSync(original,current);
 const nativeModule=new URL('./native_runtime.mjs',import.meta.url).href;
 const receiver=new URL('../bootstrap/native-runtime-input.mjs',import.meta.url).href;
 const driver=path.join(root,'existing-install.mjs');
 fs.writeFileSync(driver,`import fs from 'node:fs/promises';import path from 'node:path';import {spawnSync} from 'node:child_process';
import {installNativeRuntimeDependencies,installNativeRuntimeInputs,recordNativeRuntime} from ${JSON.stringify(nativeModule)};
import {receiveNativeRuntime} from ${JSON.stringify(receiver)};
const i=JSON.parse(await fs.readFile(process.argv[2]));
if(!i.receiveOnly){const r=spawnSync('python3',['build.py','install','--prefix',i.root],{cwd:path.join(i.source,'runtime'),stdio:'inherit'});if(r.status!==0)process.exit(r.status||1);
installNativeRuntimeDependencies({source:i.source,installRoot:i.root,buildType:'release'});
installNativeRuntimeInputs({source:i.source,installRoot:i.root,gateStatus:i.gateStatus});
await recordNativeRuntime({source:i.source,installRoot:i.root,actualRef:i.runtimeCommit,version:'1.3.0-fixture',buildType:'release',commands:[['python3','build.py','install','--prefix',i.root]]});}
const result=await receiveNativeRuntime(i);console.log('DIRECT_RECEIVE_REACHED '+JSON.stringify(result));
`);
 let serial=0;
 const invoke=(changes={},expected=0,reason)=>{
   const input={root:install,source,sourceRoot:path.join(source,'runtime'),gateStatus:current,
     sourceRepository:source,platform,llvmCommit:llvm,runtimeCommit:runtime,hostVersion:'1.3.0-fixture',work:path.join(root,'receive'),...changes};
   const name=String(++serial),file=path.join(root,'receive-'+name+'.json');fs.writeFileSync(file,JSON.stringify(input));
   const r=spawnSync(process.execPath,[driver,file],{encoding:'utf8',env:{...env,FIXTURE_ELF:'1'}});
   fs.writeFileSync(path.join(root,'receive-'+name+'-result.json'),JSON.stringify({argv:[process.execPath,driver,file],rc:r.status,signal:r.signal,stdout:r.stdout,stderr:r.stderr}));
   if(expected===0){assert.equal(r.status,0,r.stdout+r.stderr);assert.match(r.stdout,/DIRECT_RECEIVE_REACHED/);}
   else {assert.equal(r.status,expected,'DIRECT_CURRENT_INPUT_REJECTION_TARGET '+r.stdout+r.stderr);assert.equal(r.signal,null);assert.match(r.stdout+r.stderr,reason);}
   return r;
 };
 if(scenario==='reentry') {
   invoke();invoke();invoke({root:path.join(root,'other-prefix')});
   const relocated=path.join(root,'unpacked'),archive=path.join(root,'direct.tar');fs.mkdirSync(relocated);
   for(const args of [['-cf',archive,'-C',install,'.'],['-xf',archive,'-C',relocated]])assert.equal(spawnSync('tar',args).status,0);
   fs.renameSync(source,source+'.unavailable');fs.renameSync(current,current+'.unavailable');
   invoke({root:relocated,sourceRoot:undefined,gateStatus:undefined,receiveOnly:true});
   console.log('DIRECT_RECORD_RECEIVE_REENTRY_TARGET');
 } else {
   const text=fs.readFileSync(current,'utf8');
   invoke({gateStatus:current+'.missing'},1,/actual-producer.status.missing/);
   fs.writeFileSync(current,text.replace('GATE=PASS','GATE=FAIL'));invoke({},1,/current native gate did not complete/);
   fs.writeFileSync(current,text);invoke();
   fs.writeFileSync(current,text.replace('GATE=PASS','GATE=FAIL'));invoke({receiveOnly:true},1,/exact PASS/);
   fs.writeFileSync(current,text);invoke({receiveOnly:true});
   const mjs=path.join(source,'runtime/tests/gc_unit/language_toolchain.mjs');fs.renameSync(mjs,mjs+'.absent');
   invoke({},1,/language_toolchain.mjs/);fs.renameSync(mjs+'.absent',mjs);invoke();
   invoke({receiveOnly:true,runtimeCommit:'e'.repeat(40)},1,/NATIVE_RUNTIME_COMPONENT_IDENTITY/);
   const lib=path.join(install,'runtime/lib',platform+'_cjnative/libcangjie-runtime.so');const bytes=fs.readFileSync(lib);
   const recorded=fs.readFileSync(path.join(install,'RUNTIME-INPUTS.json'));
   fs.appendFileSync(lib,'changed');
   const rejected=invoke({receiveOnly:true},1,/RUNTIME_SOURCE_ARTIFACT_BINDING/);
   assert.match(rejected.stdout,/RUNTIME_PAIR_ASSERTION_REACHED/);
   assert.deepEqual(fs.readFileSync(path.join(install,'RUNTIME-INPUTS.json')),recorded,'receiving changed bytes must not rewrite producer facts');
   fs.writeFileSync(lib,bytes);invoke({receiveOnly:true});
   console.log('DIRECT_RECEIVE_BAD_INPUT_CONTROLS_TARGET');
 }
}));

// This is the actual status protocol produced by the selected shell gate, not
// a synthesized GATE_RC. Both native entry and installed/archive consumers run.
test('legacy native public entry retains schema-1 CPP status through installation and package', {skip:process.platform!=='linux'},()=>fixture(({run,install,source,root})=>{
 const r=run();console.log('LEGACY_NATIVE_STATUS_INSTALL_TARGET_REACHED');assert.equal(r.status,0,r.stdout+r.stderr);
 const status=fs.readFileSync(source+'/runtime/CMakebuild/gc-unit.status','utf8');
 assert.match(status,/SCHEMA_VERSION=1/);assert.match(status,/CPP_RUNNER_RC=0/);assert.doesNotMatch(status,/GATE_RC/);
 const archive=root+'/legacy.tar',unpack=root+'/unpack';fs.mkdirSync(unpack);
 for(const args of [['-cf',archive,'-C',install,'.'],['-xf',archive,'-C',unpack]])assert.equal(spawnSync('tar',args).status,0);
 for(const base of [install,unpack])assert.equal(fs.readFileSync(base+'/share/runtime-build/runtime/CMakebuild/gc-unit.status','utf8'),status);
 assert.ok(fs.existsSync(unpack+'/share/runtime-build/runtime/tests/gc_unit/installed-language-entry.mjs'));
},{legacy:true}));
