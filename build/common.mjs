#!/usr/bin/env node
import fs from 'node:fs/promises';
import sync from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import childProcess from 'node:child_process';
import {createHash} from 'node:crypto';
import {pipeline} from 'node:stream/promises';
import {setTimeout as delay} from 'node:timers/promises';
import {fileURLToPath} from 'node:url';

export const repo = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
export const loadPins = () => JSON.parse(sync.readFileSync(new URL('pins.json',import.meta.url),'utf8'));
export const main = url => process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(url);
export const jobs = String(os.availableParallelism());
export function parseCliArgs(argv = process.argv.slice(2)) {
  const opts={_:[]};
  for(let i=0;i<argv.length;i++){
    const arg=argv[i];
    if(!arg.startsWith('--')) { opts._.push(arg); continue; }
    const [key,inline]=arg.slice(2).split(/=(.*)/s);
    const value=inline ?? (argv[i+1] && !argv[i+1].startsWith('--') ? argv[++i] : true);
    if(['override','cross-dir'].includes(key)) (opts[key]??=[]).push(value);
    else if(Object.hasOwn(opts,key)) throw Error('duplicate --'+key);
    else opts[key]=value;
  }
  return opts;
}
function execute(cmd,args,opts,capture) {
  const r=childProcess.spawnSync(cmd,args,{stdio:capture?['ignore','pipe','inherit']:'inherit',
    encoding:'utf8',maxBuffer:256*1024*1024,...opts});
  if(r.error) throw r.error;
  if(r.status!==0) throw Error([cmd,...args].join(' ')+' exited '+(r.signal||r.status));
  return r.stdout;
}
export const run=(cmd,args=[],opts={})=>execute(cmd,args,opts,false);
export const runCapture=(cmd,args=[],opts={})=>execute(cmd,args,opts,true);
export const ensureDir=dir=>sync.mkdirSync(dir,{recursive:true});
export const rmrf=dir=>sync.rmSync(dir,{recursive:true,force:true});
export function copyTree(src,dst,options={}) {
  ensureDir(path.dirname(dst));
  sync.cpSync(src,dst,{recursive:true,force:true,verbatimSymlinks:true,...options});
}
export function copySource(src,dst) {
  copyTree(src,dst,{filter:file=>path.basename(file)!=='.git'});
}
export async function sha256File(file) {
  const hash=createHash('sha256');
  for await(const bytes of sync.createReadStream(file)) hash.update(bytes);
  return hash.digest('hex');
}
export async function downloadFile(url,dest,{size,sha256}={}) {
  const valid=async file=>(!size||(await fs.stat(file)).size===size)&&(!sha256||await sha256File(file)===sha256);
  if(sync.existsSync(dest) && (size||sha256) && await valid(dest)) return dest;
  ensureDir(path.dirname(dest));
  const tmp=dest+'.part-'+process.pid;
  for(let attempt=1;;attempt++){
    try{
      const res=await fetch(url,{signal:AbortSignal.timeout(30*60*1000)});
      if(!res.ok)throw Error(url+': HTTP '+res.status);
      await pipeline(res.body,sync.createWriteStream(tmp));
      if(!await valid(tmp))throw Error('size or sha256 mismatch: '+url);
      await fs.rename(tmp,dest);return dest;
    }catch(e){rmrf(tmp);if(attempt===3)throw e;await delay(attempt*1000);}
  }
}
export function tar() {
  if(process.platform==='win32')return path.join(process.env.SystemRoot,'System32','tar.exe');
  return process.platform==='darwin' && childProcess.spawnSync('gtar',['--version']).status===0?'gtar':'tar';
}
export function extractArchive(archive,dest,args=[]) {
  ensureDir(dest);run(tar(),['-xf',archive,'-C',dest,...args]);
}
// A Windows directory link extracted from zip can lose its directory type.
// Repair it relative to the new root, using the same unpack path for consumers and verification.
export function extractSdkArchive(archive,dest,root) {
  extractArchive(archive,dest);
  if(process.platform==='win32')linkCompilerRuntime(path.join(dest,root));
}
export function gitFetchCommit(url,sha,dest,{sparseNoZoneId=false}={}) {
  if(!/^[0-9a-f]{40}$/.test(sha)) throw Error('expected full source commit: '+sha);
  ensureDir(dest);const git=(...args)=>run('git',['-C',dest,...args]);
  git('init','-q');
  git('config','remote.origin.url',url);
  if(sparseNoZoneId && process.platform==='win32'){
    git('config','core.sparseCheckout','true');
    sync.writeFileSync(path.join(dest,'.git/info/sparse-checkout'),'/*\n!*:Zone.Identifier\n');
  }
  git('-c','http.version=HTTP/1.1','fetch','--depth=1','origin',sha);
  git(...(sparseNoZoneId && process.platform==='win32'?['-c','core.protectNTFS=false']:[]),'checkout','--detach','FETCH_HEAD');
}
function github(file,value) {
  if(/[\r\n]/.test(value))throw Error('multiline GitHub environment entry');
  if(process.env[file]) sync.appendFileSync(process.env[file],value+'\n');
}
export const appendGithubEnv=(key,value)=>github('GITHUB_ENV',key+'='+value);
export const appendGithubPath=dir=>github('GITHUB_PATH',dir);
const hosts=[
  ['linux-x64','linux_x86_64','linux','x64','ubuntu-24.04'],
  ['linux-aarch64','linux_aarch64','linux','arm64','ubuntu-24.04-arm'],
  ['darwin-arm64','darwin_aarch64','darwin','arm64','macos-15'],
  ['darwin-x64','darwin_x86_64','darwin','x64','macos-15-intel'],
  ['windows-x64','windows_x86_64','win32','x64','windows-2025'],
];
export const PLATFORMS=Object.fromEntries(hosts.map(([key,platform,os,arch,runner])=>[key,{
  key,platform,os,arch,runner,tuple:platform+'_cjnative',exe:os==='win32'?'.exe':'',
  shared:{win32:'.dll',darwin:'.dylib',linux:'.so'}[os],
  loader:{win32:'PATH',darwin:'DYLD_LIBRARY_PATH',linux:'LD_LIBRARY_PATH'}[os],
  llvmDirectory:os==='win32'?'bin':'lib',llvmLibrary:{win32:'libLLVM-15.dll',darwin:'libLLVM.dylib',linux:'libLLVM-15.so'}[os],
  llvmFoundationLibrary:os==='win32'?'libLLVM-Foundation-15.dll':null,linker:os==='darwin'?'ld64.lld':'ld.lld',
}]));
export function sdkPlatform(name) {
  const host=Object.values(PLATFORMS).find(p=>name?p.platform===name||p.key===name:p.os===process.platform&&p.arch===process.arch);
  if(!host)throw Error('unsupported native platform: '+name);
  return host;
}
export const crossTuples={
  'windows-x64':'windows_x86_64_cjnative','android-aarch64':'linux_android_aarch64_cjnative',
  'ios-aarch64':'ios_aarch64_cjnative','ios-simulator-aarch64':'ios_simulator_aarch64_cjnative','ios-simulator-x86_64':'ios_simulator_x86_64_cjnative',
  'ohos-aarch64':'linux_ohos_aarch64_cjnative','ohos-x86_64':'linux_ohos_x86_64_cjnative','wasm32-wasi':'wasi_wasm32_cjnative','linux-x64':'linux_x86_64_cjnative',
};
export const RELEASE_TARGETS=[
  ['linux-x64','linux-x64','windows-x64'],['linux-arm64','linux-aarch64','windows-x64'],['win32-x64','windows-x64'],
  ['darwin-arm64','darwin-arm64'],['darwin-x64','darwin-x64'],
  ['linux-x64-android','linux-x64','android-aarch64'],['darwin-arm64-android','darwin-arm64','android-aarch64'],['win32-x64-android','windows-x64','android-aarch64','linux-x64'],
  ['linux-x64-wasm','linux-x64','wasm32-wasi'],['darwin-arm64-wasm','darwin-arm64','wasm32-wasi'],['win32-x64-wasm','windows-x64','wasm32-wasi'],
  ['linux-x64-ohos','linux-x64','ohos-aarch64','ohos-x86_64','windows-x64'],['darwin-arm64-ohos','darwin-arm64','ohos-aarch64'],
  ['darwin-arm64-ios','darwin-arm64','ios-aarch64','ios-simulator-aarch64','ios-simulator-x86_64'],['win32-x64-ohos','windows-x64','ohos-aarch64','ohos-x86_64'],
].map(([key,host,...cross])=>({key,host,cross,archiveKey:({'linux-arm64':'linux-aarch64','win32-x64':'windows-x64'})[key]||key,runner:PLATFORMS[host].runner}));

