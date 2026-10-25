#!/usr/bin/env zx
// Fixed compiler CMake targets build the complete native LLVM/CJDB dependency closure.
import fs from 'node:fs/promises';
import {applyCompilerCjdbPatches,applyCompilerWindowsPatches,applyCompilerSchemaInstall} from '../../build/srcbuild/stages/fetch.mjs';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
import {command,copyOutputs,atomicJson,readJson,fileDigest} from './sdk-flow.mjs';
import {materializeNativeSource} from './sdk-source.mjs';
import {nativeHostFlatc} from './native-shim-inputs.mjs';
import {prepareNativeCompilerSource} from './native-compiler-input.mjs';
import {nativeAstInstallation} from './native-ast-inputs.mjs';
import {pythonConfiguration,verifyCjdbPythonConfiguration,verifyCjdbPythonInstallation,pythonSourceInputs} from './sdk-cjdb-python.mjs';
import {sdkPlatform} from './sdk-platform.mjs';
import {execute} from './sdk-io.mjs';
import {nativeWindowsPython} from './native-python-windows.mjs';
import {copyWindowsPythonInstallation} from './native-python-install.mjs';
import {probeWindowsToolchain,windowsInstalledEnvironment} from './native-windows-toolchain.mjs';
export const CJDB_SHIM_CXX_FLAGS=Object.freeze(['-std=c++17','-O2','-fPIC','-fno-rtti','-fno-exceptions','-DNDEBUG']);
export async function compileCjdbShim({flatc, compiler, llvm, llvmBuild, flatbuffers,
  generatedHeaders, repository, object, clang, launcher, env, commit, sourceArchive,
  compilerCommit, llvmCommit, install}, run) {
 if(![commit,compilerCommit,llvmCommit].every(value=>/^[a-f0-9]{40}$/.test(value||'')))
  throw Error('NATIVE_SHIM_SOURCE_REQUIRED');
 const actual=await materializeNativeSource({source:repository,commit,output:object,
  ...(sourceArchive?{'source-archive':sourceArchive.file,'source-archive-sha256':sourceArchive.sha256}:{})},run);
 const source={root:repository,commit:actual,...(sourceArchive?{archive:sourceArchive}:{})};
 const schema=path.join(compiler,'schema/CjoFormat.fbs');
 const header=path.join(generatedHeaders,'flatbuffers/CjoFormat_generated.h');
 await fs.mkdir(path.dirname(header), {recursive: true});
 // No ambient include search may substitute an older schema/header.
 const cleanEnv={...process.env,...env};
 for(const key of ['CPATH','CPLUS_INCLUDE_PATH','C_INCLUDE_PATH','OBJC_INCLUDE_PATH'])cleanEnv[key]='';
 const commands=[];
 const invoke=async argv=>{const result=await run(argv,{env:cleanEnv});commands.push(result);};
 await invoke([flatc.file, '--no-warnings', '-c', '-o', path.dirname(header),schema]);
 const argv=[...(launcher ? [launcher] : []), clang, ...CJDB_SHIM_CXX_FLAGS,
  '-MMD','-MF',object+'.d','-I'+llvm+'/llvm/include', '-I'+llvmBuild+'/include',
  '-I'+flatbuffers+'/include', '-I'+generatedHeaders,
  '-c',path.join(repository,'runtime_shim/cjselfhost_llvmshim.cpp'),'-o',object];
 await invoke(argv);
 const objectPath=path.relative(install,object).split(path.sep).join('/');
 if(objectPath!=='third_party/llvm/fixed-llc/cjselfhost_llvmshim.o')throw Error('NATIVE_SHIM_OBJECT_PATH');
 const row=async file=>({bytes:(await fs.stat(file)).size,sha256:await fileDigest(file)});
 return {source,compiler:{commit:compilerCommit,schema:'schema/CjoFormat.fbs'},llvm:{commit:llvmCommit},
  flatc,object:{path:objectPath,...await row(object)},configuration:{argv,llvmBuild,generatedHeaders},commands};
}

