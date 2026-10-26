#!/usr/bin/env zx
// Formal package/receive/compose calls with explicit unavailable SDK functional
// boundaries. Real native C fixture bytes and archive transport; NOT an SDK PASS.
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileDigest} from '../bootstrap/sdk-flow.mjs';
import {sourceToolPayloads} from './source-tool-payloads.mjs';
const base=process.env.RELEASE_EVIDENCE_TEST_ROOT;
if(!base)throw new Error('RELEASE_EVIDENCE_TEST_ROOT required');
await fs.mkdir(base,{recursive:true});const root=await fs.mkdtemp(path.join(base,'manifest-entry-'));
const publicMode=process.env.PUBLIC_PACKAGE_MODE || '';
if(publicMode && !['default-copy','explicit-copy','explicit-same','run-all'].includes(publicMode))throw Error('PUBLIC_PACKAGE_MODE');
const workspace=root+'/workspace',sdk=workspace+'/software/cangjie',records=[];
const repo=new URL('../../',import.meta.url).pathname;
const write=async(file,bytes)=>{await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,bytes);};
async function run(label,argv,env=process.env){
 const r=spawnSync(argv[0],argv.slice(1),{cwd:repo,env,encoding:'utf8',maxBuffer:16*1024*1024});
 records.push({label,argv,rc:r.status,signal:r.signal,error:r.error?.message,stdout:r.stdout,stderr:r.stderr});
 await write(root+'/commands.json',JSON.stringify(records,null,2));return r;
}
await write(root+'/native-source/main.c','int main(void){return 0;}\n');
for(const args of [['init'],['add','.'],['-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-m','finite native packaging fixture']])
 assert.equal((await run('fixture-source',['git','-C',root+'/native-source',...args])).status,0);
const commit=(await run('fixture-head',['git','-C',root+'/native-source','rev-parse','HEAD'])).stdout.trim();
const buildArgv=['cc',root+'/native-source/main.c','-o',root+'/native-product'];
assert.equal((await run('fixture-native-build',buildArgv)).status,0);
const bytes=await fs.readFile(root+'/native-product'),digest=await fileDigest(root+'/native-product');
await write(sdk+'/bin/cjcj-stage1',bytes);await write(sdk+'/bin/cjc',bytes);
await write(sdk+'/STAGE-INPUTS.json',JSON.stringify({phase:'stage3',platform:'linux_x86_64',compilerFile:'bin/cjcj-stage1',compilerCommit:commit,
 runtimeCommit:commit,compilerSha256:digest,compilerEntrySha256:digest}));
