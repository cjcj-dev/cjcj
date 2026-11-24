#!/usr/bin/env zx
// The compiler install owns LLVM, cjdb, AST and flatc. Transport that prefix
// directly; rebuilding a selection of LLVM targets loses the plugin's inputs.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {prepareDarwinLldbSource} from '../../../srcbuild/stages/fetch.mjs';
import {sdkPlatform} from '../../../../ci/bootstrap/sdk-platform.mjs';
import {download} from '../../../lib/archive.mjs';
import {preserveNativePythonInput} from '../../../../ci/bootstrap/native-cjdb-job.mjs';
import {nativeCjdb} from '../../../../ci/bootstrap/native-cjdb.mjs';
import {verifyNativeSource} from '../../../../ci/bootstrap/sdk-source.mjs';
import {WINDOWS_PYTHON_SOURCE} from '../../../../ci/bootstrap/native-python-windows.mjs';
import {selectedExecutable} from '../../../../ci/bootstrap/native-windows-toolchain.mjs';
import {selectBuildJobs} from '../../../../ci/build-resources.mjs';
import {nativeLlvmInputs,readSourcePins} from '../../../../ci/native-llvm-inputs.mjs';
import {preparePython,llvmLibrarySymbolProblems,shimRequiredSymbols,shimSymbolProblems} from './build_prepare_llvm.mjs';
import {checkSuperbuildInstall,compilerSource,prepareHost} from './prepare_native_inputs.mjs';

export async function prepareNativeSuperbuild({target,workspace,work,root,env=process.env}) {
  const platform=prepareHost(target).llvm_platform, windows=platform==='windows_x86_64';
  const pair=nativeLlvmInputs(env), pins=readSourcePins(), compiler=compilerSource(env);
  const sources={compiler:path.join(workspace,'compiler'),llvm:path.join(workspace,'llvm-fork'),
    runtime:path.join(workspace,'runtime-source'),flatbuffers:path.join(workspace,'flatbuffers'),
    bounds:path.join(workspace,'runtime-source/runtime/third_party/third_party_bounds_checking_function'),shimSource:workspace};
  const commits={compiler:compiler.commit,llvm:pair.CJCJ_NATIVE_LLVM_REF,runtime:pair.CJCJ_NATIVE_RUNTIME_REF,
    bounds:pins.source.BOUNDS_REF,flatbuffers:pins.llvm.FLATBUFFERS_SHA,shim:env.GITHUB_SHA};
  for(const [key,source] of Object.entries(sources)) {
    const commit=commits[key==='shimSource'?'shim':key];
    if(!/^[a-f0-9]{40}$/.test(commit||''))throw Error('PREPARE_NATIVE_SOURCE '+key);
    await verifyNativeSource({source,commit});
  }
  await fs.mkdir(work,{recursive:true});
  const xml2Archive={file:path.join(work,'libxml2-2.14.0.tar.xz'),
    sha256:'3e2ed89d81d210322d70b35460166d4ea285e5bb017576972a1d76a09631985c'};
  await download('https://download.gnome.org/sources/libxml2/2.14/libxml2-2.14.0.tar.xz',xml2Archive.file);
  const tools={cc:'clang',cxx:'clang++',launcher:env.CMAKE_CXX_COMPILER_LAUNCHER};
  if(platform.startsWith('darwin_')) {
    prepareDarwinLldbSource(sources.llvm);
    tools.cc='/usr/bin/clang'; tools.cxx='/usr/bin/clang++';
  }
  let pythonInputs;
  if(windows) {
    const bin=path.join(env.CJCJ_WINDOWS_TOOLCHAIN,'bin');
    tools.cc=path.join(bin,'clang.exe');tools.cxx=path.join(bin,'clang++.exe');
    const archive=path.join(work,'Python-'+WINDOWS_PYTHON_SOURCE.version+'.tar.xz');
    await download(WINDOWS_PYTHON_SOURCE.url,archive);
    pythonInputs={pythonProducer:{archive,work:path.join(work,'pcbuild'),
      tools:{bootstrapPython:await selectedExecutable('python',env),msbuild:await selectedExecutable('msbuild',env),
        tar:path.join(env.SystemRoot,'System32','tar.exe')}}};
  } else {
    const {root:python}=await preparePython({platform,out:work});
    pythonInputs={python,relocatablePython:true,pythonInputs:{record:path.join(work,'PYTHON-BUILD-INPUTS.json')}};
  }
  const install=path.join(root,'llvm');
  await nativeCjdb({...sources,commits,platform,build:path.join(work,'build'),install,tools,...pythonInputs,
    xml2Archive,libedit:windows?undefined:'/usr',jobs:await selectBuildJobs(undefined,env),linkJobs:1});
  await verifyPrepareNativeInstallation({build:path.join(work,'build'),install,platform,workspace});
}

export async function verifyPrepareNativeInstallation({build,install,platform,workspace}) {
  checkSuperbuildInstall(install,platform);
  const native=sdkPlatform(platform), llvmBin=path.join(build,'third_party/cjnative-prefix/src/cjnative-build/bin');
  const symbols=(tool,args)=>execFileSync(path.join(llvmBin,tool+native.exe),args,{encoding:'utf8',maxBuffer:256*1024*1024});
  const lib=path.join(install,'third_party/llvm',native.llvmDirectory,native.llvmLibrary);
  const exports=native.os==='win32'?symbols('llvm-readobj',['--coff-exports',lib]):
    symbols('llvm-nm',[...(native.os==='linux'?['--dynamic']:[]),'--defined-only','--extern-only',lib]);
  const missing=llvmLibrarySymbolProblems(exports);
  if(missing.length)throw Error('PREPARE_LLVM_LIBRARY_SYMBOLS '+missing.join(','));
  const required=shimRequiredSymbols(await fs.readFile(path.join(workspace,'runtime_shim/cjselfhost_llvmshim.cpp'),'utf8'));
  const shim=path.join(install,'third_party/llvm/fixed-llc/cjselfhost_llvmshim.o');
  const absent=shimSymbolProblems(symbols('llvm-nm',['--defined-only','--extern-only',shim]),required);
  if(absent.length)throw Error('PREPARE_SHIM_SYMBOLS '+absent.join(','));
  await preserveNativePythonInput(install);
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  try {const [target]=process.argv.slice(2);const temp=process.env.RUNNER_TEMP;
    await prepareNativeSuperbuild({target,workspace:process.cwd(),work:path.join(temp,'native-build'),root:path.join(temp,'native-inputs')});
  } catch(error){console.error(error.stack);process.exitCode=error.rc||1;}
}
