import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import test from 'node:test';
import {repo,compilerHeap,loadPins,sdkPlatform} from '../../build/common.mjs';
import {effectiveLinkOptions,h1HeapDefaultsBuild,h1PackageLinkOptions} from '../../build/build-compiler.mjs';

test('source pins use full commit SHAs and select the expected tools revision',()=>{
  const pins=loadPins();
  assert.equal(pins.repos.h1,undefined);
  assert.equal(Object.keys(pins.repos).length,9);
  for(const [name,pin] of Object.entries(pins.repos)){
    assert.match(pin.sha,/^[0-9a-f]{40}$/,name+' source SHA');
  }
  assert.equal(pins.repos.tools.sha,'4d14d051c58a5574d6525314b2c695e2e5dd26e6');
});

test('source pins select the expected runtime revision',()=>{
  const pins=loadPins();
  assert.equal(pins.repos.runtime.sha,'b628e2bd5183b809d04f8e5808ecf3b00e46bf29');
});

for(const workflow of ['prepare','release','ci']){
  test(workflow+' builds stage0 from its checkout',()=>{
    const yaml=fs.readFileSync(path.join(repo,'.github/workflows',workflow+'.yml'),'utf8');
    assert.doesNotMatch(yaml,/\.\.\/src\/h1\b/);
    // Join shell continuations and YAML's indented, folded command arguments.
    const commands=yaml.replace(/\\\r?\n\s*|\r?\n[ \t]+(?=--)/g,' ').split('\n');
    const stages=commands.filter(line=>line.includes('build/build-compiler.mjs --stage stage0'));
    assert.ok(stages.length>0);
    for(const command of stages)assert.doesNotMatch(command,/--source\b/);
    for(const line of commands.filter(line=>/\brepos\b/.test(line)))assert.doesNotMatch(line,/\bh1\b/);
    assert.match(yaml,/rm -rf \.\.\/stage0 \.\.\/stage0\.target\b/);
  });
}

for(const key of ['linux-x64','linux-aarch64','darwin-arm64','darwin-x64']){
  test('stage0 uses checkout link and heap inputs: '+key,{skip:process.platform==='win32'},()=>{
    const {platform,llvmDirectory,llvmLibrary,os}=sdkPlatform(key);
    const workspaceText=fs.readFileSync(path.join(repo,'cjpm.toml'),'utf8');
    const packageText=fs.readFileSync(path.join(repo,'packages/cjc/cjpm.toml'),'utf8');
    const link='runtime_shim/h1-'+llvmLibrary;
    const llvmLibraryFile=path.resolve(repo,'../native/third_party/llvm',llvmDirectory,llvmLibrary);
    for(const supports of [true,false]){
      const rewritten=h1PackageLinkOptions(packageText,{platform,source:repo,linkFile:path.join(repo,link),
        llvmLibraryFile,hostRuntimeSupportsConfigV1:supports});
      const flags=effectiveLinkOptions(rewritten,platform);
      assert.ok(flags.includes(path.normalize(link)));
      assert.equal(flags.includes('--wrap=CJ_MRT_CjRuntimeInitWithConfigV1'),os==='linux'&&supports);
    }
    const sourcePresent=fs.existsSync(path.join(repo,'runtime_shim/cjc_heap_defaults.c'));
    assert.equal(h1HeapDefaultsBuild({platform,workspaceText,packageText,sourcePresent}),os==='linux');
  });
}

