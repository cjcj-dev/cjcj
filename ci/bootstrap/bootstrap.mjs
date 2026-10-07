#!/usr/bin/env zx
// Two-stage bootstrap. The source and SDK contracts have one native selector.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {nativeHost, execute, nativeEnvironment, stdSystemPath, compilerCacheEnvironment} from './host_tools.mjs';
import {sha256File} from './sdk_verify.mjs';
import {runtimeDir, findFiles, validateTuple, nativeSymbols} from './native_libraries.mjs';
const self = fileURLToPath(import.meta.url), here = path.dirname(self);
const hash = content => crypto.createHash('sha256').update(content).digest('hex');
const file = p => { try { return fs.statSync(p).isFile(); } catch { return false; } };
const directory = p => { try { return fs.statSync(p).isDirectory(); } catch { return false; } };
const exists = p => fs.existsSync(p);
const quote = value => /^[\w/@+=:.,-]+$/.test(String(value)) ? String(value) : `'${String(value).replaceAll("'", "'\\''")}'`;
const read = p => fs.readFileSync(p, 'utf8');
function cleanReal(p) {
  const absolute = path.resolve(p);
  if (exists(absolute)) return fs.realpathSync(absolute);
  const parent = path.dirname(absolute);
  return parent === absolute ? absolute : path.join(cleanReal(parent),path.basename(absolute));
}
export class Bootstrap {
  constructor(args) {
    Object.assign(this, {WORK:'',SRC:'',STDSRC:'',HOST_LLVM_SO:'',HOST_LLVM_SHA256:'',COLOUR_LLVM_SO:'',COLOUR_LLVM_SHA256:'',COLOUR_TUPLE:'',COLOUR_LLVM_SHA:'',CRT:'',HRT:'',AST_SUPPORT:'',AST_SUPPORT_SHA256:'',CPP_SRC:'',CJCJ_SHA:'',BASE_SDK:process.env.BASE_SDK || 'cjcj-pin-937877c8',HEAP:process.env.CJ_HEAP || '96GB',STAGE1_HEAP:process.env.STAGE1_HEAP || '20GB',STAGE0_CACHE_ROOT:process.env.STAGE0_CACHE_ROOT || '/root/stage0depot',BUILD_HOME:process.env.HOME || '/root',STAGE:'init',WANT:'all',DRY:false,CHECK_ONLY:false,STAGE1_ELF:'',STAGE1_SHA256:'',HOST_SDK:'',RUNTIME_SHA:'',HOST_IDENTITIES:'',HOST_IDENTITIES_SHA256:'',RUNTIME_PIN:'',COLOUR_GATE_SOURCE:'',COLOUR_GATE_INSTALL:''});
    this.SDK_BUILD = process.env.SDK_BUILD || path.join(here,'sdk_build.sh');
    this.SDK_VERIFY = process.env.SDK_VERIFY || path.join(here,'sdk_verify.py');
    this.STAGE1_HOST_RUNNER = process.env.STAGE1_HOST_RUNNER || path.join(here,'stage1_host_runner.sh');
    const names = {'work':'WORK','src':'SRC','stdsrc':'STDSRC','cpp-src':'CPP_SRC','cjcj-sha':'CJCJ_SHA','base':'BASE_SDK','host-llvm-so':'HOST_LLVM_SO','host-llvm-sha256':'HOST_LLVM_SHA256','colour-llvm-so':'COLOUR_LLVM_SO','colour-llvm-sha256':'COLOUR_LLVM_SHA256','ast-support':'AST_SUPPORT','ast-support-a':'AST_SUPPORT','ast-support-sha256':'AST_SUPPORT_SHA256','colour-tuple':'COLOUR_TUPLE','colour-llvm-sha':'COLOUR_LLVM_SHA','colour-rt':'CRT','host-rt':'HRT','stage':'WANT','stage1-heap':'STAGE1_HEAP','runtime-pin':'RUNTIME_PIN','host-identities':'HOST_IDENTITIES','host-identities-sha256':'HOST_IDENTITIES_SHA256','stage1-elf':'STAGE1_ELF','stage1-sha256':'STAGE1_SHA256','host-sdk':'HOST_SDK','runtime-sha':'RUNTIME_SHA','colour-gate-source':'COLOUR_GATE_SOURCE','colour-gate-install':'COLOUR_GATE_INSTALL'};
    for (let i=0; i<args.length; i++) {
      const name = args[i].replace(/^--/,'');
      if (name === 'dry-run') this.DRY = true;
      else if (name === 'check-only') this.CHECK_ONLY = true;
      else if (['-h','--help'].includes(args[i])) this.HELP = true;
      else if (names[name] && args[i+1] && !args[i+1].startsWith('--')) this[names[name]] = args[++i];
      else if (['colour-llc','host-llvm','host-llc'].includes(name)) this.die(`参数 --${name} 已废弃；使用 --colour-tuple / --host-llvm-so`);
      else this.die(`未知参数 ${args[i]}`);
    }
  }
  die(message) { const error = new Error(`BOOTSTRAP-FAIL [${this.STAGE}] ${message}`); error.exitCode=1; throw error; }
  ok(message) { console.log('  ✓ ' + message); }
  cmd(command, args = [], options = {}) {
    const prefix = options.env ? 'env -i ' + Object.entries(options.env).map(([key,value]) => `${key}=${quote(value)}`).join(' ') + ' ' : '';
    console.log('CMD ' + prefix + [command,...args].map(quote).join(' ') + (options.cwd ? ` cwd=${options.cwd}` : ''));
    if (this.DRY) return {stdout:'',stderr:'',exitCode:0};
    const result = execute(command,args,{...options,check:false});
    if (result.stdout) process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
    if (result.exitCode !== 0 || result.signal) {
      const error = new Error(`BOOTSTRAP-FAIL [${this.STAGE}] 命令失败 rc=${result.exitCode} signal=${result.signal || 'none'}: ${command}`);
      error.exitCode=result.exitCode; error.signal=result.signal; throw error;
    }
    return result;
  }
  mutate(label, action) { console.log('CMD ' + label); if (!this.DRY) action(); }
  sha(p) {
    if (file(p)) return sha256File(p);
    if (directory(p)) return hash(findFiles(p,()=>true).filter(file).map(f => `${sha256File(f)}  ${f}\n`).join(''));
    return '';
  }
  record(label,p) { if (!exists(p)) this.die(`${label} 不存在: ${p}`); console.log(`INPUT ${label} path=${fs.realpathSync(p)} sha256=${this.sha(p)}`); }
  assertExpected(label,p,expected) {
    if (!/^[0-9a-fA-F]{64}$/.test(expected)) this.die(`${label} 期望 sha256 必须是 64 位十六进制数`);
    const actual=this.sha(p); console.log(`ASSERT ${label}-sha256 expected=${expected.toLowerCase()} actual=${actual}`);
    if (!actual || actual !== expected.toLowerCase()) this.die(`${label} sha256 不匹配`);
    this.ok(`${label} sha256 匹配`);
  }
  host_tuple_init() {
    this.native=nativeHost(); this.HOST_TUPLE=this.native.tuple; this.HOST_MULTIARCH=this.native.multiarch;
    this.JOBS=process.env.CJ_JOBS || String(os.availableParallelism?.() || os.cpus().length);
    console.log(`HOST-TUPLE ${this.HOST_TUPLE} multiarch=${this.HOST_MULTIARCH} home=${this.BUILD_HOME}`);
  }
  assertColourTuple(tuple,expected) {
    validateTuple(tuple);
    const manifest=/^LLVM_SHA=([^\r\n]*)$/m.exec(read(path.join(tuple,'MANIFEST')))?.[1] || '';
    if (!/^[0-9a-fA-F]{40}$/.test(manifest) || !/^[0-9a-fA-F]{40}$/.test(expected)) this.die('colour LLVM MANIFEST 与期望 SHA 必须是 40 位十六进制数');
    console.log(`ASSERT colour-manifest-sha expected=${expected.toLowerCase()} actual=${manifest.toLowerCase()}`);
    if (manifest.toLowerCase() !== expected.toLowerCase()) this.die('colour LLVM tuple MANIFEST LLVM_SHA 与期望值不匹配');
    const output=execute('strings',[path.join(tuple,'bin/opt')]).stdout;
    const stamps=[...output.matchAll(/CJLLVM-COMMIT:([0-9a-fA-F]{40})/g)].map(match=>match[1]);
    console.log(`ASSERT colour-opt-stamp ruler=strings token=CJLLVM-COMMIT:<40hex> hits=${stamps.length} sha=${stamps.join(',') || 'none'} file=${tuple}/bin/opt`);
    if (stamps.length !== 1) this.die(`colour LLVM tuple opt 的 CJLLVM-COMMIT 章计数不是 1: hits=${stamps.length}`);
    if (stamps[0].toLowerCase() !== manifest.toLowerCase()) this.die('colour LLVM tuple opt 章与 MANIFEST LLVM_SHA 不匹配');
  }
  assertLlvm(host,tuple,expected) {
    if (!file(host)) this.die(`host LLVM SO 不存在: ${host}`);
    const valid=this.native.os === 'darwin' ? /^libLLVM.*\.dylib$/ : /^libLLVM.*\.so/;
    if (!valid.test(path.basename(host))) this.die(`host LLVM SO 文件名不符合 ${this.native.format}: ${host}`);
    this.assertColourTuple(tuple,expected); this.assertExpected('host-llvm',host,this.HOST_LLVM_SHA256);
    const output=this.native.os === 'darwin' ? nativeSymbols(host,{runtime:true}).map(symbol=>symbol.name).join('\n') : execute('readelf',['--dyn-syms','--wide',host]).stdout;
    const demangled=execute('c++filt',[],{input:output}).stdout;
    const hits=demangled.split('\n').filter(line=>line.includes('llvm::isCJTypedReadHelperCandidate(')).length;
    console.log(`ASSERT host-llvm-zero ruler=${this.native.dynsymRuler} symbol=llvm::isCJTypedReadHelperCandidate hits=${hits} file=${host}`);
    if (hits !== 0) this.die(`host LLVM 含 colour 动态符号 hits=${hits}`);
    this.ok('host LLVM 动态符号零命中，colour tuple 章与 manifest 匹配');
  }
  assertOfficialOpt(opt) {
    if (!file(opt)) this.die(`official LLVM opt 不存在: ${opt}`);
    const hits=execute('strings',[opt]).stdout.split('\n').filter(line=>line.includes('CJLLVM-COMMIT:')).length;
    console.log(`ASSERT official-opt-zero ruler=strings token=CJLLVM-COMMIT: hits=${hits} file=${opt}`);
    if (hits) this.die(`official LLVM opt 含 colour commit 章 hits=${hits}`);
  }
  assertPath(label,p) {
    if (!exists(p)) this.die(`${label} 不存在: ${p}`);
    console.log(`ASSERT ${label} exists=1 path=${p}`);
  }
  assertExecutable(label,p) {
    if (this.DRY) { console.log(`ASSERT ${label} executable=planned path=${p}`); return; }
    try { fs.accessSync(p,fs.constants.X_OK); } catch { this.die(`${label} 不存在或不可执行: ${p}`); }
    console.log(`ASSERT ${label} executable=1 path=${p}`);
  }
  assertInstalledLlvm(sdk,source) {
    const target=path.join(sdk,'third_party/llvm/lib',path.basename(source));
    if (this.DRY) { console.log(`ASSERT installed-host-llvm-so sha256=planned source=${source} target=${target}`); return; }
    const expected=this.sha(source),actual=this.sha(target);
    console.log(`ASSERT installed-host-llvm-so expected=${expected} actual=${actual} target=${target}`);
    if (!file(target) || expected !== actual) this.die('host LLVM SO 安装后 sha256 不一致');
  }
  assertInstalledTuple(sdk,tuple) {
    for (const line of read(path.join(tuple,'SHA256SUMS')).trimEnd().split('\n')) {
      const [expected,rel]=line.split('  ./'), target=path.join(sdk,'third_party/llvm',rel);
      if (this.DRY) console.log(`ASSERT installed-colour-tuple sha256=planned expected=${expected} target=${target}`);
      else { const actual=this.sha(target); console.log(`ASSERT installed-colour-tuple expected=${expected} actual=${actual} target=${target}`); if (!file(target) || actual !== expected) this.die(`colour LLVM tuple 安装后 sha256 不一致: ${rel}`); }
    }
  }
  install(source,target,mode) { this.mutate(`install -m${mode.toString(8)} ${quote(source)} ${quote(target)}`,()=>{ fs.mkdirSync(path.dirname(target),{recursive:true}); fs.copyFileSync(source,target); fs.chmodSync(target,mode); }); }
  copyTree(source,target,dereference=false) { this.mutate(`cp -a${dereference?'L':''} ${quote(source)} ${quote(target)}`,()=>fs.cpSync(source,target,{recursive:true,preserveTimestamps:true,verbatimSymlinks:!dereference,dereference})); }
  remove(p) { this.mutate(`rm -rf -- ${quote(p)}`,()=>fs.rmSync(p,{recursive:true,force:true})); }
  mkdir(p) { this.mutate(`mkdir -p ${quote(p)}`,()=>fs.mkdirSync(p,{recursive:true})); }
  installCompiler(source,target,alias) {
    this.install(source,target,0o755);
    this.mutate(`ln -sfn ${quote(path.basename(target))} ${quote(alias)}`,()=>{ fs.rmSync(alias,{force:true}); fs.symlinkSync(path.basename(target),alias); });
  }
  prepareRunSdk() {
    const sdk=this.WORK+'/sdk-stage0-run',name=this.native.library;
    this.assertExpected('colour-llvm',this.COLOUR_LLVM_SO,this.COLOUR_LLVM_SHA256);
    this.remove(sdk); this.copyTree(this.WORK+'/sdk-stage0',sdk,true);
    this.install(this.COLOUR_LLVM_SO,`${sdk}/third_party/llvm/lib/${name}`,0o644);
    if (!this.DRY) { this.assertExpected('installed-colour-llvm',`${sdk}/third_party/llvm/lib/${name}`,this.COLOUR_LLVM_SHA256); this.assertExpected('preserved-host-llvm',`${this.WORK}/sdk-stage0/third_party/llvm/lib/${name}`,this.HOST_LLVM_SHA256); }
  }
  sdkLoader(sdk,runtime) { return [runtimeDir(runtime),`${sdk}/runtime/lib/${this.HOST_TUPLE}`,`${sdk}/lib/${this.HOST_TUPLE}`,`${sdk}/third_party/llvm/lib`,`${sdk}/tools/lib`,...(this.HOST_MULTIARCH ? [`/usr/lib/${this.HOST_MULTIARCH}`] : [])].join(':'); }
  async buildEnv(sdk,runtime,heap='',std=false) {
    const system=std ? await stdSystemPath() : this.native.systemPath;
    return {...compilerCacheEnvironment(),HOME:this.BUILD_HOME,...(this.BUILD_TMPDIR ? {TMPDIR:this.BUILD_TMPDIR} : {}),CANGJIE_HOME:sdk,[this.native.loader]:this.sdkLoader(sdk,runtime),PATH:`${sdk}/bin:${sdk}/tools/bin:${sdk}/third_party/llvm/bin:${system}`,...await nativeEnvironment(),...(heap?{cjHeapSize:heap}:{})};
  }
  async assertVersion(label,compiler,sdk,runtime) {
    this.assertExecutable(label,compiler);
    const env=await this.buildEnv(sdk,runtime); env.PATH=this.native.systemPath;
    this.cmd(compiler,['--version'],{env}); if (!this.DRY) this.ok(`${label} --version rc=0`);
  }
  ffiManifest(prefix) {
    const rel=`lib/${this.HOST_TUPLE}`;
    const names=findFiles(path.join(prefix,rel),name=>/FFI\.a$/i.test(name),1).map(p=>path.relative(prefix,p));
    if (file(`${prefix}/lib/libstdFFI${this.native.librarySuffix}`)) names.push(`lib/libstdFFI${this.native.librarySuffix}`);
    return names.sort().join('\n');
  }
  assertStdShape(prefix,compare='',label='stdlib') {
    if (this.DRY) { console.log(`ASSERT ${label} shape=planned Int64.ti>1 FFI-archives>0${compare?' FFI-set-equals='+compare:''}`); return; }
    const core=`${prefix}/lib/${this.HOST_TUPLE}/libcangjie-std-core.a`,shared=`${prefix}/runtime/lib/${this.HOST_TUPLE}/libcangjie-std-core${this.native.librarySuffix}`,ffi=`${prefix}/lib/libstdFFI${this.native.librarySuffix}`;
    if (![core,shared,ffi].every(file)) this.die(`${label} install shape: core archive/shared 或 libstdFFI${this.native.librarySuffix} 缺失`);
    const ti=[core,shared,ffi].flatMap(p=>nativeSymbols(p,{defined:true,archive:true})).filter(symbol=>symbol.name==='Int64.ti').length;
    if (ti <= 1) this.die(`${label} install shape: Int64.ti definitions=${ti} (expected >1)`);
    const archives=findFiles(`${prefix}/lib/${this.HOST_TUPLE}`,name=>/FFI\.a$/i.test(name),1).length;
    if (!archives) this.die(`${label} install shape: FFI archive set is empty`);
    if (compare && (!directory(compare) || this.ffiManifest(prefix)!==this.ffiManifest(compare))) this.die(`${label} install shape: FFI library set differs from same-run stage0`);
    console.log(`ASSERT ${label} shape=ok Int64.ti=${ti} FFI-archives=${archives}${compare?' FFI-set-equal=1':''}`);
  }
  resources(heap) {
    const result=execute('bash',[`${this.SRC}/ci/build_resources.sh`,heap]);
    if (result.stderr) process.stderr.write(result.stderr);
    const values=Object.fromEntries(result.stdout.trim().split('\n').map(line=>line.split('=')));
    if (!values.STD_BUILD_HEAP || !values.STD_BUILD_JOBS) this.die('cannot determine build resources');
    return values;
  }
  prepareBuildEnv() {
    this.BUILD_TMPDIR=process.env.TMPDIR || this.WORK+'/tmp-private';
    this.mkdir(this.BUILD_TMPDIR); console.log(`BUILD-ENV planned HOME=${this.BUILD_HOME} TMPDIR=${this.BUILD_TMPDIR}`);
  }
  async stdlibBuild(label,sdk,runtime,prefix,compare='',targetLib=`${sdk}/runtime/lib/${this.HOST_TUPLE}`) {
    const resources=this.resources(this.HEAP);
    this.cmd('python3',[this.SRC+'/ci/install_std_sdk_inputs.py',path.dirname(this.AST_SUPPORT),sdk,this.HOST_TUPLE]);
    this.prepareBuildEnv(); const env=await this.buildEnv(sdk,runtime,resources.STD_BUILD_HEAP,true);
    this.remove(this.STDSRC+'/build/build');
    this.cmd('python3',['build.py','clean'],{env,cwd:this.STDSRC});
    this.cmd('python3',['build.py','build','-t','relwithdebinfo','--jobs',resources.STD_BUILD_JOBS,'--target-lib='+targetLib],{env,cwd:this.STDSRC});
    this.cmd('python3',['build.py','install','--prefix',prefix],{env,cwd:this.STDSRC});
    this.assertStdShape(prefix,compare,label);
    const compiler=file(sdk+'/bin/cjcj-stage1') ? sdk+'/bin/cjcj-stage1' : sdk+'/bin/cjc';
    if (file(compiler) || this.DRY) this.mutate(`write ${prefix}/std-producer.json compiler=${compiler}`,()=>fs.writeFileSync(prefix+'/std-producer.json',JSON.stringify({compiler_sha256:sha256File(compiler)})+'\n'));
  }
  assertRoot() { if (!directory(this.SRC) || !file(this.SRC+'/cjpm.toml')) this.die(`--src 缺少 cjpm.toml: ${this.SRC}`); console.log(`ASSERT cjcj-root cjpm.toml=1 path=${this.SRC}/cjpm.toml`); }
  assertSourceSha() {
    if (!/^[0-9a-fA-F]{40}$/.test(this.CJCJ_SHA)) this.die('--cjcj-sha 必须是 40 位十六进制数');
    this.CJCJ_SHA=this.CJCJ_SHA.toLowerCase();
    const actual=execute('git',['-C',this.SRC,'rev-parse','HEAD'],{check:false}).stdout.trim().toLowerCase();
    console.log(`ASSERT cjcj-sha expected=${this.CJCJ_SHA} actual=${actual || 'unavailable'} source=${actual?'git':'explicit-pin'}`);
    if (actual && actual !== this.CJCJ_SHA) this.die('cjcj 源码 HEAD 与 --cjcj-sha 不匹配');
  }
  isolate(dest) { console.log(`ISOLATE cjcj-src from=${this.SRC} dest=${dest} (user tree untouched)`); this.mkdir(dest); this.cmd('rsync',['-a','--exclude','target','--exclude','/.srcbuild/',this.SRC+'/',dest+'/']); }
  rewriteO1(toml) {
    if (this.DRY) { console.log(`CMD sed -i s/compile-option = "-O2"/compile-option = "-O1"/ ${quote(toml)}`); console.log(`ASSERT compile-option-o1 planned file=${toml}`); return; }
    if (!file(toml)) this.die(`隔离副本缺 cjpm.toml: ${toml}`);
    const original=read(toml),content=original.replace(/^( *compile-option = ")-O2([\s"])/gm,'$1-O1$2');
    fs.writeFileSync(toml,content);
    if (!/^ *compile-option = "-O1([\s"])/m.test(content)) this.die(`隔离副本 cjpm.toml 的 compile-option 不是 -O1: ${toml}`);
    if (/^ *compile-option = "-O2([\s"])/m.test(content)) this.die(`compile-option 仍含 -O2: ${toml}`);
    console.log(`ASSERT compile-option-o1 ok file=${toml}`);
  }
  product(bin,label) {
    if (this.DRY) { console.log(`ASSERT ${label} product=planned dir=${bin} names=cjc@cjcj|cjcj::cjc`); return bin+'/cjcj::cjc'; }
    const found=['cjc@cjcj','cjcj::cjc'].map(name=>bin+'/'+name).filter(file);
    if (found.length !== 1) this.die(`${label} cjpm 产物缺失或非恰好 1 个 n=${found.length} dir=${bin}`);
    console.error(`ASSERT ${label} product exists=1 path=${found[0]}`); return found[0];
  }
  async cjpmBuild(sdk,runtime,src,extra,heap) {
    this.cmd('node',[src+'/ci/check-codegen-runtime-layout.mjs',this.WORK+'/layout-sources',this.RUNTIME_PIN,...(this.WANT==='supplied-stage1'?[this.COLOUR_LLVM_SHA]:[])]);
    const resources=this.resources(heap); this.prepareBuildEnv();
    this.cmd('node',[this.SRC+'/ci/release/trimpath.mjs',src,...(extra.includes('-g')?['--debug']:[])]);
    console.log(`CMD cjpm build${extra.length?' '+extra.join(' '):''} bin=${sdk}/tools/bin/cjpm cwd=${src} heap=${resources.STD_BUILD_HEAP}`);
    this.cmd(sdk+'/tools/bin/cjpm',['build',...extra],{env:await this.buildEnv(sdk,runtime,resources.STD_BUILD_HEAP),cwd:src});
  }
  assertCpp() {
    if (!directory(this.CPP_SRC)) this.die(`--cpp-src 不是目录: ${this.CPP_SRC}`);
    for (const rel of ['third_party/llvm-project/llvm/include','build/build/third_party/llvm/include','build/build/include','build/build/schema']) {
      const p=this.CPP_SRC+'/'+rel;
      if (!directory(p) || !findFiles(p,()=>true).length) this.die(`--cpp-src shim 头文件目录为空或缺失: ${p}`);
      console.log(`ASSERT shim-cpp-src exists=1 path=${p}`);
    }
  }
  async shimBuild(label,sdk,runtime,src,sourceObject='') {
    const npx=execute('bash',['-c','command -v npx']).stdout.trim();
    if (!npx) this.die(`${label} shim 构建需要可执行 npx`);
    console.log(`ASSERT ${label}-npx executable=1 path=${npx} node-bin=${path.dirname(npx)}`);
    if (sourceObject) { if (!this.DRY && (!file(sourceObject) || fs.statSync(sourceObject).size===0)) this.die(`${label} 四件套 shim 对象缺失或为空: ${sourceObject}`); }
    else this.assertCpp();
    console.log(`CMD shim build label=${label} cwd=${src} cpp-src=${this.CPP_SRC} source-object=${sourceObject || 'source'} sdk=${sdk} runtime=${runtime}`);
    this.remove(src+'/runtime_shim/cjselfhost_llvmshim.o'); this.remove(src+'/runtime_shim/cjc_runtime_config.o');
    const env=await this.buildEnv(sdk,runtime);
    env.CANGJIE_CPP_SRC=this.CPP_SRC; env.CJCJ_COMMIT=this.CJCJ_SHA; env.PATH=`${sdk}/bin:${sdk}/tools/bin:${sdk}/third_party/llvm/bin:${path.dirname(npx)}:${this.native.systemPath}`;
    if (sourceObject) env.CJCJ_LLVM_SHIM_O=sourceObject;
    this.cmd('bash',[src+'/runtime_shim/build_shim.sh'],{env});
    for (const [kind,name] of [['cpp','cjselfhost_llvmshim.o'],['config','cjc_runtime_config.o']]) if (this.DRY) console.log(`OUTPUT ${label}-shim-${kind} path=${src}/runtime_shim/${name} sha256=planned`); else this.record(`${label}-shim-${kind}`,src+'/runtime_shim/'+name);
  }
  treeHash(root) {
    if (!directory(root)) throw new Error('tree missing: '+root);
    const tar=this.native.os === 'darwin' ? 'gtar' : 'tar';
    return hash(execute(tar,['--sort=name','--mtime=UTC 1970-01-01','--owner=0','--group=0','--numeric-owner','-C',root,'-cf','-','.'],{encoding:null}).stdout);
  }
  sourceIdentity(label,root,required=false) {
    const head=execute('git',['-C',root,'rev-parse','HEAD'],{check:false}).stdout.trim();
    if (head) {
      const status=execute('git',['-C',root,'status','--porcelain','--untracked-files=normal'],{check:false});
      if (status.exitCode !== 0 || status.stdout) { console.error(`STAGE0_CACHE=disabled reason=${label}-${status.exitCode?'status-failed':'dirty'}`); return null; }
      return 'git:'+head.toLowerCase();
    }
    if (required) { console.error(`STAGE0_CACHE=disabled reason=${label}-not-git`); return null; }
    return 'tree:'+this.treeHash(root);
  }
  cacheKey(base,toml) {
    const identity=this.sourceIdentity('cjcj',this.SRC,true); if (!identity) return null;
    const pin=this.SRC+'/ci/host_sdk_pin.env';
    const nightly=file(pin) ? /^CJCJ_TOOLCHAIN=(.*)$/m.exec(read(pin))?.[1] : '';
    if (!nightly) { console.error('STAGE0_CACHE=disabled reason=host-nightly-pin-missing'); return null; }
    const compile=read(toml).split('\n').filter(line=>/^\s*compile-option\s*=/.test(line)).join('\n');
    if (!compile) { console.error('STAGE0_CACHE=disabled reason=compile-option-missing'); return null; }
    const runtime=path.join(runtimeDir(this.HRT),this.native.runtimeLibrary);
    if (!file(runtime)) { console.error('STAGE0_CACHE=disabled reason=host-runtime-so-missing'); return null; }
    const headers=['third_party/llvm-project/llvm/include','build/build/third_party/llvm/include','build/build/include','build/build/schema'].map(rel=>`${rel}=${this.treeHash(this.CPP_SRC+'/'+rel)}\n`).join('');
    const material=['format=stage0-cache-v2',`cjcj=${identity}`,`host_nightly=${nightly}`,`host_cjc_sha256=${this.sha(base+'/bin/cjc')}`,`host_llvm_sha256=${this.sha(this.HOST_LLVM_SO)}`,`host_runtime_so_sha256=${this.sha(runtime)}`,`ast_support_sha256=${this.sha(this.AST_SUPPORT)}`,`ast_inputs_sha256=${this.sha(path.dirname(this.AST_SUPPORT)+'/SHA256SUMS')}`,`ast_installer_sha256=${this.sha(this.SRC+'/ci/install_std_sdk_inputs.py')}`,`build_resources_sha256=${this.sha(this.SRC+'/ci/build_resources.sh')}`,`bootstrap_sha256=${this.sha(self)}`,`sdk_build_sha256=${this.sha(this.SDK_BUILD)}`,`cpp_headers_sha256=${headers}`,`cjcj_compile_options=${compile}`].join('\n');
    return hash(material);
  }
  cacheRestore(key,out) {
    const entry=this.STAGE0_CACHE_ROOT+'/'+key,manifest=entry+'/MANIFEST';
    if (!file(manifest)) { console.log(`STAGE0_CACHE=miss key=${key} reason=missing`); return false; }
    const values=Object.fromEntries(read(manifest).trimEnd().split('\n').map(line=>line.split('\t')));
    const reject=reason=>{console.log(`STAGE0_CACHE=rejected key=${key} reason=${reason}`); return false;};
    if (values.format !== 'stage0-cache-v2') return reject('format');
    if (values.key !== key) return reject('key');
    if (!/^[0-9a-f]{64}$/.test(values.cjcj_stage1_sha256 || '')) return reject('manifest-sha');
    if (!file(entry+'/cjcj-stage1')) return reject('payload-missing');
    if (this.sha(entry+'/cjcj-stage1') !== values.cjcj_stage1_sha256) return reject('cjcj-sha-mismatch');
    fs.rmSync(out,{force:true}); fs.copyFileSync(entry+'/cjcj-stage1',out); fs.chmodSync(out,0o755);
    if (this.sha(out) !== values.cjcj_stage1_sha256) return false;
    console.log(`STAGE0_CACHE=hit key=${key} path=${entry}`); return true;
  }
  cachePublish(key,out) {
    fs.mkdirSync(this.STAGE0_CACHE_ROOT,{recursive:true});
    const incoming=fs.mkdtempSync(`${this.STAGE0_CACHE_ROOT}/.incoming-${key}.`),entry=this.STAGE0_CACHE_ROOT+'/'+key;
    fs.copyFileSync(out,incoming+'/cjcj-stage1'); fs.chmodSync(incoming+'/cjcj-stage1',0o755);
    const digest=this.sha(incoming+'/cjcj-stage1');
    fs.writeFileSync(incoming+'/MANIFEST',`format\tstage0-cache-v2\nkey\t${key}\ncjcj_stage1_sha256\t${digest}\n`);
    const rejected=`${this.STAGE0_CACHE_ROOT}/.replaced-${key}-${process.pid}`;
    if (exists(entry)) fs.renameSync(entry,rejected);
    fs.renameSync(incoming,entry); fs.rmSync(rejected,{recursive:true,force:true});
    console.log(`STAGE0_CACHE=stored key=${key} path=${entry} cjcj_sha=${digest}`);
  }
  baseSdk() {
    let base=this.BASE_SDK;
    if (!path.isAbsolute(base)) base=['/root/sdks/'+base,'/root/.cjv/toolchains/'+base].find(directory);
    if (!base || !directory(base)) this.die(`官方 SDK 不存在: ${this.BASE_SDK}`);
    return fs.realpathSync(base);
  }
  sdkBuild(args) { this.cmd(this.SDK_BUILD.endsWith('.mjs')?'node':'bash',[this.SDK_BUILD,'--runtime-pin',this.RUNTIME_PIN,...args,'--colour-runtime',runtimeDir(this.CRT)+'/'+this.native.runtimeLibrary,'--host-runtime',runtimeDir(this.HRT)+'/'+this.native.runtimeLibrary,'--force']); }
  sdkVerify(sdk,role) { if (!this.DRY) this.cmd(this.SDK_VERIFY.endsWith('.mjs')?'node':'python3',[this.SDK_VERIFY,'--sdk',sdk,'--role',role,'--runtime-pin',this.RUNTIME_PIN]); }
  hostRunner(sdk,compiler,backend='') {
    this.cmd(this.STAGE1_HOST_RUNNER.endsWith('.mjs')?'node':'bash',[this.STAGE1_HOST_RUNNER,sdk,this.WORK+'/sdk-stage0',this.HRT,this.HOST_LLVM_SHA256,compiler,this.DRY?'planned':this.sha(compiler),this.WORK+'/sdk-stage0-run',this.COLOUR_LLVM_SHA256,...(backend?[backend]:[])]);
  }
  async stage0() {
    this.STAGE='stage0'; console.log('[stage0] official cjc + stdlib + host LLVM; cjcj=-O1');
    const base=this.baseSdk(),out=this.WORK+'/cjcj-stage1',sdk=this.WORK+'/sdk-stage0',copy=this.WORK+'/cjcj-src-stage0';
    for (const [label,p] of [['official-sdk',base],['host-llvm-so',this.HOST_LLVM_SO],['ast-support',this.AST_SUPPORT],['host-runtime',this.HRT],['colour-control',this.COLOUR_TUPLE]]) this.record(label,p);
    this.assertOfficialOpt(base+'/third_party/llvm/bin/opt'); this.assertExpected('ast-support',this.AST_SUPPORT,this.AST_SUPPORT_SHA256);
    this.assertLlvm(this.HOST_LLVM_SO,this.COLOUR_TUPLE,this.COLOUR_LLVM_SHA); this.assertRoot(); this.assertPath('cjcj-source',this.SRC); this.assertPath('stdlib-source',this.STDSRC);
    this.mkdir(this.WORK); console.log('OUTPUT cjcj-stage1='+out);
    this.sdkBuild(['--from',base,'--to',sdk,'--host','--llvm-so',this.HOST_LLVM_SO]); this.sdkVerify(sdk,'host'); this.assertInstalledLlvm(sdk,this.HOST_LLVM_SO);
    this.install(this.AST_SUPPORT,`${sdk}/lib/${this.HOST_TUPLE}/libcangjie-ast-support.a`,0o644);
    if (!this.DRY) this.assertExpected('installed-ast-support',`${sdk}/lib/${this.HOST_TUPLE}/libcangjie-ast-support.a`,this.AST_SUPPORT_SHA256);
    this.isolate(copy); this.rewriteO1(copy+'/cjpm.toml');
    this.cmd('node',[copy+'/ci/check-codegen-runtime-layout.mjs',this.WORK+'/layout-sources',this.RUNTIME_PIN]);
    let key=null,hit=false;
    if (!this.DRY) { key=this.cacheKey(base,copy+'/cjpm.toml'); if (key) hit=this.cacheRestore(key,out); }
    else console.log('STAGE0_CACHE=planned key=content-addressed dirty=disabled');
    if (!hit) { await this.shimBuild('stage0',sdk,this.HRT,copy); await this.cjpmBuild(sdk,this.HRT,copy,[],this.HEAP); this.installCompiler(this.product(copy+'/target/release/bin','cjcj-stage1'),out,this.WORK+'/cjc'); }
    else this.mutate('ln -sfn cjcj-stage1 '+this.WORK+'/cjc',()=>{fs.rmSync(this.WORK+'/cjc',{force:true});fs.symlinkSync('cjcj-stage1',this.WORK+'/cjc');});
    if (!this.DRY) this.assertExecutable('cjcj-stage1',out);
    this.prepareRunSdk(); await this.assertVersion('cjcj-stage1',out,this.WORK+'/sdk-stage0-run',this.HRT);
    if (this.HOST_TUPLE === 'linux_x86_64_cjnative') this.cmd('bash',[copy+'/ci/test-codegen-runtime-layout.sh',out,sdk,this.COLOUR_LLVM_SO,this.WORK+'/layout-sources/llvm',this.WORK+'/layout-sources/runtime',this.WORK+'/layout-ir-stage0',this.RUNTIME_PIN]);
    if (!this.DRY) { if (key && !hit) this.cachePublish(key,out); fs.writeFileSync(this.WORK+'/.cjcj-stage1',out+'\n'); }
  }
  assembleStage1(sdk,compiler,std) {
    this.sdkBuild(['--from',this.WORK+'/sdk-stage0','--to',sdk,'--target',this.HOST_TUPLE,'--cjc',compiler,'--llvm-tuple',this.COLOUR_TUPLE,'--llvm-so',this.COLOUR_LLVM_SO,'--runtime',this.CRT,'--std',std,'--verify-host-rt',this.HRT]);
    this.sdkVerify(sdk,'target'); this.assertInstalledTuple(sdk,this.COLOUR_TUPLE);
    if (!this.DRY) this.assertExpected('target-colour-llvm',`${sdk}/third_party/llvm/lib/${this.native.library}`,this.COLOUR_LLVM_SHA256);
    this.hostRunner(sdk,compiler); this.assertExecutable('stage1-compiler',sdk+'/bin/cjc');
  }
  async bootstrapTargetStd(compiler,std) {
    const sdk=this.WORK+'/sdk-std-bootstrap',target=runtimeDir(this.CRT),root=this.WORK+'/std-runtime-link';
    this.sdkBuild(['--from',this.WORK+'/sdk-stage0','--to',sdk,'--host','--llvm-tuple',this.COLOUR_TUPLE]);
    this.assertInstalledTuple(sdk,this.COLOUR_TUPLE); this.install(compiler,sdk+'/bin/cjc',0o755); this.install(this.COLOUR_LLVM_SO,`${sdk}/third_party/llvm/lib/${this.native.library}`,0o644);
    if (!this.DRY) for (const [label,p] of [['std-bootstrap-host-std',`${sdk}/lib/${this.HOST_TUPLE}/libcangjie-std-core.a`],['std-bootstrap-host-runtime',`${sdk}/runtime/lib/${this.HOST_TUPLE}/${this.native.runtimeLibrary}`],['std-bootstrap-target-runtime',`${target}/${this.native.runtimeLibrary}`]]) this.record(label,p);
    this.hostRunner(sdk,compiler,target);
    const common=`${root}/common/${this.native.os}_relwithdebinfo_${this.native.arch}`,native=`${common}/lib/${this.HOST_TUPLE}`,dynamic=`${common}/runtime/lib/${this.HOST_TUPLE}`;
    this.remove(root); this.mkdir(native); this.mkdir(dynamic);
    // Darwin toolchain has no GNU linker scripts. Preserve Linux's four inputs.
    const files=this.native.os === 'darwin' ? ['libcangjie-aio.a','cjstart.o','section.o'] : ['libcangjie-aio.a','cjstart.o','cjld.shared.lds','discard_eh_frame.lds'];
    for (const name of files) { this.install(`${sdk}/lib/${this.HOST_TUPLE}/${name}`,native+'/'+name,0o644); if (!this.DRY) this.record('std-bootstrap-native',native+'/'+name); }
    for (const name of [this.native.runtimeLibrary,`libboundscheck${this.native.librarySuffix}`]) { this.install(target+'/'+name,dynamic+'/'+name,0o644); if (!this.DRY) this.record('std-bootstrap-target',dynamic+'/'+name); }
    await this.stdlibBuild('stdlib-stage1',sdk,this.HRT,std,'',root);
    this.cmd('node',[here+'/std_runtime_colour.mjs','--colour-runtime',runtimeDir(this.CRT)+'/'+this.native.runtimeLibrary,'--host-runtime',runtimeDir(this.HRT)+'/'+this.native.runtimeLibrary,'--runtime',target+'/'+this.native.runtimeLibrary,'--std',`${std}/lib/${this.HOST_TUPLE}/libcangjie-std-core.a`,'--source',this.STDSRC]);
    this.remove(sdk); this.remove(root);
  }
  stage1Inputs() {
    let compiler=file(this.WORK+'/.cjcj-stage1') ? read(this.WORK+'/.cjcj-stage1').trim() : '';
    if (this.DRY) { compiler ||= this.WORK+'/cjcj-stage1'; console.log(`INPUT cjcj-stage1 path=${compiler} sha256=not-built(dry-run)`); }
    else { if (!compiler) this.die('缺少 stage0 cjcj-stage1'); this.record('cjcj-stage1',compiler); }
    this.record('colour-llvm-tuple',this.COLOUR_TUPLE); this.record('colour-runtime',this.CRT); this.assertLlvm(this.HOST_LLVM_SO,this.COLOUR_TUPLE,this.COLOUR_LLVM_SHA);
    this.phase={compiler,previousStd:this.WORK+'/stdlib-stage1',out:this.WORK+'/cjcj-stage2',std:this.WORK+'/stdlib-stage2',sdk:this.WORK+'/sdk-stage1'};
  }
  async stage1InitialStd() { this.STAGE='stage1-initial-std'; this.prepareRunSdk(); await this.bootstrapTargetStd(this.phase.compiler,this.phase.previousStd); }
  async stage1Std() { this.STAGE='stage1-std'; const {sdk,compiler,previousStd,std}=this.phase; this.assembleStage1(sdk,compiler,previousStd); await this.stdlibBuild('stdlib-stage2',sdk,this.HRT,std,previousStd); }
  async stage1Compiler() {
    this.STAGE='stage1-compiler'; const {out,std,sdk,compiler}=this.phase;
    console.log('OUTPUT cjcj-stage2='+out); console.log('OUTPUT bootstrap-std='+std);
    this.assembleStage1(sdk,compiler,std);
    const copy=this.WORK+'/cjcj-src-stage1'; this.isolate(copy);
    await this.shimBuild('stage1',sdk,this.CRT,copy,sdk+'/third_party/llvm/fixed-llc/cjselfhost_llvmshim.o');
    await this.cjpmBuild(sdk,this.HRT,copy,['-j',this.JOBS],this.STAGE1_HEAP);
    this.installCompiler(this.product(copy+'/target/release/bin','cjcj-stage2'),out,this.WORK+'/cjc-stage2');
    if (!this.DRY) { this.assertExecutable('cjcj-stage2',out); if (!directory(std)) this.die('stage1 未产出 stdlib-stage2'); }
    await this.assertVersion('cjcj-stage2',out,sdk,this.CRT);
    this.cmd('npx',['--yes','zx@8',this.SRC+'/ci/bootstrap/publish-std-output.mjs',this.WORK,std,compiler,this.HOST_TUPLE]);
    await this.stage2Forensic();
  }
  async stage1(which='all') {
    this.STAGE='stage1'; console.log('[stage1] cjcj-stage1 self-host + coloured LLVM; C++=RelWithDebInfo'); this.stage1Inputs();
    if (which === 'all' || which === 'initial-std') await this.stage1InitialStd();
    if (which === 'all' || which === 'std') await this.stage1Std();
    if (which === 'all' || which === 'compiler') await this.stage1Compiler();
  }
  async stage2Forensic() {
    if (process.env.CJCJ_FORENSIC_STAGE2 !== '1') return;
    const sdk=this.WORK+'/sdk-stage1',out=this.WORK+'/cjcj-stage2-forensic',copy=this.WORK+'/cjcj-src-stage1-forensic';
    console.log('OUTPUT cjcj-stage2-forensic='+out); console.log(`FORENSIC stage2 enabled=1 flag=-g product-dir=target/debug/bin source=${copy}`);
    this.isolate(copy); await this.shimBuild('stage1',sdk,this.CRT,copy,sdk+'/third_party/llvm/fixed-llc/cjselfhost_llvmshim.o');
    await this.cjpmBuild(sdk,this.HRT,copy,['-j',this.JOBS,'-g'],this.STAGE1_HEAP);
    this.installCompiler(this.product(copy+'/target/debug/bin','cjcj-stage2-forensic'),out,this.WORK+'/cjc-stage2-forensic');
    if (!this.DRY) { this.assertExecutable('cjcj-stage2-forensic',out); this.record('cjcj-stage2-forensic',out); this.record('cjcj-stage2-forensic-src',copy+'/cjpm.toml'); }
    else { console.log(`INPUT cjcj-stage2-forensic path=${out} sha256=planned`); console.log(`INPUT cjcj-stage2-forensic-src path=${copy}/cjpm.toml sha256=planned`); }
    console.log(`INPUT cjcj-stage2-forensic-cjcj-sha sha256=${this.CJCJ_SHA}`);
  }
  supplied_stage1_validate() {
    for (const name of ['STAGE1_ELF','STAGE1_SHA256','HOST_SDK','RUNTIME_SHA','HOST_IDENTITIES','HOST_IDENTITIES_SHA256']) if (!this[name]) this.die(`缺少参数 ${name} (supplied-stage1)`);
    if (!/^[0-9a-f]{40}$/.test(this.RUNTIME_SHA)) this.die('runtime SHA must be 40 lowercase hex digits');
    const selection=execute('node',[here+'/../runtime-pin.mjs','--shell',this.RUNTIME_PIN]).stdout;
    if (!selection.split('\n').includes(`RUNTIME_REF='${this.RUNTIME_SHA}'`)) this.die('runtime SHA differs from runtime pin');
    if (process.env.LD_LIBRARY_PATH) this.die('mixed domain: inherited LD_LIBRARY_PATH must be empty');
    if (process.env.DYLD_LIBRARY_PATH) this.die('mixed domain: inherited DYLD_LIBRARY_PATH must be empty');
    if (process.env.CANGJIE_HOME) this.die('mixed domain: inherited CANGJIE_HOME must be empty');
    this.assertExpected('host-identities',this.HOST_IDENTITIES,this.HOST_IDENTITIES_SHA256); process.env.STAGE1_HOST_IDENTITIES=this.HOST_IDENTITIES;
    this.HOST_SDK=fs.realpathSync(this.HOST_SDK); this.WORK=cleanReal(this.WORK);
    if (['/','/root'].includes(this.WORK) || /^\/root\/(sdks|\.cjv)(\/|$)/.test(this.WORK)) this.die('private work directory required');
    if (this.HOST_SDK.startsWith(this.WORK+'/')) this.die('host SDK must be outside work directory');
    if (exists(this.WORK)) this.die('supplied-stage1 refuses an existing work directory');
    this.assertExecutable('stage1 ELF',this.STAGE1_ELF);
    if (this.native.os === 'darwin') { if (!execute('file',['-b',this.STAGE1_ELF]).stdout.includes('Mach-O')) this.die('stage1 input must be Mach-O'); }
    else execute('readelf',['-h',this.STAGE1_ELF]);
    for (const [label,p,digest] of [['stage1',this.STAGE1_ELF,this.STAGE1_SHA256],['host-llvm',this.HOST_LLVM_SO,this.HOST_LLVM_SHA256],['colour-llvm',this.COLOUR_LLVM_SO,this.COLOUR_LLVM_SHA256],['ast-support',this.AST_SUPPORT,this.AST_SUPPORT_SHA256]]) this.assertExpected(label,p,digest);
    this.assertColourTuple(this.COLOUR_TUPLE,this.COLOUR_LLVM_SHA);
    if (!execute('strings',[runtimeDir(this.CRT)+'/'+this.native.runtimeLibrary]).stdout.split('\n').includes('CJRT-COMMIT:'+this.RUNTIME_SHA)) this.die('runtime artifact commit differs from explicit SHA');
    if (!file(this.STDSRC+'/build.py')) this.die('missing std source build.py');
    this.assertExecutable('host cjpm',this.HOST_SDK+'/tools/bin/cjpm');
    console.log('SUPPLIED-STAGE1-INPUTS-OK (identity/domain checks only; no compilation)');
  }
  async suppliedStage1() {
    this.mkdir(this.WORK); this.copyTree(this.HOST_SDK,this.WORK+'/sdk-stage0',true);
    this.cmd('python3',[this.SRC+'/ci/install_std_sdk_inputs.py',path.dirname(this.AST_SUPPORT),this.WORK+'/sdk-stage0',this.HOST_TUPLE]);
    this.install(this.STAGE1_ELF,this.WORK+'/cjcj-stage1',0o755);
    fs.writeFileSync(this.WORK+'/.cjcj-stage1',this.WORK+'/cjcj-stage1\n');
    this.stage1Inputs(); await this.stage1InitialStd(); this.phase.std=this.phase.previousStd;
    if (this.COLOUR_GATE_SOURCE || this.COLOUR_GATE_INSTALL) {
      if (!this.COLOUR_GATE_SOURCE || !this.COLOUR_GATE_INSTALL) this.die('colour gate requires source and install');
      this.STAGE='colour-runtime-gate'; this.assembleStage1(this.phase.sdk,this.phase.compiler,this.phase.std);
      this.cmd('npx',['--yes','zx@8',this.SRC+'/ci/release/gate_colour_runtime.mjs','--build-sdk',this.COLOUR_GATE_SOURCE,this.phase.sdk,this.WORK+'/colour-gate-active',this.COLOUR_GATE_INSTALL]);
    }
    await this.stage1Compiler(); this.STAGE='stage2-smoke'; fs.writeFileSync(this.WORK+'/main.cj','main(): Int64 { return 0 }\n');
    const env=await this.buildEnv(this.phase.sdk,this.CRT); env.PATH=this.phase.sdk+'/bin:'+this.native.systemPath;
    this.cmd(this.phase.out,[this.WORK+'/main.cj','-o',this.WORK+'/main'],{env});
    this.cmd(this.WORK+'/main',[],{env:{PATH:this.native.systemPath,[this.native.loader]:runtimeDir(this.CRT)+':'+this.phase.sdk+'/lib/'+this.HOST_TUPLE}});
  }
  async main() {
    if (this.HELP) { console.log('bootstrap.mjs --work DIR --src ROOT --cjcj-sha SHA --stdsrc DIR --cpp-src DIR --host-llvm-so FILE --host-llvm-sha256 HEX --colour-llvm-so FILE --colour-llvm-sha256 HEX --ast-support FILE --ast-support-sha256 HEX --colour-tuple DIR --colour-llvm-sha SHA --colour-rt DIR --host-rt DIR [--stage supplied-stage1|stage0|stage1|stage1-initial-std|stage1-std|stage1-compiler|all] [--dry-run]'); return; }
    for (const name of ['WORK','SRC','CJCJ_SHA','STDSRC','HOST_LLVM_SO','HOST_LLVM_SHA256','COLOUR_LLVM_SO','COLOUR_LLVM_SHA256','AST_SUPPORT','AST_SUPPORT_SHA256','COLOUR_TUPLE','COLOUR_LLVM_SHA','CRT','HRT']) if (!this[name]) this.die('缺少参数 '+name);
    if (!['supplied-stage1','stage0','stage1','stage1-initial-std','stage1-std','stage1-compiler','all'].includes(this.WANT)) this.die('invalid --stage');
    if (['stage0','all'].includes(this.WANT) && !this.CPP_SRC) this.die('缺少参数 CPP_SRC');
    this.RUNTIME_PIN=fs.realpathSync(this.RUNTIME_PIN || here+'/../runtime_pin.env');
    execute('node',[here+'/../runtime-pin.mjs','--shell',this.RUNTIME_PIN]); this.record('runtime-pin',this.RUNTIME_PIN);
    this.host_tuple_init();
    this.assertSourceSha(); this.assertRoot();
    if (this.WANT === 'supplied-stage1') { if (this.DRY) this.die('use --check-only for supplied-stage1 static validation'); this.supplied_stage1_validate(); if (this.CHECK_ONLY) return; }
    else if (this.CHECK_ONLY) this.die('--check-only requires --stage supplied-stage1');
    if (this.WANT === 'supplied-stage1') await this.suppliedStage1();
    else {
      if (['stage0','all'].includes(this.WANT)) await this.stage0();
      if (['stage1','all'].includes(this.WANT)) await this.stage1();
      if (this.WANT.startsWith('stage1-')) await this.stage1(this.WANT.slice('stage1-'.length));
    }
    console.log(`BOOTSTRAP-OK 到 ${this.WANT} work=${this.WORK}`);
    if (this.DRY) console.log('DRY-RUN: no compilation performed');
  }
}
if (process.argv[1] && path.resolve(process.argv[1]) === self) {
  try { await new Bootstrap(process.argv.slice(2)).main(); }
  catch (error) { console.error(error.message); if (error.signal) process.kill(process.pid,error.signal); else process.exitCode=error.exitCode ?? 1; }
}
