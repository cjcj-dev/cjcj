import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {repo,compilerHeap,sdkPlatform} from '../../build/common.mjs';

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