const tuple='linux_x86_64_cjnative';
function fixture(t){
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'sdk-stage-'));
  t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
  return root;
}
function put(file,data='',mode=0o644){
  fs.mkdirSync(path.dirname(file),{recursive:true});
  fs.writeFileSync(file,data,{mode});
}
function cli(name,args,env={},options=[]){
  const child=spawnSync(process.execPath,[...options,path.join(repo,'build',name+'.mjs'),...args],
    {cwd:repo,env:{...process.env,...env},encoding:'utf8'});
  assert.equal(child.status,0,child.error?.message||child.stderr+child.stdout);
}
const linux={skip:process.platform!=='linux'};
test('stage0 leaves a clean checkout for the stage2 shim build',linux,t=>{
  const dir=fixture(t),src=dir+'/checkout',host=dir+'/host',native=dir+'/native',out=dir+'/stage0';
  const shim='runtime_shim/cjselfhost_llvmshim.o',selected=native+'/third_party/llvm/fixed-llc/cjselfhost_llvmshim.o';
  for(const file of ['.gitignore','cjpm.toml','cjpm.lock','packages/cjc/cjpm.toml','build/common.mjs',
    'build/build-compiler.mjs','runtime_shim/build_shim.mjs','runtime_shim/cjc_heap_defaults.c','runtime_shim/cjc_runtime_config.c'])
    put(src+'/'+file,fs.readFileSync(path.join(repo,file)));
  const env={...process.env,CC:dir+'/bin/cc',CXX:dir+'/bin/cc',CMAKE_C_COMPILER_LAUNCHER:'',
    PATH:dir+'/bin:'+process.env.PATH};
  function exec(cmd,args,extra={},expected=0){
    const child=spawnSync(cmd,args,{cwd:src,env:{...env,...extra},encoding:'utf8'});
    assert.equal(child.status,expected,child.error?.message||child.stderr+child.stdout);
    return expected?child.stderr:child.stdout.trim();
  }
  exec('git',['init','-q']);exec('git',['add','.']);
  exec('git',['-c','user.name=Test','-c','user.email=test@example.invalid','-c','commit.gpgSign=false','commit','-qm','fixture']);
  const commit=exec('git',['rev-parse','HEAD']);
  put(selected,'stage0 shim');put(native+'/third_party/llvm/lib/libLLVM-15.so');
  put(host+'/lib/'+tuple+'/host');put(host+'/runtime/lib/'+tuple+'/host');
  // Stand in for native tools: record which inputs the real stage scripts selected.
  put(dir+'/bin/cc','#!/bin/sh\nargs="$*"\nwhile [ "$1" != "-o" ]; do shift || exit 1; done\nprintf "%s" "$args" > "$2"\n',0o755);
  put(dir+'/bin/nm','#!/bin/sh\nexit 0\n',0o755);
  put(host+'/tools/bin/cjpm',`#!/bin/sh
set -eu
test "$(cat runtime_shim/cjselfhost_llvmshim.o)" = 'stage0 shim'
test -f runtime_shim/h1-libLLVM-15.so
test -s runtime_shim/cjc_heap_defaults.o
grep -q -- '-DCJCJ_LEGACY_HOST_RUNTIME' runtime_shim/cjc_runtime_config.o
echo changed > cjpm.lock
[ "$FAIL_CJPM" = no ] || exit 42
mkdir -p "$3/release/bin"
echo stage0 > "$3/release/bin/cjc"
`,0o755);
  put(src+'/'+shim,'existing shim');put(src+'/runtime_shim/cjc_runtime_config.o','existing config');
  const args=['build/build-compiler.mjs','--stage','stage0','--host-sdk',host,'--native',native,'--out',out];
  for(const fail of [true,false]){
    const result=exec(process.execPath,args,{FAIL_CJPM:fail?'yes':'no'},fail?1:0);
    if(fail)assert.match(result,/cjpm build .* exited 42/);
    assert.equal(fs.readFileSync(src+'/'+shim,'utf8'),'existing shim');
    assert.equal(fs.readFileSync(src+'/runtime_shim/cjc_runtime_config.o','utf8'),'existing config');
    assert.ok(!fs.existsSync(src+'/runtime_shim/cjc_heap_defaults.o'));
    assert.deepEqual(fs.readdirSync(src+'/runtime_shim').filter(f=>f.startsWith('h1-')),[]);
    assert.equal(exec('git',['status','--porcelain']),'');
  }
  assert.ok(!fs.existsSync(src+'/target'),'stage0 wrote into checkout/target');
  assert.equal(fs.readFileSync(out+'.target/release/bin/cjc','utf8').trim(),'stage0');
  // Stage2 selects its own shim and recompiles both C objects using the clean revision.
  put(selected,'stage2 shim');
  exec(process.execPath,['runtime_shim/build_shim.mjs'],{CJCJ_COMMIT:commit,CJCJ_LLVM_SHIM_O:selected,CANGJIE_HOME:out});
  assert.equal(fs.readFileSync(src+'/'+shim,'utf8'),'stage2 shim');
  const config=fs.readFileSync(src+'/runtime_shim/cjc_runtime_config.o','utf8');
  assert.ok(config.includes('-DCJCJ_COMMIT="'+commit+'"'));
  assert.ok(!config.includes('-DCJCJ_LEGACY_HOST_RUNTIME'));
  assert.ok(fs.readFileSync(src+'/runtime_shim/cjc_heap_defaults.o','utf8').includes(src+'/runtime_shim/cjc_heap_defaults.c'));
});