await write(sdk+'/compiler-inputs.json',JSON.stringify({commit,compilerSha256:digest}));
const files={};
for(const name of ['cjpm','cjfmt','hle','LSPServer','cjcov','cjtrace-recover','cjlint','cjprof','cjcompat']){
 const rel='tools/bin/'+name,retained='.target-tools/'+rel;
 await write(sdk+'/'+retained,bytes);await write(sdk+'/'+rel,bytes);
 await write(sdk+'/'+rel+'.entry',['cjcj-sdk-entry-v1','2',retained,'linux','native-target:x64','runtime/lib/linux_x86_64_cjnative',''].join('\n'));
 const source={status:'resolved',repository:'file://'+root+'/native-source',commit};
 const build={rc:0,platform:'linux_x86_64',argv:buildArgv,environment:{PATH:process.env.PATH},inputs:{stage:{runtimeCommit:commit},fixture:'native C, not Cangjie tools'}};
 files[rel]={sha256:digest,source:root+'/native-product',producer:{source,build,artifact:{path:root+'/native-product',sha256:digest}},
 artifact:{path:retained,sha256:digest},entry:{path:rel,sha256:digest,recipe:{path:rel+'.entry',sha256:await fileDigest(sdk+'/'+rel+'.entry')}}};
 for(const payload of name==='cjpm'?['tools/config/cangjie-repo.toml']:sourceToolPayloads(name))
  await write(sdk+'/'+payload+(payload==='tools/dtsparser'?'/analysis.js':['tools/config','tools/config/static','.target-tools/tools/config/static'].includes(payload)?'/fixture.txt':''),'finite payload boundary');
}
if(publicMode){
 await write(sdk+'/tools/dtsparser/DEPENDENCIES.json','{}');
 await write(sdk+'/tools/bin/node',bytes);
 await write(sdk+'/stdx/linux_x86_64_cjnative/fixture.cjo','finite stdx payload, not Cangjie qualification');
}
await write(sdk+'/TOOLS-INPUTS.json',JSON.stringify({files,payloadFiles:{}}));
// Optional real Python producer handoff. LLVM/SDK functional prerequisites in
// this fixture remain controlled; these three Python files and their source
// record are copied unchanged from an actual completed native check.
let pythonRecord;
const nativeRecord=sdk+'/share/cjcj/build-inputs/native-llvm.json';
if(process.env.INSTALLED_PYTHON_RECORD){
 const original=JSON.parse(await fs.readFile(process.env.INSTALLED_PYTHON_RECORD,'utf8'));
 assert.equal(original.rc,0);assert.equal(original.platform,'linux_x86_64');
 assert.equal(original.pythonSource.source.status,'resolved');
 for(const product of original.pythonSource.artifacts){
  const source=path.join(process.env.INSTALLED_PYTHON_ROOT,product.path);
  assert.equal(await fileDigest(source),product.sha256);
  await write(sdk+'/'+product.path,await fs.readFile(source));
 }
 const library='third_party/llvm/lib/libLLVM-15.so';
 await write(sdk+'/'+library,bytes);await write(sdk+'/.native-tools/tools/bin/cjdb',bytes);
 for(const tool of ['llc','opt']){
  const rel='third_party/llvm/bin/'+tool,retained='.native-tools/'+rel;
  await write(sdk+'/'+retained,bytes);await write(sdk+'/'+rel,bytes);
  await write(sdk+'/'+rel+'.entry',['cjcj-sdk-entry-v1','2',retained,'linux','native-target:x64','runtime/lib/linux_x86_64_cjnative',''].join('\n'));
 }
 pythonRecord={...original,artifacts:[{path:library,sha256:digest},{path:'tools/bin/cjdb',sha256:digest}],
  pythonInstallation:{...original.pythonInstallation,loaded:Object.fromEntries(Object.entries(original.pythonInstallation.loaded)
   .filter(([file])=>original.pythonSource.artifacts.some(product=>path.join(original.install,product.path)===file)))}};
 await write(nativeRecord,JSON.stringify(pythonRecord));
 await write(root+'/python-boundaries.json',JSON.stringify({originalRecord:process.env.INSTALLED_PYTHON_RECORD,
  originalRecordSha256:await fileDigest(process.env.INSTALLED_PYTHON_RECORD),source:original.pythonSource,
  controlled:'LLVM artifacts are native C fixture; non-Python loaded dependency inventory and five SDK functional boundaries unavailable; no LLVM/LLDB/nativeN rerun'}));
}
// Optional original CMake AST installation, copied through the same package.
// The fixture's N/compiler/SDK functional qualifications remain unavailable.
let astRecord;
const astRecordPath=sdk+'/share/cjcj/build-inputs/native-ast.json';
if(process.env.INSTALLED_AST_ROOT){
 const input=process.env.INSTALLED_AST_ROOT;
 const originalBytes=await fs.readFile(input+'/BUILD-INPUTS.json');
 astRecord=JSON.parse(originalBytes);const ast=astRecord.astInstallation;
 assert.equal(ast.platform,'linux_x86_64');
 for(const member of Object.keys(ast.files))
  await write(sdk+'/'+member,await fs.readFile(input+'/'+member));
 await write(astRecordPath,originalBytes);
 const stage=JSON.parse(await fs.readFile(sdk+'/STAGE-INPUTS.json'));
 stage.sources={ast:{repository:'file://'+ast.source.root,commit:ast.source.commit},llvm:{commit:astRecord.commits.llvm}};
 await write(sdk+'/STAGE-INPUTS.json',JSON.stringify(stage));
 await write(root+'/ast-boundaries.json',JSON.stringify({input,originalRecordSha256:await fileDigest(input+'/BUILD-INPUTS.json'),
  source:ast.source,artifacts:ast.files,controlled:'real CMake C archive fixture; not full native N/AST or Cangjie SDK'}));
}
await write(root+'/targets.json',JSON.stringify({work:root+'/targets',stages:[{id:'stage3-std',output:root+'/std'}]}));
await write(root+'/targets/build/stage3/compiler/compiler-inputs.json','{}');
// Preserve all actual product modules and exports except these explicitly
// controlled unavailable functional prerequisites. No manifest/transport/
// source/record/compose consumer is replaced.
const boundaries={
 'build/lib/runtime-split.mjs':['assertSdkCompilerRuntimeAbi'],
 'build/lib/sdk-path-parity.mjs':['assertSdkPathParity'],
 'ci/bootstrap/sdk-verify-install.mjs':['verifyInstall'],
 'ci/srcbuild/lib/final-compiler.mjs':['produceFinalCompiler'],
 ...(publicMode?{}:{'build/srcbuild/stages/package.mjs':['packageStdx']}),
 ...(publicMode==='run-all'?Object.fromEntries(['fetch','compiler','runtime','stdlib','stdx','tools','verify'].map(name=>['build/srcbuild/stages/'+name+'.mjs',['run']])):{}),
};
await write(root+'/boundaries.json',JSON.stringify(boundaries,null,2));
await write(root+'/loader.mjs',`import fs from 'node:fs/promises';
const boundaries=${JSON.stringify(Object.fromEntries(Object.entries(boundaries).map(([file,names])=>[new URL(file,'file://'+repo).href,names])))};
export async function load(url,context,nextLoad){const result=await nextLoad(url,context);if(!boundaries[url])return result;
let source=String(result.source);for(const name of boundaries[url]){const pattern=new RegExp('export (async )?function '+name+'\\\\(');if(!pattern.test(source))throw Error('BOUNDARY_ANCHOR '+name);
source=source.replace(pattern,(_,asyncPart='')=>asyncPart+'function CONTROLLED_ORIGINAL_'+name+'(');
source+='\\nexport async function '+name+'(){console.log("CONTROLLED_UNAVAILABLE_SDK_FUNCTION '+name+'");}\\n';}return {...result,source};}
`);
const env={...process.env,NODE_OPTIONS:'--experimental-loader='+root+'/loader.mjs',CANGJIE_WORKSPACE:workspace,
 CJCJ_SRCBUILD_TARGET:'linux-x64',SOURCE_SDK_VERSION:'0.0.0-manifest-fixture',CJCJ_SDK_TARGETS:root+'/targets.json',
 CJCJ_OFFICIAL_SDK_ROOT:process.env.CJCJ_OFFICIAL_SDK_ROOT||root+'/unavailable-host'};
