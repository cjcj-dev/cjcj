#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {repo,loadPins,parseCliArgs,sdkPlatform,darwinX64OnArm,checkDarwinX64,nativeBuildEnvironment,pathEnvironment,resolveHostPython,run,runCapture,downloadFile,extractArchive,ensureDir,copySource,copyTree,jobs} from './common.mjs';

const a=parseCliArgs(),p=sdkPlatform(a.platform),win=p.os==='win32',mac=p.os==='darwin';
const sources=path.resolve(a.sources),out=path.resolve(a.out),work=path.resolve(a.work||out+'.build');
const compiler=sources+'/compiler',llvm=sources+'/llvm',runtime=sources+'/runtime',build=work+'/compiler';
const native=out+'/third_party/llvm',llvmBuild=build+'/third_party/cjnative-prefix/src/cjnative-build';
const sha=runCapture('git',['-C',llvm,'rev-parse','HEAD']).trim(),pins=loadPins().toolchains;
const python=work+'/python',xml=work+'/xml2',jobsCount=a.jobs||jobs;
ensureDir(work);
for(const name of ['bounds','flatbuffers'])copySource(sources+'/'+name,compiler+'/third_party/'+(name==='bounds'?'boundscheck':name));
async function unpack(pin,dest,strip,args=[]){
  const archive=work+'/'+path.basename(new URL(pin.url).pathname);
  await downloadFile(pin.url,archive,pin);extractArchive(archive,dest,[...(strip?['--strip-components=1']:[]),...args]);
}
await unpack(pins.libxml2,xml,true);
const pyPin=pins.python[win?'windows-x64-source':p.key];
if(win){
  const cwd=work+'/cpython',env=pathEnvironment(process.env,p);
  const selected={PYTHON:await resolveHostPython(),MSBUILD:runCapture('where.exe',['msbuild.exe']).trim().split(/\r?\n/)[0],
    IncludeTkinter:'false',IncludeCTypes:'true',IncludeSSL:'true',IncludeLibffi:'true',IncludeExternals:'true'};
  const clear=new Set(['PYTHONHOME','PYTHONPATH','VIRTUAL_ENV',...Object.keys(selected).map(k=>k.toUpperCase())]);
  for(const key of Object.keys(env))if(clear.has(key.toUpperCase()))delete env[key];
  Object.assign(env,selected);
  const opts={cwd,env,windowsVerbatimArguments:true};
  await unpack(pyPin,cwd,true);
  const msbuild=env.MSBUILD,version=runCapture(msbuild,['-nologo','-version'],{cwd,env}).trim();
  const toolset=Number(version.split('.')[0])>=18?runCapture(msbuild,['PCbuild/pythoncore.vcxproj','-nologo','-p:Configuration=Release','-p:Platform=x64','-getProperty:DefaultPlatformToolset'],{cwd,env}).trim():null;
  if(toolset&&!/^v\d+$/.test(toolset))throw Error('invalid VS toolset '+toolset);
  for(const batch of ['call PCbuild\\get_externals.bat --no-tkinter','call PCbuild\\build.bat -p x64 -c Release -e --no-tkinter -M /m:'+jobsCount+' "/p:KillPython=false"'+(toolset?' "/p:PlatformToolset='+toolset+'"':'')])
    run(process.env.ComSpec||'cmd.exe',['/d','/s','/c',batch],opts);
  run(cwd+'/PCbuild/amd64/python.exe',['-B',cwd+'/PC/layout','--source',cwd,'--build',cwd+'/PCbuild/amd64','--arch','amd64','--copy',python,'--temp',work+'/layout-temp','--include-dev','--include-stable'],{cwd,env});
}else{
  await unpack(pyPin,python,!!pyPin.prefix,['bin','lib','include','share'].map(n=>(pyPin.prefix||'.')+'/'+n));
}
const bin=win?path.join(process.env.CJCJ_WINDOWS_TOOLCHAIN,'bin'):null;
const cc=win?bin+'/clang.exe':mac?'/usr/bin/clang':'clang',cxx=win?bin+'/clang++.exe':mac?'/usr/bin/clang++':'clang++';
const pyExe=python+(win?'/python.exe':'/bin/python3'),edit=win?null:mac?'/usr/lib':'/usr/lib/'+(p.arch==='arm64'?'aarch64':'x86_64')+'-linux-gnu';
const env={...nativeBuildEnvironment(p),TARGET_PYTHON_PATH:python,CMAKE_BUILD_PARALLEL_LEVEL:jobsCount};
env.PATH=[bin,python+(win?'':'/bin'),env.PATH].filter(Boolean).join(path.delimiter);
if(!win)env[p.loader]=[python+'/lib',edit].join(':');
const conf=runCapture(pyExe,['-I','-c','import sys,sysconfig,ssl,_ctypes; assert sys.version_info[:2]==(3,11); print(sysconfig.get_config_var("EXT_SUFFIX"))'],{env}).trim();
const pyArgs=['-DPython3_EXECUTABLE='+pyExe,'-DPython3_INCLUDE_DIR='+python+(win?'/include':'/include/python3.11'),'-DPython3_LIBRARY='+python+(win?'/libs/python311.lib':mac?'/lib/libpython3.11.dylib':'/lib/libpython3.11.so')];
const launch=['-DCMAKE_C_COMPILER_LAUNCHER='+(env.CMAKE_C_COMPILER_LAUNCHER||''),'-DCMAKE_CXX_COMPILER_LAUNCHER='+(env.CMAKE_CXX_COMPILER_LAUNCHER||'')];
const ar=win?['-DCMAKE_AR='+bin+'/llvm-ar.exe','-DCMAKE_RANLIB='+bin+'/llvm-ranlib.exe']:[];
const intelMac=darwinX64OnArm(p),triple='x86_64-apple-darwin';
let toolchain=compiler+'/cmake/'+(win?'mingw_x86_64':p.platform)+'_toolchain.cmake';
const targetArgs=intelMac?['-DCMAKE_OSX_ARCHITECTURES=x86_64','-DLLVM_HOST_TRIPLE='+triple,
  '-DLLVM_DEFAULT_TARGET_TRIPLE='+triple,'-DCMAKE_SYSTEM_PROCESSOR=x86_64']:[];