test('stage 2, stage 3 and the relocated package exclude bootstrap tools',linux,t=>{
  const dir=fixture(t),host=dir+'/H',native=dir+'/N',src=dir+'/source';
  let parent=dir+'/bootstrap';
  const sentinel='tools/bin/LSPServer',git=spawnSync('git',['rev-parse','--absolute-git-dir'],{cwd:repo,encoding:'utf8'});
  assert.equal(git.status,0);
  put(host+'/'+sentinel,'official only');put(parent+'/'+sentinel,'official only');
  put(host+'/LICENSE','host license');put(host+'/Open_Source_Software_Notice.docx','notice');
  put(host+'/tools/bin/cjpm',`#!/bin/sh
set -eu
test "$cjHeapSize" = "$EXPECTED_HEAP" && test "$cjHeapSwap" = on || exit 44
mkdir -p "$3/release/bin"
cat "$CANGJIE_HOME/modules/${tuple}/current" > "$3/release/bin/cjc"
`,0o755);
  put(native+'/tools/bin/native-only','native');put(native+'/third_party/llvm/lib/libLLVM-15.so','N LLVM');
  put(native+'/third_party/llvm/bin/lldb');put(native+'/third_party/flatbuffers/bin/flatc','#!/bin/sh\nexit 0\n',0o755);
  put(src+'/cjpm.toml','[workspace]\ncompile-option = "-O2"\n');put(src+'/packages/cjc/cjpm.toml','[package]\n');
  put(src+'/runtime_shim/build_shim.mjs',`import fs from 'node:fs'; for(const n of ['cjselfhost_llvmshim','cjc_runtime_config','cjc_heap_defaults'])fs.writeFileSync('runtime_shim/'+n+'.o','fixture');`);
  put(src+'/schema/StdxChirFormat.fbs');put(src+'/packages/chir/src/Enums.cj','public func AttributeIndex(attr: Attribute): Int64 {\ncase Attribute.Debug => 0\n}\n');
  put(parent+'/.compiler-exec/runtime/lib/'+tuple+'/previous','official private');
  put(parent+'/libexec/compiler/cjcj-stage1','old compiler');
  for(const entry of ['bin/cjc','bin/cjc-frontend','bin/cjcj-stage1','tools/bin/chir-dis']){
    put(parent+'/'+entry);put(parent+'/'+entry+'.entry');
  }
  for(const stage of ['stage2','stage3']){
    const std=dir+'/'+stage+'-std',out=dir+'/'+stage;
    put(std+'/modules/'+tuple+'/current',stage);put(std+'/lib/'+tuple+'/current',stage);
    put(std+'/runtime/lib/'+tuple+'/current','R');
    cli('build-compiler',['--stage',stage,'--sdk',parent,'--std',std,'--native',native,'--host-sdk',host,'--source',src,'--out',out],
      {GIT_DIR:git.stdout.trim(),cjHeapSize:stage==='stage2'?undefined:'4GB',cjHeapSwap:undefined,EXPECTED_HEAP:stage==='stage2'?'12GB':'4GB'});
    assert.equal(fs.existsSync(out+'/'+sentinel),false,stage+' retained H/tools/bin/LSPServer');
    assert.equal(fs.readFileSync(out+'/tools/bin/native-only','utf8'),'native');
    assert.equal(fs.readFileSync(out+'/LICENSE','utf8'),'host license');
    assert.equal(fs.readFileSync(out+'/libexec/compiler/cjcj-stage1','utf8'),stage);
    assert.equal(fs.readFileSync(out+'/libexec/runtime/lib/'+tuple+'/current','utf8'),'R');
    assert.equal(fs.existsSync(out+'/.compiler-exec/runtime/lib/'+tuple+'/previous'),false);
    parent=out;
  }
  // Model an incoming transport that materialized the directory link as a file.
  fs.unlinkSync(parent+'/libexec/runtime');put(parent+'/libexec/runtime','stale link payload');
  put(parent+'/.host/'+sentinel,'private');put(parent+'/envsetup.sh','export FIXTURE=1');
  cli('package-sdk',['--sdk',parent,'--platform','linux-x64','--version','1.0.0','--out',dir+'/dist']);
  cli('setup',['unpack','--archive',dir+'/dist/cjcj-1.0.0-linux-x64.tar.gz','--dir',dir+'/fresh']);
  const sdk=dir+'/fresh/cangjie';
  assert.equal(fs.existsSync(sdk+'/'+sentinel),false);assert.equal(fs.existsSync(sdk+'/.host'),false);
  assert.equal(fs.realpathSync(sdk+'/libexec/runtime'),fs.realpathSync(sdk+'/.compiler-exec/runtime'));
  assert.equal(fs.readFileSync(sdk+'/tools/bin/native-only','utf8'),'native');
});