export async function nativeCjdb(config) {
 const {llvm,runtime,bounds,flatbuffers,libedit,xml2Archive,build,install,commits,shimSource}=config;
 let tools=config.tools;
 let python=config.python,compiler=config.compiler;
 const available=os.availableParallelism(),selectedJobs=config.jobs??available;
 if(!Number.isSafeInteger(selectedJobs)||selectedJobs<1)throw new Error('NATIVE_JOBS');
 const selectedLinkJobs=config.linkJobs??Math.min(selectedJobs,8);
 if(!Number.isSafeInteger(selectedLinkJobs)||selectedLinkJobs<1)throw new Error('NATIVE_LINK_JOBS');
 const records=[],jobs=String(selectedJobs),linkJobs=String(selectedLinkJobs),launcher=tools.launcher;
 config={...config,jobs:selectedJobs,linkJobs:selectedLinkJobs};
 if(process.env.GITHUB_ACTIONS==='true'&&!/^sccache(?:\.exe)?$/i.test(path.basename(launcher||'')))throw new Error('GHA_SCCACHE_REQUIRED');
 const platform=config.platform || ({linux:'linux',darwin:'darwin',win32:'windows'}[process.platform]+'_'+(process.arch==='arm64'?'aarch64':'x86_64'));
 const native=sdkPlatform(platform),delimiter=native.os==='win32'?';':':';
 if(process.platform!==native.os||process.arch!==native.arch)throw new Error('NATIVE_CJDB_RUNNER_REQUIRED');
 if(config.pythonProducer){
  if(native.os!=='win32'||python||config.pythonInputs)throw Error('NATIVE_PYTHON_PRODUCER_CONFLICT');
  const produced=await nativeWindowsPython({jobs:selectedJobs,...config.pythonProducer});
  config={...config,...produced};python=produced.python;
 }
 // BuildCJDB.cmake disables libedit on Windows. Unix uses the native ABI directory.
 const editDir=native.os==='win32'?null:config.libeditLibraryDirectory || path.join(libedit,'lib',...(native.os==='linux'?[(native.arch==='arm64'?'aarch64':'x86_64')+'-linux-gnu']:[]));
 const env={...process.env,CMAKE_BUILD_PARALLEL_LEVEL:jobs,
  [native.loader]:[python,python+'/lib',editDir,process.env[native.loader]].filter(Boolean).join(delimiter),
  ...(native.loader==='PATH'?{}:{PATH:[python+'/bin',process.env.PATH].join(delimiter)})};
 const selectedPython=await pythonConfiguration(python,platform,execute,config.pythonExecutable);
 const run=(argv,options={})=>command(argv,{env,records,...options});
 const prepared=await prepareNativeCompilerSource({compiler,compilerArchive:config.compilerArchive,
  bounds,flatbuffers,build,install,commits,commit:commits.compiler},run);
 compiler=prepared.compiler;
 // Preserve the existing frontend ordering fixes on the selected upstream source.
 applyCompilerCjdbPatches(compiler);
 applyCompilerSchemaInstall(compiler);
 const compilerSource=prepared.source;
 let windowsToolchain;
 if(native.os==='win32') {
  applyCompilerWindowsPatches(compiler);
  windowsToolchain=await probeWindowsToolchain({tools,compiler,work:build+'.toolchain',env});
  tools={...tools,cc:windowsToolchain.cc,cxx:windowsToolchain.cxx};
  config={...config,tools};
  env.PATH=[path.dirname(tools.cc),env.PATH].join(';');
 }
 if(await fileDigest(xml2Archive.file)!==xml2Archive.sha256)throw new Error('XML2_ARCHIVE_IDENTITY');
 const xml2=build+'/xml2-source';await fs.mkdir(xml2,{recursive:true});
 await run(['tar','-xJf',xml2Archive.file,'--strip-components=1','-C',xml2]);
 await run([selectedPython.executable,'-I','-c','import sys,sysconfig,ssl,_ctypes; assert sys.version_info[:2]==(3,11); print(sys.version)']);
 const pythonArgs=[`-DPython3_EXECUTABLE=${selectedPython.executable}`,`-DPython3_INCLUDE_DIR=${selectedPython.include}`,`-DPython3_LIBRARY=${selectedPython.library}`];
 const toolchain=config.toolchain || path.join(compiler,'cmake',platform==='windows_x86_64'?'mingw_x86_64_toolchain.cmake':platform+'_toolchain.cmake');
 await fs.stat(toolchain);
 const llvmArgs=[`-DCANGJIE_RUNTIME_SOURCE_DIR=${runtime}`,`-DCMAKE_C_COMPILER_LAUNCHER=${launcher}`,
  `-DCMAKE_CXX_COMPILER_LAUNCHER=${launcher}`,`-DLLVM_PARALLEL_LINK_JOBS=${linkJobs}`,`-DCJ_LLVM_COMMIT=${commits.llvm}`];
 await run([tools.cmake||'cmake','-G','Ninja','-S',compiler,'-B',build,'-DCMAKE_BUILD_TYPE=Release',
  `-DCMAKE_TOOLCHAIN_FILE=${toolchain}`,`-DCMAKE_C_COMPILER=${tools.cc}`,
  `-DCMAKE_CXX_COMPILER=${tools.cxx}`,`-DCMAKE_C_COMPILER_LAUNCHER=${launcher}`,`-DCMAKE_CXX_COMPILER_LAUNCHER=${launcher}`,
  '-DCANGJIE_BUILD_CJC=ON','-DCANGJIE_BUILD_STD_SUPPORT=ON','-DCANGJIE_BUILD_TESTS=OFF','-DCANGJIE_BUILD_CJDB=ON',
  ...(windowsToolchain?[`-DCANGJIE_TOOLCHAIN_RUNTIME_FILES=${windowsToolchain.runtimeFiles.join(';')}`]:[]),
  '-DCANGJIE_LLVM_BUILD_TYPE=Release','-DCANGJIE_CJDB_BUILD_TYPE=Release',`-DCANGJIE_CJNATIVE_SOURCE_DIR=${llvm}`,
  `-DCANGJIE_RUNTIME_SOURCE_DIR=${runtime}`,`-DCANGJIE_XML2_SOURCE_DIR=${xml2}`,
  `-DCMAKE_PREFIX_PATH=${[python,libedit,build+'/third_party/xml2'].filter(Boolean).join(';')}`,`-DPython3_EXECUTABLE=${selectedPython.executable}`,
  `-DLLVM_BUILD_ARG=${pythonArgs.join(';')}`,`-DCANGJIE_LLVM_BUILD_ARGS=${llvmArgs.join(';')}`,
  `-DCANGJIE_LINK_JOB_POOL=${linkJobs}`,`-DCMAKE_INSTALL_PREFIX=${install}`]);
 const targets=[...new Set([...native.nativeTargets,'cangjie-ast-support'])];
 await run([tools.cmake||'cmake','--build',build,'--target',...targets.filter(t=>!['all','install'].includes(t)),'-j',jobs]);
 await run([tools.cmake||'cmake','--build',build,'-j',jobs]);await run([tools.cmake||'cmake','--install',build]);
 const astInstallation=await nativeAstInstallation({compiler,build,install,platform,source:compilerSource,commands:records,cmakeCommand:tools.cmake||'cmake'});
 // CMake is the only native library installer; Python and libedit are explicit
 // runtime dependencies copied once, with conflicts diagnosed at installation.
 const nativeRoot=install+'/third_party/llvm';
 let pythonInstallationInput;
 if(native.os==='win32')pythonInstallationInput=await copyWindowsPythonInstallation({root:python,nativeRoot,inputs:config.pythonInputs});
 else await copyOutputs(nativeRoot,['bin','lib','include','share'].map(rel=>({from:python+'/'+rel,to:rel,owner:'Python',exclude:config.pythonExclude?.[rel]||[]})));

 const edit=editDir;
 if(edit)await copyOutputs(nativeRoot,(await fs.readdir(edit)).filter(n=>(native.os==='darwin'?/^libedit.*\.dylib$/:native.os==='win32'?/^(?:lib)?edit.*\.dll$/i:/^libedit\.so(?:\.|$)/).test(n)).map(name=>({from:edit+'/'+name,to:'lib/'+name,owner:'libedit'})));
 const observed=await verifyCjdbPythonConfiguration(python,build+'/third_party/lldb-build',execute,platform,selectedPython.executable);
 const installed=await verifyCjdbPythonInstallation(python,nativeRoot,execute,platform,selectedPython.executable);
 const pythonSource=await pythonSourceInputs({...config.pythonInputs,root:python,nativeRoot,platform,selected:observed.selected});
 const fixed=nativeRoot+'/fixed-llc';await fs.mkdir(fixed,{recursive:true});
 const nativeShim=await compileCjdbShim({flatc:await nativeHostFlatc(install,astInstallation),compiler,llvm,llvmBuild:build+'/third_party/cjnative-prefix/src/cjnative-build',flatbuffers,
  generatedHeaders:build+'/shim-schema',repository:shimSource,object:fixed+'/cjselfhost_llvmshim.o',clang:tools.cxx,launcher,env,install,commit:commits.shim,sourceArchive:config.shimArchive,compilerCommit:commits.compiler,llvmCommit:commits.llvm},run);
 if(windowsToolchain) {
  const manifest=(await fs.readFile(build+'/install_manifest.txt','utf8')).split(/\r?\n/).map(n=>path.resolve(n).toLowerCase());
  const installedFiles=[];
  for(const directory of ['bin','third_party/llvm/bin','third_party/flatbuffers/bin'])for(const row of windowsToolchain.facts.runtimes) {
   const file=path.join(install,directory,path.basename(row.path));
   if(!manifest.includes(path.resolve(file).toLowerCase())||await fileDigest(file)!==row.sha256)throw Error('WINDOWS_TOOLCHAIN_RUNTIME_INSTALL '+file);
   installedFiles.push({path:path.relative(install,file).split(path.sep).join('/'),sha256:row.sha256});
  }
  const installedEnv=windowsInstalledEnvironment(process.env,install);
  for(const relative of ['third_party/llvm/bin/llc.exe','third_party/flatbuffers/bin/flatc.exe'])
   await run([path.join(install,relative),'--version'],{env:installedEnv,cwd:install});
  const original='share/cjcj/build-inputs/windows-toolchain.json';
  await fs.mkdir(path.dirname(path.join(install,original)),{recursive:true});
  await fs.copyFile(windowsToolchain.record,path.join(install,original));
  windowsToolchain={compiler:windowsToolchain.facts.compiler,installedFiles,original:{path:original,sha256:await fileDigest(path.join(install,original))}};
 }
 await atomicJson(install+'/BUILD-INPUTS.json',{commits,compilerSource,platform,llvmLibrary:{file:'third_party/llvm/'+native.llvmDirectory+'/'+native.llvmLibrary,sha256:await fileDigest(nativeRoot+'/'+native.llvmDirectory+'/'+native.llvmLibrary)},targets,
  astInstallation,nativeShim,pythonInstallationInput,...(windowsToolchain?{windowsToolchain}:{}),configuration:config,python:{configured:observed,installed},pythonSource,commands:records});
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{await nativeCjdb(await readJson(process.argv[2]));}catch(e){console.error(e.stack);process.exitCode=e.rc||1;}
}