export function pathEnvironment(base=process.env,native=sdkPlatform()) {
  const env={...base};
  if(native.os==='win32'){
    // A plain object copied from process.env loses Windows' case folding.
    const keys=Object.keys(env).filter(k=>k.toUpperCase()==='PATH');
    const value=env.PATH??env[keys[0]];
    for(const key of keys)delete env[key];
    if(value!==undefined)env.PATH=value;
  }
  return env;
}
// xcrun follows the active Xcode selection. An explicit caller SDK always wins.
const macosSdkRoots = new Map();
function macosSdkRoot(env) {
  const selection = env.DEVELOPER_DIR || '';
  if (!macosSdkRoots.has(selection)) {
    const root = childProcess.execFileSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], {encoding: 'utf8', env}).trim();
    if (!root) throw new Error('xcrun returned an empty macOS SDK path');
    macosSdkRoots.set(selection, root);
  }
  return macosSdkRoots.get(selection);
}

export function sdkEnvironment(sdk, platform, base = process.env, runtimeRoot = sdk) {
  const native = sdkPlatform(platform), delimiter = native.os === 'win32' ? ';' : ':';
  base=pathEnvironment(base,native);
  if (native.os === 'darwin' && process.platform === 'darwin' && !base.SDKROOT) base.SDKROOT = macosSdkRoot(base);
  const tools = [sdk+'/bin', sdk+'/tools/bin', sdk+'/third_party/llvm/bin'];
  const libraries = [runtimeRoot+'/runtime/lib/'+native.tuple, runtimeRoot+'/lib/'+native.tuple,
    sdk+'/third_party/llvm/'+native.llvmDirectory, sdk+'/tools/lib'];
  return {...base, CANGJIE_HOME:sdk,
    PATH:[...tools, ...(native.loader === 'PATH' ? libraries : []), base.PATH].filter(Boolean).join(delimiter),
    ...(native.loader === 'PATH' ? {} : {[native.loader]:[...libraries,base[native.loader]].filter(Boolean).join(delimiter)})};
}