for(const [platform,tuple,suffix] of [['linux-x64','linux_x86_64_cjnative','.so'],['windows-x64','windows_x86_64_cjnative','.dll'],['darwin-arm64','darwin_aarch64_cjnative','.dylib']]){
  test('stdlib preserves runtime bytes and native inputs: '+platform,linux,t=>{
    const dir=fixture(t),src=dir+'/src',sdk=dir+'/sdk',rt=dir+'/R',out=dir+'/out';
    const lib='lib/'+tuple,run='runtime/'+lib,bounds='libboundscheck'+suffix;
    put(src+'/bounds/header');put(src+'/pcre2/header');put(rt+'/'+lib+'/rt.a');put(rt+'/'+run+'/'+bounds,'validated R');
    for(const rel of [lib+'/libcangjie-ast-support.a','schema/StdAstFormat.fbs','include/flatbuffers/StdAstFormat_generated.h',
      'third_party/flatbuffers/bin/flatc'+(suffix==='.dll'?'.exe':'')])put(sdk+'/'+rel,'native');
    const files=['modules/'+tuple+'/std/std.core.cjo','modules/'+tuple+'/std/libstd.core.bc',lib+'/libcangjie-std-core.a',
      run+'/libcangjie-std-core'+suffix,'lib/libstdFFI'+suffix,lib+'/'+bounds,run+'/'+bounds,lib+'/libcangjie-ast-support.a',
      'schema/old','include/old','third_party/flatbuffers/bin/old','third_party/python/old','third_party/flatbuffers/modules/current'];
    put(src+'/runtime/stdlib/build.py',`import pathlib, sys
if sys.argv[1]=='install':
 for rel in ${JSON.stringify(files)}:
  f=pathlib.Path(sys.argv[-1])/rel; f.parent.mkdir(exist_ok=True,parents=True); f.write_text('std')
`);
    cli('build-stdlib',['--stage','stage1-std','--platform',platform,'--sources',src,'--runtime',rt,'--sdk',sdk,'--out',out]);
    assert.equal(fs.readFileSync(out+'/'+run+'/'+bounds,'utf8'),'validated R',platform+' std overwrote R');
    assert.equal(fs.readFileSync(out+'/third_party/flatbuffers/modules/current','utf8'),'std');
    for(const f of [lib+'/libcangjie-ast-support.a','schema/old','include/old','third_party/flatbuffers/bin/old','third_party/python/old'])
      assert.equal(fs.existsSync(out+'/'+f),false,f);
    if(platform==='linux-x64')assert.equal(fs.readlinkSync(out+'/'+lib+'/'+bounds),'../../'+run+'/'+bounds,'relative boundscheck link');
    else assert.equal(fs.existsSync(out+'/'+lib+'/'+bounds),false);
  });
}

