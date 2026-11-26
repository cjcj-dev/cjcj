#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {run,runCapture,loadPins,parseCliArgs,sdkPlatform,cleanSdkEnvironment,downloadFile,extractArchive,extractSdkArchive,tar,pathEnvironment,
  gitFetchCommit,ensureDir,copyTree,appendGithubPath,appendGithubEnv,jobs,main,resolveHostPython} from './common.mjs';

const {toolchains:t,hostSdk,crossSdks,repos}=loadPins();
async function unpack(pin,dir,strip=false) {
  const file=path.join(dir+'.downloads',path.basename(new URL(pin.url).pathname));
  await downloadFile(pin.url,file,pin);extractArchive(file,dir,strip?['--strip-components=1']:[]);
  return file;
}
async function deps(p,mode) {
  if(!['full','prepare'].includes(mode))throw Error('expected prepare or full');
  if(p.os==='linux'){
    const old=/^VERSION_ID="?22\.04"?$/m.test(fs.readFileSync('/etc/os-release','utf8'));
    const packages='clang llvm lld cmake ninja-build make gdb coreutils swig libedit-dev libffi-dev'.split(' ');
    if(mode==='full') packages.push(...'tar unzip wget curl libcurl4 expat openssl gcc g++ gettext nfs-common libtool sqlite3 zlib1g-dev libssl-dev libcurl4-openssl-dev autoconf build-essential rapidjson-dev texinfo binutils libelf-dev libdwarf-dev openssh-client ssh dos2unix libxext-dev libxtst-dev libxt-dev libcups2-dev clang-15 libxrender-dev zip bzip2 libopenmpi-dev vim lldb libclang-15-dev libgtest-dev rpm patch cpio rpm2cpio strace net-tools python3-dev'.split(' '));
    run('sudo',['apt-get','update','-qq']);
    run('sudo',['env','DEBIAN_FRONTEND=noninteractive','apt-get','install','-y','--no-install-recommends',...packages,...(old?['libtinfo5','libncurses5-dev']:['libtinfo6','libncurses-dev'])]);
  }else if(p.os==='darwin'){
    const pkgs=['ninja','llvm@16','openssl@3','bison','googletest','gnu-tar','swig','coreutils',...(p.arch==='x64'?['uv']:[])];
    const deps=runCapture('brew',['deps','--formula',...pkgs]).split(/\s+/).filter(s=>/^python@\d+\.\d+$/.test(s));
    run('brew',['install','--skip-link',...new Set(['python@3.11',...deps])]);run('brew',['install',...pkgs]);
    appendGithubPath(runCapture('brew',['--prefix','python@3.11']).trim()+'/libexec/bin');
    const dir=path.join(process.env.RUNNER_TEMP||os.tmpdir(),'cmake-'+t.cmakeMacos.version);
    await unpack(t.cmakeMacos,dir,true);appendGithubPath(path.join(dir,'CMake.app/Contents/bin'));
  }else{
    if(!runCapture('git',['--version']).includes('.windows.'))throw Error('Git for Windows is required');
    for(const tool of ['cmake','ninja','clang'])run(tool,['--version']);
  }
}
async function mingw(out) {
  const pin=t.linuxCrossMingw,src=out+'.src',target=out+'/x86_64-w64-mingw32';
  await unpack(pin,src,true);
  gitFetchCommit(pin.llvmProjectUrl,pin.llvmProjectSha,src+'/llvm-project');
  run('git',['clone','--depth=1',pin.mingwW64Url,src+'/mingw-w64']);
  const env={...pathEnvironment(),TOOLCHAIN_ARCHS:'x86_64',MAKEFLAGS:'-j'+jobs};
  for(const [script,...args] of [['build-llvm','--disable-lldb'],['strip-llvm'],['install-wrappers'],['build-mingw-w64','--with-default-msvcrt=msvcrt'],['build-mingw-w64-tools'],['build-compiler-rt'],['build-libcxx'],['build-mingw-w64-libraries']]){
    run('./'+script+'.sh',[out,...args],{cwd:src,env:script==='build-llvm'?{...env,LLVM_CMAKEFLAGS:'-DLLVM_USE_LINKER=lld'}:env});
  }
  for(const lib of ['libssp','libssp_nonshared']) if(!fs.existsSync(target+'/lib/'+lib+'.a'))copyTree(target+'/lib/libmingwex.a',target+'/lib/'+lib+'.a');
  const ssl=out+'.openssl';await unpack({url:pin.opensslUrl},ssl,true);
  const opts={cwd:ssl,env:{...env,PATH:out+'/bin:'+env.PATH}};
  run('./Configure',['mingw64','--prefix='+target,'--cross-compile-prefix=x86_64-w64-mingw32-','--libdir=lib'],opts);
  run('make',['-j'+jobs],opts);run('make',['install'],opts);appendGithubEnv('MINGW_PATH',out);
}
async function staticLibs(out) {
  const pin=t.staticLibs,n=out+'/ncurses-'+pin.ncursesVersion,e=out+'/'+pin.libeditTarball;
  const cc=[process.env.CMAKE_C_COMPILER_LAUNCHER,'clang'].filter(Boolean).join(' ');
  for(const [url,cwd,args,extra,install] of [
    [pin.ncursesUrl,n+'.src',['--prefix=/usr','--libdir=/usr/lib','--with-termlib','--with-terminfo-dirs=/etc/terminfo:/lib/terminfo:/usr/share/terminfo','--disable-widec','--disable-overwrite','--disable-root-environ'],
      {CFLAGS:'-fPIC -fstack-protector-strong -Wl,-z,relro,-z,now,-z,noexecstack',CXXFLAGS:'-fstack-protector-strong -Wl,-z,relro,-z,now,-z,noexecstack',CXX:[process.env.CMAKE_CXX_COMPILER_LAUNCHER,'clang++'].filter(Boolean).join(' ')},['DESTDIR='+n]],
    [pin.libeditUrl,e+'.src',['--with-pic','--enable-shared=no','--prefix='+e],{CPPFLAGS:'-I'+n+'/usr/include -I'+n+'/usr/include/ncurses',LDFLAGS:'-L'+n+'/usr/lib'},[]],
  ]) {
    await unpack({url},cwd,true);const opts={cwd,env:{...process.env,CC:cc,...extra}};
    run('./configure',args,opts);run('make',['-j'+jobs],opts);run('make',['install',...install],opts);
  }
  appendGithubEnv('CMAKE_PREFIX_PATH',[e,n+'/usr',process.env.CMAKE_PREFIX_PATH].filter(Boolean).join(':'));
}
async function crossSdk(kind,out) {
  if(kind==='mingw')return mingw(out);
  if(kind==='wasi'){
    await unpack(crossSdks.wasiSysroot,out);fs.accessSync(out+'/wasi-sysroot/lib/wasm32-wasi/libc.a');
    appendGithubEnv('CJCJ_WASI_SYSROOT',out+'/wasi-sysroot');
  }else if(kind==='android-ndk'){
    const home=process.env.ANDROID_HOME,ver=crossSdks.androidNdk.version;
    const manager=path.join(home,'cmdline-tools/latest/bin/sdkmanager');
    if(process.platform==='win32')
      run(process.env.ComSpec||'cmd.exe',['/d','/s','/c','""'+manager+'.bat" "ndk;'+ver+'""'],{windowsVerbatimArguments:true});
    else run(manager,['ndk;'+ver]);
    appendGithubEnv('ANDROID_NDK_ROOT',path.join(home,'ndk',ver));
  }else if(kind==='xcode-ios'){
    const dev='/Applications/Xcode.app/Contents/Developer';run('sudo',['xcode-select','--switch',dev]);appendGithubEnv('DEVELOPER_DIR',dev);
  }else if(kind==='ohos'){
    const host=process.platform==='win32'?'windows':process.platform,pin=crossSdks.ohos[host],archive=path.join(out,pin.archive);
    await downloadFile(pin.url,archive,pin);
    run(await resolveHostPython(),['-I','-c',ohosExtract,archive,out,host]);
    const sdk=path.join(out,'sdk');run(path.join(sdk,'native/llvm/bin/clang'+sdkPlatform().exe),['--version']);appendGithubEnv('OHOS_SDK_HOME',sdk);
  }else throw Error('unknown cross SDK '+kind);
}
async function setup(a) {
  const [sub,dest]=a._,p=sdkPlatform(a.platform);
  if(sub==='pack'){
    // The Linux overlay is consumed on Windows: store physical tuple files only.
    const tuple=sdkPlatform('linux-x64').tuple;
    const members=a['linux-overlay']?['modules/','lib/','runtime/lib/'].map(d=>d+tuple):['.'];
    return run(tar(),[...(a['linux-overlay']?['--dereference']:[]),'-cf',a.archive,'-C',a.dir,...members]);
  }
  if(sub==='unpack')return a['sdk-root']?extractSdkArchive(a.archive,a.dir,a['sdk-root']):extractArchive(a.archive,a.dir);
  if(sub==='swap'){
    appendGithubEnv('cjHeapSwap',process.env.cjHeapSwap||'on');
    const file='/mnt/cjcj-bootstrap.swap';
    if(runCapture('swapon',['--noheadings','--show=NAME']).trim().split(/\s+/).includes(file))return;
    run('sudo',['fallocate','-l','12G',file]);run('sudo',['chmod','600',file]);
    run('sudo',['mkswap',file]);run('sudo',['swapon',file]);return;
  }
  if(sub==='deps')return deps(p,a.mode||'full');
  const out=path.resolve(a.out||dest);ensureDir(out);
  if(sub==='sources'){
    const overrides=Object.fromEntries((a.override||[]).map(pair=>pair.split('=')));
    const keys=a.repos.split(',');
    for(const name of Object.keys(overrides)) if(!keys.includes(name))throw Error('unused source override '+name);
    for(const name of keys){const pin=repos[name];if(!pin)throw Error('unknown repo '+name);
      gitFetchCommit(pin.url,overrides[name]||pin.sha,path.join(out,name),{sparseNoZoneId:name==='flatbuffers'});}
  }else if(sub==='host-sdk'){
    await unpack(hostSdk.platforms[p.key],out,true);fs.accessSync(out+'/bin/cjc'+p.exe);
  }else if(sub==='windows-toolchain'){
    await unpack(t.windowsLlvmMingw,out,true);
    for(const f of ['bin/clang.exe','bin/clang++.exe','bin/llvm-readobj.exe','x86_64-w64-mingw32/bin/libc++.dll','x86_64-w64-mingw32/bin/libunwind.dll'])fs.accessSync(path.join(out,f));
    appendGithubEnv('CJCJ_WINDOWS_TOOLCHAIN',out);appendGithubPath(path.join(out,'bin'));
  }else if(sub==='cross-sdk')await crossSdk(a.kind,out);
  else if(sub==='static-libs')await staticLibs(out);
  else if(sub==='cjbind'){
    const file=path.join(out,'cjbind'+p.exe);
    if(p.key==='darwin-x64'){
      const pin=t.cjbind['darwin-x64-source'],src=out+'.src';gitFetchCommit(pin.url,pin.sha,src);
      const opts={cwd:src,env:cleanSdkEnvironment(path.resolve(a['host-sdk']),p.key)};
      run('uv',['run','--python','3.13','./scripts/download.py'],opts);
      run('uv',['run','--python','3.13','./scripts/cjpm.py','build','--cfg_verbose','-V'],opts);
      copyTree(src+'/target/release/bin/main',file);
    }else {const pin=t.cjbind[p.key];await downloadFile(pin.url,file,pin);}
    fs.chmodSync(file,0o755);
  }else throw Error('unknown setup command '+sub);
}