export const darwinX64OnArm = p => p.key==='darwin-x64' && process.arch==='arm64';
export const homebrewPrefix = () => process.arch==='arm64'?'/opt/homebrew':'/usr/local';
export function checkDarwinX64(file,{thin=false}={}) {
  const archs=runCapture('lipo',['-archs',file]).trim();
  if(!(thin?archs==='x86_64':archs.split(/\s+/).includes('x86_64')))
    throw Error(file+': expected '+(thin?'only ':'')+'x86_64, got '+archs);
}

function appendMacBinutils(clean,native) {
  if(native.os!=='darwin')return;
  // Use keg-only tools such as llvm-ranlib only after the SDK and host tools.
  const keg=homebrewPrefix()+'/opt/llvm@16/bin';
  const hostPath=clean.PATH?clean.PATH.split(':').filter(dir=>dir!==keg):[];
  clean.PATH=[...hostPath,keg].join(':');
}

export function nativeBuildEnvironment(native,base=process.env) {
  const env=pathEnvironment(base,native);
  if(native.os==='darwin'){
    // runtime/build.py selects clang by name. Keep the selected CMake on PATH.
    env.CC='/usr/bin/clang';env.CXX='/usr/bin/clang++';
    appendMacBinutils(env,native);
  }
  return env;
}