test('macOS installs Python dependencies from the formula union before the requested packages',{skip:process.platform==='win32'},t=>{
  const dir=fixture(t),log=dir+'/brew.log';
  put(dir+'/arch','#!/bin/sh\nexit 0\n',0o755);
  put(dir+'/brew',`#!${process.execPath}
const fs=require('node:fs'),args=process.argv.slice(2);
fs.appendFileSync(process.env.BREW_LOG,JSON.stringify(args)+'\\n');
if(args[0]==='deps' && args.includes('--union'))console.log('mpdecimal python@3.12');
// Stop after both installs, before the unrelated CMake download.
if(args[0]==='--prefix')process.exit(42);
`,0o755);
  const child=spawnSync(process.execPath,[path.join(repo,'build/setup.mjs'),'deps','--platform','darwin-x64','--mode','prepare'],
    {env:{...process.env,PATH:dir,BREW_LOG:log},encoding:'utf8'});
  assert.equal(child.status,1,child.error?.message||child.stderr);
  assert.match(child.stderr,/brew --prefix python@3\.11 exited 42/);
  const calls=fs.readFileSync(log,'utf8').trim().split('\n').map(line=>JSON.parse(line));
  const pkgs=calls[2].slice(1);
  assert.ok(pkgs.length>1 && pkgs.includes('llvm@16'));
  assert.deepEqual(calls,[
    ['deps','--formula','--union',...pkgs],
    ['install','--skip-link','python@3.11','python@3.12'],
    ['install',...pkgs],
    ['--prefix','python@3.11'],
  ]);
});

test('Linux overlay contains physical files in just three target directories',linux,t=>{
  const dir=fixture(t),sdk=dir+'/host';
  put(sdk+'/tools/unrelated');put(sdk+'/runtime/lib/'+tuple+'/bounds','R');put(sdk+'/modules/'+tuple+'/std/core','std');
  fs.mkdirSync(sdk+'/lib/'+tuple,{recursive:true});fs.symlinkSync('../../runtime/lib/'+tuple+'/bounds',sdk+'/lib/'+tuple+'/bounds');
  cli('setup',['pack','--linux-overlay','--archive',dir+'/cross.tar','--dir',sdk]);
  cli('setup',['unpack','--archive',dir+'/cross.tar','--dir',dir+'/overlay']);
  const overlay=dir+'/overlay';
  assert.deepEqual(fs.readdirSync(overlay).sort(),['lib','modules','runtime']);
  assert.ok(fs.lstatSync(overlay+'/lib/'+tuple+'/bounds').isFile());assert.equal(fs.readFileSync(overlay+'/lib/'+tuple+'/bounds','utf8'),'R');
});

test('heap defaults and explicit overrides cover all host families',()=>{
  for(const [key,heap] of [['linux-x64','12GB'],['darwin-arm64','6GB'],['windows-x64','12GB']]){
    const p=sdkPlatform(key);
    assert.deepEqual(compilerHeap(p,{}),{cjHeapSize:heap,...(p.os==='linux'?{cjHeapSwap:'on'}:{})});
    assert.equal(compilerHeap(p,{cjHeapSize:'4GB'}).cjHeapSize,'4GB');
  }
});

