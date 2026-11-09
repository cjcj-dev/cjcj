import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {TOOL_NAMES,TOOL_PUBLIC_NAMES,retainedToolPath} from '../srcbuild/tool-layout.mjs';
import {resolveOfficialSdkRoot} from '../lib/config.mjs';
import {
  classifyProvenanceText,
  collectContentFindings,
  inspectPackagedLineage,
  listPackagedArtifacts,
  pinnedOfficialSdkRoot,
  readHostSdkPinToolchain,
} from '../lib/package-lineage.mjs';

const TUPLE = 'linux_x86_64_cjnative';
const STAGE2 = 'a'.repeat(40);
const STD = 'b'.repeat(40);

const digest = contents => crypto.createHash('sha256').update(contents).digest('hex');

test('default lineage reference selects the independently declared execution host SDK', async () => {
  const versions = {
    'linux-x64': 'nightly-' + '1.3.0-alpha.20261025001053',
    'linux-arm64': 'nightly-' + '1.3.0-alpha.20261025001053',
    'darwin-x64': 'nightly-' + '1.3.0-alpha.20261025001053',
    'darwin-arm64': 'nightly-' + '1.3.0-alpha.20261025001053',
    'win32-x64': 'nightly-' + '1.3.0-alpha.20261025001053',
  };
  const expected = versions[`${process.platform}-${process.arch}`];
  assert.ok(expected, 'execution host must have an independent SDK declaration');
  const actual = await pinnedOfficialSdkRoot();
  console.log(`ASSERT_LINEAGE_HOST_REFERENCE actual=${actual} expected=${expected}`);
  assert.equal(actual, path.join(os.homedir(), '.cjv', 'toolchains', expected));
});

test('lineage reference retains the custom pinFile API and platform override', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'lineage-pin-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const pinFile = path.join(root, 'pin.env');
  await fs.writeFile(pinFile, 'CJCJ_TOOLCHAIN=nightly-custom\nCJCJ_TOOLCHAIN_LINUX_X86_64=nightly-linux-custom\n');
  const expected = process.platform === 'linux' && process.arch === 'x64' ? 'nightly-linux-custom' : 'nightly-custom';
  assert.equal(await readHostSdkPinToolchain(pinFile), expected);
  assert.equal(await pinnedOfficialSdkRoot(pinFile), path.join(os.homedir(), '.cjv', 'toolchains', expected));
});

async function write(root, relative, contents, mode) {
  const file = path.join(root, relative);
  await fs.mkdir(path.dirname(file), {recursive: true});
  await fs.writeFile(file, contents, mode ? {mode} : undefined);
  return file;
}

