#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {loadPins,parseCliArgs,sdkPlatform,homebrewPrefix,repo,cleanSdkEnvironment,resolveHostPython,jobs,run,runCapture,ensureDir,copyTree} from './common.mjs';

const a=parseCliArgs(),p=sdkPlatform(a.platform),src=path.resolve(a.sources),sdk=path.resolve(a.sdk),host=path.resolve(a['host-sdk']||sdk);
const work=path.resolve(a.work||sdk+'.extras'),env=cleanSdkEnvironment(sdk,p.key),py=await resolveHostPython(sdk),j=a.jobs||jobs;
const cwd=src+'/stdx',opts={cwd,env};ensureDir(work);
const setupSource=src+'/compiler/utils/envsetup/llvm_'+(p.os==='win32'?'windows_x86_64':p.os);
for(const ext of p.os==='win32'?['sh','bat','ps1']:['sh'])copyTree(setupSource+'.'+ext,sdk+'/envsetup.'+ext);
const openssl=p.os==='linux'?'/usr/lib/'+(p.arch==='arm64'?'aarch64':'x86_64')+'-linux-gnu':p.os==='win32'?env.CJCJ_NATIVE_OPENSSL_LIB:(env.CJCJ_NATIVE_OPENSSL_LIB||homebrewPrefix()+'/opt/openssl@3/lib');
Object.assign(env,{CANGJIE_BUILD_JOBS:j,STDX_HOST_CANGJIE_HOME:host});
for(const key of ['CFLAGS','CXXFLAGS'])env[key]=[env[key],'-ffile-prefix-map='+src+'=.','-fdebug-compilation-dir=.'].filter(Boolean).join(' ');
if(p.os==='linux')Object.assign(env,{LDFLAGS:'-fuse-ld=lld',CC:'/usr/lib/llvm-15/bin/clang',CXX:'/usr/lib/llvm-15/bin/clang++'});
const steps=(a.only||('stdx,tools'+(p.key==='linux-x64'?',java-interop':''))).split(',');
if(steps.includes('stdx')){
  run(py,['-I','build.py','clean'],opts);
  run(py,['-I','build.py','build','-t','release','--include='+sdk+'/include','--target-lib='+openssl,'--jobs',j],opts);
  run(py,['-I','build.py','install','--prefix',sdk+'/stdx'],opts);
}
if(steps.includes('tools')){
  const tools=src+'/tools',sha=runCapture('git',['-C',repo,'rev-parse','HEAD']).trim(),tsha=runCapture('git',['-C',tools,'rev-parse','HEAD']).trim();
  const cjo=sdk+'/share/cjcj/cjo',rc=sdk+'/share/cjcj/runtime_shim/cjc_runtime_config.o',shim=sdk+'/share/cjcj/runtime_shim/cjselfhost_llvmshim.o';
  const llvm=sdk+'/third_party/llvm/'+p.llvmDirectory+'/'+p.llvmLibrary,runtime=sdk+'/runtime/lib/'+p.tuple;
  Object.assign(env,{CANGJIE_STDX_PATH:sdk+'/stdx/'+p.tuple+'/static/stdx',CJFMT_FRONTEND_CJO:cjo,CJFMT_FRONTEND_LIB:cjo,CJFMT_FRONTEND_NATIVE:rc,CJFMT_FRONTEND_REF:sha,CJFMT_SOURCE_REF:tsha});
  if(p.os==='win32')Object.assign(env,{MINGW_PATH:env.CJCJ_WINDOWS_TOOLCHAIN,CC:env.CJCJ_WINDOWS_TOOLCHAIN+'/bin/clang.exe',CXX:env.CJCJ_WINDOWS_TOOLCHAIN+'/bin/clang++.exe'});
  const origin=p.os==='darwin'?'@loader_path':'$ORIGIN';
  const flags={
    cjpm:['-t','release','--jobs',j,...(p.os!=='win32'?['--set-rpath',origin+'/../../runtime/lib/'+p.tuple]:[])],
    cjfmt:['-t','release','--jobs',j,'--cjpm-sdk',host],hle:['-t','release'],cjcov:['-t','release'],
    'cjtrace-recover':['-t','release','--cangjie-sdk',sdk,'--mangle-source',repo+'/packages/mangle/src',...(p.os!=='win32'?['--set-rpath',origin+'/../lib']:[])],
    cjcompat:['--type','release','--sdk',sdk,'--compiler-source',repo,'--frontend-ref',sha,'--compiler-libs',cjo,'--runtime-config',rc,'--shim',shim,'--llvm',llvm,'--jobs',j,'--tools-revision',tsha],
  };
  if(['linux-x64','windows-x64'].includes(p.key)){
    const lombok=a.lombok||env.CJPROF_LOMBOK_JAR;
    if(!lombok||!fs.existsSync(lombok))throw Error('cjprof requires --lombok <jar>');
    Object.assign(flags,{
      lsp:['--sdk',sdk,'--cjpm',host+'/tools/bin/cjpm'+p.exe,'--server','stdio','--jobs',j,'--frontend-packages',cjo,'--runtime-config',rc,'--json-build',sdk+'/stdx','--llvm-shim',shim,'--llvm-library',llvm],
      cjhead:['--cjc',sdk+'/bin/cjc'+p.exe,'--frontend-dir',cjo,'--shim',shim,'--runtime-config',rc,'--llvm-lib',llvm,'--frontend-commit',sha,'--source-commit',tsha,'--runtime-dir',runtime,'--jobs',j],
      cjlint:['--sdk',sdk,'--cjpm-sdk',host,'--analysis-sdk',sdk,'--frontend-source',repo,'--frontend-ref',sha,'--frontend-artifacts',cjo,'--frontend-runtime-object',rc,'--llvm-shim',shim,'--llvm-library',llvm,'--jobs',j],
      cjprof:['--sdk',sdk,'--jni-home',env.JAVA_HOME,'--runtime-header',sdk+'/runtime/include/Cangjie.h','--lombok-jar',path.resolve(lombok)],
    });
  }
  const parser=sdk+'/tools/dtsparser';
  copyTree(tools+'/packages/hle/src/dtsparser',parser,{filter:f=>!f.endsWith('.cj')&&path.basename(f)!=='node_modules'});
  const npmCli=path.join(path.dirname(process.execPath),'node_modules/npm/bin/npm-cli.js');
  if(p.os==='win32')run(process.execPath,[npmCli,'install','--ignore-scripts','--no-package-lock','--no-audit','--no-fund'],{cwd:parser});
  else run('npm',['install','--ignore-scripts','--no-package-lock','--no-audit','--no-fund'],{cwd:parser});
  copyTree(path.resolve(a.cjbind),parser+'/node_modules/.bin/cjbind'+p.exe);copyTree(process.execPath,sdk+'/tools/bin/node'+p.exe);
  env.CJCJ_HLE_DEPENDENCIES=work+'/hle-dependencies.json';
  fs.writeFileSync(env.CJCJ_HLE_DEPENDENCIES,JSON.stringify({platform:p.platform,
    node:{source:'host node',version:process.version,path:process.execPath},
    modules:{source:tools+'/packages/hle/src/dtsparser/package.json',version:tsha,path:parser+'/node_modules'},
    cjbind:{source:'cjbind',version:loadPins().toolchains.cjbind.version,path:path.resolve(a.cjbind)}}));
  for(const [name,args] of Object.entries(flags)){
    const prefix=work+'/install/'+name;
    const tool=(phase,extra)=>run(process.execPath,[tools+'/build.mjs',phase,'--tool',name,'--build-root',work+'/build',...(phase==='install'?['--prefix',prefix]:[]),'--',...extra],{cwd:tools,env});
    tool('build',args);tool('install',name==='cjlint'?['--analysis-sdk',sdk]:[]);
    const privateDir=sdk+'/.target-tools/tools/'+name;
    if(['cjlint','lsp','cjhead','cjtrace-recover'].includes(name))copyTree(prefix,privateDir);
    const binary=name==='lsp'?'cangjie-lsp':name,publicName=name==='lsp'?'LSPServer':name;
    const installed=[binary,...(name==='hle'?['main']:[])].map(n=>prefix+'/bin/'+n+p.exe).find(f=>fs.existsSync(f));
    if(!installed)throw Error('missing installed '+name+' binary under '+prefix);
    copyTree(installed,sdk+'/.target-tools/tools/bin/'+publicName+p.exe);
    for(const part of ['config','lib','share'])if(fs.existsSync(prefix+'/'+part)&&(!['cjlint','lsp','cjhead','cjtrace-recover'].includes(name)||part==='config')){
      copyTree(prefix+'/'+part,sdk+'/tools/'+part);if(name==='cjprof')copyTree(prefix+'/'+part,sdk+'/.target-tools/tools/'+part);
    }
    if(name==='cjhead'&&p.os==='win32')for(const f of fs.readdirSync(prefix+'/bin').filter(n=>n.endsWith('.dll')))copyTree(prefix+'/bin/'+f,privateDir+'/lib/'+f);
  }

}
if(steps.includes('java-interop')){
  if(p.key!=='linux-x64')throw Error('Java interop needs linux-x64');
  const home=env.JAVA_HOME,jenv={cjHeapSize:env.cjHeapSize,cjHeapSwap:env.cjHeapSwap,LC_ALL:'C',TZ:'UTC',JAVA_HOME:home,CANGJIE_HOME:sdk,HOME:work+'/home',PATH:[home+'/bin',sdk+'/bin','/usr/lib/llvm-15/bin','/usr/bin','/bin'].join(':')};
  ensureDir(jenv.HOME);if(!/^javac 17(?:\.|$)/.test(runCapture(home+'/bin/javac',['-version']).trim()))throw Error('JDK 17 required');
  const javaOpts={cwd:src+'/javaInterop/java',env:jenv},prefix=work+'/java';
  run(py,['-I','-B','build/build.py','build','-t','release','--target-lib',p.tuple,'--target','x86_64-linux-gnu'],javaOpts);
  run(py,['-I','-B','build/build.py','install','--target',p.platform,'--prefix',prefix],javaOpts);
  for(const f of [...['internal','lang'].flatMap(n=>['cjo','bc'].map(ext=>'modules/'+p.tuple+'/java.'+n+'.'+ext)),
    ...['internal','lang'].map(n=>'runtime/lib/'+p.tuple+'/libjava.'+n+'.so'),...['internal','internalFFI','lang'].map(n=>'lib/'+p.tuple+'/libjava.'+n+'.a'),'lib/library-loader.jar'])copyTree(prefix+'/'+f,sdk+'/'+f);
}
