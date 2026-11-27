import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import test from 'node:test';
import {repo,RELEASE_TARGETS,parallelCompilerBudget,compilerStageBudget,homebrewPrefix,cleanSdkEnvironment,compilerHeap,loadPins,sdkPlatform} from '../../build/common.mjs';
import {cjpmBuildEnvironment,effectiveLinkOptions,h1HeapDefaultsBuild,h1PackageLinkOptions,wireAttributeHeader} from '../../build/build-compiler.mjs';

test('source pins use full commit SHAs and select the expected tools revision',()=>{
  const pins=loadPins();
  assert.equal(pins.repos.h1,undefined);
  assert.equal(Object.keys(pins.repos).length,9);
  for(const [name,pin] of Object.entries(pins.repos)){
    assert.match(pin.sha,/^[0-9a-f]{40}$/,name+' source SHA');
  }
  assert.equal(pins.repos.tools.sha,'30b72a46b25eb191877ca47ff91f9bfbe458166c');
});

test('source pins select the expected runtime revision',()=>{
  const pins=loadPins();
  assert.equal(pins.repos.runtime.sha,'9830715f11f510aec027a1ad51a4cab09480b76f');
});

test('source pins select Darwin cross stdx',()=>{
  assert.equal(loadPins().repos.stdx.sha,'7780ef7b507b411bdffeb66e84a66dd5d215006c');
});

