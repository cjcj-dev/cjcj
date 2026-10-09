#!/usr/bin/env zx
// The LLVM stamp names its fixed baseline. This separate mandatory record
// qualifies the five actual inputs copied by the compiler's native PATCH.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {canonical, objectId, fileDigest, readJson, atomicJson, execute, reject} from './sdk-manifest.mjs';

export const CJDB_QUALIFICATION = 'cjcj-native-patch-qualification-v1';
export const CJDB_INPUTS = Object.freeze({
  'utils/demangle/CangjieDemangle.h': ['demangler', 'include/CangjieDemangle.h'],
  'utils/demangle/libcangjie-demangle.a': ['demangler', 'lib/libcangjie-demangle.a'],
  'utils/boundscheck/include/securec.h': ['bounds', 'include/securec.h'],
  'utils/boundscheck/include/securectype.h': ['bounds', 'include/securectype.h'],
  'utils/boundscheck/lib/x86_64/libboundscheck.so': ['build', 'lib/libboundscheck.so'],
});
const pin = source => ({commit:source.commit, tree:source.tree});
const fixed = {llvm:'7ed574d4ba6ff1ebeceeb339ab4795e0141e4a60', compiler:'174db8f40d5efddee63c47a3162bbf676bc227a0', bounds:'2ae82839ecaaa7d031e66ccbd2076d671acfd615'};
export function qualificationRecipe(component) {
  const options = component.config.options;
  if (component.source.commit !== fixed.llvm || options.compilerSource.commit !== fixed.compiler
    || options.boundscheckSource.commit !== fixed.bounds) reject('CJDB_QUALIFICATION_SCOPE',component.id,'qualification applies only to the declared fixed native graph');
  return {schema:CJDB_QUALIFICATION, llvm:pin(component.source), compiler:pin(options.compilerSource), bounds:pin(options.boundscheckSource),
    demangler:{source:'compiler:demangler', entry:'CMakeLists.txt:cangjie-demangler', configuration:'Release', install:'cangjie-demangler'},
    patch:{source:'compiler:third_party/CMakeLists.txt', target:'cjnative', files:Object.keys(CJDB_INPUTS)},
    configuration:{host:component.config.host,target:component.config.target,rtti:'ON',dylib:'ON',targets:['X86','ARM','AArch64'],tools:component.config.tools,options},
    producer:component.producer.version};
}
export async function prepareQualification(request, roots, outputDirectory) {
  await fs.mkdir(outputDirectory,{recursive:true});
  const gate = fileURLToPath(import.meta.url);
  const contract = {schema:CJDB_QUALIFICATION, component:request.component, buildId:request.identity.buildId,
    recipe:qualificationRecipe(request.component), roots, outputDirectory, gateSha256:await fileDigest(gate)};
  const contractFile = path.join(outputDirectory,'contract.json');
  await atomicJson(contractFile,contract);
  const quote = text => `"${text.replaceAll('\\','\\\\').replaceAll('"','\\"').replaceAll('$','\\$')}"`;
  const hook = path.join(outputDirectory,'before-llvm-project.cmake');
  // This hook is the first step of project(LLVM), after ExternalProject's
  // unchanged PATCH_COMMAND and before any LLVM configuration/stamp logic.
  await fs.writeFile(hook,`execute_process(COMMAND ${[request.component.config.tools.node.path,gate,contractFile,'preconfigure'].map(quote).join(' ')} RESULT_VARIABLE native_patch_rc)\nif(NOT native_patch_rc EQUAL 0)\n  message(FATAL_ERROR "CJDB_NATIVE_PATCH_QUALIFICATION_FAILED rc=\${native_patch_rc}")\nendif()\n`);
  return {contractFile,hook};
}
async function checkSource(root, expected, git, label, allowed=[]) {
  const run = async (...args) => (await execute(git,['-C',root,...args])).stdout;
  const actual = {commit:(await run('rev-parse','HEAD')).trim(), tree:(await run('rev-parse','HEAD^{tree}')).trim(),
    status:(await run('status','--porcelain','-z','--untracked-files=all')).split('\0').filter(Boolean).sort()};
  if (canonical(pin(actual)) !== canonical(pin(expected))) reject('CJDB_SOURCE_IDENTITY',label,'HEAD/tree differ');
  if (canonical(actual.status) !== canonical(allowed.map(rel=>`?? ${rel}`).sort())) reject('CJDB_SOURCE_STATUS',label,canonical(actual.status).trim());
  return actual;
}
export async function qualifyGeneratedInputs(contractFile, phase) {
  if (!['preconfigure','preseal'].includes(phase)) reject('CJDB_QUALIFICATION_PHASE','llvm','invalid phase');
  const contract = await readJson(contractFile), {component, roots, outputDirectory} = contract;
  if (contract.schema !== CJDB_QUALIFICATION || canonical(contract.recipe) !== canonical(qualificationRecipe(component))
    || contract.gateSha256 !== await fileDigest(fileURLToPath(import.meta.url))) reject('CJDB_QUALIFICATION_CONTRACT',component.id,'recipe or gate changed');
  for (const [name,tool] of Object.entries(component.config.tools)) {
    if (await fileDigest(tool.path) !== tool.sha256) reject('CJDB_QUALIFICATION_TOOL',component.id,name);
  }
  const git = component.config.tools.git.path;
  const llvm = await checkSource(roots.llvm,component.source,git,'llvm',Object.keys(CJDB_INPUTS));
  const compiler = await checkSource(roots.compiler,component.config.options.compilerSource,git,'compiler');
  const bounds = await checkSource(roots.bounds,component.config.options.boundscheckSource,git,'bounds',['CMakeLists.txt']);
  const rule = path.join(roots.compiler,'third_party/cmake/BoundsCheck.cmake');
  if (await fileDigest(rule) !== await fileDigest(path.join(roots.bounds,'CMakeLists.txt'))) reject('CJDB_PATCH_RULE',component.id,'bounds generated CMake recipe differs');
  const rules = {};
  for (const rel of ['CMakeLists.txt','third_party/CMakeLists.txt','third_party/cmake/BoundsCheck.cmake','demangler/CMakeLists.txt']) {
    const current = await fs.readFile(path.join(roots.compiler,rel));
    const original = (await execute(git,['-C',roots.compiler,'show',`${component.config.options.compilerSource.commit}:${rel}`],{encoding:'buffer'})).stdout;
    if (!current.equals(original)) reject('CJDB_PATCH_RULE',component.id,rel);
    rules[rel]=await fileDigest(path.join(roots.compiler,rel));
  }
  const demanglerBuild=path.join(roots.build,'cangjie-demangler-prefix/src/cangjie-demangler-build');
  const cache=await fs.readFile(path.join(demanglerBuild,'CMakeCache.txt'),'utf8');
  const value = name => cache.match(new RegExp(`^${name}:[^=]+=([^\\n]*)$`,'m'))?.[1];
  for (const [key,expected] of Object.entries({CMAKE_HOME_DIRECTORY:path.join(roots.compiler,'demangler'),CMAKE_INSTALL_PREFIX:roots.demangler,CMAKE_BUILD_TYPE:'Release',CMAKE_C_COMPILER:component.config.tools.clang.path,CMAKE_CXX_COMPILER:component.config.tools['clang++'].path})) {
    if (value(key)!==expected) reject('CJDB_DEMANGLER_PRODUCER',component.id,`${key}: ${value(key)} != ${expected}`);
  }
  const generated = {};
  for (const [rel,[root,inputRel]] of Object.entries(CJDB_INPUTS)) {
    const input=path.join(roots[root],inputRel), copied=path.join(roots.llvm,rel);
    for (const file of [input,copied]) if (!(await fs.lstat(file)).isFile()) reject('CJDB_GENERATED_TYPE',component.id,rel);
    const sha256=await fileDigest(input);
    if (await fileDigest(copied)!==sha256) reject('CJDB_GENERATED_BYTES',component.id,rel);
    generated[rel]={sha256,mode:(await fs.stat(copied)).mode&0o777,size:(await fs.stat(copied)).size,input,
      artifact:`native-inputs/${rel}`};
  }
  const body={schema:CJDB_QUALIFICATION,buildId:contract.buildId,recipe:contract.recipe,roots,llvm,compiler,bounds,rules,generated,
    demangler:{cacheSha256:await fileDigest(path.join(demanglerBuild,'CMakeCache.txt')),buildGraphSha256:await fileDigest(path.join(roots.build,'build.ninja'))}};
  const preFile=path.join(outputDirectory,'preconfigure.json');
  if (phase==='preseal') {
    const pre=await readJson(preFile);
    if (pre.phase!=='preconfigure' || canonical(pre.body)!==canonical(body)) reject('CJDB_GENERATED_CHANGED',component.id,'generated input identity changed since configure');
  } else {
    try { const previous=await readJson(preFile); if(canonical(previous.body)!==canonical(body))reject('CJDB_GENERATED_CHANGED',component.id,'reconfigure inputs differ'); }
    catch(error){if(error.code!=='ENOENT')throw error;}
  }
  const record={phase,checkedAt:new Date().toISOString(),contractSha256:await fileDigest(contractFile),body};
  await atomicJson(path.join(outputDirectory,`${phase}.json`),record);
  console.log(`CJDB_GENERATED_INPUTS_ASSERT_REACHED phase=${phase} files=${Object.keys(generated).length} identity=${objectId(body)}`);
  return record;
}
export async function exportQualification(contractFile, artifacts) {
  const contract=await readJson(contractFile), post=await qualifyGeneratedInputs(contractFile,'preseal');
  const certificate={schema:CJDB_QUALIFICATION,preconfigure:await readJson(path.join(contract.outputDirectory,'preconfigure.json')),preseal:post};
  for(const [rel,row] of Object.entries(post.body.generated)){
    const destination=path.join(artifacts,row.artifact);await fs.mkdir(path.dirname(destination),{recursive:true});
    await fs.copyFile(path.join(contract.roots.llvm,rel),destination);await fs.chmod(destination,row.mode);
  }
  await atomicJson(path.join(artifacts,'native-inputs/qualification.json'),certificate);
  return certificate;
}
export function verifyQualificationCertificate(component, buildId, certificate, files, directory) {
  const fail = detail => reject('CJDB_QUALIFICATION_RECEIPT',component.id,detail);
  if (!certificate || certificate.schema!==CJDB_QUALIFICATION || certificate.preconfigure?.phase!=='preconfigure'
    || certificate.preseal?.phase!=='preseal') fail('both actual phase records required');
  const pre=certificate.preconfigure, post=certificate.preseal, body=post.body;
  if (!body || canonical(pre.body)!==canonical(body) || pre.contractSha256!==post.contractSha256
    || !/^[a-f0-9]{64}$/.test(post.contractSha256||'') || body.schema!==CJDB_QUALIFICATION
    || body.buildId!==buildId || canonical(body.recipe)!==canonical(qualificationRecipe(component))) fail('phase, recipe or build binding differs');
  const build=path.join(directory,'build/compiler'), compiler=path.join(directory,'source-inputs/compiler');
  const roots={llvm:path.join(directory,'source-inputs/llvm'),compiler,bounds:path.join(compiler,'third_party/boundscheck'),build,demangler:path.join(build,'cangjie-demangler')};
  if(canonical(body.roots)!==canonical(roots))fail('actual producer locations differ');
  if(!Number.isFinite(Date.parse(pre.checkedAt)) || !Number.isFinite(Date.parse(post.checkedAt)) || Date.parse(post.checkedAt)<Date.parse(pre.checkedAt))fail('actual phase times differ');
  for (const [label,expected] of [['llvm',component.source],['compiler',component.config.options.compilerSource],['bounds',component.config.options.boundscheckSource]]) {
    const actual=body[label], allowed=label==='llvm'?Object.keys(CJDB_INPUTS):label==='bounds'?['CMakeLists.txt']:[];
    if (!actual || canonical(pin(actual))!==canonical(pin(expected)) || canonical(actual.status)!==canonical(allowed.map(rel=>`?? ${rel}`).sort())) fail(`${label} actual source identity/status differs`);
  }
  if (canonical(Object.keys(body.generated||{}).sort())!==canonical(Object.keys(CJDB_INPUTS).sort())) fail('exact five generated entities required');
  if (!body.demangler || ![body.demangler.cacheSha256,body.demangler.buildGraphSha256,...Object.values(body.rules||{})].every(value=>/^[a-f0-9]{64}$/.test(value))
    || canonical(Object.keys(body.rules||{}).sort())!==canonical(['CMakeLists.txt','third_party/CMakeLists.txt','third_party/cmake/BoundsCheck.cmake','demangler/CMakeLists.txt'].sort())) fail('actual demangler graph and PATCH rules required');
  for (const [rel,row] of Object.entries(body.generated)) {
    const artifact=`native-inputs/${rel}`, sealed=files?.[artifact];
    const [root,inputRel]=CJDB_INPUTS[rel];
    if (row.artifact!==artifact || !/^[a-f0-9]{64}$/.test(row.sha256||'') || sealed?.type!=='file'
      || row.input!==path.join(roots[root],inputRel) || sealed.sha256!==row.sha256 || sealed.mode!==row.mode || sealed.size!==row.size) fail(`sealed generated entity differs: ${rel}`);
  }
  const expectedFiles=['native-inputs/qualification.json',...Object.keys(CJDB_INPUTS).map(rel=>`native-inputs/${rel}`)].sort();
  if(canonical(Object.keys(files||{}).filter(rel=>rel.startsWith('native-inputs/')).sort())!==canonical(expectedFiles))fail('extra or missing sealed qualification entity');
  const encoded=Buffer.from(canonical(certificate)), sealed=files?.['native-inputs/qualification.json'];
  if(sealed?.type!=='file' || sealed.sha256!==objectId(certificate) || sealed.size!==encoded.length)fail('certificate must be an actual sealed install artifact');
  return certificate;
}
export async function verifyInstalledQualification(sdk, plan, manifest) {
  for (const component of plan.components.filter(row=>row.producer.adapter==='llvm-cjdb')) {
    const receipt=JSON.parse(manifest.components[component.id].receiptJson), certificate=receipt.execution.generatedInputs;
    verifyQualificationCertificate(component,receipt.buildId,certificate,receipt.files,receipt.directory);
    const required=['native-inputs/qualification.json',...Object.keys(CJDB_INPUTS).map(rel=>`native-inputs/${rel}`)];
    for(const rel of required){
      const actual=manifest.files[rel], expected=receipt.files[rel];
      if(actual?.component!==component.id || actual.buildId!==receipt.buildId || actual.sha256!==expected.sha256
        || !(await fs.lstat(path.join(sdk,rel))).isFile() || await fileDigest(path.join(sdk,rel))!==expected.sha256) reject('CJDB_QUALIFICATION_INSTALL',component.id,`required installed qualification: ${rel}`);
    }
    if(canonical(await readJson(path.join(sdk,'native-inputs/qualification.json')))!==canonical(certificate))reject('CJDB_QUALIFICATION_INSTALL',component.id,'installed certificate differs');
    for(const [rel,row] of Object.entries(manifest.files)){
      if ((rel.startsWith('third_party/llvm/') || rel.startsWith('native-closure/') || rel==='tools/bin/cjdb'
        || /^tools\/lib\/(?:liblldb|libcangjie-(?:frontend|lsp))/.test(rel)) && row.component!==component.id)
        reject('CJDB_QUALIFICATION_INSTALL',component.id,`mixed native LLVM/LLDB producer: ${rel}`);
    }
  }
}
if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  try{await qualifyGeneratedInputs(process.argv[2],process.argv[3]);}
  catch(error){console.error(error.message);process.exitCode=1;}
}
