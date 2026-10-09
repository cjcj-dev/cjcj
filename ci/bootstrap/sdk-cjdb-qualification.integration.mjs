#!/usr/bin/env zx
// Qualification-only integration over real dependencies from a failed native
// graph. It never mints a successful LLVM/LLDB receipt or substitutes a library.
import fs from 'node:fs/promises';
import path from 'node:path';
import test,{after} from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {prepareQualification,exportQualification,verifyQualificationCertificate,CJDB_INPUTS} from './sdk-cjdb-qualification.mjs';
import {readJson,inventory,fileDigest,atomicJson} from './sdk-manifest.mjs';

const request=await readJson(process.env.CJDB_REQUEST), root=process.env.CJDB_QUALIFICATION_EVIDENCE;
await fs.mkdir(root,{recursive:true});
const directory=request.directory, compiler=path.join(directory,'source-inputs/compiler'),build=path.join(directory,'build/compiler');
const roots={llvm:path.join(directory,'source-inputs/llvm'),compiler,bounds:path.join(compiler,'third_party/boundscheck'),build,demangler:path.join(build,'cangjie-demangler')};
const gate=fileURLToPath(new URL('./sdk-cjdb-qualification.mjs',import.meta.url));
const prepared=await prepareQualification(request,roots,path.join(root,'qualification'));
const records=[];
function command(name,argv){const started=performance.now(),r=spawnSync(argv[0],argv.slice(1),{encoding:'utf8',env:process.env});records.push({name,argv,rc:r.status,signal:r.signal,wall:(performance.now()-started)/1000});return r;}
let certificate,files;
test('actual CMake preconfigure hook reads the five real producer bytes',async()=>{
  const r=command('preconfigure-hook',[request.component.config.tools.cmake.path,'-P',prepared.hook]);
  await fs.writeFile(path.join(root,'preconfigure.log'),r.stdout+r.stderr);
  assert.equal(r.status,0,r.stderr);
  const pre=await readJson(path.join(root,'qualification/preconfigure.json'));
  console.log('CJDB_FIVE_REAL_BYTES_ASSERT_REACHED');
  assert.deepEqual(Object.keys(pre.body.generated).sort(),Object.keys(CJDB_INPUTS).sort());
  for(const [rel,row] of Object.entries(pre.body.generated))assert.equal(row.sha256,await fileDigest(path.join(roots.llvm,rel)),rel);
  const artifacts=path.join(root,'dependency-capsule');
  certificate=await exportQualification(prepared.contractFile,artifacts);files=await inventory(artifacts);
  // This is the genuine dependency capsule, not a completed native SDK.
  await atomicJson(path.join(root,'capsule-files.json'),files);
});
test('formal certificate consumer observes missing, changed and extra generated records',async()=>{
  // Independent of the first test so a focused consumer cut executes the
  // normal producer and reaches this assertion without a preceding test.
  if(!certificate){const r=command('preconfigure-hook',[request.component.config.tools.cmake.path,'-P',prepared.hook]);assert.equal(r.status,0,r.stderr);const artifacts=path.join(root,'dependency-capsule');certificate=await exportQualification(prepared.contractFile,artifacts);files=await inventory(artifacts);}
  assert.equal(verifyQualificationCertificate(request.component,request.identity.buildId,certificate,files,directory),certificate);
  console.log('CJDB_MISSING_CERTIFICATE_ASSERT_REACHED');
  assert.throws(()=>verifyQualificationCertificate(request.component,request.identity.buildId,undefined,files,directory),/CJDB_QUALIFICATION_RECEIPT.*both actual phase records/);
  for(const rel of Object.keys(CJDB_INPUTS)){
    const absent=structuredClone(files);delete absent[`native-inputs/${rel}`];
    assert.throws(()=>verifyQualificationCertificate(request.component,request.identity.buildId,certificate,absent,directory),/CJDB_QUALIFICATION_RECEIPT/);
    const changed=structuredClone(files);changed[`native-inputs/${rel}`].sha256='0'.repeat(64);
    assert.throws(()=>verifyQualificationCertificate(request.component,request.identity.buildId,certificate,changed,directory),/CJDB_QUALIFICATION_RECEIPT/);
  }
  const extra=structuredClone(files);extra['native-inputs/unexpected']={...files['native-inputs/qualification.json']};
  assert.throws(()=>verifyQualificationCertificate(request.component,request.identity.buildId,certificate,extra,directory),/extra or missing sealed qualification/);
});
test('preseal refuses a changed actual generated producer byte',async()=>{
  // Mutate an isolated source clone, leaving original failed production
  // sources, objects and the five source files untouched.
  const clone=path.join(root,'isolated-llvm'),git=request.component.config.tools.git.path;
  const r=command('isolated-clone',[git,'clone','--shared','--no-checkout',roots.llvm,clone]);assert.equal(r.status,0,r.stderr);
  const checkout=command('isolated-checkout',[git,'-C',clone,'checkout','--detach',request.component.source.commit]);assert.equal(checkout.status,0,checkout.stderr);
  for(const rel of Object.keys(CJDB_INPUTS)){const dest=path.join(clone,rel);await fs.mkdir(path.dirname(dest),{recursive:true});await fs.copyFile(path.join(roots.llvm,rel),dest);}
  const isolated=await prepareQualification(request,{...roots,llvm:clone},path.join(root,'isolated-qualification'));
  const before=command('isolated-preconfigure',[process.execPath,gate,isolated.contractFile,'preconfigure']);assert.equal(before.status,0,before.stderr);
  const rel='utils/boundscheck/include/securec.h';await fs.appendFile(path.join(clone,rel),'\n/* deliberate qualification fault */\n');
  const rejected=command('isolated-preseal',[process.execPath,gate,isolated.contractFile,'preseal']);
  await fs.writeFile(path.join(root,'changed-input.log'),rejected.stdout+rejected.stderr);
  console.log('CJDB_CHANGED_REAL_INPUT_ASSERT_REACHED');
  assert.equal(rejected.status,1);assert.match(rejected.stderr,/CJDB_GENERATED_BYTES.*securec.h/);
});
test('fixed LLVM project invokes the preconfigure gate and retains the actual dirty stamp',async()=>{
  const configured=await prepareQualification(request,roots,path.join(root,'project-qualification'));
  const actualRecipe=await fs.readFile(path.join(build,'third_party/cjnative-prefix/tmp/cjnative-cfgcmd.txt'),'utf8');
  const fields=actualRecipe.match(/^cmd='([\s\S]*)'\s*$/)?.[1].split(';');assert.ok(fields,'actual native configure command required');
  const forbiddenFlags='-DCMAKE_CXX_FLAGS=-include cstdint -include unordered_map -include map -include vector -include string';
  const argv=fields.filter(field=>field!==forbiddenFlags).map(field=>field.replaceAll('|',';').replace('<SOURCE_DIR><SOURCE_SUBDIR>',path.join(roots.llvm,'llvm')));
  // Configuration only: preserve the original -dirty interpretation. The new
  // plain baseline stamp and native production remain held for review.
  assert.ok(!argv.some(field=>field.startsWith('-DCJ_LLVM_COMMIT=')));
  argv.push('-B',path.join(root,'llvm-project-configuration'),`-DCMAKE_PROJECT_LLVM_INCLUDE_BEFORE=${configured.hook}`);
  const r=command('actual-llvm-project-configure',argv);await fs.writeFile(path.join(root,'llvm-project.log'),r.stdout+r.stderr);
  assert.equal(r.status,0,r.stderr);
  const pre=await readJson(path.join(root,'project-qualification/preconfigure.json'));
  console.log('CJDB_PROJECT_BEFORE_CONFIGURE_ASSERT_REACHED');
  assert.deepEqual(Object.keys(pre.body.generated).sort(),Object.keys(CJDB_INPUTS).sort());
  const configuredText=await fs.readFile(path.join(root,'llvm-project-configuration/build.ninja'),'utf8');
  assert.ok(configuredText.includes(`${request.component.source.commit}-dirty`),'configuration must retain actual old dirty stamp');
});
after(async()=>{await atomicJson(path.join(root,'commands.json'),records);});