export function compilerHeap(native,env=process.env) {
  return {cjHeapSize:env.cjHeapSize||(native.os==='darwin'?'6GB':'12GB'),
    ...(native.os==='linux'?{cjHeapSwap:env.cjHeapSwap||'on'}:{})};
}

export function linkCompilerRuntime(sdk) {
  const link=path.join(sdk,'libexec/runtime');
  rmrf(link);sync.symlinkSync(path.join('..','.compiler-exec','runtime'),link,'dir');
}

// Installed consumers must not inherit an earlier SDK's module/library search
// path. Keep unrelated build controls (including jobserver descriptors) intact.
export function cleanSdkEnvironment(sdk,platform,base=process.env,runtimeRoot=sdk) {
  const native=sdkPlatform(platform),clean=pathEnvironment(base,native);
  for(const key of ['CANGJIE_HOME','CANGJIE_PATH','LIBRARY_PATH','LD_LIBRARY_PATH','LD_PRELOAD','LD_AUDIT',
    'DYLD_LIBRARY_PATH','DYLD_FALLBACK_LIBRARY_PATH','DYLD_INSERT_LIBRARIES','CPATH','C_INCLUDE_PATH','CPLUS_INCLUDE_PATH'])delete clean[key];
  if(base.CANGJIE_HOME) {
    const delimiter=sdkPlatform(platform).os==='win32'?';':':';
    const key=p=>native.os==='win32'?p.replaceAll('\\','/').toLowerCase():p;
    const previous=key(base.CANGJIE_HOME).replace(/\/+$/,'');
    clean.PATH=(clean.PATH||'').split(delimiter).filter(p=>key(p)!==previous&&!key(p).startsWith(previous+'/')).join(delimiter);
  }
  appendMacBinutils(clean,native);
  return sdkEnvironment(sdk,platform,clean,runtimeRoot);
}

export async function resolveHostPython(sdk, env = process.env) {
  const roots = [];
  for (const root of new Set([sdk, env.CANGJIE_HOME].filter(Boolean))) {
    roots.push(path.resolve(root));
    try { roots.push(await fs.realpath(root)); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  const inSdk = file => roots.some(root => {
    const rel = path.relative(root, file);
    return rel !== '..' && !rel.startsWith('..' + path.sep) && !path.isAbsolute(rel);
  });
  const search = pathEnvironment(env).PATH ?? '';
  const names = process.platform === 'win32' ? ['python3.exe', 'python.exe'] : ['python3','python'];
  for (const dir of search.split(path.delimiter)) {
    if (!path.isAbsolute(dir) || inSdk(dir)) continue;
    for (const name of names) {
      const file = path.join(dir, name);
      try {
        if (inSdk(await fs.realpath(dir)) || inSdk(await fs.realpath(file))) continue;
        if (!(await fs.stat(file)).isFile()) continue;
        await fs.access(file, fs.constants.X_OK);
        return file;
      } catch (error) {
        if (!['ENOENT', 'ENOTDIR', 'EACCES'].includes(error.code)) throw error;
      }
    }
  }
  throw new Error('Host Python 3 executable not found outside the SDK on PATH');
}

export function makeLauncher(file,p) {
  ensureDir(path.dirname(file));
  const args=['-std=c++17','-O2',path.join(repo,'build/entry.cpp'),'-o',file];
  if(p.os==='win32')args.push('-static','-lshell32');
  run(p.os==='win32'?path.join(process.env.CJCJ_WINDOWS_TOOLCHAIN,'bin/clang++.exe'):(process.env.CXX||'c++'),args);
}
export function installEntry(sdk,entry,real,libraries,launcher,p) {
  const bin=path.join(sdk,entry);
  sync.accessSync(path.join(sdk,real));
  rmrf(bin);copyTree(launcher,bin);
  sync.writeFileSync(bin+'.entry',['cjcj-sdk-entry-v1',entry.split('/').length-1,real,p.os==='win32'?'windows':p.os,'native-target:'+p.arch,...libraries].join('\n')+'\n');
}