test('Windows runtime load probes preserve a Path-only host environment',linux,t=>{
  const dir=fixture(t),src=dir+'/src',out=dir+'/R',win='windows_x86_64_cjnative',bin=dir+'/tools';
  put(src+'/bounds/header');put(src+'/runtime/runtime/src/windows_x86_64_exports.def');
  for(const name of ['libcangjie-thread.a','libcangjie-aio.a'])put(out+'/lib/'+win+'/'+name);
  for(const name of ['libboundscheck.dll','libcangjie-runtime.dll'])put(out+'/runtime/lib/'+win+'/'+name);
  // Exercise the CLI and inspect both real child environments at the loader boundary.
  put(bin+'/python.exe','#!/bin/sh\nexit 0\n',0o755);put(bin+'/bash','#!/bin/sh\nexit 0\n',0o755);
  put(bin+'/clang++.exe','#!/bin/sh\n/bin/cp "$PROBE" "$3"\n',0o755);
  put(dir+'/probe','#!/usr/bin/python3\nimport json,os\nwith open(os.environ["PROBE_LOG"],"a") as f: print(json.dumps({k:v for k,v in os.environ.items() if k.upper()=="PATH"}),file=f)\n',0o755);
  const original=bin+':/usr/bin:/bin';
  cli('build-runtime',['--platform','windows-x64','--sources',src,'--out',out],{
    PATH:undefined,Path:original,MSYS2_BASH:bin+'/bash',CJCJ_NATIVE_LLVM_BIN:bin,PROBE:dir+'/probe',PROBE_LOG:dir+'/probe.log'
  });
  const rows=fs.readFileSync(dir+'/probe.log','utf8').trim().split('\n').map(s=>JSON.parse(s));
  assert.equal(rows.length,2);
  for(const row of rows){
    assert.deepEqual(Object.keys(row),['PATH'],'duplicate Windows Path key at load probe');
    assert.ok(row.PATH.endsWith(original),'load probe lost system PATH');
  }
});

// Run the stage entry on a simulated Apple Silicon host. Record the arguments at
// the subprocess boundary; these fixtures do not compile or execute Mach-O code.
function darwinStage(dir,name,args,respond,extra={},options=[]){
  const preload=dir+'/host.mjs',log=dir+'/calls';
  put(preload,`
import fs from 'node:fs';
import cp from 'node:child_process';
Object.defineProperty(process,'arch',{value:'arm64'});
Object.defineProperty(process,'platform',{value:'darwin'});
cp.spawnSync=(cmd,args,opts)=>{
  const env=opts?.env??process.env;
  fs.appendFileSync(${JSON.stringify(log)},JSON.stringify({cmd,args,path:env.PATH,arch:env.CMAKE_OSX_ARCHITECTURES,processor:env.CMAKE_APPLE_SILICON_PROCESSOR})+'\\n');
  ${respond}
  return {status:0,stdout:''};
};
`);
  const child=spawnSync(process.execPath,[...options,'--import',preload,path.join(repo,'build',name+'.mjs'),...args],{
    cwd:repo,encoding:'utf8',env:{...process.env,SDKROOT:'/fixture/MacOSX.sdk',...extra}
  });
  return {child,calls:fs.readFileSync(log,'utf8').trim().split('\n').map(JSON.parse)};
}