if(intelMac){
  // flatc configures without the parent toolchain. Give nested CMake processes
  // the same target architecture even when they initialize their own caches.
  env.CMAKE_OSX_ARCHITECTURES='x86_64';
  env.CMAKE_APPLE_SILICON_PROCESSOR='x86_64';
  // Xml2 configures separately with this same file. Rosetta can run the generated tools.
  const wrapper=work+'/darwin_x86_64_cross_toolchain.cmake';
  fs.writeFileSync(wrapper,'set(CMAKE_OSX_ARCHITECTURES "x86_64" CACHE STRING "" FORCE)\ninclude("'+toolchain+'")\nset(CMAKE_CROSSCOMPILING OFF)\n');
  toolchain=wrapper;
}
const child=[...targetArgs,...launch,'-DLLVM_PARALLEL_LINK_JOBS=1','-DCJ_LLVM_COMMIT='+sha,'-DCANGJIE_RUNTIME_SOURCE_DIR='+runtime,...(win?['-DCOMPILER_RT_INCLUDE_TESTS=OFF','-DLLVM_SPLIT_LLVM_DYLIB=ON']:[])];
const lldb=[...targetArgs,...ar,...pyArgs,...launch,'-DLLVM_PARALLEL_LINK_JOBS=1','-DLLDB_PYTHON_EXT_SUFFIX='+conf,'-DClang_DIR='+llvmBuild+'/lib/cmake/clang',
  '-DLLVM_TABLEGEN='+llvmBuild+'/bin/llvm-tblgen'+p.exe,'-DLIBXML2_INCLUDE_DIR='+build+'/third_party/xml2/include/libxml2','-DLIBXML2_LIBRARY='+build+'/third_party/xml2/lib/libxml2'+(win?'.dll.a':p.shared)];