if(process.env.INSTALLED_PYTHON_RECORD && !publicMode){
 const wrong=await run('formal-package-wrong-source',[process.execPath,repo+'ci/srcbuild/steps/package-install.mjs'],
  {...env,CJCJ_PACKAGE_SOURCE_REPOSITORY:env.CJCJ_PACKAGE_SOURCE_REPOSITORY||'file://'+repo,CJCJ_PACKAGE_SOURCE_COMMIT:'0'.repeat(40)});
 assert.equal(wrong.status,1);assert.match(wrong.stderr,/PACKAGE_SOURCE_SELECTION_CHANGED/);
 const incomplete=await run('formal-package-incomplete-source',[process.execPath,repo+'ci/srcbuild/steps/package-install.mjs'],
  {...env,CJCJ_PACKAGE_SOURCE_REPOSITORY:env.CJCJ_PACKAGE_SOURCE_REPOSITORY||'file://'+repo,CJCJ_PACKAGE_SOURCE_COMMIT:''});
 assert.equal(incomplete.status,1);assert.match(incomplete.stderr,/PACKAGE_SOURCE_SELECTION_REQUIRED/);
}
let inputSdk=sdk;
if(publicMode){
 inputSdk=publicMode==='explicit-same'?sdk:publicMode==='explicit-copy'?root+'/consumer-sdk':workspace+'/cangjie_compiler/output';
 if(inputSdk!==sdk){await fs.mkdir(path.dirname(inputSdk),{recursive:true});await fs.rename(sdk,inputSdk);}
 if(publicMode.startsWith('explicit'))env.CJCJ_SRCBUILD_CONSUMER_SDK=inputSdk;
 else delete env.CJCJ_SRCBUILD_CONSUMER_SDK;
 env.CANGJIE_VERSION=env.SOURCE_SDK_VERSION;
 await fs.mkdir(env.CJCJ_OFFICIAL_SDK_ROOT,{recursive:true});
 const control=await run('public-full-stdx-control',[process.execPath,repo+'build/cli.mjs','--target','linux-x64','--stdx-profile','sdk-tools','package'],env);
 assert.equal(control.status,1);assert.match(control.stderr,/complete SDK packaging requires full stdx/);
 console.log('PUBLIC_PACKAGE_STDX_CONTROL_REACHED '+publicMode);
}
const packageArgv=publicMode?[process.execPath,repo+'build/cli.mjs','--target','linux-x64',
 ...(publicMode==='run-all'?['run-all','--skip-system-deps','--skip-install-libs']:['package'])]
 :[process.execPath,repo+'ci/srcbuild/steps/package-install.mjs'];
