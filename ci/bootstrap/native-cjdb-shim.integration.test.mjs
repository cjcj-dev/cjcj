import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFile,spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
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

test('public native-stage selects independent source-owned shim and links the real macro package',async()=>{
 const {sdk,host,producerTarget,shimInstall,shimSource,sourceArchive,zx}=input.consumer;
 const source=path.join(root,'consumer-source'),target=path.join(root,'consumer-target'),output=path.join(root,'consumer-install');
 await fs.mkdir(source,{recursive:true});
 // Fixed current shim sources, plus a bounded CJ consumer fixture. No compiler
 // package is rebuilt, and the existing producer target is only a link input.
 await fs.cp(path.join(shimSource,'runtime_shim'),path.join(source,'runtime_shim'),{recursive:true});
 const packages=[];
 for(const name of await fs.readdir(producerTarget)){
  const dir=path.join(producerTarget,name);
  if(!(await fs.stat(dir)).isDirectory())continue;
  const members=await fs.readdir(dir);
  if(members.some(n=>n.endsWith('.cjo')))packages.push({dir,archives:members.filter(n=>n.endsWith('.a')).map(n=>path.join(dir,n))});
 }
 assert(packages.some(p=>p.archives.some(a=>a.endsWith('/libmacro_pkg@cjcj.a'))));
 const compile='-O0 '+packages.map(p=>'--import-path '+p.dir).join(' ');
 const link='--export-dynamic --trace-symbol=CJSelfhostCheckMacroRuntimeBinding --start-group '+packages.flatMap(p=>p.archives).join(' ')+' --end-group runtime_shim/cjselfhost_llvmshim.o '+sdk+'/third_party/llvm/lib/libLLVM-15.so -lstdc++ -ldl';
 const manifest='[package]\ncjc-version = "1.1.0"\nname = "cjc"\norganization = "cjcj"\nversion = "0.0.1"\nsrc-dir = "src"\noutput-type = "executable"\ncompile-option = '+JSON.stringify(compile)+'\nlink-option = '+JSON.stringify(link)+'\n';
 await fs.writeFile(path.join(source,'cjpm.toml'),manifest);
 await fs.mkdir(path.join(source,'src'));
 await fs.writeFile(path.join(source,'src/main.cj'),'package cjcj::cjc\nimport cjcj::macro_pkg.*\nmain(): Int64 {\n    let handle = OpenMacroLibrary("/nonexistent-shim-consumer")\n    println("MACRO_LINK_CONSUMER_REACHED")\n    return 0\n}\n');
 const argv=[process.execPath,fileURLToPath(new URL('./sdk-native-stage.mjs',import.meta.url)),
  '--kind','compiler','--source',source,'--commit',input.commit,
  '--source-archive',sourceArchive.file,'--source-archive-sha256',sourceArchive.sha256,
  '--sdk',sdk,'--host',host,'--output',output,'--target-dir',target,
  '--phase','stage2','--platform','linux_x86_64','--jobs','8','--heap','2GB','--zx',zx];
 const env={...process.env,CC:'/usr/bin/gcc',CXX:'/usr/bin/g++'};
 const calls=[];
 async function invoke(label,args,want=0){
  const out=await fs.open(path.join(root,label+'.stdout'),'wx'),err=await fs.open(path.join(root,label+'.stderr'),'wx');
  const p=spawnSync(args[0],args.slice(1),{cwd:root,env,stdio:['ignore',out.fd,err.fd],timeout:180000});
  await out.close();await err.close();calls.push({label,argv:args,rc:p.status,signal:p.signal,error:p.error?.message});
  await fs.writeFile(path.join(root,'consumer-commands.json'),JSON.stringify(calls,null,2));
  assert.ifError(p.error);assert.equal(p.status,want,await fs.readFile(path.join(root,label+'.stderr'),'utf8'));
 }
 await invoke('old-installed-refused',argv,1);
 assert.match(await fs.readFile(path.join(root,'old-installed-refused.stderr'),'utf8'),/NATIVE_SHIM_COMPILER_SOURCE/);
 assert.equal(await fs.stat(path.join(target,'release')).catch(()=>null),null,'stale input refused before compiler');
 console.log('STALE_SHIM_SELECTION_ASSERT_REACHED');
 await invoke('native-stage',[...argv,'--shim-install',shimInstall]);
 const trace=await fs.readFile(path.join(root,'native-stage.stderr'),'utf8');
 assert.match(trace,/libmacro_pkg@cjcj.a.*reference to.*CJSelfhostCheckMacroRuntimeBinding/);
 assert.match(trace,/cjselfhost_llvmshim.o.*definition of.*CJSelfhostCheckMacroRuntimeBinding/);
 const facts=JSON.parse(await fs.readFile(path.join(output,'compiler-inputs.json'),'utf8'));
 assert.equal(facts.nativeShim.source.commit,input.commit);
 assert.equal(facts.nativeShim.object.sha256,await fileDigest(path.join(source,'runtime_shim/cjselfhost_llvmshim.o')));
 assert.equal(await fs.readFile(path.join(source,'cjpm.toml'),'utf8'),manifest);
 // The installed executable uses the original SDK execution domain, not the
 // shim-only installation (which contains no runtime, std or compiler).
 env.LD_LIBRARY_PATH=sdk+'/runtime/lib/linux_x86_64_cjnative:'+sdk+'/third_party/llvm/lib:'+sdk+'/tools/lib';
 env.CANGJIE_HOME=sdk;
 await invoke('installed-consumer',[path.join(output,'bin/cjcj-stage1')]);
 assert.match(await fs.readFile(path.join(root,'installed-consumer.stdout'),'utf8'),/MACRO_LINK_CONSUMER_REACHED/);
 console.log('NATIVE_STAGE_MACRO_LINK_AND_INSTALL_ASSERT_REACHED '+root);
});
