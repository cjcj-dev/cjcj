import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {prepareNativeCompilerSource} from './native-compiler-input.mjs';
import {command,fileDigest} from './sdk-flow.mjs';
const input=JSON.parse(await fs.readFile(process.env.NATIVE_SOURCE_REENTRY_INPUT,'utf8'));
const work=await fs.mkdtemp(path.join(input.work,'official-'));
console.log('OFFICIAL_REENTRY_WORK='+work);
const records=[],run=async(argv,options={})=>{
 try{return await command(argv,{...options,records});}
 finally{await fs.writeFile(path.join(work,'commands.json'),JSON.stringify(records,null,2));}
};
const selected={...input,build:path.join(work,'build'),install:path.join(work,'install')};
let prepared;
test('complete official configure and ExternalProject recover without recopy or patch replay',async()=>{
 prepared=await prepareNativeCompilerSource(selected,run);
 const configure=['cmake','-G','Ninja','-S',prepared.compiler,'-B',selected.build,
  '-DCMAKE_BUILD_TYPE=Release','-DCMAKE_C_COMPILER=/usr/lib/llvm-15/bin/clang','-DCMAKE_CXX_COMPILER=/usr/lib/llvm-15/bin/clang++',
  '-DCANGJIE_BUILD_CJC=OFF','-DCANGJIE_BUILD_STD_SUPPORT=OFF','-DCANGJIE_BUILD_TESTS=OFF',
  '-DCANGJIE_CODEGEN_CJNATIVE_BACKEND=OFF','-DCANGJIE_SKIP_BUILD_CLANG_RT=ON',
  '-DCMAKE_INSTALL_PREFIX='+selected.install];
 await assert.rejects(run([...configure,'-DCANGJIE_ENABLE_COMPILER_TSAN=ON']),error=>error.rc===1);
 const bounds=path.join(prepared.compiler,'third_party/boundscheck/CMakeLists.txt');
 assert.equal(await fileDigest(bounds),await fileDigest(path.join(prepared.compiler,'third_party/cmake/BoundsCheck.cmake')));
 const before=records.length,boundsStat=await fs.stat(bounds);
 console.log('OFFICIAL_SOURCE_RECOVERY_ASSERT_REACHED bounds');
 assert.deepEqual(await prepareNativeCompilerSource(selected,run),prepared);
 assert.equal(records.length,before,'resume does not replay source commands');
 assert.equal((await fs.stat(bounds)).ino,boundsStat.ino);
 await run([...configure,'-DCANGJIE_ENABLE_COMPILER_TSAN=OFF']);
 const bin=path.join(work,'compiler-wrapper');await fs.mkdir(bin);
 const wrapper='#!'+process.execPath+'\nimport {spawnSync} from "node:child_process";\nif(process.env.FAIL_DEPENDENCY_CONFIGURE==="1"&&process.argv.some(arg=>arg.endsWith("/src/idl_gen_cangjie.cpp")))process.exit(42);\nconst r=spawnSync("/usr/lib/llvm-15/bin/clang",process.argv.slice(2),{stdio:"inherit"});process.exit(r.status??1);\n';
 await fs.writeFile(path.join(bin,'clang'),wrapper,{mode:0o755});
 await fs.writeFile(path.join(bin,'clang++'),wrapper.replace('/usr/lib/llvm-15/bin/clang','/usr/lib/llvm-15/bin/clang++'),{mode:0o755});
 const build=['cmake','--build',selected.build,'--target','flatbuffers','-j','8'];
 await assert.rejects(run(build,{env:{PATH:bin+':'+process.env.PATH,FAIL_DEPENDENCY_CONFIGURE:'1'}}),error=>error.rc===1);
 const idl=path.join(prepared.compiler,'third_party/flatbuffers/src/idl_gen_cangjie.cpp');
 assert.match(await fs.readFile(idl,'utf8'),/MapFbsNamespaceToCangjiePackage/);
 const patchBytes=await fileDigest(idl),patchStat=await fs.stat(idl);
 console.log('OFFICIAL_SOURCE_RECOVERY_ASSERT_REACHED patch');
 assert.deepEqual(await prepareNativeCompilerSource(selected,run),prepared);
 assert.equal(await fileDigest(idl),patchBytes);assert.equal((await fs.stat(idl)).ino,patchStat.ino);
 await run(build,{env:{PATH:bin+':'+process.env.PATH,FAIL_DEPENDENCY_CONFIGURE:'0'}});
 await prepareNativeCompilerSource(selected,run);
 await run(build,{env:{PATH:bin+':'+process.env.PATH,FAIL_DEPENDENCY_CONFIGURE:'0'}});
 const flatc=path.join(selected.build,'bin/flatc');
 await run([flatc,'--version']);
 const schema=path.join(input.compiler,'schema/CjoFormat.fbs'),out=path.join(work,'generated');await fs.mkdir(out);
 await run([flatc,'--no-warnings','-c','-o',out,schema]);
 assert.ok((await fs.stat(path.join(out,'CjoFormat_generated.h'))).size>10000);
 // Official install is the ExternalProject's normal install, not a manual file substitute.
 const moved=path.join(work,'relocated');await fs.cp(path.join(selected.build,'bin'),path.join(moved,'bin'),{recursive:true});
 await run([path.join(moved,'bin/flatc'),'--no-warnings','-c','-o',out,schema]);
 const dirty=spawnSync('git',['-C',input.compiler,'status','--porcelain','--untracked-files=no'],{encoding:'utf8'});
 assert.equal(dirty.status,0);assert.equal(dirty.stdout.trim(),'');
 await fs.writeFile(path.join(work,'result.json'),JSON.stringify({source:prepared.source,flatc:{path:flatc,sha256:await fileDigest(flatc)},
  scope:'complete official root configure and FlatBuffers target/install only; full N/AST/SDK NOT_RUN',commands:records},null,2));
});
test('a different explicit selection cannot overwrite a prepared build; missing source is rejected',async()=>{
 assert.ok(prepared);
 await assert.rejects(prepareNativeCompilerSource({...selected,commit:'0'.repeat(40)},run),/NATIVE_COMPILER_SOURCE_SELECTION_CHANGED/);
 const fresh={...selected,build:path.join(work,'wrong-source'),install:path.join(work,'wrong-install')};
 const missing=input.compilerArchive?{...fresh,compilerArchive:{...input.compilerArchive,file:path.join(work,'missing.tar')}}:{...fresh,compiler:path.join(work,'missing')};
 await assert.rejects(prepareNativeCompilerSource(missing,run),/ENOENT/);
 const wrong=input.compilerArchive?{...fresh,compilerArchive:{...input.compilerArchive,sha256:'0'.repeat(64)}}:{...fresh,commit:'0'.repeat(40)};
 await assert.rejects(prepareNativeCompilerSource(wrong,run),/NATIVE_SOURCE_(?:COMMIT|ARCHIVE_DIGEST)/);
 console.log('OFFICIAL_SOURCE_BAD_INPUT_CONTROL_REACHED');
});