for(const platform of ['darwin-arm64','darwin-x64']){
  test('Apple Silicon LLVM stages: '+platform,{skip:process.platform==='win32'},t=>{
    const dir=fixture(t),src=dir+'/sources',work=dir+'/work',out=dir+'/out';
    put(src+'/bounds/header');put(src+'/flatbuffers/header');
    const llvm=out+'/third_party/llvm';
    for(const name of ['llvm-ar','llvm-ranlib','llvm-nm','wasm-ld'])put(llvm+'/bin/'+name);
    for(const rel of ['lldb/__init__.py','six.py'])put(llvm+'/lib/python3.11/site-packages/'+rel);
    put(work+'/compiler/third_party/cjnative-prefix/src/cjnative-build/CMakeCache.txt');

    // Skip downloading the pinned archives; the stage still constructs the real CMake command.
    const loader=dir+'/archives.mjs';
    const common=pathToFileURL(path.join(repo,'build/common.mjs')).href;
    put(dir+'/fixture-common.mjs',`export * from ${JSON.stringify(common)}; export const downloadFile=async()=>{};`);
    put(loader,`import {registerHooks} from 'node:module';
registerHooks({resolve(specifier,ctx,next){
  return next(specifier==='./common.mjs' && ctx.parentURL?.endsWith('/build/build-llvm.mjs')
    ? new URL('./fixture-common.mjs',import.meta.url).href : specifier,ctx);
}});`);
    const {child,calls}=darwinStage(dir,'build-llvm',['--platform',platform,'--sources',src,'--work',work,'--out',out],
      "if(cmd==='lipo')return {status:0,stdout:'arm64 x86_64'}; if(cmd.endsWith('/llvm-nm'))return {status:42};",
      {CMAKE_CXX_COMPILER_LAUNCHER:'sccache'},['--import',loader]);
    assert.equal(child.status,1);assert.match(child.stderr,/llvm-nm .* exited 42/);
    const configure=calls.find(c=>c.cmd==='cmake'),args=configure.args;
    assert.ok(configure.path.endsWith(':/opt/homebrew/opt/llvm@16/bin'));
    assert.ok(args.includes('-DCMAKE_CXX_COMPILER=/usr/bin/clang++'));
    const value=key=>args.find(a=>a.startsWith('-D'+key+'=')).slice(key.length+3);
    const wrapper=value('CMAKE_TOOLCHAIN_FILE'),intel=platform==='darwin-x64';
    if(intel){assert.equal(configure.arch,'x86_64');assert.equal(configure.processor,'x86_64');}
    if(intel)assert.deepEqual(fs.readFileSync(wrapper,'utf8').trimEnd().split('\n'),[
      'set(CMAKE_OSX_ARCHITECTURES "x86_64" CACHE STRING "" FORCE)',
      'include("'+src+'/compiler/cmake/darwin_x86_64_toolchain.cmake")','set(CMAKE_CROSSCOMPILING OFF)']);
    else assert.equal(wrapper,src+'/compiler/cmake/darwin_aarch64_toolchain.cmake');
    for(const key of ['CANGJIE_LLVM_BUILD_ARGS','CJCJ_LLDB_ARGS']){
      const childArgs=value(key).split(';');
      assert.ok(childArgs.includes('-DCMAKE_CXX_COMPILER_LAUNCHER=sccache'));
      for(const flag of ['-DCMAKE_OSX_ARCHITECTURES=x86_64','-DLLVM_HOST_TRIPLE=x86_64-apple-darwin',
        '-DLLVM_DEFAULT_TARGET_TRIPLE=x86_64-apple-darwin','-DCMAKE_SYSTEM_PROCESSOR=x86_64'])
        assert.equal(childArgs.includes(flag),intel,key+' '+flag);
    }
    const shim=calls.find(c=>c.cmd==='sccache').args,i=shim.indexOf('-arch');
    assert.equal(shim[0],'/usr/bin/clang++');assert.equal(i!==-1,intel);
    if(intel)assert.equal(shim[i+1],'x86_64');
    const slices=calls.filter(c=>c.cmd==='lipo').map(c=>c.args);
    assert.deepEqual(slices,intel?['../flatbuffers/bin/flatc','lib/libLLVM.dylib','lib/liblldb.dylib','bin/llc','lib/libxml2.dylib',
      'fixed-llc/cjselfhost_llvmshim.o'].map(rel=>['-archs',path.join(llvm,rel)]):[]);

  });
}

test('Rosetta is probed before the first Intel binary runs',{skip:process.platform==='win32'},t=>{
  for(const installed of [true,false]){
    const dir=fixture(t);
    const {child,calls}=darwinStage(dir,'setup',['deps','--platform','darwin-x64','--mode','prepare'],`
      if(cmd==='arch')return {status:${installed} || fs.existsSync('${dir}/installed')?0:1};
      if(cmd==='softwareupdate')fs.writeFileSync('${dir}/installed','');
      if(cmd==='brew')return {status:42};`);
    assert.match(child.stderr,/brew deps .* exited 42/);
    const probe=['arch','-x86_64','/usr/bin/true'];
    assert.deepEqual(calls.slice(0,-1).map(({cmd,args})=>[cmd,...args]),
      installed?[probe]:[probe,['softwareupdate','--install-rosetta','--agree-to-license'],probe]);
  }
});

