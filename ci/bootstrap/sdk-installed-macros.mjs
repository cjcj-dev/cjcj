#!/usr/bin/env zx
// Public installed cjc is both macro producer and consumer. This gate belongs
// after R-host C2 installation, and is reused after C3/package relocation.
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {sdkPlatform,cleanSdkEnvironment} from './sdk-platform.mjs';
import {atomicJson,fileDigest,privateRoot} from './sdk-flow.mjs';
import {compilerRuntimeDirectory} from '../../build/lib/runtime-split.mjs';

export async function macroInstall({sdk,work,platform}) {
 const native=sdkPlatform(platform);
 if(process.platform!==native.os||process.arch!==native.arch)throw new Error('MACRO_NATIVE_RUNNER_REQUIRED');
 sdk=await fs.realpath(sdk);work=await privateRoot(work);
 await fs.mkdir(work,{recursive:true});
 // Keep every attempt, including a failing compile, and never consume a stale SO.
 work=await fs.mkdtemp(path.join(work,'public cjc '));
 const base={...process.env};
 for(const key of ['LD_PRELOAD','LD_AUDIT','DYLD_INSERT_LIBRARIES','LD_LIBRARY_PATH',
   'DYLD_LIBRARY_PATH','DYLD_FALLBACK_LIBRARY_PATH','CANGJIE_PATH','LIBRARY_PATH'])delete base[key];
 const env=cleanSdkEnvironment(sdk,platform,base), commands=[], artifacts=[];
 const result={sdk,platform,work,status:'WIP',commands,artifacts};
 const record=()=>atomicJson(path.join(work,'macro-result.json'),result);
 const lines=text=>text.replace(/\r\n/g,'\n').split('\n');
 function requireLine(row,line) {
  // Test runners decorate marker lines with ANSI cursor/save/restore codes.
  // Normalize only the assertion view; command logs retain stdout verbatim.
  // std.unittest/pretty_console.cj emits CSI plus the two-byte DECSC/DECRC.
  // CSI: ESC [ + parameter bytes 0x30-3f + intermediates 0x20-2f + one
  // final byte 0x40-7e. ESC 7/8 end at the digit, never at the next letter.
  // Keep unrecognized controls/text intact so exact-line checks stay strict.
  const text=row.stdout.replace(/\x1b(?:\[[0-?]*[ -/]*[@-~]|[78])/g,'');
  if(!lines(text).includes(line))throw new Error('INSTALLED_MACRO_ASSERT '+row.name+' missing '+line);
 }
 async function invoke(name,argv,{expectedRc=0}={}) {
  const start=performance.now();
  console.log(JSON.stringify({event:'installed-macro-command',name,argv,cwd:work}));
  const row=await new Promise(resolve=>{
   let stdout='',stderr='';
   const child=spawn(argv[0],argv.slice(1),{cwd:work,env,stdio:['ignore','pipe','pipe']});
   child.stdout.on('data',b=>{stdout+=b;process.stdout.write(b);});
   child.stderr.on('data',b=>{stderr+=b;process.stderr.write(b);});
   child.once('error',error=>resolve({rc:null,signal:null,error:error.message,stdout,stderr}));
   child.once('close',(rc,signal)=>resolve({rc,signal,stdout,stderr}));
  });
  Object.assign(row,{name,argv,cwd:work,wall:(performance.now()-start)/1000});commands.push(row);
  await fs.writeFile(path.join(work,name+'.log'),JSON.stringify(row,null,2)+'\n');
  await record();
  if(row.rc!==expectedRc||row.signal||row.error)
   throw Object.assign(new Error('INSTALLED_MACRO_COMMAND '+name+' rc='+row.rc),{rc:row.rc,signal:row.signal});
  return row;
 }
 async function source(name,text) {
  const file=path.join(work,name);await fs.writeFile(file,text);return file;
 }
 async function artifact(file) {artifacts.push({file,sha256:await fileDigest(file)});await record();}
 const cjc='cjc'+native.exe; // PATH resolves the public entry, including relocated SDKs.
 const compile=async(name,input,output,flags=[])=>{
  const row=await invoke(name,[cjc,input,...flags,'-o',output]);await artifact(output);return row;
 };
 try {
  // Check the actual launcher recipe/runtime link, not a COMPLETE label. Macro
  // task/loader API image binding remains enforced in InvokeUtil.cj.
  const publicEntry=await fs.realpath(path.join(sdk,'bin',cjc));
  const recipe=await fs.readFile(publicEntry+'.entry','utf8');
  const recipeLines=lines(recipe);
  const executionLib=compilerRuntimeDirectory({sdk,compiler:publicEntry,
    target:{spec:{runtimeLibrary:'libcangjie-runtime'+native.shared,exeSuffix:native.exe}}});
  if(recipeLines[0]!=='cjcj-sdk-entry-v1'||recipeLines[2]!=='libexec/compiler/cjcj-stage1'+native.exe
    ||recipeLines.slice(5).some(line=>line.startsWith('.host/'))
    ||!['runtime/lib/'+native.tuple,'.compiler-exec/runtime/lib/'+native.tuple].includes(path.relative(sdk,executionLib).split(path.sep).join('/')))throw new Error('MACRO_R_HOST_ENTRY');
  const runtime=await fs.realpath(path.join(sdk,'libexec/runtime'));
  if(await fs.realpath(path.join(runtime,'lib',native.tuple))!==await fs.realpath(executionLib))throw new Error('MACRO_R_HOST_RUNTIME');
  result.entry={recipe,runtime,compilerSha256:await fileDigest(path.join(sdk,recipeLines[2])),
   runtimeSha256:await fileDigest(path.join(runtime,'lib',native.tuple,'libcangjie-runtime'+native.shared))};
  await record();

  const plain=await source('ordinary control.cj','func value(): Int64 { 40 + 2 }\nmain(): Int64 { if (value() != 42) { return 1 }; println("ORDINARY_CONTROL value=42"); return 0 }\n');
  const plainBin=path.join(work,'ordinary control'+native.exe);
  await compile('ordinary-compile',plain,plainBin);
  requireLine(await invoke('ordinary-run',[plainBin]),'ORDINARY_CONTROL value=42');

  // Preserve the existing identity macro and its 42 runtime assertion verbatim.
  const def=await source('def.cj',await fs.readFile(new URL('../../test/macro_same_runtime/def.cj',import.meta.url),'utf8'));
  const use=await source('use.cj',await fs.readFile(new URL('../../test/macro_same_runtime/use.cj',import.meta.url),'utf8'));
  await invoke('macro-definition',[cjc,'--compile-macro',def]);
  await artifact(path.join(work,'lib-macro_f1def'+native.shared));
  const macroBin=path.join(work,'macro use'+native.exe);
  requireLine(await compile('macro-expansion',use,macroBin,['--import-path',work]),'MACRO_BODY_EXECUTED');
  requireLine(await invoke('macro-run',[macroBin]),'MACRO_VALUE_ASSERT value=42');

  // Separately compiled ordinary CJ dependencies, actually called by the macro.
  // Static libraries preserve macro -> helper -> leaf calls without requiring
  // inherited loader paths (the public launcher selects its own runtime domain).
  // No official H compiler/std is used for any of these products.
  const leaf=await source('leaf.cj',`package sdkleaf
public func leafValue(): Int64 { 40 }
`);
  const helper=await source('helper.cj',`package sdkhelper
import sdkleaf.*
public func helperValue(): Int64 { leafValue() + 2 }
`);
  const leafLib=path.join(work,'libsdkleaf.a'),helperLib=path.join(work,'libsdkhelper.a');
  await compile('leaf-compile',leaf,leafLib,['--output-type=staticlib']);
  await compile('helper-compile',helper,helperLib,['--output-type=staticlib','--import-path',work,'-L',work,'-lsdkleaf']);
  const chainDef=await source('chain.cj',`macro package sdkchain
import std.ast.*
import std.time.*
import sdkhelper.*
import f1def.*
@Keep
func dependencyValue(): Int64 { helperValue() }
public macro Chain(input: Tokens): Tokens {
    // A real std.time call adds a std dependency outside the old five-library
    // preload list. Keep it in the macro body, not in the generated program.
    if (DateTime.nowUTC().year < 1970) { throw Exception("MACRO_STD_TIME_VALUE") }
    println("MACRO_STD_TIME_EXECUTED")
    let value = dependencyValue()
    if (value != 42) { throw Exception("MACRO_HELPER_VALUE") }
    println("MACRO_HELPER_EXECUTED value=42")
    input
}
`);
  requireLine(await invoke('chain-definition',[cjc,'--compile-macro',chainDef,'--import-path',work,'-L',work,'-lsdkhelper','-lsdkleaf']),
    'MACRO_BODY_EXECUTED');
  const chainLibrary=path.join(work,'lib-macro_sdkchain'+native.shared);
  await artifact(chainLibrary);
  if(native.os==='linux') {
    // Inspect the actual public producer output, without adding test-only link flags.
    const dynamic=await invoke('chain-dynamic-table',['readelf','-d',chainLibrary]);
    const rpath=dynamic.stdout.match(/\(RPATH\).*\[([^\]]+)\]/)?.[1];
    if(!rpath||dynamic.stdout.includes('(RUNPATH)')||!rpath.split(':').some(item=>
      path.resolve(item)===path.join(sdk,'runtime','lib',platform+'_cjnative')))
      throw Error('MACRO_PRODUCER_TARGET_RPATH_MISSING');
  }
  const chainUse=await source('chain use.cj',`import sdkchain.*
@Chain
func value(): Int64 { 42 }
main(): Int64 {
    if (value() != 42) { return 1 }
    println("MACRO_CHAIN_VALUE value=42")
    return 0
}
`);
  const chainBin=path.join(work,'chain use'+native.exe);
  const expandedChain=await compile('chain-expansion',chainUse,chainBin,['--import-path',work]);
  requireLine(expandedChain,'MACRO_STD_TIME_EXECUTED');
  requireLine(expandedChain,'MACRO_HELPER_EXECUTED value=42');
  requireLine(await invoke('chain-run',[chainBin]),'MACRO_CHAIN_VALUE value=42');

  // R stdlib/doc/libs/std_en/deriving/deriving_samples/deriving_user_guide.md.
  // The empty-class case consumes deriving.builtins/tostring.cj's real literal.
  // Its pre-assertion output and dedicated rc 42 distinguish the planned semantic
  // cut from an earlier parsing, linking or macro-loader error.
  const deriving=await source('deriving.cj',`import std.deriving.*
@Derive[ToString]
class Empty { Empty() {} }
main(): Int64 {
    let actual = Empty().toString()
    println("DERIVING_ASSERTION_REACHED value=" + actual)
    if (actual != "Empty()") { return 42 }
    println("DERIVING_VALUE_PASS")
    return 0
}
`);
  const derivingBin=path.join(work,'deriving'+native.exe);
  await compile('deriving-compile',deriving,derivingBin);
  const derived=await invoke('deriving-run',[derivingBin]);
  requireLine(derived,'DERIVING_ASSERTION_REACHED value=Empty()');requireLine(derived,'DERIVING_VALUE_PASS');

  // The explicit consumer and the no-import consumer are distinct obligations.
  // FrontendModel.AddImplicitImports adds unittest/testmacro only for --test.
  for(const implicit of [false,true]) {
   const name=implicit?'implicit-testmacro':'explicit-testmacro';
   const input=await source(name+'_test.cj',`${implicit?'':'import std.unittest.*\nimport std.unittest.testmacro.*\n'}
@Test
class InstalledTest {
    @TestCase
    func valueCase() {
        @Assert(40 + 2 == 42)
        println("${name}_BODY_EXECUTED")
    }
}
`);
   const binary=path.join(work,name+native.exe);
   await compile(name+'-compile',input,binary,['--test']);
   requireLine(await invoke(name+'-run',[binary]),name+'_BODY_EXECUTED');
  }
  // R mock_framework_getting_started.md uses mock<Interface>() and @On(...).
  // mock_framework_basics.md: --test enables mocking without extra flags.
  const mock=await source('mock_test.cj',`import std.unittest.mock.*
import std.unittest.mock.mockmacro.*
public interface Repository { func requestData(id: UInt64, timeoutMs: Int64): String }
@Test
class InstalledMockTest {
    @TestCase
    func valueCase() {
        let repository = mock<Repository>()
        let id: UInt64 = 100
        @On(repository.requestData(id, _)).returns("value=42")
        @Assert(repository.requestData(id, 100) == "value=42")
        println("MOCKMACRO_BODY_EXECUTED value=42")
    }
}
`);
  const mockBin=path.join(work,'mock'+native.exe);
  await compile('mockmacro-compile',mock,mockBin,['--test']);
  requireLine(await invoke('mockmacro-run',[mockBin]),'MOCKMACRO_BODY_EXECUTED value=42');
  result.status='PASS';await record();return result;
 }catch(error){
  result.status='FAILED';result.error=error.message;result.rc=error.rc??null;
  await record();throw error;
 }
}
