// Install native toolchain components from the same completed LLVM CMake graph.
// The compiler's outer installation deliberately filters its bin/include trees.
import fs from 'node:fs/promises';
import path from 'node:path';
import {sdkPlatform} from './sdk-platform.mjs';
import {execute} from './sdk-io.mjs';
import {fileDigest} from './sdk-flow.mjs';

export async function installNativeClang({build,install,platform,cmake='cmake',env},run) {
 const native=sdkPlatform(platform),llvmBuild=path.join(build,'third_party/cjnative-prefix/src/cjnative-build');
 const root=path.join(install,'third_party/llvm');
 const components=['clang','clang-resource-headers','llvm-headers'];
 for(const component of components)
  await run([cmake,'--install',llvmBuild,'--prefix',root,'--component',component]);
 const clang=path.join(root,'bin','clang'+native.exe);
 const installedEnv={...env,PATH:[path.join(root,'bin'),env.PATH].filter(Boolean).join(native.os==='win32'?';':':')};
 if(native.loader!=='PATH')installedEnv[native.loader]=[path.join(root,'lib'),env[native.loader]].filter(Boolean).join(':');
 for(const key of ['CPATH','C_INCLUDE_PATH','CPLUS_INCLUDE_PATH','OBJC_INCLUDE_PATH','SDKROOT'])installedEnv[key]='';
 const argv=[clang,'-print-resource-dir'];
 let query;
 try {const r=await execute(argv[0],argv.slice(1),{env:installedEnv});query={argv,rc:0,stdout:r.stdout,stderr:r.stderr};}
 catch(error){query={argv,rc:error.code??null,signal:error.signal??null,stdout:error.stdout,stderr:error.stderr};throw error;}
 finally {console.log(JSON.stringify({event:'native-clang-resource',...query}));}
 const resource=await fs.realpath(query.stdout.trim()),realRoot=await fs.realpath(root);
 if(!resource.startsWith(realRoot+path.sep))throw Error('NATIVE_CLANG_RESOURCE_OUTSIDE_INSTALL '+resource);
 const manifests={};
 for(const component of components)manifests[component]=(await fs.readFile(path.join(llvmBuild,'install_manifest_'+component+'.txt'),'utf8')).split(/\r?\n/).filter(Boolean);
 const source=path.join(build,'installed-clang-consumer.c'),object=path.join(build,'installed-clang-consumer.o'),deps=path.join(build,'installed-clang-consumer.d');
 await fs.writeFile(source,'#include <stddef.h>\n#include <stdint.h>\n#include <stdarg.h>\n_Static_assert(sizeof(uintptr_t)==sizeof(void *), "native pointer width");\nint native_clang_header_consumer(int n, ...) { va_list a; va_start(a,n); int v=va_arg(a,int); va_end(a); return v+(int)offsetof(struct { char c; int i; },i); }\n');
 await run([clang,'-ffreestanding','-nostdlibinc','-MD','-MF',deps,'-c',source,'-o',object],{env:installedEnv});
 const files=['bin/clang'+native.exe,'bin/clang++'+native.exe,'include/llvm-c/Core.h','include/llvm/Config/llvm-config.h'];
 const installed={};
 for(const relative of files) {
  const file=path.join(root,relative),stat=await fs.stat(file);
  if(!stat.isFile()||!stat.size)throw Error('NATIVE_CLANG_INSTALL_FILE '+relative);
  installed[relative]={bytes:stat.size,sha256:await fileDigest(file)};
 }
 // The header set is owned by LLVM's component, not a CI-curated substitute.
 for(const header of ['stddef.h','stdint.h','stdarg.h']) {
  const file=path.join(resource,'include',header);
  if(!manifests['clang-resource-headers'].some(item=>path.resolve(item)===path.resolve(file)))throw Error('NATIVE_CLANG_HEADER_NOT_INSTALLED '+file);
 }
 return {components,files:installed,resource:path.relative(root,resource),resourceQuery:query,
  consumer:{source,object,dependencies:deps},manifests};
}
