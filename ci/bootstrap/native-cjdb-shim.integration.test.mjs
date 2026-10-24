import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {compileCjdbShim} from './native-cjdb.mjs';
import {nativeHostFlatc,readInstalledNativeShim} from './native-shim-inputs.mjs';
import {command,fileDigest} from './sdk-flow.mjs';
const execute=promisify(execFile);
const request=process.env.NATIVE_SHIM_TEST_INPUT;
if(!request)throw Error('NATIVE_SHIM_TEST_INPUT: fixed real source/tool/config inputs required');
const input=JSON.parse(await fs.readFile(request,'utf8'));
const root=await fs.mkdtemp(path.join(input.work,'shim-integration-'));
const records=[];
const run=async(argv,options={})=>{
 try{return await command(argv,{...options,records});}
 finally{await fs.writeFile(path.join(root,'commands.json'),JSON.stringify(records,null,2));}
};
const flatc=await nativeHostFlatc(input.flatcInstall,input.astInstallation);
const make=async label=>{
 const install=path.join(root,label),object=path.join(install,'third_party/llvm/fixed-llc/cjselfhost_llvmshim.o');
 await fs.mkdir(path.dirname(object),{recursive:true});
 return {...input,flatc,install,object,generatedHeaders:path.join(install,'generated')};
};
test('real complete compileCjdbShim produces a repeatable installed object and preserves source/bytes checks',async()=>{
 const args=await make('actual');
 // Exercise the real archive consumer with a new private source, not the
 // producer's already materialized input. Keep the original handoff untouched.
 if(input.sourceArchive) {
  const file=path.join(root,'shim.tar');await fs.copyFile(input.sourceArchive.file,file);
  args.sourceArchive={...input.sourceArchive,file};args.repository=path.join(root,'source');
 }
 console.log('NATIVE_SHIM_COMPILE_ASSERT_REACHED');
 let result;await assert.doesNotReject(async()=>{result=await compileCjdbShim(args,run);});
 if(args.sourceArchive) {
  await fs.rename(args.sourceArchive.file,args.sourceArchive.file+'.moved');
  const before=records.length;
  await assert.doesNotReject(()=>compileCjdbShim(args,run));
  assert.ok(records.slice(before).some(row=>row.argv.includes('-c')));
  assert.ok(records.slice(before).every(row=>row.argv[0]!=='tar'));
  console.log('NATIVE_SHIM_ARCHIVE_REMOVED_REENTRY_COMPILED');
 }
 const symbols=(await execute('nm',['-g','--defined-only',args.object])).stdout;
 const exported=symbols.split('\n').filter(s=>/\b(?:LLVMGlobalObjectAddStringAttribute|LLVMSelfhost\w+)$/.test(s));
 assert.ok(exported.length>10,'real complete shim exports required, not a small stand-in');
 assert.match(symbols,/\bLLVMGlobalObjectAddStringAttribute$/m);
 const deps=await fs.readFile(args.object+'.d','utf8');
 assert.match(deps,/CjoFormat_generated\.h/);assert.doesNotMatch(deps,/ModuleFormat_generated\.h/);
 const facts={commits:{shim:input.commit,compiler:input.compilerCommit,llvm:input.llvmCommit},nativeShim:result};
 assert.equal((await readInstalledNativeShim({install:args.install,facts})).object.sha256,await fileDigest(args.object));
 const old=await fs.readFile(args.object);await fs.appendFile(args.object,'unexpected bytes');
 console.log('NATIVE_SHIM_INSTALLED_BYTES_ASSERT_REACHED');
 await assert.rejects(readInstalledNativeShim({install:args.install,facts}),/NATIVE_SHIM_INSTALLED_BYTES/);
 await fs.writeFile(args.object,old);
 await readInstalledNativeShim({install:args.install,facts});
 await assert.rejects(readInstalledNativeShim({install:args.install,facts:{...facts,commits:{...facts.commits,shim:'0'.repeat(40)}}}),/NATIVE_SHIM_SOURCE_PAIR/);
 await fs.writeFile(path.join(root,'actual-object.json'),JSON.stringify({facts,exported,dependencies:deps},null,2));
 const out=path.join(root,'independent-schema');await fs.mkdir(out);
 await run([flatc.file,'--no-warnings','-c','-o',out,path.join(input.compiler,'schema/StdAstFormat.fbs')]);
 const generated=path.join(out,'StdAstFormat_generated.h');assert.ok((await fs.stat(generated)).size>1000);
 const wrong=structuredClone(input.astInstallation);
 for(const name of Object.keys(wrong.files))if(/\/bin\/flatc(?:\.exe)?$/.test(name))wrong.files[name].sha256='0'.repeat(64);
 await assert.rejects(nativeHostFlatc(input.flatcInstall,wrong),/NATIVE_SHIM_HOST_FLATC_BYTES/);
 console.log('NATIVE_SHIM_INDEPENDENT_SCHEMA_CONTROL_REACHED');
 const wrongArgs=await make('wrong-source'),before=records.length;
 const wrongSource=input.sourceArchive?{...wrongArgs,repository:path.join(root,'unmaterialized-rejected-shim'),sourceArchive:{...input.sourceArchive,sha256:'0'.repeat(64)}}:{...wrongArgs,commit:'0'.repeat(40)};
 await assert.rejects(compileCjdbShim(wrongSource,run),/NATIVE_SOURCE_(?:COMMIT|ARCHIVE_DIGEST)/);
 assert.equal(await fs.stat(wrongArgs.object).catch(()=>null),null);
 assert.ok(records.slice(before).every(row=>row.argv[0]==='tar'));
 console.log('NATIVE_SHIM_FIXED_SOURCE_CONTROL_REACHED');
});