const packaged=await run(publicMode?'formal-public-package':'formal-package-install',packageArgv,env);
if(publicMode)console.log('PUBLIC_PACKAGE_AST_ASSERT_REACHED '+JSON.stringify({mode:publicMode,rc:packaged.status,stderr:packaged.stderr}));
assert.equal(packaged.status,0,packaged.stderr);
if(publicMode){
 for(const member of Object.keys(astRecord.astInstallation.files))assert.equal(await fileDigest(inputSdk+'/'+member),astRecord.astInstallation.files[member].sha256);
 // Re-entry uses the same actual input; it must retain its library and records.
 const repeated=await run('formal-public-package-repeat',packageArgv,env);assert.equal(repeated.status,0,repeated.stderr);
}
const artifactDir=workspace+'/software',archiveName=(await fs.readdir(artifactDir)).find(name=>name.startsWith('cangjie-sdk-')&&name.endsWith('.tar.gz'));
assert.ok(archiveName);const archive=artifactDir+'/'+archiveName;
const releaseEnv={...env,NATIVE_SDK_ARTIFACT_DIR:artifactDir,NATIVE_SDK_INSTALL_DIR:root+'/received',RELEASE_PLATFORM:'linux-x64',RELEASE_KEY:'linux-x64',
 CJCJ_NATIVE_SDK_VERSION:env.SOURCE_SDK_VERSION,CJCJ_RELEASE_SOURCE_SHA:commit,CJCJ_NATIVE_RUNTIME_REF:commit,FINAL_STD_DIR:root+'/std',RELEASE_DIST:root+'/dist'};
const composed=await run('formal-compose-unresolved',[process.execPath,repo+'ci/release/compose-package.mjs'],releaseEnv);
// A checksum failure is an independent earlier transport control.
const archiveBytes=await fs.readFile(archive);await fs.appendFile(archive,'changed');
const transport=await run('independent-transport-control',[process.execPath,repo+'ci/release/compose-package.mjs'],{...releaseEnv,NATIVE_SDK_INSTALL_DIR:root+'/bad-transport'});
assert.match(transport.stderr,/NATIVE_SDK_ARCHIVE_DIGEST/);await fs.writeFile(archive,archiveBytes);
console.log('INSTALLED_MANIFEST_CONSUMER_ASSERT_REACHED '+JSON.stringify({rc:composed.status,stderr:composed.stderr,transport:'rejected'}));
assert.equal(composed.status,1);assert.match(composed.stderr,/cjcj.source.status is unresolved/);
assert.doesNotMatch(composed.stdout,/NATIVE_RELEASE_ARCHIVE/);
const original=await fs.readFile(sdk+'/RELEASE-MANIFEST.jsonl');
for(const file of [archive+'.unpacked/cangjie/RELEASE-MANIFEST.jsonl',root+'/received/cangjie/RELEASE-MANIFEST.jsonl'])
 assert.deepEqual(await fs.readFile(file),original);