const args=['-G','Ninja','-S',compiler,'-B',build,'-DCMAKE_BUILD_TYPE=Release','-DCMAKE_TOOLCHAIN_FILE='+toolchain,
  '-DCMAKE_C_COMPILER='+cc,'-DCMAKE_CXX_COMPILER='+cxx,...launch,...ar,'-DCANGJIE_BUILD_CJC=ON','-DCANGJIE_BUILD_STD_SUPPORT=ON','-DCANGJIE_BUILD_CJDB=ON','-DCANGJIE_BUILD_TESTS=OFF',
  '-DCJCJ_NATIVE_NODE='+process.execPath,'-DCJ_LLVM_COMMIT='+sha,'-DCANGJIE_CJNATIVE_SOURCE_DIR='+llvm,'-DCANGJIE_RUNTIME_SOURCE_DIR='+runtime,'-DCANGJIE_XML2_SOURCE_DIR='+xml,
  '-DCANGJIE_LLVM_BUILD_TYPE=Release','-DCANGJIE_CJDB_BUILD_TYPE=Release','-DCANGJIE_LLVM_BUILD_ARGS='+child.join(';'),'-DCJCJ_LLDB_ARGS='+lldb.join(';'),
  '-DLLVM_BUILD_ARG='+pyArgs.join(';'),pyArgs[0],'-DCMAKE_PREFIX_PATH='+[python,build+'/third_party/xml2',...(!win?['/usr']:[])].join(';'),
  ...(win?['-DCANGJIE_TOOLCHAIN_RUNTIME_FILES='+['libc++.dll','libunwind.dll'].map(n=>process.env.CJCJ_WINDOWS_TOOLCHAIN+'/x86_64-w64-mingw32/bin/'+n).join(';')]:[]),
  '-DCANGJIE_LINK_JOB_POOL=1','-DCMAKE_INSTALL_PREFIX='+out];
const cmake=(...args)=>run('cmake',args,{env});
cmake(...args.map(arg=>arg.replaceAll('\\','/')));
cmake('--build',build,'--target','lldb','cangjie-ast-support',...(win?[]:['cjdb','lldb-boundscheck','lldb-cangjie-lsp','lldb-cangjie-frontend']),'-j',jobsCount);
cmake('--build',build,'-j',jobsCount);cmake('--install',build);
for(const component of ['clang','clang-resource-headers','llvm-headers'])cmake('--install',llvmBuild,'--prefix',native,'--component',component);
for(const name of ['llvm-ar','llvm-ranlib','llvm-nm','wasm-ld'])if(!fs.existsSync(native+'/bin/'+name+p.exe))
  copyTree(fs.realpathSync(llvmBuild+'/bin/'+(name==='wasm-ld'?'lld':name)+p.exe),native+'/bin/'+name+p.exe);