const ohosExtract = String.raw`import sys, os, shutil, stat, tarfile, zipfile
from pathlib import Path
archive, root = map(Path, sys.argv[1:3])
native_zip = root / 'native.zip'
wanted = sys.argv[3]
matches = []
with tarfile.open(archive, 'r|gz') as bundle:
    for member in bundle:
        name = Path(member.name).name
        if member.isfile() and name.startswith('native-') and name.endswith('.zip') and wanted in name:
            matches.append(member.name)
            with bundle.extractfile(member) as source, native_zip.open('wb') as target:
                shutil.copyfileobj(source, target)
if len(matches) != 1:
    raise ValueError(f'expected one native {wanted} package, found {matches}')
print(f'OHOS_NATIVE_PACKAGE={matches[0]}', flush=True)
sdk = root / 'sdk'
sdk.mkdir(exist_ok=True)
links = {}
with zipfile.ZipFile(native_zip) as bundle:
    for item in bundle.infolist():
        destination = (sdk / item.filename).resolve()
        if not destination.is_relative_to(sdk.resolve()):
            raise ValueError(f'archive member escapes SDK: {item.filename}')
        mode = item.external_attr >> 16
        if stat.S_ISLNK(mode):
            links[destination] = (destination.parent / bundle.read(item).decode('utf-8')).resolve()
            continue
        bundle.extract(item, sdk)
        if mode and os.name != 'nt':
            destination.chmod(mode & 0o777)
# zipfile.extract writes Unix link payloads as ordinary text files (clang
# becomes the eight bytes "clang-15"). Materialize aliases as physical
# copies, including chains such as clang++ -> clang -> clang-15.
visiting = set()

def materialize(destination):
    if destination not in links:
        return
    if destination in visiting:
        raise ValueError(f'cyclic SDK alias: {destination}')
    visiting.add(destination)
    target = links[destination]
    if not target.is_relative_to(sdk.resolve()):
        raise ValueError(f'SDK alias escapes root: {destination} -> {target}')
    materialize(target)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if target.is_dir():
        shutil.copytree(target, destination)
    else:
        shutil.copy2(target, destination)
    visiting.remove(destination)
    del links[destination]

for destination in list(links):
    materialize(destination)
`;
if(main(import.meta.url))await setup(parseCliArgs());