const build=JSON.parse(await fs.readFile(sdk+'/BUILD-MANIFEST.json'));
assert.equal(build.files,undefined);
assert.equal(build.target,'linux-x64');
const rows=original.toString().trim().split('\n').map(line=>JSON.parse(line));
assert.equal(rows.find(row=>row.component==='cjcj').source.status,'unresolved');
assert.equal(rows.find(row=>row.component==='tool-LSPServer').source.commit,commit);
if(pythonRecord){
 const python=rows.find(row=>row.component==='python');
 console.log('INSTALLED_PYTHON_SOURCE_CONSUMER_ASSERT_REACHED '+JSON.stringify(python));
 assert.deepEqual(python.source,pythonRecord.pythonSource.source);
 assert.deepEqual(python.artifacts,pythonRecord.pythonSource.artifacts);
 assert.deepEqual(python.build.configuration,pythonRecord.pythonSource.build.configuration);
 for(const destination of [archive+'.unpacked/cangjie',root+'/received/cangjie']){
  assert.deepEqual(await fs.readFile(destination+'/share/cjcj/build-inputs/native-llvm.json'),await fs.readFile(nativeRecord));
  for(const product of pythonRecord.pythonSource.artifacts)assert.equal(await fileDigest(destination+'/'+product.path),product.sha256);
 }
 const invoke=label=>run(label,packageArgv,env);
 const cases=[
  ['source',record=>record.pythonSource.source.sha256='wrong',/INSTALLED_PYTHON_SOURCE/],
  ['version',record=>record.pythonSource.source.version='3.11.999',/INSTALLED_PYTHON_SOURCE/],
  ['configure',record=>record.pythonSource.build.configuration.configure+=' changed',/INSTALLED_PYTHON_CONFIGURATION/],
  ['missing-product',record=>record.pythonSource.artifacts.pop(),/INSTALLED_PYTHON_ARTIFACTS/],
  ['product-bytes',record=>record.pythonSource.artifacts[1].sha256='0'.repeat(64),/INSTALLED_INPUT_BYTES/],
  ['escape',record=>record.pythonSource.artifacts[1].path='third_party/llvm/../../outside/Python.h',/INSTALL_PATH/],
 ];
 for(const [name,change,diagnostic]of cases){
  const record=structuredClone(pythonRecord);change(record);await write(nativeRecord,JSON.stringify(record));
  const result=await invoke('python-'+name);assert.equal(result.status,1,result.stderr);assert.match(result.stderr,diagnostic);
 }
 const missing=structuredClone(pythonRecord);delete missing.pythonSource;await write(nativeRecord,JSON.stringify(missing));
 const unknown=await invoke('python-no-original-record');assert.equal(unknown.status,0,unknown.stderr);
 const unknownRows=(await fs.readFile(sdk+'/RELEASE-MANIFEST.jsonl','utf8')).trim().split('\n').map(line=>JSON.parse(line));
 assert.equal(unknownRows.find(row=>row.component==='python').source.status,'unresolved');
 await write(nativeRecord,JSON.stringify(pythonRecord));
 const restored=await invoke('python-restored');assert.equal(restored.status,0,restored.stderr);
 console.log('INSTALLED_PYTHON_FORMAL_PACKAGE_FINITE_PASS');
}
if(astRecord){
 const ast=rows.find(row=>row.component==='ast-support');
 console.log('INSTALLED_AST_SOURCE_CONSUMER_ASSERT_REACHED '+JSON.stringify(ast));
 assert.equal(ast.source.commit,astRecord.astInstallation.source.commit);
 assert.equal(ast.source.repository,'file://'+astRecord.astInstallation.source.root);
 assert.deepEqual(ast.build,astRecord.astInstallation.build);
 for(const destination of [archive+'.unpacked/cangjie',root+'/received/cangjie']){
  assert.deepEqual(await fs.readFile(destination+'/share/cjcj/build-inputs/native-ast.json'),await fs.readFile(astRecordPath));
  for(const [member,record]of Object.entries(astRecord.astInstallation.files))
   assert.equal(await fileDigest(destination+'/'+member),record.sha256);
 }
 const invoke=label=>run(label,packageArgv,env);
 const mutationSdk=publicMode?inputSdk:sdk;
 const library=mutationSdk+'/'+astRecord.astInstallation.library,original=await fs.readFile(library);
 try{
  await fs.appendFile(library,'changed');const bad=await invoke('ast-changed-library');
  console.log('INSTALLED_AST_BAD_BYTES_ASSERT_REACHED rc='+bad.status);
  assert.equal(bad.status,1,bad.stderr);assert.match(bad.stderr,/NATIVE_AST_INSTALL_BYTES/);
 }finally{await fs.writeFile(library,original);}
 const mutationRecord=mutationSdk+'/share/cjcj/build-inputs/native-ast.json';
 const recordBytes=await fs.readFile(mutationRecord);
 try{
  await fs.unlink(mutationRecord);const missing=await invoke('ast-missing-original');
  assert.equal(missing.status,1);assert.match(missing.stderr,/INSTALLED_AST_ORIGINAL_RECORD/);
 }finally{await write(mutationRecord,recordBytes);}
 const restored=await invoke('ast-restored');assert.equal(restored.status,0,restored.stderr);
 console.log('INSTALLED_AST_FORMAL_PACKAGE_FINITE_PASS');
}
console.log('INSTALLED_MANIFEST_ENTRY_FINITE_PASS '+root);