const pyOut=out+'/third_party/python';copyTree(python,pyOut);
const site=win?'Lib/site-packages':'lib/python3.11/site-packages';
for(const name of ['lldb','six.py']){
  const src=[native+'/'+site,native+'/lib/python3.11/site-packages',build+'/third_party/lldb-build/'+site].map(s=>s+'/'+name).find(s=>fs.existsSync(s));
  if(!src)throw Error('missing LLDB Python module '+name);
  copyTree(src,pyOut+'/'+site+'/'+name);
}
// Unix LLDB installs relative links to its library and argument dumper. The
// Python prefix is a sibling of LLVM, so rebase those links after the move.
if(!win){
  const pkg=pyOut+'/'+site+'/lldb',built=build+'/third_party/lldb-build';
  for(const member of fs.readdirSync(pkg)){
    const file=pkg+'/'+member;if(!fs.lstatSync(file).isSymbolicLink())continue;
    const name=path.basename(fs.readlinkSync(file));
    const locations=[native+'/lib/'+name,native+'/bin/'+name,pyOut+'/'+site+'/'+name];
    if(name==='lldb-argdumper'&&!fs.existsSync(native+'/bin/'+name))copyTree(built+'/bin/'+name,native+'/bin/'+name);
    const target=locations.find(f=>fs.existsSync(f));
    if(target){fs.unlinkSync(file);fs.symlinkSync(path.relative(pkg,target),file);}
    fs.accessSync(file);
  }
}
if(edit)for(const name of fs.readdirSync(edit).filter(n=>mac?/^libedit.*\.dylib$/.test(n):/^libedit\.so(\.|$)/.test(n)))copyTree(path.join(edit,name),native+'/lib/'+name);
if(mac){
  const lib=pyOut+'/lib/libpython3.11.dylib';run('install_name_tool',['-id','@rpath/libpython3.11.dylib',lib]);
  for(const file of [native+'/bin/lldb',...fs.readdirSync(native+'/lib').filter(n=>/^liblldb.*\.dylib$/.test(n)).map(n=>native+'/lib/'+n)]){
    for(const line of runCapture('otool',['-L',file]).split('\n').slice(1)){
      const dep=line.trim().split(' (')[0];if(/3\.11/.test(dep)&&/\/(Python3?|libpython3\.11.*\.dylib)$/.test(dep))
        run('install_name_tool',['-change',dep,'@loader_path/'+path.relative(path.dirname(file),lib),file]);
    }
  }
}
const fixed=native+'/fixed-llc',headers=work+'/shim-schema',object=fixed+'/cjselfhost_llvmshim.o';
ensureDir(fixed);ensureDir(headers+'/flatbuffers');
const clean={...process.env};for(const k of ['CPATH','CPLUS_INCLUDE_PATH','C_INCLUDE_PATH','OBJC_INCLUDE_PATH','LD_LIBRARY_PATH','DYLD_LIBRARY_PATH'])delete clean[k];
run(out+'/third_party/flatbuffers/bin/flatc'+p.exe,['--no-warnings','-c','-o',headers+'/flatbuffers',compiler+'/schema/CjoFormat.fbs'],{env:clean});
const launcher=env.CMAKE_CXX_COMPILER_LAUNCHER;
run(launcher||cxx,[...(launcher?[cxx]:[]),...(intelMac?['-arch','x86_64']:[]),'-std=c++17','-O2',...(!win?['-fPIC']:[]),'-fno-rtti','-fno-exceptions',
  ...(/^LLVM_ENABLE_ASSERTIONS:BOOL=ON$/m.test(fs.readFileSync(llvmBuild+'/CMakeCache.txt','utf8'))?[]:['-DNDEBUG']),
  ...[llvm+'/llvm/include',llvmBuild+'/include',sources+'/flatbuffers/include',headers].map(dir=>'-I'+dir),'-c',repo+'/runtime_shim/cjselfhost_llvmshim.cpp','-o',object],{env:clean});
const tool=name=>llvmBuild+'/bin/'+name+p.exe,library=native+'/'+p.llvmDirectory+'/'+p.llvmLibrary;
if(intelMac)for(const file of [out+'/third_party/flatbuffers/bin/flatc',library,native+'/lib/liblldb.dylib',native+'/bin/llc',native+'/lib/libxml2.dylib',object])checkDarwinX64(file);
const symbols=runCapture(tool(win?'llvm-readobj':'llvm-nm'),win?['--coff-exports',library]:[...(!mac?['--dynamic']:[]),'--defined-only','--extern-only',library]);
if(!symbols.includes('LLVMInitializeX86TargetInfo'))throw Error('missing libLLVM X86 target export');
const exports=runCapture(tool('llvm-nm'),['--defined-only','--extern-only',object]);
const defined=new Set(exports.trim().split(/\r?\n/).map(line=>line.trim().split(/\s+/).at(-1).replace(/^_/,'')));
const declarations=fs.readFileSync(repo+'/runtime_shim/cjselfhost_llvmshim.cpp','utf8').matchAll(/^extern "C" [^\n(]*?\b(LLVMSelfhost\w+|CJOF\w+|LLVMGlobalObjectAddStringAttribute)\s*\(/gm);
for(const name of new Set(['LLVMSelfhostInitTargetComponent','CJOFPackageViewOpen','LLVMGlobalObjectAddStringAttribute',...Array.from(declarations,m=>m[1])]))
  if(!defined.has(name))throw Error('missing shim export '+name);
if(p.os==='linux')for(const f of [library,...['llc','opt','lld'].map(n=>native+'/bin/'+n)])
  if(/NEEDED.*libxml2/.test(runCapture('readelf',['-d',f])))throw Error('unexpected libxml2 dependency: '+f);
for(const name of [...(mac?['libclang_rt.osx.a']:p.arch==='x64'?['libclang_rt-builtins.a']:[]),'libclang_rt-profile.a',...(win?[]:['libclang_rt.fuzzer_no_main.a'])])fs.accessSync(out+'/lib/'+p.tuple+'/'+name);