async function miniTree(kind) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), `pkg-lineage-${kind}-`));
  const stdBytes = kind === 'nightly' || kind === 'forge'
    ? 'official-nightly-std-bytes\n'
    : 'normal std fixture without a dye string';
  await write(root, `modules/${TUPLE}/std/std.core.a`, stdBytes);
  await write(root, `lib/${TUPLE}/libcangjie-std-core.a`, stdBytes);
  const runtimeBytes=`runtime fixture\0CJRT-COMMIT:${STD}\0`;
  const runtimeFiles=[`runtime/lib/${TUPLE}/libcangjie-runtime.so`,`lib/${TUPLE}/libcangjie-runtime.a`];
  for(const file of runtimeFiles)await write(root,file,runtimeBytes);
  const source={status:'resolved',repository:'https://example.invalid/finite-native-fixture.git',commit:STD};
  await write(root,'RUNTIME-INPUTS.json',JSON.stringify({source,embedded_stamp:'CJRT-COMMIT:'+STD,artifacts:runtimeFiles.map(path=>({path,sha256:digest(runtimeBytes)}))}));
  const compiler='#!/bin/sh\necho FINITE_COMPILER_CONSUMER_REACHED >&2\nexit 93\n';
  await write(root,'bin/cjcj-stage1',compiler,0o755);
  for(const name of ['cjc','cjc-frontend'])await fs.symlink('cjcj-stage1',path.join(root,'bin',name));
  await write(root,'STAGE-INPUTS.json',JSON.stringify({platform:'linux_x86_64',compilerFile:'bin/cjcj-stage1',compilerSha256:digest(compiler),compilerEntrySha256:digest(compiler),sources:{compiler:source,std:source,runtime:source}}));
  const nativeRecord={runtime_sha:STD,paired_llvm_sha:STAGE2,platform:'linux_x86_64',files:{}};
  for(const rel of [`runtime/lib/${TUPLE}/libboundscheck.so`,`lib/${TUPLE}/libcangjie-aio.a`]){
    const bytes='normal R dependency '+rel;await write(root,rel,bytes);nativeRecord.files[rel]=digest(bytes);
  }
  await fs.symlink(`../../runtime/lib/${TUPLE}/libboundscheck.so`,path.join(root,`lib/${TUPLE}/libboundscheck.so`));
  await write(root,'share/cjcj/build-inputs/native-runtime.json',JSON.stringify(nativeRecord));
  const stage=JSON.parse(await fs.readFile(path.join(root,'STAGE-INPUTS.json'),'utf8'));
  stage.sources.llvm={...source,commit:STAGE2};stage.selection={targetComponents:{runtime:{buildResult:'/unavailable-original/NATIVE-INPUTS.json'}}};
  await write(root,'STAGE-INPUTS.json',JSON.stringify(stage));
  const tools={files:{},payloadFiles:{}};
  for(const producer of TOOL_NAMES){
    const name=TOOL_PUBLIC_NAMES[producer]??producer,to='tools/bin/'+name,retained=retainedToolPath({producer,name,to});
    const bytes='normal native fixture '+name,entry='finite launcher '+name,recipe='cjcj-sdk-entry-v1\n1\n'+retained+'\n';
    await write(root,retained,bytes);await write(root,to,entry);await write(root,to+'.entry',recipe);
    tools.files[to]={sha256:digest(bytes),producer:{source,build:{rc:0,fixture:true},artifact:{sha256:digest(bytes)}},entry:{sha256:digest(entry),recipe:{sha256:digest(recipe)}}};
  }
  await write(root,'TOOLS-INPUTS.json',JSON.stringify(tools));
  if (kind === 'stage1') {
    await write(root, 'PROVENANCE.txt', [
      `CJSTD-COMMIT:${STD} BUILT-BY:${STAGE2}`,
      'LINEAGE=stdlib-stage1',
      'BOOTSTRAP-STAGE: stage1',
      '',
    ].join('\n'));
  } else if (kind === 'nightly') {
    await write(root, 'PROVENANCE.txt', [
      `STD_SOURCE_COMMIT = ${STD}`,
      'LINEAGE=official-nightly',
      'BUILT-WITH-SDK=nightly-1.3.0-alpha.20260904010027',
      'ARTIFACT-SHA256:',
      `${digest(stdBytes)}  modules/${TUPLE}/std/std.core.a`,
      `${digest(stdBytes)}  lib/${TUPLE}/libcangjie-std-core.a`,
      `${digest('excluded std bounds')}  lib/${TUPLE}/libboundscheck.so`,
      '',
    ].join('\n'));
  } else {
    await write(root, 'PROVENANCE.txt', [
      `CJSTD-COMMIT:${STD} BUILT-BY:${STAGE2}`,
      'LINEAGE=final-std',
      `STD_SOURCE_COMMIT = ${STD}`,
      `ARTIFACT-SHA256:`,
      `${digest(stdBytes)}  modules/${TUPLE}/std/std.core.a`,
      `${digest(stdBytes)}  lib/${TUPLE}/libcangjie-std-core.a`,
      `${digest('excluded std bounds')}  lib/${TUPLE}/libboundscheck.so`,
      '',
    ].join('\n'));
  }
  return {root, stdSha: digest(stdBytes)};
}

async function copyOfficialStdModules(dest) {
  const official = resolveOfficialSdkRoot() ?? await pinnedOfficialSdkRoot();
  const srcModules = path.join(official, 'modules');
  await fs.rm(path.join(dest,'modules'),{recursive:true,force:true});
  await fs.cp(srcModules, path.join(dest, 'modules'), {recursive: true});
  const files=(await listPackagedArtifacts(dest)).filter(file=>file.startsWith(path.join(dest,'modules')+path.sep)||file.endsWith('libcangjie-std-core.a'));
  const rows=await Promise.all(files.map(async file=>`${digest(await fs.readFile(file))}  ${path.relative(dest,file)}`));
  await write(dest,'PROVENANCE.txt',`STD_SOURCE_COMMIT = ${STD}\nLINEAGE=final-std\nARTIFACT-SHA256:\n${rows.join('\n')}\n`);
}

test('pinned official SDK supplies the lineage comparison input', async () => {
  const official = resolveOfficialSdkRoot() ?? await pinnedOfficialSdkRoot();
  const installed = await fs.stat(official).catch(error => {
    if (error.code === 'ENOENT') return null;
    throw error;
  });
  // This is the provisioning invariant itself, separate from classification:
  // a missing install must fail here, not masquerade as a lineage verdict.
  assert.equal(installed?.isDirectory() ?? false, true,
    `official lineage comparison input was not provisioned: ${official}`);
  const artifacts = (await listPackagedArtifacts(official))
    .filter(file => file.startsWith(path.join(official, 'modules') + path.sep));
  assert.ok(artifacts.length > 0, 'the official input must supply comparison artifacts');
});

test('feeds nightly std and turns red exactly official-std', async t => {
  const {root} = await miniTree('nightly');
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const result = await inspectPackagedLineage(root);
  assert.equal(result.ok, false);
  assert.equal(result.code, 'official-std');
  assert.match(result.message, /official-std/);
  assert.equal(classifyProvenanceText(await fs.readFile(path.join(root, 'PROVENANCE.txt'), 'utf8')),
    'official-std');
  const allowed = await inspectPackagedLineage(root, {allowNightlyStd: true});
  assert.equal(allowed.ok, true);
  assert.equal(allowed.allowedNightly, true);
});