test('source pins select the expected LLVM revision',()=>{
  const pins=loadPins();
  assert.equal(pins.repos.llvm.sha,'95bc92f8348f77236a5373817cc0e1b677fd3d08');
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

for(const workflow of ['prepare','release']){
  test(workflow+' builds final std with the native compiler headers',()=>{
    const yaml=fs.readFileSync(path.join(repo,'.github/workflows',workflow+'.yml'),'utf8');
    const commands=yaml.replace(/\\\r?\n\s*|\r?\n[ \t]+(?=--)/g,' ').split('\n');
    const stages=commands.filter(line=>/^\s*node build\/build-stdlib\.mjs\b/.test(line) && /--stage stage3-std\b/.test(line));
    assert.ok(stages.length>0,'missing stage3-std command');
    for(const command of stages){
      const includes=Array.from(command.matchAll(/(?:^|\s)--include(?:=|\s+)(\S+)/g),m=>m[1]);
      assert.deepEqual(includes,['../base/native/include']);
    }
  });
}

for(const workflow of ['prepare','release']){
  test(workflow+' builds extras with the native compiler headers',()=>{
    const yaml=fs.readFileSync(path.join(repo,'.github/workflows',workflow+'.yml'),'utf8');
    const commands=yaml.replace(/\\\r?\n\s*|\r?\n[ \t]+(?=--)/g,' ').split('\n');
    const extras=commands.filter(line=>/^\s*node build\/build-extras\.mjs\b/.test(line));
    assert.ok(extras.length>0,'missing extras command');
    for(const command of extras)assert.deepEqual(Array.from(command.matchAll(/(?:^|\s)--include(?:=|\s+)(\S+)/g),m=>m[1]),['../base/native/include']);
  });
}

for(const [workflow,jobs] of Object.entries({prepare:['ci-sdk'],ci:['build-and-smoke','package-tests'],release:['host-sdk','host-sdk-darwin-x64']})){
  test(workflow+' sets the compiler heap for each SDK job',()=>{
    const yaml=fs.readFileSync(path.join(repo,'.github/workflows',workflow+'.yml'),'utf8');
    const blocks=yaml.split(/^  (?=[\w-]+:[ \t]*$)/m);
    for(const job of jobs){
      const block=blocks.find(b=>b.startsWith(job+':\n'));
      assert.ok(block,job);
      const env=block.match(/^    env:\n((?:      .*\n)+)/m)?.[1]||'';
      assert.ok(env.split('\n').includes('      CJCJ_HEAP_SIZE: ${{ vars.cjHeapSize }}'),job);
    }
    assert.doesNotMatch(yaml,/^\s*cjHeapSize:/m);
    assert.doesNotMatch(yaml,/^\s*CJCJ_HEAP_SIZE:.*\b(?:6|12|16|20)GB\b/m);
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
function compilerFixture(t){
  const dir=fixture(t),src=dir+'/checkout',host=dir+'/host',native=dir+'/native',out=dir+'/stage0';
  const shim='runtime_shim/cjselfhost_llvmshim.o',selected=native+'/third_party/llvm/fixed-llc/cjselfhost_llvmshim.o';
  for(const file of ['.gitignore','cjpm.toml','cjpm.lock','packages/cjc/cjpm.toml','build/common.mjs',
    'packages/basic/src/Version.cj','schema/StdxChirFormat.fbs','packages/chir/src/Enums.cj',
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
  put(host+'/LICENSE');put(host+'/Open_Source_Software_Notice.docx');
  put(dir+'/std/lib/'+tuple+'/current');put(dir+'/std/runtime/lib/'+tuple+'/current');
  put(native+'/third_party/flatbuffers/bin/flatc','#!/bin/sh\nexit 0\n',0o755);
  return {dir,src,host,native,out,shim,selected,commit,exec};
}

test('stage0 leaves a clean checkout for the stage2 shim build',linux,t=>{
  const {dir,src,host,native,out,shim,selected,commit,exec}=compilerFixture(t);
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
  // Build stage2 with a version that differs from the tracked source.
  put(selected,'stage2 shim');
  put(host+'/tools/bin/cjpm',`#!/bin/sh
set -eu
grep -Fx 'public let CANGJIE_VERSION: String = "9.8.7"' packages/basic/src/Version.cj
mkdir -p "$3/release/bin"
echo stage2 > "$3/release/bin/cjc"
`,0o755);
  exec(process.execPath,['build/build-compiler.mjs','--stage','stage2','--sdk',out,'--native',native,
    '--std',dir+'/std','--host-sdk',host,'--version','9.8.7','--out',dir+'/stage2']);
  assert.equal(exec('git',['status','--porcelain']),'');
  assert.equal(fs.readFileSync(src+'/'+shim,'utf8'),'stage2 shim');
  const config=fs.readFileSync(src+'/runtime_shim/cjc_runtime_config.o','utf8');
  assert.match(config,new RegExp('-DCJCJ_COMMIT="'+commit+'"'));
  assert.ok(!config.includes('-DCJCJ_LEGACY_HOST_RUNTIME'));
  assert.ok(fs.readFileSync(src+'/runtime_shim/cjc_heap_defaults.o','utf8').includes(src+'/runtime_shim/cjc_heap_defaults.c'));
});

const cmcDefaults={cjRegionSize:'2048KB',cjExemptionThreshold:'1.0',cjGarbageThreshold:'0.1'};
test('stage2 resolves each CMC setting independently',()=>{
  const input={cjRegionSize:' 1024KB ',cjExemptionThreshold:' \t',PATH:'/bin'};
  assert.deepEqual(cjpmBuildEnvironment('stage2',input),{...cmcDefaults,cjRegionSize:'1024KB',PATH:'/bin'});
});

test('other compiler stages preserve the caller CMC environment',()=>{
  for(const stage of ['stage0','stage3','installed']){
    for(const env of [{},{cjRegionSize:'512KB',cjGarbageThreshold:'0.4'}])
      assert.deepEqual(cjpmBuildEnvironment(stage,{...env}),env,stage);
  }
});

test('build-compiler CLI passes CMC settings to cjpm build',linux,async t=>{
  const {dir,host,native,out,exec}=compilerFixture(t);
  const keys=Object.keys(cmcDefaults);
  const unset=Object.fromEntries(keys.map(k=>[k,undefined]));
  put(host+'/tools/bin/cjpm',`#!${process.execPath}
const fs=require('node:fs'),[cmd,flag,target]=process.argv.slice(2);
if(cmd!=='build'||flag!=='--target-dir')process.exit(1);
fs.mkdirSync(target+'/release/bin',{recursive:true});
fs.writeFileSync(target+'/release/bin/cjc','fixture');
fs.writeFileSync(target+'/cmc.json',JSON.stringify(Object.fromEntries(${JSON.stringify(keys)}.map(k=>[k,process.env[k]]))));
`,0o755);
  const overrides={cjRegionSize:'1024KB',cjExemptionThreshold:'0.9',cjGarbageThreshold:'0.2'};
  for(const [stage,label,input,expected] of [
    ['stage0','unset',{},{}],
    ['stage2','unset',{},cmcDefaults],
    ['stage2','explicit',Object.fromEntries(Object.entries(overrides).map(([k,v])=>[k,' '+v+' '])),overrides],
    ['stage2','blank',{cjRegionSize:' \t',cjExemptionThreshold:'',cjGarbageThreshold:'  '},cmcDefaults],
    ['stage3','unset',{},{}],
    ['installed','unset',{},{}],
  ]){
    await t.test(stage+' '+label,()=>{
      const dest=stage==='stage0'?out:dir+'/'+stage+'-'+label;
      exec(process.execPath,['build/build-compiler.mjs','--stage',stage,'--host-sdk',host,'--native',native,
        '--sdk',stage==='stage0'?host:out,'--std',dir+'/std','--out',dest],{...unset,...input});
      assert.deepEqual(JSON.parse(fs.readFileSync(dest+'.target/cmc.json','utf8')),expected);
    });
  }
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
      {GIT_DIR:git.stdout.trim(),cjHeapSize:stage==='stage2'?'':'4GB',CJCJ_HEAP_SIZE:'',cjHeapSwap:undefined,
        EXPECTED_HEAP:stage==='stage2'?compilerHeap(sdkPlatform(),{},os.totalmem(),true).cjHeapSize:'4GB'});
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

function stdlibFixture(t,tuple,suffix,withAst=false){
  const dir=fixture(t),src=dir+'/src',sdk=dir+'/sdk',rt=dir+'/R',out=dir+'/out';
  const lib='lib/'+tuple,run='runtime/'+lib,bounds='libboundscheck'+suffix;
  put(src+'/bounds/header');put(src+'/pcre2/header');put(rt+'/'+lib+'/rt.a');put(rt+'/'+run+'/'+bounds,'validated R');
  for(const rel of [lib+'/libcangjie-ast-support.a','schema/StdAstFormat.fbs','include/flatbuffers/StdAstFormat_generated.h',
    'third_party/flatbuffers/bin/flatc'+(suffix==='.dll'?'.exe':'')])put(sdk+'/'+rel,'native');
  const files=['modules/'+tuple+'/std/std.core.cjo','modules/'+tuple+'/std/libstd.core.bc',lib+'/libcangjie-std-core.a',
    run+'/libcangjie-std-core'+suffix,'lib/libstdFFI'+suffix,lib+'/'+bounds,run+'/'+bounds,lib+'/libcangjie-ast-support.a',
    'schema/old','include/old','third_party/flatbuffers/bin/old','third_party/python/old','third_party/flatbuffers/modules/current'];
  if(withAst)files.push('modules/'+tuple+'/std/std.ast.cjo');
  put(src+'/runtime/stdlib/build.py',`import json, os, pathlib, sys
with open('calls.jsonl','a') as f: print(json.dumps(sys.argv[1:]),file=f)
if sys.argv[1]=='build': pathlib.Path('build.heap').write_text(os.environ.get('cjHeapSize', ''))
if sys.argv[1]=='install':
 for rel in ${JSON.stringify(files)}:
  f=pathlib.Path(sys.argv[-1])/rel; f.parent.mkdir(exist_ok=True,parents=True); f.write_text('std')
`);
  return {dir,src,sdk,rt,out,lib,run,bounds};
}

for(const [platform,tuple,suffix] of [['linux-x64','linux_x86_64_cjnative','.so'],['windows-x64','windows_x86_64_cjnative','.dll'],['darwin-arm64','darwin_aarch64_cjnative','.dylib']]){
  test('stdlib preserves runtime bytes and native inputs: '+platform,linux,t=>{
    const {src,sdk,rt,out,lib,run,bounds}=stdlibFixture(t,tuple,suffix);
    cli('build-stdlib',['--stage','stage1-std','--platform',platform,'--sources',src,'--runtime',rt,'--sdk',sdk,'--out',out],
      {cjHeapSize:' ',CJCJ_HEAP_SIZE:''});
    assert.equal(fs.readFileSync(src+'/runtime/stdlib/build.heap','utf8'),compilerHeap(sdkPlatform(platform),{}).cjHeapSize);
    assert.equal(fs.readFileSync(out+'/'+run+'/'+bounds,'utf8'),'validated R',platform+' std overwrote R');
    assert.equal(fs.readFileSync(out+'/third_party/flatbuffers/modules/current','utf8'),'std');
    for(const f of [lib+'/libcangjie-ast-support.a','schema/old','include/old','third_party/flatbuffers/bin/old','third_party/python/old'])
      assert.equal(fs.existsSync(out+'/'+f),false,f);
    if(platform==='linux-x64')assert.equal(fs.readlinkSync(out+'/'+lib+'/'+bounds),'../../'+run+'/'+bounds,'relative boundscheck link');
    else assert.equal(fs.existsSync(out+'/'+lib+'/'+bounds),false);
  });
}

for(const kind of ['compiler','wire','missing']){
  test('final std --include: '+kind+' header',linux,t=>{
    const {dir,src,sdk,rt,out}=stdlibFixture(t,tuple,'.so',true);
    const include=dir+'/include',header=include+'/cangjie/CHIR/IR/AttributeInfo.h';
    if(kind==='compiler')put(header,'namespace Cangjie::CHIR { class AttributeInfo {}; }');
    if(kind==='wire')put(header,wireAttributeHeader(fs.readFileSync(path.join(repo,'packages/chir/src/Enums.cj'),'utf8')));
    const child=spawnSync(process.execPath,[path.join(repo,'build/build-stdlib.mjs'),'--stage','stage3-std',
      '--platform','linux-x64','--sources',src,'--sdk',sdk,'--runtime',rt,'--include','include','--out',out],
      {cwd:dir,encoding:'utf8'});
    const log=src+'/runtime/stdlib/calls.jsonl';
    if(kind==='compiler'){
      assert.equal(child.status,0,child.error?.message||child.stderr);
      const calls=fs.readFileSync(log,'utf8').trim().split('\n').map(JSON.parse);
      assert.deepEqual(calls.map(args=>args[0]),['clean','build','install']);
      assert.ok(calls[1].includes('--include='+include));
      assert.equal(fs.readFileSync(out+'/modules/'+tuple+'/std/std.ast.cjo','utf8'),'std');
    }else{
      assert.equal(fs.existsSync(log),false,'invalid header reached build.py');
      assert.equal(child.status,1,child.error?.message||child.stderr);
      assert.ok(child.stderr.includes(header),child.stderr);
      assert.match(child.stderr,kind==='wire'?/defining class AttributeInfo/:/ENOENT/);
    }
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

test('default compiler heap stays below runner RAM and within runtime limits',()=>{
  for(const [platform,gib,mb] of [
    ['darwin-arm64',7,6737], ['darwin-x64',14,13475], ['linux-x64',15.6,15015],
    ['windows-x64',16,15360], ['linux-aarch64',64,49152], ['linux-x64',24,19660],
  ]){
    const p=sdkPlatform(platform),bytes=Math.floor(gib*1024**3);
    const heap=compilerHeap(p,{},bytes);
    assert.deepEqual(heap,{cjHeapSize:`${mb}MB`,...(p.os==='linux'?{cjHeapSwap:'on'}:{})},platform);
    assert.ok(parseInt(heap.cjHeapSize,10)*1024**2<bytes,platform);
  }
  assert.equal(compilerHeap(sdkPlatform('linux-x64'),{},4*1024**2).cjHeapSize,'4MB');
});

test('SDK environments resolve overrides and replace blank runtime heap settings',()=>{
  const p=sdkPlatform('linux-x64');
  for(const blank of ['', '  ']){
    const env=cleanSdkEnvironment('/sdk',p.key,{cjHeapSize:blank,CJCJ_HEAP_SIZE:'',cjHeapSwap:blank});
    assert.equal(env.cjHeapSize,compilerHeap(p,{}).cjHeapSize);
    assert.equal(env.cjHeapSwap,'on');
  }
  for(const platform of ['linux-x64','linux-aarch64','darwin-arm64','darwin-x64','windows-x64']){
    const host=sdkPlatform(platform);
    assert.equal(compilerHeap(host,{cjHeapSize:'',CJCJ_HEAP_SIZE:' 5GB '}).cjHeapSize,'5GB');
    assert.equal(compilerHeap(host,{cjHeapSize:' 4GB ',CJCJ_HEAP_SIZE:'5GB'}).cjHeapSize,'4GB');
  }
  assert.equal(compilerHeap(p,{cjHeapSwap:' off '}).cjHeapSwap,'off');
});

function stdxStage(t,kind='compiler',env={}){
  const dir=fixture(t),src=dir+'/src',sdk=dir+'/sdk',host=dir+'/bootstrap',include=dir+'/native/include';
  const rel='/cangjie/CHIR/IR/AttributeInfo.h',wire=wireAttributeHeader(fs.readFileSync(path.join(repo,'packages/chir/src/Enums.cj'),'utf8'));
  put(sdk+'/include'+rel,wire);
  if(kind==='compiler')put(include+rel,'class AttributeInfo {};');
  if(kind==='wire')put(include+rel,wire);
  if(kind==='declaration')put(include+rel,'/* class AttributeInfo {} */\nclass AttributeInfo;');
  for(const home of [sdk,host])put(home+'/bin/cjc','',0o755);
  put(src+'/compiler/utils/envsetup/llvm_linux.sh');
  put(src+'/stdx/build.py',`import json, os, shutil, sys
with open('calls.jsonl','a') as f:
 print(json.dumps(dict(args=sys.argv[1:], home=os.environ['STDX_HOST_CANGJIE_HOME'], cjc=shutil.which('cjc'), heap=os.environ['cjHeapSize'])),file=f)
`);
  const args=['--platform','linux-x64','--sdk',sdk,'--host-sdk',host,'--sources',src,'--only','stdx'];
  if(kind!=='omitted')args.push('--include','native/include');
  const child=spawnSync(process.execPath,[path.join(repo,'build/build-extras.mjs'),...args],{cwd:dir,env:{...process.env,...env},encoding:'utf8'});
  const log=src+'/stdx/calls.jsonl',calls=fs.existsSync(log)?fs.readFileSync(log,'utf8').trimEnd().split('\n').map(JSON.parse):[];
  return {sdk,include,wire,rel,child,calls};
}

test('stdx macro host matches the cjc selected on PATH',linux,t=>{
  const {sdk,child,calls}=stdxStage(t);
  assert.equal(child.status,0,child.stderr);
  const build=calls.find(c=>c.args[0]==='build');
  assert.equal(build.cjc,sdk+'/bin/cjc');
  assert.equal(build.home,sdk);
});

test('stdx build receives the native include and preserves the SDK wire header',linux,t=>{
  const {sdk,include,wire,rel,child,calls}=stdxStage(t);
  assert.equal(child.status,0,child.stderr);
  assert.deepEqual(calls.map(c=>c.args[0]),['clean','build','install']);
  assert.deepEqual(calls[1].args.filter(arg=>arg.startsWith('--include=')),['--include='+include]);
  assert.equal(fs.readFileSync(sdk+'/include'+rel,'utf8'),wire);
});

test('stdx rejects unusable compiler headers before clean',linux,t=>{
  for(const kind of ['omitted','missing','wire','declaration']){
    const {child,calls,include,rel}=stdxStage(t,kind);
    assert.deepEqual(calls,[],kind+' reached build.py');
    assert.equal(child.status,1,child.stderr);
    assert.match(child.stderr,kind==='omitted'?/--include requires a compiler include directory/:kind==='missing'?/ENOENT/:/defining class AttributeInfo/);
    if(kind!=='omitted')assert.ok(child.stderr.includes(include+rel),child.stderr);
  }
});

function stdxBuildHeap(t,env){
  const {child,calls}=stdxStage(t,'compiler',env);
  assert.equal(child.status,0,child.stderr);
  return calls.find(c=>c.args[0]==='build').heap;
}

test('extras passes the repository heap override to the stdx build',linux,t=>{
  assert.equal(stdxBuildHeap(t,{cjHeapSize:'',CJCJ_HEAP_SIZE:'5GB'}),'5GB');
});

test('whitespace-only cjHeapSize preserves the trimmed repository override in stdx',linux,t=>{
  assert.equal(stdxBuildHeap(t,{cjHeapSize:'  ',CJCJ_HEAP_SIZE:' 5GB '}),'5GB');
});

// Drive the tools-only CLI and record its child commands for each LSP host.
// Stand in for git, npm and tools/build.mjs; the stage copies real fixture outputs.
for(const platform of ['linux-x64','windows-x64']){
  test('tools-only LSP selects the stdx JSON layout for '+platform,linux,t=>{
    const dir=fixture(t),src=dir+'/src',sdk=dir+'/sdk',host=dir+'/bootstrap',p=sdkPlatform(platform);
    const windows=p.os==='win32',tools=src+'/tools',log=dir+'/tools.jsonl',preload=dir+'/children.mjs';
    for(const ext of windows?['sh','bat','ps1']:['sh'])put(src+'/compiler/utils/envsetup/llvm_'+(windows?'windows_x86_64':'linux')+'.'+ext);
    put(tools+'/packages/hle/src/dtsparser/package.json','{}');put(dir+'/cjbind');put(dir+'/lombok.jar');
    put(preload,`import fs from 'node:fs';
import cp from 'node:child_process';
cp.spawnSync=(cmd,args)=>{
  if(cmd==='git')return {status:0,stdout:'fixture-ref'};
  if(cmd==='npm'||args[0].endsWith('/npm-cli.js'))return {status:0};
  if(cmd!==process.execPath||args[0]!==${JSON.stringify(tools)}+'/build.mjs')throw Error('unexpected command: '+cmd+' '+args);
  const tool=args[args.indexOf('--tool')+1];
  if(args[1]==='build')fs.appendFileSync(${JSON.stringify(log)},JSON.stringify({tool,args})+'\\n');
  if(args[1]==='install'){
    const bin=args[args.indexOf('--prefix')+1]+'/bin';
    fs.mkdirSync(bin,{recursive:true});fs.writeFileSync(bin+'/'+(tool==='lsp'?'cangjie-lsp':tool)+${JSON.stringify(p.exe)},'');
  }
  return {status:0};
};`);
    cli('build-extras',['--platform',platform,'--only','tools','--sdk',sdk,'--host-sdk',host,'--sources',src,
      '--lombok',dir+'/lombok.jar','--cjbind',dir+'/cjbind'],{JAVA_HOME:dir+'/jdk'},['--import',preload]);
    const calls=fs.readFileSync(log,'utf8').trimEnd().split('\n').map(JSON.parse);
    function option(tool,key){
      const {args}=calls.find(c=>c.tool===tool),i=args.indexOf(key);
      assert.notEqual(i,-1,tool+' '+key);return args[i+1];
    }
    assert.equal(option('lsp','--json-build'),windows?sdk+'/stdx':src+'/stdx/build_temp/build');
    assert.equal(option('lsp','--cjpm'),host+'/tools/bin/cjpm'+p.exe);
    for(const tool of ['cjfmt','cjlint'])assert.equal(option(tool,'--cjpm-sdk'),host);
  });
}

test('Linux full dependencies install patchelf for cjlint',linux,t=>{
  const dir=fixture(t),log=dir+'/sudo.jsonl';
  put(dir+'/sudo',`#!${process.execPath}
require('node:fs').appendFileSync(${JSON.stringify(log)},JSON.stringify(process.argv.slice(2))+'\\n');
`,0o755);
  for(const mode of ['full','prepare']){
    put(log);
    cli('setup',['deps','--platform','linux-x64','--mode',mode],{PATH:dir});
    const calls=fs.readFileSync(log,'utf8').trimEnd().split('\n').map(JSON.parse);
    const install=calls.find(args=>args.includes('apt-get')&&args.includes('install'));
    assert.ok(install?.includes('cmake'),mode+' apt-get install');
    assert.equal(install.includes('patchelf'),mode==='full',mode+' patchelf');
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
function darwinStage(dir,name,args,respond,extra={},options=[],arch='arm64'){
  const preload=dir+'/host.mjs',log=dir+'/calls';
  put(preload,`
import fs from 'node:fs';
import cp from 'node:child_process';
const exists=fs.existsSync;
fs.existsSync=file=>file==='/opt/homebrew/bin/brew'||exists(file);
Object.defineProperty(process,'arch',{value:${JSON.stringify(arch)}});
Object.defineProperty(process,'platform',{value:'darwin'});
cp.spawnSync=(cmd,args,opts)=>{
  const env=opts?.env??process.env;
  fs.appendFileSync(${JSON.stringify(log)},JSON.stringify({cmd,args,path:env.PATH,home:env.CANGJIE_HOME,host:env.STDX_HOST_CANGJIE_HOME,heap:env.cjHeapSize,jobs:env.CANGJIE_BUILD_JOBS,targetArch:env.CJCJ_TARGET_ARCH,arch:env.CMAKE_OSX_ARCHITECTURES,processor:env.CMAKE_APPLE_SILICON_PROCESSOR})+'\\n');
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

// Expectations from the pinned compiler toolchains and runtime/stdlib/build.py.
const crossRows=[
  ['android-aarch64','linux_android_aarch64_cjnative','aarch64-linux-android23','android_aarch64'],
  ['ohos-aarch64','linux_ohos_aarch64_cjnative','aarch64-linux-ohos','ohos_aarch64_clang'],
  ['ohos-x86_64','linux_ohos_x86_64_cjnative','x86_64-linux-ohos','ohos_x86_64_clang'],
  ['ios-aarch64','ios_aarch64_cjnative','arm64-apple-ios11','ios_arm64'],
  ['ios-simulator-aarch64','ios_simulator_aarch64_cjnative','arm64-apple-ios11-simulator','ios_simulator_arm64'],
  ['ios-simulator-x86_64','ios_simulator_x86_64_cjnative','x86_64-apple-ios11-simulator','ios_simulator_x86_64'],
];
function releaseJobs(){
  const result=spawnSync('/usr/bin/python3',['-c','import json,sys,yaml; print(json.dumps(yaml.safe_load(sys.stdin)["jobs"]))'],
    {input:fs.readFileSync(path.join(repo,'.github/workflows/release.yml')),encoding:'utf8'});
  assert.equal(result.status,0,result.stderr);return JSON.parse(result.stdout);
}

test('release produces exactly one overlay for every package dependency',linux,()=>{
  const workflow=releaseJobs(),{'host-sdk':host,'cross-std':cross,package:pkg}=workflow;
  assert.deepEqual(pkg.needs.sort(),['cross-std','host-sdk','host-sdk-darwin-x64']);
  assert.match(pkg.strategy.matrix,/fromJSON\(needs\.host-sdk\.outputs\.packages\)/);
  assert.match(host.steps.find(s=>s.id==='matrix').run,/RELEASE_TARGETS as include/);
  assert.deepEqual(cross.strategy.matrix.include.map(r=>r.target).sort(),[...crossRows.map(([t])=>t),'wasm32-wasi'].sort());
  const hosts=host.strategy.matrix.include.map(r=>r.platform);
  const producers=[];
  for(const platform of ['windows-x64','linux-x64']){
    const condition="matrix.platform == '"+platform+"'";
    const upload=host.steps.find(s=>s.with?.name==='cross-std-'+platform);
    assert.equal(upload?.if,condition);assert.match(upload.uses,/actions\/upload-artifact@/);
    const flag=platform==='windows-x64'?'--windows-overlay':'--linux-overlay';
    const pack=host.steps.find(s=>s.run?.includes(flag));
    assert.equal(pack?.if,condition);
    assert.equal(pack.run,'node build/setup.mjs pack '+flag+' --archive '+upload.with.path+' --dir ../host-sdk');
    assert.equal(upload.with.path,'cross.tar');assert.ok(hosts.includes(platform));
    producers.push(platform);
  }
  const upload=cross.steps.find(s=>s.with?.name==='cross-std-${{ matrix.target }}');
  assert.match(upload.uses,/actions\/upload-artifact@/);assert.equal(upload.with.path,'cross.tar');
  for(const {target,host:platform} of cross.strategy.matrix.include){assert.ok(hosts.includes(platform));producers.push(target);}
  const expected={
    'linux-x64':['windows-x64'],'linux-arm64':['windows-x64'],'win32-x64':[],'darwin-arm64':[],'darwin-x64':[],
    'linux-x64-android':['android-aarch64'],'darwin-arm64-android':['android-aarch64'],'win32-x64-android':['android-aarch64','linux-x64'],
    'linux-x64-wasm':['wasm32-wasi'],'darwin-arm64-wasm':['wasm32-wasi'],'win32-x64-wasm':['wasm32-wasi'],
    'linux-x64-ohos':['ohos-aarch64','ohos-x86_64','windows-x64'],'darwin-arm64-ohos':['ohos-aarch64'],
    'win32-x64-ohos':['ohos-aarch64','ohos-x86_64'],'darwin-arm64-ios':['ios-aarch64','ios-simulator-aarch64','ios-simulator-x86_64'],
  };
  assert.deepEqual(RELEASE_TARGETS.map(p=>p.key).sort(),Object.keys(expected).sort());
  assert.deepEqual([...new Set(Object.values(expected).flat())].sort(),producers.sort());
  for(const p of RELEASE_TARGETS){assert.ok(hosts.includes(p.host)||workflow['host-sdk-'+p.host]?.steps.some(s=>s.with?.name==='host-sdk-'+p.host&&s.uses?.includes('upload-artifact')),p.key);assert.deepEqual(p.cross,expected[p.key],p.key);}
  assert.equal(pkg.env.CROSS,'${{ toJSON(matrix.cross) }}');
  const download=pkg.steps.find(s=>s.run?.includes('JSON.parse(process.env.CROSS)'));
  assert.match(download.run,/'--name','cross-std-'\+target/);assert.match(download.run,/dir\+'\/cross\.tar'/);
});

test('release fetches and passes cross compiler inputs only for native std targets',linux,t=>{
  const dir=fixture(t),steps=releaseJobs()['cross-std'].steps,cwd=dir+'/checkout';
  fs.mkdirSync(cwd);put(dir+'/stage2/llvm.ref','selected-llvm');put(dir+'/stage2/runtime.ref','selected-runtime');
  const script=steps.filter(s=>s.run?.includes('build/setup.mjs sources')||s.run?.includes('build/build-stdlib.mjs')).map(s=>s.run).join('\n');
  // Execute the actual bash branches; intercept only the external producers.
  for(const target of [...crossRows.map(([t])=>t),'wasm32-wasi']){
    const result=spawnSync('bash',['-eu','-c',`node(){ printf '%s\\037' "$@"; printf '\\n'; }\n`+script],{cwd,env:{...process.env,TARGET:target},encoding:'utf8'});
    assert.equal(result.status,0,result.stderr);
    const calls=result.stdout.trimEnd().split('\n').map(line=>line.split('\x1f').slice(0,-1));
    const sources=calls.find(c=>c[1]==='sources'),build=calls.find(c=>c[0]==='build/build-stdlib.mjs'),native=target!=='wasm32-wasi';
    assert.deepEqual(sources[sources.indexOf('--repos')+1].split(',').sort(),
      ['runtime','bounds','pcre2',...(native?['compiler','llvm','flatbuffers']:[])].sort());
    assert.deepEqual(sources.flatMap((v,i)=>v==='--override'?[sources[i+1]]:[]),['runtime=selected-runtime',...(native?['llvm=selected-llvm']:[])]);
    assert.deepEqual(build.flatMap((v,i)=>v==='--include'?[build[i+1]]:[]),native?['../src/compiler/include']:[]);
    assert.deepEqual(calls.find(c=>c[1]==='pack'),['build/setup.mjs','pack','--dereference','--archive','cross.tar','--dir','../cross']);
  }
});

test('Windows overlay contains only physical tuple files and both root FFI libraries',linux,t=>{
  const root=fixture(t),sdk=root+'/sdk',out=root+'/unpacked',tuple='windows_x86_64_cjnative';
  const files=['modules/'+tuple+'/std/std.core.cjo','runtime/lib/'+tuple+'/runtime.dll','lib/'+tuple+'/std.a','lib/libstdFFI.dll','lib/libstdFFI.dll.a'];
  for(const rel of files){put(sdk+'/private/'+path.basename(rel),rel);fs.mkdirSync(path.dirname(sdk+'/'+rel),{recursive:true});
    fs.symlinkSync(path.relative(path.dirname(sdk+'/'+rel),sdk+'/private/'+path.basename(rel)),sdk+'/'+rel);}
  put(sdk+'/lib/unrelated');put(sdk+'/modules/other/mod');
  cli('setup',['pack','--windows-overlay','--archive',root+'/cross.tar','--dir',sdk]);
  cli('setup',['unpack','--archive',root+'/cross.tar','--dir',out]);
  const entries=fs.readdirSync(out,{recursive:true}).filter(f=>!fs.lstatSync(path.join(out,f)).isDirectory());
  assert.deepEqual(entries.sort(),files.sort());
  for(const rel of files){assert.ok(fs.lstatSync(out+'/'+rel).isFile(),rel);assert.equal(fs.readFileSync(out+'/'+rel,'utf8'),rel);}
});

test('cross tar materializes chained pcre2 links only when dereference is selected',linux,t=>{
  const root=fixture(t),sdk=root+'/sdk';put(sdk+'/libpcre2-8.so.0.12','target bytes');
  fs.symlinkSync('libpcre2-8.so.0.12',sdk+'/libpcre2-8.so.0');fs.symlinkSync('libpcre2-8.so.0',sdk+'/libpcre2-8.so');
  for(const follow of [false,true]){
    const out=root+'/out-'+follow,archive=out+'.tar';
    cli('setup',['pack',...(follow?['--dereference']:[]),'--archive',archive,'--dir',sdk]);
    cli('setup',['unpack','--archive',archive,'--dir',out]);
    for(const name of ['libpcre2-8.so','libpcre2-8.so.0']){
      assert.equal(fs.lstatSync(out+'/'+name).isSymbolicLink(),!follow);assert.equal(fs.readFileSync(out+'/'+name,'utf8'),'target bytes');
    }
  }
});

const wireHeader=()=>wireAttributeHeader(fs.readFileSync(path.join(repo,'packages/chir/src/Enums.cj'),'utf8'));
function crossStage(t,row,{header='compiler',withAst=true}={}){
  const [target,tuple,triple,name]=row,ios=target.startsWith('ios-'),android=target.startsWith('android-');
  const {dir,src,sdk,rt,out}=stdlibFixture(t,tuple,ios?'.dylib':'.so',withAst);
  const include=src+'/compiler/include',rel='/cangjie/CHIR/IR/AttributeInfo.h';
  if(header==='compiler')put(include+rel,'namespace Cangjie::CHIR { class AttributeInfo {}; }');
  if(header==='wire')put(include+rel,wireHeader());
  put(sdk+'/include'+rel,wireHeader());
  const bin=dir+'/bin',ndk=dir+'/NDK',ohos=dir+'/Harmony SDK',xcode=dir+'/Xcode Toolchain';
  const pre=ndk+'/toolchains/llvm/prebuilt/linux-x86_64';
  const tool=ios?xcode+'/bin':android?pre+'/bin':ohos+'/native/llvm/bin';
  const id=target.includes('simulator')?'iphonesimulator':'iphoneos';
  const sysroot=ios?dir+'/SDKs/'+id+'.sdk':android?pre+'/sysroot':ohos+'/native/sysroot';
  const resource=dir+'/clang resource/21';
  put(bin+'/xcrun',`#!/bin/sh
set -eu
case "$3" in
--show-sdk-path) echo "$FIXTURE/SDKs/$2.sdk";;
--find) echo "$FIXTURE/Xcode Toolchain/bin/$4";;
*) exit 3;;
esac\n`,0o755);
  put(tool+'/clang','#!/bin/sh\n[ "$1" = -print-resource-dir ] && echo "$RESOURCE"\n',0o755);
  // Run CMake and Ninja without target compilers. Each toolchain selects a
  // distinct install tuple. Capture effective variables after toolchain inclusion.
  const original=src+'/compiler/cmake/'+name+'_toolchain.cmake';
  put(original,`set(tuple ${tuple})\n`+(ios?'set(CMAKE_IOS_SDK_ROOT /old/17.5.sdk)\nset(CMAKE_OSX_SYSROOT /old/17.5.sdk)\n':''));
  const keys=['tuple','CMAKE_IOS_SDK_ROOT','CMAKE_OSX_SYSROOT','CMAKE_OSX_ARCHITECTURES','CMAKE_C_COMPILER','CMAKE_CXX_COMPILER',
    'CMAKE_AR','CMAKE_RANLIB','CANGJIE_TARGET_TOOLCHAIN','CANGJIE_TARGET_SYSROOT','CMAKE_C_COMPILER_TARGET','CMAKE_CXX_COMPILER_TARGET',
    'CMAKE_TRY_COMPILE_PLATFORM_VARIABLES','CMAKE_ANDROID_NDK','CMAKE_ANDROID_API','CANGJIE_CJNATIVE_SOURCE_DIR','FLATBUFFERS_BUILD_FLATC'];
  const project='cmake_minimum_required(VERSION 3.16)\nproject(fixture LANGUAGES NONE)\n'+
    'file(WRITE ${CMAKE_BINARY_DIR}/effective "'+keys.map(k=>k+'=${'+k+'}\\n').join('')+'hostSDK=$ENV{SDKROOT}\\n")\n';
  put(src+'/compiler/CMakeLists.txt',project+'add_subdirectory(src)\n');
  put(src+'/flatbuffers/CMakeLists.txt',project);
  put(src+'/compiler/src/CMakeLists.txt',`add_custom_target(boundscheck COMMAND "\${CMAKE_COMMAND}" -E touch bounds.shared)
add_custom_target(boundscheck-static COMMAND "\${CMAKE_COMMAND}" -E touch bounds.static)
add_custom_target(cangjie-ast-support COMMAND "\${CMAKE_COMMAND}" -E copy "\${CMAKE_CURRENT_SOURCE_DIR}/marker" libcangjie-ast-support.a)
install(FILES "\${CMAKE_CURRENT_BINARY_DIR}/libcangjie-ast-support.a" DESTINATION lib/\${tuple})\n`);
  put(src+'/compiler/src/marker','AST '+target);
  const stdlib=src+'/runtime/stdlib',link=out+'.work/sdk/modules/'+tuple;
  fs.appendFileSync(stdlib+'/build.py',`if sys.argv[1]=='build':
 link=pathlib.Path(os.environ['CANGJIE_HOME'])/'modules'/'${tuple}'
 pathlib.Path('module-path').write_text(str(link.resolve()) if link.is_dir() and link.is_symlink() else 'missing')
`);
  const args=['--platform',ios?'darwin-arm64':'linux-x64','--cross',target,'--sources',src,'--runtime',rt,'--sdk',sdk,'--out',out];
  if(header!=='omitted')args.push('--include','src/compiler/include');
  const child=spawnSync(process.execPath,[path.join(repo,'build/build-stdlib.mjs'),...args],{cwd:dir,encoding:'utf8',
    env:{...process.env,PATH:bin+':'+process.env.PATH,FIXTURE:dir,RESOURCE:resource,ANDROID_NDK_ROOT:ndk,OHOS_SDK_HOME:ohos,
      SDKROOT:'/inherited-sdk',CMAKE_TOOLCHAIN_FILE:'/inherited-toolchain'}});
  const log=stdlib+'/calls.jsonl',calls=fs.existsSync(log)?fs.readFileSync(log,'utf8').trim().split('\n').map(JSON.parse):[];
  return {child,calls,stdlib,out,sdk,include,tool,sysroot,resource,ndk,ios,android,link};
}

test('six cross targets reject omitted, missing and wire compiler headers before clean',linux,t=>{
  for(const row of crossRows)for(const header of ['omitted','missing','wire']){
    const {child,calls}=crossStage(t,row,{header});
    assert.deepEqual(calls,[],row[0]+' '+header+' reached build.py');
    assert.equal(child.status,1,child.stderr);
    assert.match(child.stderr,header==='omitted'?/--include requires a compiler include directory/:
      header==='missing'?/ENOENT.*AttributeInfo\.h/:/defining class AttributeInfo/);
  }
});

for(const row of crossRows){
  const [target,tuple,triple]=row;
  test('cross std builds and installs the selected target: '+target,linux,t=>{
    const {child,calls,stdlib,out,sdk,include,tool,sysroot,resource,ndk,ios,android,link}=crossStage(t,row);
    assert.equal(child.status,0,child.stderr+child.stdout);
    assert.deepEqual(calls.map(args=>args[0]),['clean','build','install']);
    const build=calls[1];
    assert.deepEqual(build.filter(v=>v.startsWith('--include=')),['--include='+include]);
    for(const [arg,value] of [['--target',target],['--target-toolchain',tool],['--target-sysroot',sysroot]])assert.equal(build[build.indexOf(arg)+1],value);
    const libs=build.filter(v=>v.startsWith('--target-lib=')).map(v=>v.slice(13));
    const rt=path.dirname(sdk)+'/R',source=path.dirname(include)+'/..';
    assert.deepEqual(libs,[path.resolve(source,'runtime/runtime/output'),rt+'/lib/'+tuple,rt+'/runtime/lib/'+tuple,
      ...(ios?[resource+'/lib/darwin']:android?[]:[resource+'/lib/'+triple,path.dirname(tool)+'/lib/'+triple])]);
    const moduleDir=stdlib+'/build/build-libs-'+triple+'/modules/'+tuple;
    assert.equal(fs.readFileSync(stdlib+'/module-path','utf8'),moduleDir);assert.equal(fs.realpathSync(link),moduleDir);
    for(const root of [out+'.work/sdk',out])assert.equal(fs.readFileSync(root+'/lib/'+tuple+'/libcangjie-ast-support.a','utf8'),'AST '+target);
    assert.equal(fs.readFileSync(out+'/modules/'+tuple+'/std/std.ast.cjo','utf8'),'std');
    assert.equal(fs.readFileSync(sdk+'/include/cangjie/CHIR/IR/AttributeInfo.h','utf8'),wireHeader());
    const ast=out+'.work/ast.build';
    for(const marker of ['bounds.shared','bounds.static'])assert.ok(fs.statSync(ast+'/src/'+marker).isFile());
    for(const loc of [ast,ast+'/third_party/flatbuffers-prefix/src/flatbuffers-build']){
      const defs=Object.fromEntries(fs.readFileSync(loc+'/effective','utf8').trimEnd().split('\n').map(line=>line.split('=')));
      const expected={tuple,CMAKE_C_COMPILER:tool+'/clang',CMAKE_CXX_COMPILER:tool+'/clang++',CMAKE_AR:tool+(ios?'/ar':'/llvm-ar'),
        CMAKE_RANLIB:tool+(ios?'/ranlib':'/llvm-ranlib'),CANGJIE_TARGET_TOOLCHAIN:tool,CANGJIE_TARGET_SYSROOT:sysroot,hostSDK:''};
      if(ios)Object.assign(expected,{CMAKE_IOS_SDK_ROOT:sysroot,CMAKE_OSX_SYSROOT:sysroot,CMAKE_OSX_ARCHITECTURES:triple.split('-')[0]});
      if(android)Object.assign(expected,{CMAKE_ANDROID_API:'23',CMAKE_ANDROID_NDK:ndk});
      else Object.assign(expected,{CMAKE_C_COMPILER_TARGET:triple,CMAKE_CXX_COMPILER_TARGET:triple});
      for(const [k,v] of Object.entries(expected))assert.equal(defs[k],v,k+' @ '+loc);
      assert.equal(loc===ast?defs.CANGJIE_CJNATIVE_SOURCE_DIR:defs.FLATBUFFERS_BUILD_FLATC,loc===ast?path.resolve(source,'llvm'):'OFF');
      for(const k of ['CANGJIE_TARGET_TOOLCHAIN','CANGJIE_TARGET_SYSROOT',...(android?['CMAKE_ANDROID_NDK','CMAKE_ANDROID_API']:[])])
        assert.ok(defs.CMAKE_TRY_COMPILE_PLATFORM_VARIABLES.split(';').includes(k),k+' in compiler probes');
    }
  });
}
test('cross install rejects a missing std.ast module for each native target',linux,t=>{
  for(const row of crossRows){
    const {child,calls}=crossStage(t,row,{withAst:false});
    assert.deepEqual(calls.map(args=>args[0]),['clean','build','install']);assert.equal(child.status,1,child.stderr);
    assert.match(child.stderr,/ENOENT.*std\.ast\.cjo/);
  }
});

test('WASI builds std.core without compiler sources or an include argument',linux,t=>{
  const dir=fixture(t),src=dir+'/src',sdk=dir+'/sdk',rt=dir+'/rt',out=dir+'/out',tuple='wasi_wasm32_cjnative';
  const core=src+'/runtime/stdlib/libs/std/core',bin=sdk+'/third_party/llvm/bin';
  put(core+'/core.cj','package std.core');put(core+'/native/typetemplate.c');
  put(core+'/native/CMakeLists.txt','--redefine-sym ${SYM_PREFIX}Old=${SYM_PREFIX}New');
  put(src+'/bounds/include/b.h');put(src+'/bounds/src/b.c');put(src+'/pcre2/p.h');
  put(dir+'/sysroot/marker');put(rt+'/runtime/lib/'+tuple+'/libcangjie-runtime.a','runtime');
  put(sdk+'/bin/cjc','#!/bin/sh\nfor a do case "$a" in --output=*) f=${a#*=}; echo core > "$f"; echo mod > "$f.cjo"; exit 0;; esac; done; exit 1\n',0o755);
  put(bin+'/clang','#!/bin/sh\nwhile [ "$1" != -o ]; do shift; done; echo @Old > "$2"\n',0o755);
  put(bin+'/llvm-ar','#!/bin/sh\ntest -s "$2"\n',0o755);
  cli('build-stdlib',['--cross','wasm32-wasi','--sources',src,'--runtime',rt,'--sdk',sdk,'--out',out],{CJCJ_WASI_SYSROOT:dir+'/sysroot'});
  assert.equal(fs.readFileSync(out+'/modules/'+tuple+'/std/std.core.cjo','utf8'),'mod\n');
  assert.match(fs.readFileSync(out+'/lib/'+tuple+'/wasm-toolchain.id','utf8'),/^cjw2-[0-9a-f]{32}\n$/);
});

test('Homebrew follows the installed brew under x64 Node',t=>{
  const exists=fs.existsSync;
  t.mock.method(fs,'existsSync',file=>file==='/opt/homebrew/bin/brew'||exists(file));
  const arch=Object.getOwnPropertyDescriptor(process,'arch');
  try {
    Object.defineProperty(process,'arch',{value:'x64'});
    assert.equal(homebrewPrefix(),'/opt/homebrew');
    fs.existsSync.mock.mockImplementation(()=>false);
    assert.equal(homebrewPrefix(),'/usr/local');
  }finally{Object.defineProperty(process,'arch',arch);}
});

test('compiler budgets divide the host memory across active processes',()=>{
  const p=sdkPlatform('linux-x64'),GiB=1024**3;
  for(const [gib,cpus,jobs,mb,largeJobs,largeMb] of [
    [7,3,2,2688,1,6737],[16,4,3,4096,1,15360],[128,32,24,4096,8,12288]
  ]){
    const mem=gib*GiB;
    assert.deepEqual(parallelCompilerBudget(p,cpus,{},mem),{jobs:String(jobs),cjHeapSize:mb+'MB'});
    assert.deepEqual(compilerStageBudget('stage3',p,undefined,{},mem,cpus),{jobs:String(largeJobs),cjHeapSize:largeMb+'MB'});
    for(const stage of ['stage0','stage2'])assert.deepEqual(compilerStageBudget(stage,p,undefined,{},mem,cpus),
      {jobs:String(cpus),cjHeapSize:(gib===7?6737:15360)+'MB'});
  }
  const mem=16*GiB;
  for(const key of ['cjHeapSize','CJCJ_HEAP_SIZE']){
    assert.deepEqual(parallelCompilerBudget(p,4,{[key]:' 6GB '},mem),{jobs:'4',cjHeapSize:'6GB'});
    assert.deepEqual(compilerStageBudget('stage3',p,'2',{[key]:'6GB'},mem,4),{jobs:'2',cjHeapSize:'6GB'});
  }
  assert.deepEqual(parallelCompilerBudget(p,4,{},mem,'2'),{jobs:'2',cjHeapSize:'15360MB'});
});

// Pin the simulated hardware, not the budget implementation. Assert what the child received.
function macHardware(dir,gib,cpus){
  const file=dir+'/hardware.mjs';
  put(file,`import os from 'node:os'; os.totalmem=()=>${gib}*1024**3; os.availableParallelism=()=>${cpus};`);
  return ['--import',file];
}
const noHeap={cjHeapSize:'',CJCJ_HEAP_SIZE:''},macTuple='darwin_x86_64_cjnative';
const macros=['unittest.testmacro','unittest.mock.mockmacro','deriving'];
function macInputs(dir) {
  const parent=dir+'/stage2',src=dir+'/src',native=dir+'/native',rt=dir+'/runtime',out=dir+'/out';
  for(const bin of ['opt','llc','ld64.lld'])put(parent+'/third_party/llvm/bin/'+bin,'arm');
  for(const rel of ['bin/cjc','third_party/flatbuffers/bin/flatc','schema/StdAstFormat.fbs',
    'include/flatbuffers/StdAstFormat_generated.h','LICENSE','Open_Source_Software_Notice.docx'])put(parent+'/'+rel,'arm');
  put(native+'/lib/'+macTuple+'/builtins','x64');put(native+'/libcangjie-ast-support.a','ast-x64');
  put(native+'/include/cangjie/CHIR/IR/AttributeInfo.h','class AttributeInfo {};');
  put(rt+'/lib/'+macTuple+'/thread','x64');put(rt+'/runtime/lib/'+macTuple+'/runtime','x64');
  return {parent,src,native,rt,out};
}
test('ARM64 final std consumes prepared Intel AST, installs the target macros and budgets Ninja',linux,t=>{
  for(const bad of [false,true]){
    const dir=fixture(t),{parent,src,native,rt,out}=macInputs(dir);
    put(src+'/bounds/b');put(src+'/pcre2/p');put(src+'/runtime/stdlib/build.py');
    const files=['lib/libstdFFI.dylib','modules/'+macTuple+'/std/std.core.cjo','modules/'+macTuple+'/std/std.ast.cjo',
      'lib/'+macTuple+'/libcangjie-std-core.a',...['core',...macros].map(n=>'runtime/lib/'+macTuple+'/libcangjie-std-'+n+'.dylib'),
      ...macros.map(n=>'modules/'+macTuple+'/std/std.'+n+'.cjo')];
    const {child,calls}=darwinStage(dir,'build-stdlib',['--platform','darwin-x64','--stage','stage3-std','--sdk',parent,
      '--out',out,'--runtime',rt,'--native',native,'--include',native+'/include','--sources',src],`
      if(cmd==='lipo')return {status:0,stdout:${bad}&&args[1].endsWith('deriving.dylib')?'arm64 x86_64':'x86_64'};
      if(args.includes('build')){
        for(const [rel,want] of ${JSON.stringify([['bin/cjc','arm'],['third_party/flatbuffers/bin/flatc','arm'],['lib/'+macTuple+'/libcangjie-ast-support.a','ast-x64'],['runtime/lib/'+macTuple+'/runtime','x64']])})
          if(fs.readFileSync(env.CANGJIE_HOME+'/'+rel,'utf8')!==want)throw Error(rel);
      }
      if(args.includes('install'))for(const rel of ${JSON.stringify(files)}){
        const f=args.at(-1)+'/'+rel;fs.mkdirSync(f.slice(0,f.lastIndexOf('/')),{recursive:true});fs.writeFileSync(f,'std');
      }`,noHeap,macHardware(dir,7,3));
    assert.equal(child.status,bad?1:0,child.stderr);
    if(bad){assert.match(child.stderr,/deriving.dylib: expected only x86_64/);continue;}
    for(const rel of files)assert.ok(fs.existsSync(out+'/'+rel),rel);
    const py=calls.filter(c=>c.args.includes('build.py'));
    assert.deepEqual(py.map(c=>c.args[2]),['clean','build','install']);
    assert.deepEqual(py[2].args.slice(2,-1),['install','--prefix']);
    const b=py[1];assert.equal(b.heap,'2688MB');assert.equal(b.args[b.args.indexOf('--jobs')+1],'2');
    for(const arg of ['relwithdebinfo','--local_mode_api','--include='+native+'/include'])assert.ok(b.args.includes(arg));
    assert.deepEqual(b.args.slice(b.args.indexOf('--target'),b.args.indexOf('--target')+6),
      ['--target','darwin-x86_64','--target-toolchain','/usr/bin','--target-sysroot','/fixture/MacOSX.sdk']);
    assert.ok(!calls.some(c=>c.cmd==='cmake'));assert.ok(!fs.existsSync(parent+'/lib/'+macTuple));
  }
});

test('ARM64 stdx uses the stage2 compiler on PATH with the Intel std and budget',linux,t=>{
  const dir=fixture(t),{parent,src,native,out}=macInputs(dir);
  for(const rel of ['lib/'+macTuple,'modules/'+macTuple,'runtime/lib/'+macTuple,'third_party/flatbuffers/modules'])
    put(out+'/'+rel+'/target','x64');
  put(src+'/compiler/utils/envsetup/llvm_darwin.sh');
  const {calls,child}=darwinStage(dir,'build-extras',['--platform','darwin-x64','--only','stdx','--sdk',out,'--host-sdk',parent,
    '--include',native+'/include','--sources',src],`
    if(fs.readFileSync(env.STDX_HOST_CANGJIE_HOME+'/bin/cjc','utf8')!=='arm'||
       fs.readFileSync(env.CANGJIE_HOME+'/modules/${macTuple}/target','utf8')!=='x64')throw Error('wrong SDK');`,
    noHeap,macHardware(dir,16,4));
  assert.equal(child.status,0,child.stderr);
  assert.deepEqual(calls.map(c=>c.args[2]),['clean','build','install']);
  const b=calls[1];assert.equal(b.path.split(':')[0],b.host+'/bin');assert.equal(b.heap,'4096MB');
  assert.deepEqual(b.args.slice(2),['build','-t','release','--target','darwin-x86_64','--target-toolchain','/usr/bin',
    '--target-sysroot','/fixture/MacOSX.sdk','--include='+native+'/include','--target-lib=/opt/homebrew/opt/openssl@3/lib','--jobs','3']);
  assert.deepEqual(calls[2].args.slice(2),['install','--prefix',out+'/stdx']);
  assert.ok(!fs.existsSync(parent+'/modules/'+macTuple));
});

test('ARM64 stage3 keeps native tools, links Intel LLVM, restores manifests and serializes cjpm',linux,t=>{
  for(const fail of [true,false]){
    const dir=fixture(t),{parent,native,out}=macInputs(dir),std=dir+'/std',source=dir+'/source',host=dir+'/arm-host';
    const triple='x86_64-apple-darwin',release=out+'.target/'+triple+'/release';
    const manifest=fs.readFileSync(repo+'/packages/cjc/cjpm.toml','utf8');
    put(source+'/packages/cjc/cjpm.toml',manifest);put(source+'/cjpm.toml','compile-option = "-O2"\n');
    put(source+'/packages/chir/src/Enums.cj',fs.readFileSync(repo+'/packages/chir/src/Enums.cj'));
    put(source+'/schema/StdxChirFormat.fbs');
    for(const rel of ['third_party/llvm/lib/libLLVM.dylib','third_party/llvm/bin/opt','third_party/flatbuffers/bin/flatc'])
      put(native+'/'+rel,'intel');
    for(const dir of ['lib/'+macTuple,'runtime/lib/'+macTuple,'modules/'+macTuple,'third_party/flatbuffers/modules'])
      put(std+'/'+dir+'/current','final');
    const objects=['cjselfhost_llvmshim','cjc_runtime_config','cjc_heap_defaults'];
    const {child,calls}=darwinStage(dir,'build-compiler',['--platform','darwin-x64','--stage','stage3','--sdk',parent,
      '--native',native,'--std',std,'--source',source,'--out',out,'--host-sdk',host],`
      const put=(p,s)=>{fs.mkdirSync(p.slice(0,p.lastIndexOf('/')),{recursive:true});fs.writeFileSync(p,s)};
      if(cmd==='git')return {status:0,stdout:'12345'};
      if(cmd==='lipo')return {status:0,stdout:'x86_64'};
      if(args[0]?.endsWith('build_shim.mjs'))for(const name of ${JSON.stringify(objects)})put(opts.cwd+'/runtime_shim/'+name+'.o','intel');
      if(cmd.endsWith('/cjpm')){
        const text=fs.readFileSync(opts.cwd+'/packages/cjc/cjpm.toml','utf8');
        fs.writeFileSync('${dir}/during',text);
        for(const rel of ['third_party/llvm/bin/opt','third_party/llvm/bin/llc','third_party/llvm/bin/ld64.lld','bin/cjc'])
          if(fs.readFileSync(env.CANGJIE_HOME+'/'+rel,'utf8')!=='arm')throw Error(rel);
        if(fs.readFileSync(env.CANGJIE_HOME+'/modules/${macTuple}/current','utf8')!=='final')throw Error('target modules');
        if(${fail})return {status:42};
        put('${release}/bin/cjc','intel');put('${release}/driver.cjo','intel');
      }
      if(args.includes('-std=c++17'))put(args[args.indexOf('-o')+1],'launcher');`,noHeap,macHardware(dir,16,4));
    assert.equal(child.status,fail?1:0,child.stderr);
    assert.equal(fs.readFileSync(source+'/packages/cjc/cjpm.toml','utf8'),manifest);
    const during=fs.readFileSync(dir+'/during','utf8');
    assert.ok(effectiveLinkOptions(during,'darwin_x86_64').includes(native+'/third_party/llvm/lib/libLLVM.dylib'));
    assert.deepEqual(effectiveLinkOptions(during,'darwin_aarch64'),effectiveLinkOptions(manifest,'darwin_aarch64'));
    const build=calls.find(c=>c.cmd===host+'/tools/bin/cjpm');
    assert.deepEqual(build.args,['build','--target',triple,'--target-dir',out+'.target','-j','1']);assert.equal(build.heap,'15360MB');
    assert.equal(calls.find(c=>c.args[0]?.endsWith('build_shim.mjs')).targetArch,'x86_64');
    if(fail){assert.match(child.stderr,/exited 42/);continue;}
    assert.equal(fs.readFileSync(out+'/libexec/compiler/cjcj-stage1','utf8'),'intel');
    assert.equal(fs.readFileSync(out+'/share/cjcj/cjo/driver.cjo','utf8'),'intel');
    assert.equal(fs.readFileSync(out+'/third_party/llvm/bin/opt','utf8'),'intel');
    assert.ok(calls.some(c=>c.cmd===build.home+'/third_party/flatbuffers/bin/flatc'));
    for(const rel of ['libexec/compiler/cjcj-stage1','bin/cjc',...objects.map(n=>'share/cjcj/runtime_shim/'+n+'.o')])
      assert.ok(calls.some(c=>c.cmd==='lipo' && c.args[1]===out+'/'+rel),rel);
  }
});

test('Darwin shim passes -arch to both target C compiles',linux,t=>{
  const dir=fixture(t),src=dir+'/runtime_shim',cc=dir+'/cc';
  put(src+'/build_shim.mjs',fs.readFileSync(repo+'/runtime_shim/build_shim.mjs'));
  put(dir+'/prebuilt','intel');
  put(cc,'#!/bin/sh\nprintf "%s\\n" "$*" >> "$CC_LOG"\n',0o755);
  put(dir+'/darwin.mjs',"Object.defineProperty(process,'platform',{value:'darwin'});");
  const child=spawnSync(process.execPath,['--import',dir+'/darwin.mjs',src+'/build_shim.mjs'],{encoding:'utf8',
    env:{...process.env,CC:cc,CC_LOG:dir+'/log',CMAKE_C_COMPILER_LAUNCHER:'',CANGJIE_HOME:'',CJCJ_COMMIT:'fixture',
      CJCJ_TARGET_ARCH:'x86_64',CJCJ_LLVM_SHIM_O:dir+'/prebuilt'}});
  assert.equal(child.status,0,child.stderr);
  const lines=fs.readFileSync(dir+'/log','utf8').trim().split('\n');
  assert.equal(lines.length,2);
  for(const [i,name] of ['cjc_runtime_config','cjc_heap_defaults'].entries()){
    assert.ok(lines[i].includes('-arch x86_64'));assert.ok(lines[i].includes(name+'.c'));
  }
});

test('Rosetta tools validate the copied Node and all six installed executables',linux,t=>{
  const dir=fixture(t),{src,out}=macInputs(dir);
  put(src+'/compiler/utils/envsetup/llvm_darwin.sh');put(src+'/tools/packages/hle/src/dtsparser/package.json','{}');put(dir+'/cjbind');
  const {calls,child}=darwinStage(dir,'build-extras',['--only','tools','--platform','darwin-x64','--sdk',out,
    '--sources',src,'--cjbind',dir+'/cjbind'],`
    if(cmd==='lipo')return {status:0,stdout:'x86_64'};
    if(args[1]==='install'){
      const bin=args[args.indexOf('--prefix')+1]+'/bin';fs.mkdirSync(bin,{recursive:true});
      fs.writeFileSync(bin+'/'+args[args.indexOf('--tool')+1],'tool');
    }`,{},[],'x64');
  assert.equal(child.status,0,child.stderr);
  assert.deepEqual(calls.filter(c=>c.cmd==='lipo').map(c=>c.args),[
    out+'/tools/bin/node',...['cjpm','cjfmt','hle','cjcov','cjtrace-recover','cjcompat'].map(n=>out+'/.target-tools/tools/bin/'+n)
  ].map(f=>['-archs',f]));
  assert.ok(!calls.some(c=>c.args.includes('build.py')));
});

test('Intel packaging builds two thin launchers and verifies the requested platform',linux,t=>{
  const dir=fixture(t),sdk=dir+'/sdk',out=dir+'/dist';
  for(const rel of ['libexec/compiler/cjcj-stage1','third_party/llvm/bin/lldb','LICENSE','envsetup.sh'])put(sdk+'/'+rel);
  const {child,calls}=darwinStage(dir,'package-sdk',['--sdk',sdk,'--target','darwin-x64','--out',out,'--version','1.0.0','--verify-relocated'],`
    if(cmd==='lipo')return {status:0,stdout:'x86_64'};
    if(args.includes('-o'))fs.writeFileSync(args[args.indexOf('-o')+1],'entry');
    if(args[0]==='-czf')fs.writeFileSync(args[1],'archive');`,{},[],'x64');
  assert.equal(child.status,0,child.stderr);
  const compiles=calls.filter(c=>c.args.includes('-std=c++17'));
  assert.equal(compiles.length,2);
  for(const c of compiles){
    assert.ok(c.args.includes('-arch'));assert.equal(c.args[c.args.indexOf('-arch')+1],'x86_64');
    assert.ok(calls.some(l=>l.cmd==='lipo'&&l.args[1]===c.args[c.args.indexOf('-o')+1]));
  }
  const verify=calls.find(c=>c.args[0]?.endsWith('test-sdk.mjs'));
  assert.equal(verify.args[verify.args.indexOf('--platform')+1],'darwin-x64');
});

test('Release builds the Intel host next to cross-std and switches Node only for tools and packaging',linux,()=>{
  const jobs=releaseJobs(),host=jobs['host-sdk'],intel=jobs['host-sdk-darwin-x64'],pkg=jobs.package;
  assert.ok(!host.strategy.matrix.include.some(row=>row.platform==='darwin-x64'));
  assert.equal(intel['runs-on'],'macos-15');assert.equal(intel.needs,'host-sdk');assert.equal(jobs['cross-std'].needs,'host-sdk');
  const downloads=intel.steps.filter(s=>s.uses?.includes('download-artifact')).map(s=>[s.with.name,s.with['run-id']]);
  assert.deepEqual(downloads,[['native-base-darwin-x64','${{ inputs.prepare_run_id }}'],['stage2-sdk-darwin-arm64',undefined]]);
  let arch;const sequence=[];
  for(const step of intel.steps){
    if(step.uses?.includes('setup-node'))arch=step.with.architecture;
    for(const line of (step.run||'').split('\n'))if(line.startsWith('node build/build-')){
      assert.ok(line.includes('--platform darwin-x64'));sequence.push([arch,line.match(/--(?:only|stage) (\S+)/)[1]]);
    }
  }
  assert.deepEqual(sequence,[['arm64','stage3-std'],['arm64','stage3'],['arm64','stdx'],['x64','tools']]);
  assert.equal(intel.steps.at(-1).with.name,'host-sdk-darwin-x64');
  assert.deepEqual(pkg.needs,['host-sdk','host-sdk-darwin-x64','cross-std']);
  assert.equal(RELEASE_TARGETS.find(r=>r.key==='darwin-x64').runner,'macos-15');
  const rosetta=pkg.steps.findIndex(s=>s.run?.includes('setup.mjs rosetta'));
  const x64=pkg.steps.findIndex(s=>s.uses?.includes('setup-node')&&s.with.architecture==='x64');
  assert.ok(rosetta>=0 && x64>rosetta && x64<pkg.steps.findIndex(s=>s.run?.includes('--verify-relocated')));
  for(const i of [rosetta,x64])assert.equal(pkg.steps[i].if,"matrix.host == 'darwin-x64'");
});