test('cjbind uses Intel Python and checks the installed executable',{skip:process.platform==='win32'},t=>{
  for(const arch of ['x86_64','arm64']){
    const dir=fixture(t),out=dir+'/tools';
    put(out+'.src/target/release/bin/main');
    const {child,calls}=darwinStage(dir,'setup',['cjbind','--platform','darwin-x64','--host-sdk',dir+'/sdk','--out',out],
      `if(cmd==='lipo')return {status:0,stdout:'${arch}'};`);
    assert.equal(child.status,arch==='x86_64'?0:1,child.stderr);
    if(arch==='arm64')assert.match(child.stderr,/cjbind: expected only x86_64, got arm64/);
    const uv=calls.filter(c=>c.cmd==='uv');
    assert.deepEqual(uv.map(c=>c.args[3]),['python','./scripts/download.py','./scripts/cjpm.py']);
    for(const c of uv){
      assert.deepEqual(c.args.slice(0,3),['run','--python','cpython-3.13-macos-x86_64']);
      assert.ok(c.path.endsWith(':/opt/homebrew/opt/llvm@16/bin'));
    }
    assert.deepEqual(calls.at(-1).args,['-archs',out+'/cjbind']);
  }
});

test('Intel runtime stages boundscheck and loads both thin libraries',{skip:process.platform==='win32'},t=>{
  const dir=fixture(t),src=dir+'/sources',out=dir+'/runtime',tuple='darwin_x86_64_cjnative';
  const lib=out+'/runtime/lib/'+tuple;
  put(src+'/bounds/header');
  put(src+'/runtime/runtime/CMakebuild/runtime-staging/lib/x86_64_Release/libboundscheck.dylib','staged');
  put(lib+'/libcangjie-runtime.dylib');
  for(const name of ['libcangjie-thread.a','libcangjie-aio.a'])put(out+'/lib/'+tuple+'/'+name);
  const {child,calls}=darwinStage(dir,'build-runtime',['--platform','darwin-x64','--sources',src,'--out',out],`
    if(cmd==='lipo')return {status:0,stdout:'x86_64'};
    if(cmd==='xcrun')return {status:0,stdout:'/fixture/MacOSX.sdk'};`);
  assert.equal(child.status,0,child.stderr);
  const invocations=calls.filter(c=>c.args.includes('build.py'));
  assert.deepEqual(invocations.map(c=>[c.cmd,...c.args.slice(0,5)]),['build','install'].map(op=>
    ['arch','-x86_64','/usr/bin/python3','-I','build.py',op]));
  assert.deepEqual(invocations[0].args.slice(4,7),['build','--target','native']);
  assert.match(fs.readFileSync(out+'.work/runtime.cmake','utf8'),/^set\(CMAKE_OSX_ARCHITECTURES "x86_64" CACHE STRING "" FORCE\)$/m);
  for(const c of invocations){assert.equal(c.arch,'x86_64');assert.equal(c.processor,'x86_64');}
  assert.equal(fs.readFileSync(lib+'/libboundscheck.dylib','utf8'),'staged');
  assert.deepEqual(calls.filter(c=>c.cmd==='lipo').map(c=>c.args),[
    ['-archs',lib+'/libcangjie-runtime.dylib'],['-archs',lib+'/libboundscheck.dylib']]);
  const cc=calls.find(c=>c.cmd==='/usr/bin/clang++').args,i=cc.indexOf('-arch');
  assert.ok(i>=0);assert.equal(cc[i+1],'x86_64');
  assert.deepEqual(calls.filter(c=>c.cmd===out+'.work/load').map(c=>c.args),[
    [lib+'/libcangjie-runtime.dylib','CJ_MCC_HandleReturnSafepoint'],[lib+'/libboundscheck.dylib','memset_s']]);
});