test('feeds stage1 marker and turns red exactly bootstrap-intermediate', async t => {
  const {root} = await miniTree('stage1');
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const result = await inspectPackagedLineage(root);
  assert.equal(result.ok, false);
  assert.equal(result.code, 'bootstrap-intermediate');
  assert.match(result.message, /bootstrap-intermediate/);
  assert.notEqual(result.code, 'official-std');
});

test('feeds final-std and stays green; official tree is not classified green', async t => {
  const final = await miniTree('final');
  const official = await miniTree('nightly');
  t.after(() => fs.rm(final.root, {recursive: true, force: true}));
  t.after(() => fs.rm(official.root, {recursive: true, force: true}));
  const green = await inspectPackagedLineage(final.root);
  assert.equal(green.ok, true);
  assert.equal(green.code, 'ok');
  const positive = await inspectPackagedLineage(official.root);
  assert.equal(positive.ok, false, 'official tree must not be classified green');
  assert.equal(positive.code, 'official-std');
});

test('official 0904 modules/std is rejected with per-file reasons', async t => {
  const {root} = await miniTree('final');
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  await copyOfficialStdModules(root);
  const stdFiles = (await listPackagedArtifacts(root))
    .filter(file => file.includes(`${path.sep}std${path.sep}`) || file.includes('/std/'));
  assert.ok(stdFiles.length > 0, '0904 modules/std must be present');
  const result = await inspectPackagedLineage(root);
  assert.equal(result.ok, false);
  assert.equal(result.code, 'official-std');
  const listed = new Set(result.findings.map(item => item.file));
  for (const file of stdFiles) {
    assert.ok(listed.has(file), `missing per-file reason for ${file}`);
    assert.match(result.message, new RegExp(file.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
    const finding = result.findings.find(item => item.file === file);
    assert.ok(finding.reasons.some(reason => /matches official nightly sha256/.test(reason)));
  }
  const {root:forge} = await miniTree('forge');
  t.after(() => fs.rm(forge, {recursive: true, force: true}));
  await copyOfficialStdModules(forge);
  const forged = await inspectPackagedLineage(forge);
  assert.equal(forged.ok, false);
  assert.equal(forged.code, 'official-std');
  assert.ok(forged.findings.length > 0);
  assert.match(forged.message, /matches official nightly sha256/);
});

test('content findings cover lib runtime modules and tools', async t => {
  const {root} = await miniTree('final');
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const files = await listPackagedArtifacts(root);
  assert.ok(files.some(file => file.includes(`${path.sep}modules${path.sep}`)));
  assert.ok(files.some(file => file.includes(`${path.sep}lib${path.sep}`)));
  assert.ok(files.some(file => file.includes(`${path.sep}runtime${path.sep}lib${path.sep}`)));
  assert.ok(files.some(file => file.endsWith(`${path.sep}tools${path.sep}bin${path.sep}cjpm`)));
  const findings = await collectContentFindings(root, new Set());
  assert.equal(findings.length, 0);
});

// Same public fullselfhost entry, stopped by an explicitly non-compiler body
// only after lineage and compiler identity reached their real consumers.
test('normal native facts reach public verify after relocation; missing/tampered/unrecorded products refuse', async t => {
  const f=await miniTree('final');t.after(()=>fs.rm(f.root,{recursive:true,force:true}));
  const official=await miniTree('nightly');t.after(()=>fs.rm(official.root,{recursive:true,force:true}));
  // Official comparison fixture must not share the finite runtime bytes.
  await fs.rm(path.join(official.root,'runtime'),{recursive:true,force:true});
  await fs.rm(path.join(official.root,`lib/${TUPLE}/libcangjie-runtime.a`));
  await fs.rm(path.join(official.root,`lib/${TUPLE}/libcangjie-aio.a`));
  await fs.rm(path.join(official.root,'tools'),{recursive:true,force:true});
  const relocated=f.root+'-relocated';await fs.rename(f.root,relocated);t.after(()=>fs.rm(relocated,{recursive:true,force:true}));
  const run=()=>spawnSync('npx',['--yes','zx@8',path.resolve('ci/srcbuild/steps/verify.mjs'),relocated],{
    encoding:'utf8',timeout:120000,env:{...process.env,CJCJ_OFFICIAL_SDK_ROOT:official.root,CJCJ_SRCBUILD_TARGET:'linux-x64',CANGJIE_WORKSPACE:relocated,TMPDIR:relocated,RUNNER_TEMP:relocated,CJCJ_ALLOW_NIGHTLY_STD:'0',CJCJ_VERIFY_NO_FAIL_FAST:'0'}});
  let r=run();assert.ifError(r.error);assert.equal(r.status,1);assert.match(r.stdout+r.stderr,/FINITE_COMPILER_CONSUMER_REACHED/);
  console.log('NATIVE_LINEAGE_PUBLIC_CONSUMER_REACHED rc='+r.status);
  for(const rel of [`modules/${TUPLE}/std/std.core.a`,'.target-tools/tools/bin/cjpm',`runtime/lib/${TUPLE}/libboundscheck.so`,'share/cjcj/build-inputs/native-runtime.json']){
    const file=path.join(relocated,rel),bytes=await fs.readFile(file);
    for(const mode of ['missing','tampered']){
      if(mode==='missing')await fs.unlink(file);else await fs.writeFile(file,'replaced native product');
      const rejected=await inspectPackagedLineage(relocated,{officialRoot:official.root});
      assert.equal(rejected.ok,false,mode+' '+rel);assert.equal(rejected.code,'installed-lineage');
      console.log('NATIVE_LINEAGE_REFUSAL '+mode+' '+rel+' '+rejected.message);
      await fs.writeFile(file,bytes);
    }
  }
  const alias=path.join(relocated,`lib/${TUPLE}/libboundscheck.so`),link=await fs.readlink(alias);
  await fs.unlink(alias);await fs.symlink('libcangjie-runtime.a',alias);
  assert.match((await inspectPackagedLineage(relocated,{officialRoot:official.root})).message,/INSTALLED_RUNTIME_ALIAS/);
  await fs.unlink(alias);await fs.symlink(link,alias);
  await write(relocated,`lib/${TUPLE}/unrecorded.a`,'unrecorded bytes');
  assert.equal((await inspectPackagedLineage(relocated,{officialRoot:official.root})).ok,false);
  await fs.unlink(path.join(relocated,`lib/${TUPLE}/unrecorded.a`));
  r=run();assert.ifError(r.error);assert.match(r.stdout+r.stderr,/FINITE_COMPILER_CONSUMER_REACHED/);
  console.log('NATIVE_LINEAGE_PUBLIC_RESTORED rc='+r.status);
});

// The component payloads are finite fixtures, not an SDK. Unlike miniTree's
// installed-only tests, R/C/std/N below traverse the entire public installer.
// Existing unrelated tool fixtures are added separately; they never supply R
// records, runtime files or language results and do not claim tool production.
for(const separateBackend of [false,true])test('normal install pair and language transition reach release rows and relocated lineage'+(separateBackend?' with separate backend':''),async t=>{
  const {directSource,directBuild}=await import('../../ci/fixtures/runtime-direct-inputs.mjs');
  const {installedInputs}=await import('../../ci/srcbuild/lib/installed-inputs.mjs');
  const {writeInstalledReleaseManifest,verifyInstalledReleaseManifest}=await import('../lib/release-manifest.mjs');
  const {archiveInstall}=await import('../../ci/bootstrap/sdk-flow.mjs');
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'lineage-normal-install-')),{root:fixture}=await miniTree('final');
  t.after(()=>Promise.all([root,fixture].map(dir=>fs.rm(dir,{recursive:true,force:true}))));
  const platform='linux_x86_64',H=root+'/H',C=root+'/C',R=root+'/R',S=root+'/std',sdk=root+'/installed';
  let N=root+'/N';
  const source={status:'resolved',repository:'https://example.invalid/finite-native-fixture.git',commit:STD};
  const runtime=root+'/source/runtime';directSource(runtime);directBuild(runtime);
  const statusRel='runtime/lib/'+TUPLE+'/gc_unit_gate.status',deferred=await fs.readFile(runtime+'/CMakebuild/gc-unit.status');
  const copy=async(from,to,rel)=>{await fs.mkdir(path.dirname(to+'/'+rel),{recursive:true});await fs.cp(from+'/'+rel,to+'/'+rel,{recursive:true});};
  const files={};
  for(const rel of ['runtime/lib/'+TUPLE+'/libcangjie-runtime.so','lib/'+TUPLE+'/libcangjie-runtime.a',
    'runtime/lib/'+TUPLE+'/libboundscheck.so','lib/'+TUPLE+'/libcangjie-aio.a','RUNTIME-INPUTS.json']){
    await copy(fixture,R,rel);files[rel]=digest(await fs.readFile(R+'/'+rel));
  }
  await write(R,statusRel,deferred);files[statusRel]=digest(deferred);
  await write(R,'include/schedule.h','finite installed runtime headers');
  let original=JSON.stringify({runtime_sha:STD,paired_llvm_sha:STAGE2,platform,files});
  await write(R,'NATIVE-INPUTS.json',original);
  for(const rel of ['modules','lib/'+TUPLE+'/libcangjie-std-core.a','PROVENANCE.txt'])await copy(fixture,S,rel);
  const cjo='modules/'+TUPLE+'/std/std.core.cjo';await write(S,cjo,'finite std CJO');
  await fs.appendFile(S+'/PROVENANCE.txt',digest('finite std CJO')+'  '+cjo+'\n');
  await fs.mkdir(S+'/third_party/flatbuffers/modules',{recursive:true});
  await copy(fixture,C,'bin/cjcj-stage1');
  for(const [rel,bytes] of [['runtime/lib/'+TUPLE+'/libcangjie-runtime.so','finite compiler runtime'],
    ['lib/'+TUPLE+'/libcangjie-std-core.a','finite compiler std'],['third_party/llvm/lib/libLLVM-15.so','finite compiler LLVM']])await write(C,'.compiler-exec/'+rel,bytes);
  await write(C,'compiler-inputs.json',JSON.stringify({commit:STD,compilerSha256:digest(await fs.readFile(C+'/bin/cjcj-stage1')),stdCoreSha256:digest('finite compiler std')}));
  await fs.mkdir(C+'/share/cjcj',{recursive:true});
  for(const rel of ['LICENSE','Open_Source_Software_Notice.docx'])await write(H,rel,'finite legal text');
  await write(N,'envsetup.sh','# finite environment entry');
  const astLibrary='lib/'+TUPLE+'/libcangjie-ast-support.a',astFiles={};
  for(const rel of [astLibrary,'schema/StdAstFormat.fbs','include/flatbuffers/StdAstFormat_generated.h','third_party/flatbuffers/bin/flatc']){
    const bytes='finite AST '+rel;await write(N,rel,bytes);astFiles[rel]={sha256:digest(bytes),bytes:Buffer.byteLength(bytes)};
  }
  const exec='#!'+process.execPath+'\nconsole.log("finite native recorder");\n';
  for(const rel of ['tools/bin/cjdb','tools/bin/chir-dis','tools/bin/LSPMacroServer','third_party/llvm/bin/llc','third_party/llvm/bin/opt'])await write(N,rel,exec,0o755);
  const llvm='third_party/llvm/lib/libLLVM-15.so',shim='third_party/llvm/fixed-llc/cjselfhost_llvmshim.o';
  await write(N,llvm,'finite LLVM');await write(N,shim,'finite shim');
  await write(N,'third_party/llvm/lib/clang/15/include/fixture.h','finite clang resource');
  const pythonFiles=[];
  for(const rel of ['third_party/llvm/bin/python3.11','third_party/llvm/include/Python.h','third_party/llvm/lib/libpython3.11.so']){
    const bytes='finite Python '+rel;await write(N,rel,bytes);pythonFiles.push({path:rel,sha256:digest(bytes)});
  }
  const python={source:{status:'resolved',kind:'archive',url:'https://example.invalid/Python-3.11.0.tar.xz',version:'3.11.0',sha256:'a'.repeat(64)},
    build:{producer:source,originalInputs:{path:'finite-python.json',sha256:'a'.repeat(64)},configuration:{target:platform,host:platform,configure:'--finite-fixture'}},artifacts:pythonFiles};
  const native={platform,commits:{llvm:STAGE2,compiler:STD},configuration:{install:N},
    astInstallation:{platform,source,library:astLibrary,files:astFiles,build:{target:'cangjie-ast-support',configuration:{stdSupport:'ON'}}},
    llvmLibrary:{file:llvm,sha256:digest('finite LLVM')},nativeShim:{object:{path:shim,sha256:digest('finite shim')}},
    python:{configured:{selected:{version:'3.11.0',configure:'--finite-fixture'}},installed:{observed:{version:'3.11.0'}}},pythonSource:python};
  await write(N,'share/cjcj/build-inputs/python-original.json',JSON.stringify(python));
  // Complete the finite N via real CMake targets/install, then invoke the normal
  // native CLI install-only path. Only unrelated Python/CJDB and clang probes
  // are finite boundaries; native record generation and both installers remain
  // product code. The fourth library proves there is no compiler-rt name list.
  const {command}=await import('../../ci/bootstrap/sdk-flow.mjs');
  const {nativeAstInstallation}=await import('../../ci/bootstrap/native-ast-inputs.mjs');
  const nSource=root+'/N-source',nBuild=root+'/N-build',payload=root+'/N-payload',records=[];
  await fs.rename(N,payload);
  await write(nSource,'finite.c','int finite_native_library(void) { return 42; }\n');
  await write(nSource,'cmake/linux_x86_64_toolchain.cmake','set(CMAKE_SYSTEM_NAME Linux)\n');
  await write(nSource,'CMakeLists.txt',`cmake_minimum_required(VERSION 3.20)
project(FiniteNativeInstall C)
option(CANGJIE_BUILD_STD_SUPPORT "AST enabled" ON)
add_library(cangjie-ast-support STATIC finite.c)
add_library(finite-native STATIC finite.c)
install(DIRECTORY "${payload}/" DESTINATION . USE_SOURCE_PERMISSIONS PATTERN "libcangjie-ast-support.a" EXCLUDE)
install(TARGETS cangjie-ast-support DESTINATION lib/${TUPLE})
# Upstream CJDB embeds its alias prefix at configure time. Exercise that branch.
install(CODE "file(WRITE \\\"\${CMAKE_INSTALL_PREFIX}/configured-prefix.txt\\\" \\\"finite prefix output\\\")")
foreach(name libclang_rt-builtins.a libclang_rt-profile.a libclang_rt.fuzzer_no_main.a libfuture-native.a)
 install(FILES "$<TARGET_FILE:finite-native>" DESTINATION lib/${TUPLE} RENAME \${name})
endforeach()
`);
  await command(['cmake','-G','Ninja','-S',nSource,'-B',nBuild,'-DCMAKE_BUILD_TYPE=Release','-DCMAKE_INSTALL_PREFIX='+N],{records});
  await command(['cmake','--build',nBuild,'--target','cangjie-ast-support','finite-native','--parallel','4'],{records});
  await command(['cmake','--install',nBuild],{records});
  native.compilerSource={root:nSource,commit:STD};native.commits.shim=STD;
  native.astInstallation=await nativeAstInstallation({compiler:nSource,build:nBuild,install:N,platform,source:native.compilerSource,commands:records});
  native.nativeShim={source:{commit:STD},compiler:{commit:STD},llvm:{commit:STAGE2},object:{path:shim,bytes:Buffer.byteLength('finite shim'),sha256:digest('finite shim')}};
  const pythonRoot=root+'/python';for(const rel of ['bin','lib','include','share'])await fs.mkdir(pythonRoot+'/'+rel,{recursive:true});
  await fs.mkdir(root+'/libedit',{recursive:true});
  native.configuration={platform,compiler:nSource,build:nBuild,install:N,commits:native.commits,jobs:4,linkJobs:1,
    tools:{cmake:'cmake',cc:'/usr/bin/cc',cxx:'/usr/bin/c++',launcher:''},python:pythonRoot,libeditLibraryDirectory:root+'/libedit',llvm:root+'/finite-llvm',runtime:R};
  native.commands=records;
  const prior=JSON.stringify(native);await write(N,'BUILD-INPUTS.json',prior);
  const moduleSource=`export async function pythonConfiguration(){return {executable:'/usr/bin/python3',include:'finite',library:'finite'};}
export async function verifyCjdbPythonConfiguration(){return ${JSON.stringify(native.python.configured)};}
export async function verifyCjdbPythonInstallation(){return ${JSON.stringify(native.python.installed)};}
export async function pythonSourceInputs(){return ${JSON.stringify(python)};}
export async function verifyRelocatedCjdbPython(){throw Error('not used');}`;
  const loader=await write(root,'finite-native-boundaries.mjs',`export async function load(url,context,next){
 if(url.endsWith('/ci/bootstrap/sdk-cjdb-python.mjs'))return {format:'module',shortCircuit:true,source:${JSON.stringify(moduleSource)}};
 if(url.endsWith('/ci/bootstrap/native-clang-install.mjs'))return {format:'module',shortCircuit:true,source:'export async function installNativeClang(){console.log("FINITE_UNRELATED_CLANG_PYTHON_PROBES");return {fixture:true};}'};
 return next(url,context);}`);
  const oldN=N;N=root+'/N-reinstalled';
  const nRequest=await write(root,'native-install.json',JSON.stringify({nativeInstall:oldN,install:N}));
  const nArgv=['--loader',loader,new URL('../../ci/bootstrap/native-cjdb.mjs',import.meta.url).pathname,nRequest,'--install-only'];
  const nRun=spawnSync(process.execPath,nArgv,{encoding:'utf8',maxBuffer:8*1024*1024});
  console.log('NATIVE_INSTALL_ONLY_RESULT '+JSON.stringify({argv:nArgv,rc:nRun.status,signal:nRun.signal,stdout:nRun.stdout,stderr:nRun.stderr}));
  assert.equal(nRun.status,0,nRun.stderr);
  assert.equal(await fs.readFile(N+'/configured-prefix.txt','utf8'),'finite prefix output');
  assert.equal(await fs.readFile(oldN+'/BUILD-INPUTS.json','utf8'),prior,'original N facts unchanged');
  const produced=JSON.parse(await fs.readFile(N+'/BUILD-INPUTS.json','utf8'));
  console.log('NATIVE_TARGET_RECORD_ASSERTION_REACHED');
  assert.deepEqual(produced.targetLibraries.map(row=>path.basename(row.path)).sort(),['libclang_rt-builtins.a','libclang_rt-profile.a','libclang_rt.fuzzer_no_main.a','libfuture-native.a'].sort());
  assert.ok(produced.astInstallation.build.commandIndexes.install>=records.length,'AST points to this installation');
  assert.ok(produced.commands.slice(records.length).every(row=>!row.argv.includes('--build')),'install-only must not rebuild targets');
  // The bootstrap-check branch must consume the same original library facts.
  // Native check results do not replace N's installed target-library record.

  const component=(install,extra={})=>({...source,platform,install,...extra});
  const target={compiler:component(C,{product:C+'/bin/cjcj-stage1'}),std:component(S),
    runtime:component(R,{buildResult:R+'/NATIVE-INPUTS.json',sourceRoot:root+'/source',gateStatus:runtime+'/CMakebuild/gc-unit.status'}),
    llvm:component(N,{commit:STAGE2,buildResult:N+'/BUILD-INPUTS.json'}),ast:component(N,{astInstallation:produced.astInstallation})};
  let backend;
  if(separateBackend) {
    const sourceRoot=root+'/backend-source',build=root+'/backend-build',install=root+'/backend-install';
    await write(sourceRoot,'main.c','#include <stdio.h>\nint main(void){puts("BACKEND_COMPONENT_EXECUTED");puts("CJLLVM-COMMIT:" BACKEND_COMMIT);return 0;}\n');
    await write(sourceRoot,'CMakeLists.txt',`cmake_minimum_required(VERSION 3.20)
project(FiniteBackend C)
foreach(tool llc opt)
 add_executable(\${tool} main.c)
 target_compile_definitions(\${tool} PRIVATE BACKEND_COMMIT="\${BACKEND_COMMIT}")
 install(TARGETS \${tool} RUNTIME DESTINATION bin COMPONENT \${tool})
endforeach()
`);
    await command(['git','init',sourceRoot],{records});
    await command(['git','-C',sourceRoot,'add','.'],{records});
    await command(['git','-C',sourceRoot,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-m','test: finite backend producer'],{records});
    const commit=spawnSync('git',['-C',sourceRoot,'rev-parse','HEAD'],{encoding:'utf8'}).stdout.trim();
    await command(['cmake','-S',sourceRoot,'-B',build,'-DCMAKE_INSTALL_PREFIX='+install,'-DBACKEND_COMMIT='+commit],{records});
    await command(['cmake','--build',build,'--parallel','2'],{records});
    for(const tool of ['llc','opt'])await command(['cmake','--install',build,'--component',tool],{records});
    backend=component(install,{commit,build});target.backend=backend;
    original=JSON.stringify({runtime_sha:STD,paired_llvm_sha:commit,platform,files});
    await write(R,'NATIVE-INPUTS.json',original);
  }
  const descriptor={work:root+'/work',install:sdk,selection:{platform,hostPlatform:platform,bootstrapHost:{install:H,platform},
    compilerExecution:{role:'target',stage:'finite-final',platform,...target},targetComponents:target},test:{commands:[
      {argv:[process.execPath,'-e',`const f=require('node:fs'),a=require('node:assert/strict'),s=process.argv[1];console.log('INSTALL_PAIR_ASSERTION_REACHED');a.equal(f.readFileSync(s+'/RUNTIME-INPUTS.json','utf8'),f.readFileSync(${JSON.stringify(R+'/RUNTIME-INPUTS.json')},'utf8'));`, '${install}']},
      {argv:[process.execPath,new URL('../../ci/bootstrap/sdk-installed-language.mjs',import.meta.url).pathname,'--sdk','${install}','--platform',platform,'--work','${work}/language']},
  ]}};
  const input=await write(root,'install.json',JSON.stringify(descriptor)),argv=[new URL('../cli.mjs',import.meta.url).pathname,'install','--inputs',input,'--no-package'];
  const run=spawnSync(process.execPath,argv,{encoding:'utf8',maxBuffer:8*1024*1024,
    env:{...process.env,GC_UNIT_GATE_CONTRACT_SELFTEST:'1',GC_UNIT_GATE_SKIP:'0',MRT_TESTABLE_INTERNALS:'0',DIRECT_TRACE:root+'/language.jsonl'}});
  console.log('NORMAL_INSTALL_RESULT '+JSON.stringify({argv,rc:run.status,signal:run.signal,stdout:run.stdout,stderr:run.stderr}));
  assert.equal(run.status,0,run.stderr);assert.match(run.stdout,/INSTALL_PAIR_ASSERTION_REACHED/);
  assert.match(await fs.readFile(sdk+'/'+statusRel,'utf8'),/LANGUAGE_TESTS=LANGUAGE_DONE/);
  assert.deepEqual((await fs.readFile(root+'/language.jsonl','utf8')).trim().split('\n').map(line=>JSON.parse(line).kind),['FINALIZER','PHASE']);
  assert.equal(await fs.readFile(sdk+'/share/cjcj/build-inputs/native-runtime.json','utf8'),original);
  // Only unrelated tools use the existing installed fixture; the core tree and
  // both original R records must come exclusively from the public installer.
  for(const rel of ['TOOLS-INPUTS.json','.target-tools'])await copy(fixture,sdk,rel);
  for(const producer of TOOL_NAMES){const name=TOOL_PUBLIC_NAMES[producer]??producer;
    for(const suffix of ['','.entry'])await copy(fixture,sdk,'tools/bin/'+name+suffix);}
  console.log('POST_LANGUAGE_INSTALLED_INPUTS_ASSERTION_REACHED');
  const inputs=await installedInputs(sdk,platform),r=inputs.components.find(row=>row.component==='runtime');
  if(separateBackend) {
    console.log('SEPARATE_BACKEND_SELECTION_ASSERTION_REACHED');
    const selected=inputs.components.find(row=>row.component==='llvm-backend');
    assert.equal(selected.source.commit,backend.commit);
    assert.equal(inputs.components.find(row=>row.component==='llvm-cjdb').source.commit,STAGE2);
    assert.equal(await fs.readFile(sdk+'/'+llvm,'utf8'),'finite LLVM');
    for(const name of ['llc','opt']) {
      const file=sdk+'/.native-tools/third_party/llvm/bin/'+name;
      assert.equal(digest(await fs.readFile(file)),digest(await fs.readFile(backend.install+'/bin/'+name)));
      const r=spawnSync(sdk+'/third_party/llvm/bin/'+name,[],{encoding:'utf8'});
      assert.equal(r.status,0,r.stderr);assert.match(r.stdout,/BACKEND_COMPONENT_EXECUTED/);
    }
    const file=sdk+'/.native-tools/third_party/llvm/bin/opt',bytes=await fs.readFile(file);
    await fs.appendFile(file,'changed backend');await assert.rejects(installedInputs(sdk,platform),/INSTALLED_INPUT_BYTES/);
    await fs.writeFile(file,bytes);
  }
  assert.ok(r.artifacts.some(row=>row.path.endsWith('libcangjie-aio.a')));
  assert.ok(!r.artifacts.some(row=>row.path===statusRel));
  assert.deepEqual(r.results,[{path:statusRel,sha256:digest(await fs.readFile(sdk+'/'+statusRel))}]);
  assert.notEqual(r.results[0].sha256,files[statusRel]);
  const {rows}=await writeInstalledReleaseManifest({stage:sdk,platform,...inputs});
  assert.deepEqual(rows.find(row=>row.component==='runtime').results,r.results);
  await verifyInstalledReleaseManifest({stage:sdk,platform,...inputs});
  const lineage=await inspectPackagedLineage(sdk);console.log('NATIVE_TARGET_LINEAGE_ASSERTION_REACHED '+JSON.stringify(lineage));
  assert.equal(lineage.ok,true,lineage.message);
  const llvmRow=inputs.components.find(row=>row.component==='llvm-cjdb');
  for(const item of produced.targetLibraries)assert.ok(llvmRow.artifacts.some(row=>row.path===item.path&&row.sha256===item.sha256));
  const check={...llvmRow,rc:0,platform,install:N,pythonConfiguration:produced.python.configured,pythonInstallation:produced.python.installed,pythonSource:produced.pythonSource,
    artifacts:llvmRow.artifacts.filter(row=>!row.path.startsWith('lib/'))};
  await write(sdk,'share/cjcj/build-inputs/native-llvm.json',JSON.stringify(check));
  assert.equal((await inspectPackagedLineage(sdk)).ok,true);
  await fs.unlink(sdk+'/share/cjcj/build-inputs/native-llvm.json');
  const nLibrary=sdk+'/'+produced.targetLibraries[0].path,nBytes=await fs.readFile(nLibrary);
  await fs.appendFile(nLibrary,'changed N');assert.match((await inspectPackagedLineage(sdk,{allowNightlyStd:true})).message,/INSTALLED_INPUT_BYTES/);
  await fs.writeFile(nLibrary,nBytes);await fs.rename(nLibrary,nLibrary+'.missing');
  assert.equal((await inspectPackagedLineage(sdk,{allowNightlyStd:true})).ok,false);await fs.rename(nLibrary+'.missing',nLibrary);
  const library=sdk+'/lib/'+TUPLE+'/libcangjie-aio.a',bytes=await fs.readFile(library);
  await fs.appendFile(library,'tamper');assert.match((await inspectPackagedLineage(sdk,{allowNightlyStd:true})).message,/INSTALLED_INPUT_BYTES/);
  await fs.writeFile(library,bytes);await fs.rename(library,library+'.missing');
  assert.equal((await inspectPackagedLineage(sdk,{allowNightlyStd:true})).ok,false);await fs.rename(library+'.missing',library);
  const archive=root+'/installed.tar.gz';await archiveInstall({install:sdk,archive,records:[]});
  for(const dir of [C,R,N,oldN,nSource,nBuild,payload,S,root+'/source',...(backend?[backend.install,backend.build,root+'/backend-source']:[]),sdk])await fs.rename(dir,dir+'.unavailable');
  const relocated=archive+'.unpacked/installed';
  assert.equal((await inspectPackagedLineage(relocated)).ok,true);
  const moved=await installedInputs(relocated,platform);await verifyInstalledReleaseManifest({stage:relocated,platform,...moved});
  const verify=spawnSync(process.env.ZX||'zx',[path.resolve('ci/srcbuild/steps/verify.mjs'),relocated],{encoding:'utf8',timeout:120000,
    env:{...process.env,CJCJ_SRCBUILD_TARGET:'linux-x64',CANGJIE_WORKSPACE:root,TMPDIR:root,RUNNER_TEMP:root,CJCJ_ALLOW_NIGHTLY_STD:'0',CJCJ_VERIFY_NO_FAIL_FAST:'0'}});
  console.log('NORMAL_INSTALL_PUBLIC_VERIFY '+JSON.stringify({rc:verify.status,signal:verify.signal,stdout:verify.stdout,stderr:verify.stderr}));
  assert.ifError(verify.error);assert.equal(verify.status,1);assert.match(verify.stdout+verify.stderr,/FINITE_COMPILER_CONSUMER_REACHED/);
  console.log('NORMAL_INSTALL_LANGUAGE_RELEASE_LINEAGE_RELOCATED_REACHED finite=true');
});
