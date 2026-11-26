#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {parseCliArgs,sdkPlatform,darwinX64OnArm,checkDarwinX64,crossTuples,nativeBuildEnvironment,loadPins,jobs,copySource,copyTree,ensureDir,run,runCapture,resolveHostPython} from './common.mjs';

const a=parseCliArgs(),p=sdkPlatform(a.platform),cross=a.cross,tuple=cross?crossTuples[cross]:p.tuple;
if(!tuple)throw Error('unknown cross target: '+cross);
const sources=path.resolve(a.sources),cwd=path.join(sources,'runtime/runtime'),out=path.resolve(a.out);
const build=cwd+'/CMakebuild',work=out+'.work';
ensureDir(work);copySource(sources+'/bounds',cwd+'/third_party/third_party_bounds_checking_function');
const version=loadPins().runtimeVersion,env={...nativeBuildEnvironment(p),RUNTIME_VERSION:version,CANGJIE_BUILD_JOBS:a.jobs||jobs};
const opts={cwd,env},python=await resolveHostPython(a.sdk,env);
if(cross==='wasm32-wasi'){
  const bin=path.resolve(a.sdk,'third_party/llvm/bin');
  env.LD_LIBRARY_PATH=[path.resolve(a.sdk,'third_party/llvm/lib'),env.LD_LIBRARY_PATH].filter(Boolean).join(':');
  run('cmake',['-G','Ninja','-S',cwd+'/src/wasm','-B',work,'-DCMAKE_C_COMPILER='+bin+'/clang',
    '-DCMAKE_AR='+bin+'/llvm-ar','-DCMAKE_RANLIB='+bin+'/llvm-ranlib','-DWASI_SYSROOT='+env.CJCJ_WASI_SYSROOT,'-DCMAKE_INSTALL_PREFIX='+out],opts);
  run('cmake',['--build',work],opts);run('cmake',['--install',work],opts);
  run(bin+'/llvm-ar',['s',out+'/runtime/lib/'+tuple+'/libcangjie-runtime.a'],opts);
}else{
  const windows=(cross||p.key)==='windows-x64',ios=cross?.startsWith('ios-'),ohos=cross?.startsWith('ohos-');
  const intelMac=!cross && darwinX64OnArm(p);
  const target=cross==='windows-x64'?'windows-x86_64':cross||(windows?'windows-x86_64':'native');
  const args=['build','--target',target,'--build-type','release','--prefix',cwd+'/output/common','-v',version];
  const arch=tuple.includes('aarch64')?'aarch64':'x86_64',suffix=windows?'.dll':ios||(!cross&&p.os==='darwin')?'.dylib':'.so';
  const toolchain=path.join(work,'runtime.cmake');
  if(!cross){
    let cmake=windows?'cmake_minimum_required(VERSION 3.29)\nset(CMAKE_LINKER_TYPE LLD)\n':'';
    if(p.os==='darwin')cmake+='set(CMAKE_C_COMPILER /usr/bin/clang CACHE FILEPATH "" FORCE)\nset(CMAKE_CXX_COMPILER /usr/bin/clang++ CACHE FILEPATH "" FORCE)\n';
    if(env.SCCACHE_PATH) for(const key of ['CANGJIE_COMPILER_CACHE','CMAKE_C_COMPILER_LAUNCHER','CMAKE_CXX_COMPILER_LAUNCHER'])
      cmake+='set('+key+' "$ENV{SCCACHE_PATH}" CACHE STRING "" FORCE)\n';
    fs.writeFileSync(toolchain,cmake);env.CMAKE_TOOLCHAIN_FILE=toolchain.replaceAll('\\','/');
    env.GC_UNIT_GATE_LANGUAGE_TESTS=p.os==='linux'?'defer':'all';env.GC_UNIT_GATE_STATUS=build+'/gc-unit.status';
    if(p.os==='linux'){run('gdb',['--version']);run('timeout',['--version']);}
    if(p.os==='darwin')env.SDKROOT=runCapture('xcrun',['--sdk','macosx','--show-sdk-path']).trim();
    if(windows){
      env.MSYSTEM='MINGW64';env.MSYS2_PATH_TYPE='inherit';env.CHERE_INVOKING='1';env.CMAKE_GENERATOR='Unix Makefiles';
      args.push('--target-toolchain',path.dirname(env.CJCJ_NATIVE_LLVM_BIN));
    }
  }else if(windows){
    args.push('--target-toolchain',env.MINGW_PATH+'/bin');
    Object.assign(env,{CMAKE_PREFIX_PATH:env.MINGW_PATH+'/x86_64-w64-mingw32',LDFLAGS:'-fuse-ld=lld',PATH:env.MINGW_PATH+'/bin:'+env.PATH});
  }else if(ios){
    const sdk=cross.includes('simulator')?'iphonesimulator':'iphoneos';
    env.SDKROOT=runCapture('xcrun',['--sdk',sdk,'--show-sdk-path']).trim();
    args.push('--target-sysroot',env.SDKROOT,'--target-toolchain',path.dirname(path.dirname(runCapture('xcrun',['--sdk',sdk,'--find','clang']).trim())));
  }else if(ohos){
    args.push('--ohos-public-sdk',env.OHOS_SDK_HOME+'/native');
    if(a['local-export']){fs.writeFileSync(toolchain,'set(GLOBAL_EXPORT_FLAG "0" CACHE STRING "" FORCE)\n');env.CMAKE_TOOLCHAIN_FILE=toolchain;}
  }else args.push('--target-toolchain',path.join(env.ANDROID_NDK_ROOT,'toolchains'));
  function buildPy(args){
    if(!cross && windows){
      run(env.MSYS2_BASH,['--login','-c','set -eu; export PATH="/mingw64/bin:/usr/bin:$PATH"; [[ "$(git --version)" == *.windows.* ]]; cd "$1"; shift; exec "$@"','build-runtime',cwd.replaceAll('\\','/'),python.replaceAll('\\','/'),'build.py',...args.map(x=>x.replaceAll('\\','/'))],opts);
    }else run(python,['-I','build.py',...args],opts);
  }
  if(cross)buildPy(['clean']);buildPy(args);buildPy(['install','--prefix',out]);
  const lib=out+'/runtime/lib/'+tuple,staging=build+'/runtime-staging/'+(windows?'bin':'lib')+'/'+arch+'_Release';
  if(!fs.existsSync(lib+'/libboundscheck'+suffix))copyTree(staging+'/libboundscheck'+suffix,lib+'/libboundscheck'+suffix);
  if(ios) for(const name of ['libboundscheck','libcangjie-runtime']){
    const file=lib+'/'+name+suffix,info=runCapture('otool',['-l',file]);
    if(!info.includes('@rpath/'+name+suffix)||!(/LC_BUILD_VERSION|LC_VERSION_MIN_IPHONEOS/.test(info))||
      runCapture('lipo',['-archs',file]).trim()!==(arch==='aarch64'?'arm64':'x86_64'))throw Error('wrong iOS library '+file);
  }
  if(!cross){
    if(windows)copyTree(cwd+'/src/windows_x86_64_exports.def',out+'/windows_x86_64_exports.def');
    for(const name of ['libcangjie-thread.a','libcangjie-aio.a']){
      const dest=out+'/lib/'+tuple+'/'+name;
      if(!fs.existsSync(dest)){
        const found=fs.readdirSync(build+'/cjthread-build',{recursive:true}).find(f=>path.basename(f)===name);
        if(!found)throw Error('missing '+name);copyTree(build+'/cjthread-build/'+found,dest);
      }
    }
    if(intelMac)for(const name of ['libcangjie-runtime','libboundscheck'])checkDarwinX64(lib+'/'+name+suffix,{thin:true});
    const probe=work+'/load'+p.exe;
    fs.writeFileSync(work+'/load.cpp',[
      '#ifdef _WIN32','#include <windows.h>','int main(int n,char**v){auto h=LoadLibraryA(v[1]);return !(h&&GetProcAddress(h,v[2]));}',
      '#else','#include <dlfcn.h>','#include <cstdio>','int main(int n,char**v){auto h=dlopen(v[1],RTLD_NOW);if(!h){puts(dlerror());return 1;}return !dlsym(h,v[2]);}','#endif'].join('\n'));
    run(windows?path.join(env.CJCJ_NATIVE_LLVM_BIN,'clang++.exe'):(env.CXX||'c++'),[work+'/load.cpp','-o',probe,...(windows?['-static']:p.os==='linux'?['-ldl']:[...(intelMac?['-arch','x86_64']:[]),'-isysroot',env.SDKROOT])]);
    for(const [name,sym] of [['libcangjie-runtime','CJ_MCC_HandleReturnSafepoint'],['libboundscheck','memset_s']])
      run(probe,[lib+'/'+name+suffix,sym],{env:{...env,[p.loader]:[lib,...(windows?[env.CJCJ_NATIVE_LLVM_BIN,env.PATH]:[])].join(path.delimiter)}});
  }
}
// Keep inputs for the deferred Linux language tests outside the SDK archive.
// The C++ result and its optional gtest executable must come from this build.
if(!cross && p.os==='linux' && a['language-inputs']){
  const dest=path.resolve(a['language-inputs'],'runtime'),status=build+'/gc-unit.status';
  const fields=new Map(fs.readFileSync(status,'utf8').trim().split(/\r?\n/).map(s=>[s.split('=')[0],s.slice(s.indexOf('=')+1)]));
  if(fields.get('GATE')!=='PASS'||fields.get('CPP_SUITE')!=='PASS'||fields.get('LANGUAGE_TESTS')!=='LANGUAGE_DEFERRED')
    throw Error('native C++ suite did not complete: '+status);
  for(const rel of ['tests/gc_unit','tests/perf_vs_official','src','include','build/resolve_runtime_headers.py','build/resolve_runtime_headers.mjs',
    'third_party/third_party_bounds_checking_function/include','CMakebuild/compile_commands.json','CMakebuild/gc-unit.status'])
    copyTree(cwd+'/'+rel,dest+'/'+rel,{filter:f=>!['__pycache__','build_standalone','.git'].includes(path.basename(f))});
  copyTree(build+'/runtime-staging/include',out+'/include');
  if(fields.get('SEGMENTED_ARRAY_MANAGED_CAN_RUN')==='1')copyTree(fields.get('EVIDENCE_DIR')+'/cj_gc_unit',dest+'/CMakebuild/cj_gc_unit');
}
