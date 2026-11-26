#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import sync from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawn,spawnSync,execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {pathToFileURL} from 'node:url';
import {parseCliArgs,repo,sdkPlatform,pathEnvironment,compilerHeap,cleanSdkEnvironment,run,runCapture,resolveHostPython,ensureDir,rmrf,jobs,sha256File as fileDigest} from './common.mjs';

const execute=promisify(execFile),privateRoot=path.resolve.bind(path);
const atomicJson=(file,value)=>fs.writeFile(file,JSON.stringify(value,null,2)+'\n');
const readJson=async file=>JSON.parse(await fs.readFile(file,'utf8'));
const command=([cmd,...args],opts)=>run(cmd,args,{...opts,env:{...pathEnvironment(),...pathEnvironment(opts.env||{})}});

export async function precompiledStdxMacros({sdk,work,platform}) {
 const native=sdkPlatform(platform);
 if(process.platform!==native.os||process.arch!==native.arch)throw Error('MACRO_NATIVE_RUNNER_REQUIRED');
 sdk=await fs.realpath(sdk);work=await privateRoot(work);
 await fs.mkdir(work,{recursive:true});work=await fs.mkdtemp(path.join(work,'published stdx '));
 const modules=path.join(sdk,'stdx',native.tuple,'static','stdx');
 const libraries=path.join(sdk,'stdx',native.tuple,'dynamic','stdx');
 const inputs=['chir.to_string_macro','plugin'].flatMap(name=>[
  path.join(modules,'stdx.'+name+'.cjo'),path.join(modules,'lib-macro_stdx.'+name+native.shared)]);
 const env=cleanSdkEnvironment(sdk,platform);
 env.CANGJIE_STDX_PATH=modules;
 const result={sdk,work,platform,inputs,status:'WIP',commands:[]};
 const save=()=>atomicJson(path.join(work,'precompiled-macros.json'),result);
 async function run(name,argv,environment=env,marker) {
  const started=new Date().toISOString();
  const row=await new Promise(resolve=>{
   let stdout='',stderr='';const child=spawn(argv[0],argv.slice(1),{cwd:work,env:environment,stdio:['ignore','pipe','pipe']});
   child.stdout.on('data',b=>{stdout+=b;process.stdout.write(b);});
   child.stderr.on('data',b=>{stderr+=b;process.stderr.write(b);});
   child.once('error',error=>resolve({rc:null,signal:null,error:error.message,stdout,stderr}));
   child.once('close',(rc,signal)=>resolve({rc,signal,stdout,stderr}));
  });
  Object.assign(row,{name,argv,cwd:work,started,ended:new Date().toISOString()});result.commands.push(row);
  await atomicJson(path.join(work,name+'.json'),row);await save();
  if(row.rc!==0||row.signal||row.error)throw Object.assign(Error('PRECOMPILED_MACRO_COMMAND '+name),{rc:row.rc,signal:row.signal});
  if(marker&&!row.stdout.replace(/\r\n/g,'\n').split('\n').includes(marker))throw Error('PRECOMPILED_MACRO_ASSERT '+marker);
 }
 try {
  for(const input of inputs)await fs.access(input);
  const cases=[
   ['ordinary',`main(): Int64 { println("PRECOMPILED_ORDINARY value=42"); return 0 }\n`,'PRECOMPILED_ORDINARY value=42',[]],
   ['to-string',`package stdx.chir.relocation_consumer
import stdx.chir.to_string_macro.*
@CHIREnumToString
public enum MacroBody { PRECOMPILED_TOSTRING_BODY_EXECUTED }
main(): Int64 {
 let value = MacroBody.PRECOMPILED_TOSTRING_BODY_EXECUTED.toString()
 if (value != "PRECOMPILED_TOSTRING_BODY_EXECUTED") { return 41 }
 println(value)
 println("PRECOMPILED_TOSTRING value=42")
 return 0
}
`,'PRECOMPILED_TOSTRING value=42',[]],
   ['plugin',`import stdx.chir.*
import stdx.plugin.*
@CHIRPlugin
class PRECOMPILED_PLUGIN_BODY_EXECUTED {
 public override func run(pkg: Package): Bool { return pkg.name == "relocated" }
}
main(): Int64 {
 let plugin = PRECOMPILED_PLUGIN_BODY_EXECUTED()
 if (plugin.name != "PRECOMPILED_PLUGIN_BODY_EXECUTED") { return 41 }
 if (!plugin.run(Package("relocated", AccessLevel.Public))) { return 42 }
 println(plugin.name)
 println("PRECOMPILED_PLUGIN value=42")
 return 0
}
`,'PRECOMPILED_PLUGIN value=42',['-L',libraries,'-lstdx.plugin.manager','-lstdx.chir']],
  ];
  for(const [name,text,marker,flags]of cases) {
   const input=path.join(work,name+'.cj'),output=path.join(work,name+native.exe);
   await fs.writeFile(input,text);
   await run(name+'-compile',[path.join(sdk,'bin','cjc'+native.exe),input,'--import-path',modules,...flags,'-o',output]);
   const runEnv={...env,[native.loader]:[libraries,env[native.loader]].filter(Boolean).join(native.os==='win32'?';':':')};
   await run(name+'-run',[output],runEnv,marker);
   if(name!=='ordinary') {
    const body='PRECOMPILED_'+(name==='to-string'?'TOSTRING':'PLUGIN')+'_BODY_EXECUTED';
    if(!result.commands.at(-1).stdout.replace(/\r\n/g,'\n').split('\n').includes(body))throw Error('PRECOMPILED_MACRO_ASSERT '+body);
   }
  }
  result.status='PASS';return result;
 } catch(error) {result.status='FAILED';result.error=error.message;throw error;}
 finally {await save();}
}

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
  const executionLib=path.join(sdk,recipeLines.slice(5).find(rel=>rel.endsWith('runtime/lib/'+native.tuple)));
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
  const def=await source('def.cj',await fs.readFile(new URL('../test/macro_same_runtime/def.cj',import.meta.url),'utf8'));
  const use=await source('use.cj',await fs.readFile(new URL('../test/macro_same_runtime/use.cj',import.meta.url),'utf8'));
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

  if(native.os==='linux') {
   // Keep the static chain above. This separate public producer chain must
   // contain real DT_NEEDED edges; it cannot pass by folding dependencies into
   // the macro. Explicit $ORIGIN locates only these private CJ libraries. The
   // target SDK runtime path must still come from the compiler's macro link.
   const privateRpath=['--link-option','--disable-new-dtags','--link-option','-rpath','--link-option','$ORIGIN'];
   const dynLeaf=await source('dynamic leaf.cj',`package sdkdynleaf
public func dynamicLeafValue(): Int64 { 40 }
`);
   const dynHelper=await source('dynamic helper.cj',`package sdkdynhelper
import sdkdynleaf.*
public func dynamicHelperValue(): Int64 { dynamicLeafValue() + 2 }
`);
   const dynLeafLib=path.join(work,'libsdkdynleaf.so');
   const dynHelperLib=path.join(work,'libsdkdynhelper.so');
   await compile('dynamic-leaf-compile',dynLeaf,dynLeafLib,
     ['--output-type=dylib','--link-option','-soname','--link-option','libsdkdynleaf.so',...privateRpath]);
   await compile('dynamic-helper-compile',dynHelper,dynHelperLib,
     ['--output-type=dylib','--import-path',work,'-L',work,'-lsdkdynleaf',
      '--link-option','-soname','--link-option','libsdkdynhelper.so',...privateRpath]);
   async function requireNeeded(name,file,dependency) {
    const row=await invoke(name,['readelf','-d',file]);
    const needed=[...row.stdout.matchAll(/\(NEEDED\).*\[([^\]]+)\]/g)].map(match=>match[1]);
    if(!needed.includes(dependency))throw Error('MACRO_DYNAMIC_DEPENDENCY_MISSING '+dependency);
    return row;
   }
   await requireNeeded('dynamic-helper-needed',dynHelperLib,'libsdkdynleaf.so');
   const dynControl=await source('dynamic control.cj',`import sdkdynhelper.*
main(): Int64 {
    if (dynamicHelperValue() != 42) { return 1 }
    println("DYNAMIC_ORDINARY_CONTROL value=42")
    return 0
}
`);
   const dynControlBin=path.join(work,'dynamic control');
   await compile('dynamic-control-compile',dynControl,dynControlBin,
     ['--import-path',work,'-L',work,'-lsdkdynhelper','-lsdkdynleaf',...privateRpath]);
   requireLine(await invoke('dynamic-control-run',[dynControlBin]),'DYNAMIC_ORDINARY_CONTROL value=42');
   const dynDef=await source('dynamic macro.cj',`macro package sdkdynamic
import std.ast.*
import std.time.*
import sdkdynhelper.*
public macro Dynamic(input: Tokens): Tokens {
    if (DateTime.nowUTC().year < 1970) { throw Exception("DYNAMIC_STD_TIME_VALUE") }
    if (dynamicHelperValue() != 42) { throw Exception("DYNAMIC_CJ_DEPENDENCY_VALUE") }
    println("MACRO_DYNAMIC_DEPENDENCIES_EXECUTED value=42")
    input
}
`);
   await invoke('dynamic-macro-definition',[cjc,'--compile-macro',dynDef,'--import-path',work,
     '-L',work,'-lsdkdynhelper',...privateRpath]);
   const dynMacroLib=path.join(work,'lib-macro_sdkdynamic.so');
   await artifact(dynMacroLib);
   const dynamic=await requireNeeded('dynamic-macro-needed',dynMacroLib,'libsdkdynhelper.so');
   const paths=dynamic.stdout.match(/\(RPATH\).*\[([^\]]+)\]/)?.[1]?.split(':')??[];
   if(dynamic.stdout.includes('(RUNPATH)')||!paths.includes('$ORIGIN')||
      !paths.some(item=>path.resolve(item)===path.join(sdk,'runtime','lib',native.tuple)))
     throw Error('MACRO_DYNAMIC_RUNTIME_AND_PRIVATE_RPATH_MISSING');
   const dynUse=await source('dynamic use.cj',`import sdkdynamic.*
@Dynamic
func value(): Int64 { 42 }
main(): Int64 {
    if (value() != 42) { return 1 }
    println("MACRO_DYNAMIC_TARGET value=42")
    return 0
}
`);
   const dynBin=path.join(work,'dynamic use');
   requireLine(await compile('dynamic-macro-expansion',dynUse,dynBin,['--import-path',work]),
     'MACRO_DYNAMIC_DEPENDENCIES_EXECUTED value=42');
   requireLine(await invoke('dynamic-macro-run',[dynBin]),'MACRO_DYNAMIC_TARGET value=42');
  }

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
   requireLine(await invoke(name+'-run',[binary,'--no-progress']),name+'_BODY_EXECUTED');
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
  requireLine(await invoke('mockmacro-run',[mockBin,'--no-progress']),'MOCKMACRO_BODY_EXECUTED value=42');
  result.status='PASS';await record();return result;
 }catch(error){
  result.status='FAILED';result.error=error.message;result.rc=error.rc??null;
  await record();throw error;
 }
}
export async function verifyInstalledRegex({sdk, work, platform}) {
  sdk = await fs.realpath(sdk);
  const env = cleanSdkEnvironment(sdk, platform);
  delete env.LD_DEBUG_OUTPUT;
  const lib = path.join(sdk, 'runtime/lib', sdkPlatform(platform).tuple);
  await fs.mkdir(work, {recursive:true});
  const source=path.join(work,'regex.cj');await fs.writeFile(source,"import std.regex.{Regex, RegexOption}\n\nmain(): Int64 {\n    let pattern = Regex(\"^(Cat|Dog)[0-9]+$\", RegexOption().ignoreCase())\n    if (!pattern.matches(\"cat231\") || pattern.matches(\"cat\")) {\n        return 1\n    }\n    println(\"SDK_REGEX_MATCH_PASS\")\n    return 0\n}\n");
  const exe = path.resolve(work, 'regex');
  await execute(path.join(sdk, 'bin/cjc'), ['--dy-std', source, '-o', exe], {cwd:work, env});
  const {stdout, stderr} = await execute(exe, [], {cwd:work, env:{...env, LD_DEBUG:'libs', LC_ALL:'C'}});
  if (stdout.trim() !== 'SDK_REGEX_MATCH_PASS') throw Error('SDK_REGEX_VALUE ' + stdout);
  const initialized = [...stderr.matchAll(/^\s*\d+:\s+calling init: (.+)$/gm)].map(match => path.normalize(match[1].trim()));
  for (const relative of ['libcangjie-std-regex.so', 'pcre2/libpcre2-8.so.0']) {
    const expected = path.join(lib, relative);
    const paths = initialized.filter(file => path.basename(file) === path.basename(expected));
    console.log('SDK_REGEX_LOADED ' + JSON.stringify({expected, paths}));
    if (paths.length !== 1 || paths[0] !== expected ||
        path.dirname(await fs.realpath(expected)) !== path.dirname(expected))
      throw Error('SDK_REGEX_ORIGIN ' + relative);
  }
  console.log(stdout.trim());
}
export async function verifyInstalledJava(sdk,work,jdkHome) {
  const home=jdkHome;
  await fs.mkdir(work,{recursive:true});
  const cwd=await fs.mkdtemp(path.join(work,'java-'));
  await fs.mkdir(path.join(cwd,'src'));await fs.mkdir(path.join(cwd,'generated'));
  await fs.writeFile(path.join(cwd,'src/probe.cj'),`package sdkprobe
import java.lang.*
@Java["check.Base"]
public open foreign class Base {
    public init()
    public static func Record(s: JString): Unit
}
@Java
public class Probe <: Base {
    public init(active: Bool) {
        if (active) { Record(JString("sdk-java")) }
    }
}
`);
  await fs.writeFile(path.join(cwd,'Base.java'),`package check;
public class Base {
    static String result;
    public static void Record(String s) { result = s; }
    public static void main(String[] args) {
        new sdkprobe.Probe(true);
        if (!"sdk-java".equals(result)) throw new AssertionError(result);
    }
}
`);
  const runtime=path.join(sdk,'runtime/lib/linux_x86_64_cjnative'),cp='.'+path.delimiter+path.join(sdk,'lib/library-loader.jar');
  const env={CANGJIE_HOME:sdk,JAVA_HOME:home,LD_LIBRARY_PATH:[cwd,runtime,path.join(sdk,'lib/linux_x86_64_cjnative')].join(path.delimiter)};
  for(const argv of [[path.join(sdk,'bin/cjc'),'--output-type=dylib','-p','src','-L'+runtime,'-ljava.internal','-ljava.lang','--output-javagen-dir=generated'],
    [path.join(home,'bin/javac'),'-cp',cp,'Base.java','generated/Probe.java','-d','.'],
    [path.join(home,'bin/java'),'-cp',cp,'-Djava.library.path='+cwd,'check.Base']])await command(argv,{cwd,env});
}
function frame(value) {
  const body=Buffer.from(JSON.stringify({jsonrpc:'2.0',...value}));
  return Buffer.concat([Buffer.from('Content-Length: '+body.length+'\r\n\r\n'),body]);
}
function messages(bytes) {
  const rows=[];
  while(bytes.length) {
    const end=bytes.indexOf('\r\n\r\n');
    const header=end>=0&&/^Content-Length: (\d+)$/i.exec(bytes.subarray(0,end).toString());
    if(!header||Number(header[1])>bytes.length-end-4)throw Error('LSP_MACRO_INVALID_FRAME');
    const next=end+4+Number(header[1]);
    rows.push(JSON.parse(bytes.subarray(end+4,next)));bytes=bytes.subarray(next);
  }
  return rows;
}
export async function consumeInstalledLspMacro({sdk,platform,work,env=process.env}) {
  const native=sdkPlatform(platform);
  if(native.os!==process.platform||native.arch!==process.arch)throw Error('LSP_MACRO_NATIVE_HOST_REQUIRED');
  sdk=await fs.realpath(sdk);
  const base=path.resolve(work,'lsp-macro');await fs.mkdir(base,{recursive:true});
  const cwd=await fs.mkdtemp(path.join(base,'analysis '));
  const cjc=path.join(sdk,'bin','cjc'+native.exe),lsp=path.join(sdk,'tools/bin','LSPServer'+native.exe);
  const environment=cleanSdkEnvironment(sdk,platform,env);
  async function run(name,argv,input) {
    const result=spawnSync(argv[0],argv.slice(1),{cwd,env:environment,input,timeout:120000,maxBuffer:8*1024*1024});
    await fs.writeFile(path.join(cwd,name+'.stdout'),result.stdout??Buffer.alloc(0));
    await fs.writeFile(path.join(cwd,name+'.stderr'),result.stderr??Buffer.alloc(0));
    await atomicJson(path.join(cwd,name+'.json'),{argv,cwd,rc:result.status,signal:result.signal,error:result.error?.message});
    if(result.error||result.status!==0||result.signal)throw Object.assign(Error('LSP_MACRO_PROCESS '+name+' '+cwd),{rc:result.status??1});
    return result.stdout;
  }
  const def=path.join(cwd,'definition.cj');
  await fs.writeFile(def,'macro package sdkprobe\nimport std.ast.*\npublic macro FromBody(input: Tokens): Tokens { return quote(true) }\n');
  await run('compile',[cjc,'--compile-macro',def]);
  for(const name of ['sdkprobe.cjo','lib-macro_sdkprobe'+native.shared])await fs.access(path.join(cwd,name));
  const file=path.join(cwd,'consumer.cj'),uri=pathToFileURL(file).href;
  // Keep the opened URI for diagnostics; later requests name the same on-disk
  // file through another valid URI, including drive and filename case on Windows.
  const alias=native.os==='win32'
    ? uri.replace(/^file:\/\/\/([A-Za-z]):/,(_,d)=>'file:///'+(d===d.toUpperCase()?d.toLowerCase():d.toUpperCase())+':').replace(/consumer\.cj$/,'CONSUMER.cj')
    : uri;
  const source=value=>'package sdkclient\nimport sdkprobe.*\nfunc inspect(): Unit {\n    let inferred = '+value+'\n    println(inferred)\n}\n';
  const plain=source('17'),expanded=source('@FromBody(17)');
  await fs.writeFile(file,plain);
  const database=path.join(cwd,'compile_commands.json');
  await atomicJson(database,[{directory:cwd,file,arguments:[cjc,'--output-type=staticlib','--import-path',cwd,file]}]);
  const hover=id=>({id,method:'textDocument/hover',params:{textDocument:{uri:alias},position:{line:3,character:9}}});
  const requests=[
    {id:1,method:'initialize',params:{initializationOptions:{compilationDatabase:database}}},
    {method:'initialized',params:{}},
    {method:'textDocument/didOpen',params:{textDocument:{uri,languageId:'cangjie',version:1,text:plain}}},hover(2),
    {method:'textDocument/didChange',params:{textDocument:{uri:alias,version:2},contentChanges:[{text:expanded}]}},hover(3),
    {id:4,method:'shutdown',params:{}},{method:'exit',params:{}}];
  const input=Buffer.concat(requests.map(frame));await fs.writeFile(path.join(cwd,'requests.lsp'),input);
  const rows=messages(await run('server',[lsp,'--sdk',sdk],input));
  const response=id=>{const matches=rows.filter(r=>r.id===id);assert.equal(matches.length,1,'LSP_MACRO_RESPONSE '+id);return matches[0].result;};
  assert.equal(response(1)?.capabilities?.hoverProvider,true);
  for(const [id,version,type] of [[2,1,'Int64'],[3,2,'Bool']]) {
    const batch=rows.filter(r=>r.method==='textDocument/publishDiagnostics'&&r.params.uri===uri&&r.params.version===version);
    assert.ok(batch.length,'LSP_MACRO_DIAGNOSTICS '+version);
    assert.deepEqual(batch.flatMap(r=>r.params.diagnostics.filter(d=>d.severity===1)),[],'LSP_MACRO_SEMA '+version);
    assert.equal(response(id)?.contents?.value,'inferred: '+type,'LSP_MACRO_INFERRED_TYPE version='+version);
    console.log('LSP_MACRO_HOVER version='+version+' type='+type);
  }
  assert.equal(response(4),null);
}
async function consumeWindowsLint(sdk,work,env) {
  const dir=path.resolve(work,'cjlint'),src=path.join(dir,'src'),file=path.join(src,'main.cj');
  await fs.mkdir(src,{recursive:true});
  const exe=path.join(sdk,'tools/bin/cjlint.exe');
  for(const [label,keyword] of [['positive','var'],['control','let']]) {
    const report=path.join(dir,label+'.json');
    await fs.writeFile(file,`package example\n${keyword} value = 1\nfunc api(): Int64 { value }\n`);
    const args=['-f',src,'-o',report],r=spawnSync(exe,args,{cwd:dir,env,encoding:'utf8'});
    await fs.writeFile(path.join(dir,label+'.command.json'),JSON.stringify({argv:[exe,...args],cwd:dir,
      rc:r.status,signal:r.signal,error:r.error?.message,stdout:r.stdout,stderr:r.stderr},null,2));
    if(r.error||r.status!==0)throw Object.assign(Error('WINDOWS_CJLINT_PROCESS '+label),{rc:r.status??1});
    const findings=await readJson(report);
    const matches=findings.filter(row=>row.defectType==='G_VAR_01_prefer_immutable_var'
      &&path.resolve(dir,row.file)===file&&row.analyzerName==='cangjieCodeCheck');
    if(matches.length!==(keyword==='var'?1:0))throw Error('WINDOWS_CJLINT_FINDINGS '+label);
  }
}

export async function consumeWindowsProfiler(sdk,work,env) {
  const dir=path.join(work,'cjprof'), input=path.join(dir,'heap input.data');
  const fixtures=dir;
  await fs.mkdir(dir,{recursive:true});
  await fs.writeFile(input,Buffer.from('Q0FOR0pJRSBQUk9GSUxFIDEuMC4xAAAAAAgAAAGeAUVi2QEAAAAAAAAACAAAAABAAAAPAQAAAAAAAABWAAAAAEAAAAkvaG9tZS9saXV6aGVuZy9jYW5namllL3J1bnRpbWUvbGliL2xpbnV4X3g4Nl82NF9jam5hdGl2ZS9saWJjYW5namllLXJ1bnRpbWUuc28BAAAAAAAAACUAAAAAQAAADC9ob21lL2xpdXpoZW5nL3NhbXBsZS9oZWFwLmNqAQAAAAAAAAAeAAAAAEAAAApDSl9NQ0NfSGFuZGxlU2FmZXBvaW50AQAAAAAAAAAXAAAAAEAAABFSYXdBcnJheTxJbnQzMj4BAAAAAAAAABcAAAAAQAAAA1Jhd0FycmF5PEludDY0PgEAAAAAAAAAGAAAAABAAAAZUmF3QXJyYXk8VUludDY0PgEAAAAAAAAAFwAAAABAAAACUmF3QXJyYXk8VUludDg+AQAAAAAAAAAsAAAAAEAAABhSYXdBcnJheTxzdGQuY29yZTpTdGFja1RyYWNlRWxlbWVudD4BAAAAAAAAACEAAAAAQAAABFJhd0FycmF5PHN0ZC5jb3JlOlN0cmluZz4BAAAAAAAAABEAAAAAQAAAFFJlZkZpZWxkcwEAAAAAAAAAEgAAAABAAAAVVmFsdWVGaWVsZAEAAAAAAAAAEQAAAABAAAAQY2pfZW50cnkkAQAAAAAAAAAmAAAAAEAAAAtkZWZhdWx0LkZ1bmMoZGVmYXVsdDo6RGlyaXZlZCkBAAAAAAAAABYAAAAAQAAADWRlZmF1bHQubWFpbigpAQAAAAAAAAAXAAAAAEAAABJkZWZhdWx0OkRpcml2ZWQBAAAAAAAAABQAAAAAQAAACGRlZmF1bHROYW1lMQEAAAAAAAAAEAAAAABAAAATcmVzZXJ2ZWQBAAAAAAAAAGAAAAAAQAAABXN0ZC5jb3JlOkF0b21pY0JveDxzdGQuY29yZTpPcHRpb248Q2xvc3VyZTwoc3RkLmNvcmU6VGhyZWFkLHN0ZC5jb3JlOkV4Y2VwdGlvbiktPlVuaXQ+Pj4BAAAAAAAAABwAAAAAQAAABnN0ZC5jb3JlOkF0b21pY0ludDY0AQAAAAAAAAB0AAAAAEAAABdzdGQuY29yZTpBdG9taWNSZWZlcmVuY2U8c3RkLmNvcmU6Qm94PHN0ZC5jb3JlOk9wdGlvbjxDbG9zdXJlPChzdGQuY29yZTpUaHJlYWQsc3RkLmNvcmU6RXhjZXB0aW9uKS0+VW5pdD4+Pj4BAAAAAAAAAFoAAAAAQAAAFnN0ZC5jb3JlOkJveDxzdGQuY29yZTpPcHRpb248Q2xvc3VyZTwoc3RkLmNvcmU6VGhyZWFkLHN0ZC5jb3JlOkV4Y2VwdGlvbiktPlVuaXQ+Pj4BAAAAAAAAABoAAAAAQAAAAHN0ZC5jb3JlOkZ1dHVyZUVycgEAAAAAAAAAIQAAAABAAAABc3RkLmNvcmU6T3V0T2ZNZW1vcnlFcnJvcgEAAAAAAAAAFwAAAABAAAAac3RkLmNvcmU6U3RyaW5nAQAAAAAAAAAfAAAAAEAAAAdzdGQuY29yZTpUaHJlYWRMb2NhbEtleQEAAAAAAAAAEQAAAABAAAAOdXNlci5tYWluAgAAAAAAAAAQAABgsToSeaAAAAAAQAAAEQIAAAAAAAAAEAAAYLE6EnpgAAAAAEAAABICAAAAAAAAABAAAGCxOhJ/QAAAAABAAAARAgAAAAAAAAAQAABgsToSiEAAAAAAQAAABgIAAAAAAAAAEAAAYLE6EougAAAAAEAAAAcCAAAAAAAAABAAAGCxOhKNIAAAAABAAAABAgAAAAAAAAAQAABgsToSm2AAAAAAQAAAGgIAAAAAAAAAEAAAYLE6EqHAAAAAAEAAAAACAAAAAAAAABAAAGCxOhKiIAAAAABAAAADAgAAAAAAAAAQAABgsToSooAAAAAAQAAAAgIAAAAAAAAAEAAAYLE6EqNAAAAAAEAAAAUCAAAAAAAAABAAAGCxOhKjoAAAAABAAAAWAgAAAAAAAAAQAABgsToSpAAAAAAAQAAAFwIAAAAAAAAAEAAAYLE6EqcAAAAAAEAAABgCAAAAAAAAABAAAGCxOhKqAAAAAABAAAAZAgAAAAAAAAAQAABgsToSfQAAAAAAQAAABAIAAAAAAAAAEAAAYLE6EqLgAAAAAEAAAAQEAAAAAAAAABwAAAAAAAAAAAAAAABAAAAKAAAAAEAAAAkAAAAABAAAAAAAAAAcAAAAAAAAAAEAAAAAQAAACwAAAABAAAAMAAAAAAQAAAAAAAAAHAAAAAAAAAACAAAAAEAAAA0AAAAAQAAADAAAACEEAAAAAAAAABwAAAAAAAAAAwAAAABAAAAOAAAAAEAAAA8AAAAABAAAAAAAAAAcAAAAAAAAAAQAAAAAQAAAEAAAAABAAAAPAAAAAAUAAAAAAAAANAAAAAEAAAABAAAABQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAgAAAAAAAAADAAAAAAAAAAQKAAAAAAAAABgAAAABAAAAAIAAAAAAAAABAAAAAEAAAAgMAAAAAAAABAEgAABgsToSeaAAAAAAIAAAYLE6EnpgAAAASCAAAGCxOhJ/QAAAAAAgAABgsToSiEAAAAAQIAAAYLE6EougAAAAECAAAGCxOhKNIAAAADggAABgsToSm2AAAAAAIAAAYLE6EqHAAAAAECAAAGCxOhKiIAAAAAAgAABgsToSooAAAAAAIAAAYLE6EqNAAAAAECAAAGCxOhKjoAAAABAgAABgsToSpAAAAAAQIAAAYLE6EqcAAAAAACAAAGCxOhKqAAAAAAAgAABgsToSfQAAAAAQIAAAYLE6EqLgAAAAEAEAAH5TQeACWAEAAH5TQeABeAEAAH5TQeAAYAEAAH5TQeABOAEAAH5TQeABSAEAAH5TQeABWAEAAH5TQeABaAEAAH5TQeAAMAEAAH5TQeAAAAEAAH5TQeAAEAEAAH5TQeAAIAEAAH5TQeAAEAEAAH5TQeAAEAEAAH5TQeAAIAEAAH5TQeAAIAIAAH5TQeADqAAAAAEAAAABAgAAflNB4AJoAAAAAQAAAAIhAAB+U0HgAAAAAGCxOhKIQAAAAAAhAAB+U0HgABAAAGCxOhKLoAAAAAAhAAB+U0HgACAAAGCxOhKLoAAAAAAhAAB+U0HgADAAAGCxOhKjQAAAAAEAAH5TQeAAUCEAAH5TQeAAQAAAYLE6EqOgAAAAAQAAAAAAAAAAIQAAflNB4ABQAABgsToSpAAAAAABAAB+U0HgAEAjAAB+U0HgAGAAAADIBCMAAH5TQeABOAAAAAAEIwAAflNB4AFIAAAAAAQjAAB+U0HgAVgAAAAACyQAAH5TQeABaAAAAAAAAAAAAABgsToSouAhAAB+U0HgAXgAAGCxOhKNIAAAAAMAAH5TQeABsAAAflNB4AHQAABgsToRLxAiAAB+U0HgAbAAAAAAAABgsToSpwAjAAB+U0HgAcAAAAAABCMAAH5TQeAB0AAAAA8LIQAAflNB4AJYAABgsToSocAAAAABAAB+U0HgAXghAAB+U0HgAmgAAGCxOhJ6YAAAAAMAAH5TQeACsAAAYLE6ESfQAAB+U0HgAvAkAAB+U0HgArAAAAADAAAAAwAAYLE6En0AAAB+U0HgA3AAAGCxOhEnMAAAYLE6EScwIwAAflNB4ALwAAAAAwohAAB+U0HgAxAAAGCxOhKbYAAAAAEAAGCxOhEnMCEAAH5TQeADKAAAYLE6EptgAAAAAQAAYLE6EScwIQAAflNB4ANAAABgsToSm2AAAAABAABgsToRJzAhAAB+U0HgA1gAAGCxOhKbYAAAAAEAAGCxOhEnMCMAAH5TQeADcAAAAAkEIQAAflNB4AOQAABgsToSm2AAAAABAAB+U0HgA3AjAAB+U0HgA6gAAAADCg==','base64'));
  await fs.writeFile(path.join(fixtures,'CjprofInstalled.java'),"// Exercise the Java API in the installed jar. No producer classpath is used.\nimport com.cjprof.jni.Cjprof;\nimport java.util.Collections;\n\nclass CjprofInstalled {\n    public static void main(String[] args) {\n        Cjprof.initialize();\n        if (!Cjprof.queryAllHeapSnapshot().isEmpty()) throw new AssertionError(\"unexpected initial snapshot\");\n        if (!Cjprof.parseHeapSnapshotFiles(Collections.singletonList(args[0]))) throw new AssertionError(\"heap file was not parsed\");\n        long id = Cjprof.getSnapshotIDByFilePath(args[0]);\n        if (Cjprof.queryAllHeapSnapshot().size() != 1 || Cjprof.getConstructorNodesBySnapshotID(id).isEmpty())\n            throw new AssertionError(\"heap graph not available through JNI\");\n        Cjprof.cleanHeapSnapshotFiles(Collections.singletonList(id));\n        if (!Cjprof.queryAllHeapSnapshot().isEmpty()) throw new AssertionError(\"cleanup did not remove the snapshot\");\n        System.out.println(\"CJPROF_INSTALLED_HEAP_GRAPH\");\n    }\n}\n");
  async function run(label,program,args,environment) {
    const r=spawnSync(program,args,{cwd:dir,env:environment,encoding:'utf8',timeout:120000});
    await fs.writeFile(path.join(dir,label+'.json'),JSON.stringify({
      argv:[program,...args],cwd:dir,rc:r.status,signal:r.signal,error:r.error?.message,stdout:r.stdout,stderr:r.stderr
    },null,2));
    if(r.error||r.status!==0)throw Object.assign(Error('WINDOWS_CJPROF_PROCESS '+label),{rc:r.status??1});
    return r.stdout;
  }
  const heap=JSON.parse(await run('cli',path.join(sdk,'tools/bin/cjprof.exe'),['heap','-i',input,'--json'],env));
  if(!heap.objects.some(o=>o.retainedSize>o.shallowSize)||!heap.constructors.length)throw Error('WINDOWS_CJPROF_HEAP_GRAPH');
  const lib=path.join(sdk,'tools/lib');
  env=pathEnvironment(env,sdkPlatform('windows-x64'));
  const java=path.join(process.env.JAVA_HOME,'bin/java.exe');
  const out=await run('jni',java,['-Xcheck:jni','-Djava.library.path='+lib,'--class-path',path.join(sdk,'tools/share/java/cjprof.jar'),
    path.join(fixtures,'CjprofInstalled.java'),input],{...env,PATH:[lib,path.join(sdk,'runtime/lib/windows_x86_64_cjnative'),path.join(sdk,'lib/windows_x86_64_cjnative'),env.PATH].join(path.delimiter)});
  if(!out.split(/\r?\n/).includes('CJPROF_INSTALLED_HEAP_GRAPH'))throw Error('WINDOWS_CJPROF_JNI_GRAPH');
}
export function packageCompileOptions(manifest, source = 'cjpm.toml') {
  const fail = why => {
    throw new Error(`${source}: [package] compile-option ${why}`);
  };
  let table = '';
  let value;
  for (const [index, raw] of manifest.split(/\r?\n/).entries()) {
    const line = raw.trim();
    if (line === '' || line.startsWith('#')) continue;
    const header = line.match(/^\[(\[?)\s*([A-Za-z0-9_.-]+)\s*\]\1\s*(?:#.*)?$/);
    if (header) {
      table = header[1] ? `[${header[2]}]` : header[2];
      continue;
    }
    if (table === '' && /^package\s*\.\s*compile-option\s*=/.test(line)) {
      fail(`as a dotted key on line ${index + 1} is not supported`);
    }
    if (table !== 'package') continue;
    const entry = line.match(/^(?:compile-option|"compile-option"|'compile-option')\s*=\s*(.*)$/);
    if (!entry) continue;
    if (value !== undefined) fail(`is defined again on line ${index + 1}`);
    value = decodeString(entry[1], why => fail(`on line ${index + 1} ${why}`));
  }
  return splitArguments(value ?? '', fail);
}

const BASIC_ESCAPES = {b: '\b', t: '\t', n: '\n', f: '\f', r: '\r', '"': '"', '\\': '\\'};

function decodeString(text, fail) {
  let body;
  let rest;
  if (text.startsWith('"""') || text.startsWith("'''")) {
    fail('is a multi-line string, which is not supported');
  } else if (text.startsWith('"')) {
    const match = text.match(/^"((?:[^"\\]|\\.)*)"(.*)$/);
    if (!match) fail('is an unterminated string');
    body = match[1].replace(/\\(?:u([0-9A-Fa-f]{4})|U([0-9A-Fa-f]{8})|(.))/g, (all, short, long, single) => {
      if (single !== undefined) {
        if (!Object.hasOwn(BASIC_ESCAPES, single)) fail(`has an invalid escape ${all}`);
        return BASIC_ESCAPES[single];
      }
      const code = parseInt(short ?? long, 16);
      if (code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff)) fail(`has an invalid escape ${all}`);
      return String.fromCodePoint(code);
    });
    rest = match[2];
  } else if (text.startsWith("'")) {
    const match = text.match(/^'([^']*)'(.*)$/);
    if (!match) fail('is an unterminated string');
    [, body, rest] = match;
  } else {
    fail(`must be a string, found ${JSON.stringify(text)}`);
  }
  if (!/^\s*(?:#.*)?$/.test(rest)) fail(`has unexpected text after the string: ${JSON.stringify(rest.trim())}`);
  return body;
}

function splitArguments(options, fail) {
  const argument = /\s*(?:"((?:[^"\\]|\\.)*)"|'([^']*)'|([^\s"']+))(?=\s|$)/y;
  const result = [];
  let at = 0;
  while (!/^\s*$/.test(options.slice(at))) {
    argument.lastIndex = at;
    const match = argument.exec(options);
    if (!match) fail(`has unsupported quoting near ${JSON.stringify(options.slice(at).trim())}`);
    if (match[1] !== undefined) {
      try {
        result.push(JSON.parse(`"${match[1]}"`));
      } catch {
        fail(`has an invalid escape in the argument "${match[1]}"`);
      }
    } else {
      result.push(match[2] ?? match[3]);
    }
    at = argument.lastIndex;
  }
  return result;
}

const smokeSources={
  '01_hello.cj': "main(): Int64 {\n    println(\"hello from cjcj\")\n    return 0\n}",
  '02_generics.cj': "class Box<T> {\n    let v: T\n    init(x: T) { v = x }\n    func get(): T { v }\n}\n\nfunc firstOf<T>(xs: Array<T>): T { xs[0] }\n\nmain(): Int64 {\n    let b = Box<Int64>(42)\n    let s = Box<String>(\"hi\")\n    println(\"${b.get()} ${s.get()} ${firstOf<Int64>([7, 8, 9])}\")\n    return 0\n}",
  '03_closures.cj': "func adder(n: Int64): (Int64) -> Int64 { { x => x + n } }\n\nmain(): Int64 {\n    let add5 = adder(5)\n    var acc = 0\n    let nums = [1, 2, 3, 4]\n    for (x in nums) { acc += add5(x) }\n    println(acc)\n    return 0\n}",
  '04_iface_enum.cj': "interface Shape { func area(): Float64 }\n\nclass Circle <: Shape {\n    let r: Float64\n    init(r: Float64) { this.r = r }\n    public func area(): Float64 { 3.14 * r * r }\n}\n\nenum Tree { Leaf | Node(Int64, Tree, Tree) }\n\nfunc sum(t: Tree): Int64 {\n    match (t) {\n        case Leaf => 0\n        case Node(v, l, r) => v + sum(l) + sum(r)\n    }\n}\n\nmain(): Int64 {\n    let c: Shape = Circle(2.0)\n    let t = Tree.Node(1, Tree.Node(2, Tree.Leaf, Tree.Leaf), Tree.Leaf)\n    println(\"${c.area()} ${sum(t)}\")\n    return 0\n}",
  '05_ffi.cj': "foreign func abs(i: Int32): Int32\n\nmain(): Int64 {\n    unsafe { println(abs(-7)) }\n    return 0\n}",
  'macro_demo/app/main.cj': "import mymacros.*\n\nmain(): Int64 {\n    @Twice(println(\"tick\"))\n    return 0\n}",
  'macro_demo/mymacros/def.cj': "macro package mymacros\n\nimport std.ast.*\n\npublic macro Twice(input: Tokens): Tokens {\n    return quote($input; $input)\n}",
};
async function installedLanguage(inputs,sdk,p,work,env){
  const root=path.resolve(inputs),runtime=root+'/runtime',unit=runtime+'/tests/gc_unit',bin=sdk+'/bin/cjc';
  const dir=work+'/gc-unit',library=sdk+'/runtime/lib/'+p.tuple,hostRuntime=sdk+'/.compiler-exec/runtime/lib/'+p.tuple;
  ensureDir(dir);
  const status=Object.fromEntries((await fs.readFile(runtime+'/CMakebuild/gc-unit.status','utf8')).trim().split(/\r?\n/).map(s=>[s.split('=')[0],s.slice(s.indexOf('=')+1)]));
  assert.equal(status.GATE,'PASS');assert.equal(status.CPP_SUITE,'PASS');assert.equal(status.LANGUAGE_TESTS,'LANGUAGE_DEFERRED');
  for(const file of [bin,hostRuntime+'/libcangjie-runtime.so',library+'/libcangjie-runtime.so',library+'/libboundscheck.so',sdk+'/runtime/include/schedule.h',
    sdk+'/lib/'+p.tuple+'/libcangjie-std-core.a',sdk+'/third_party/llvm/bin/llc',sdk+'/third_party/llvm/bin/opt'])await fs.access(file);
  const opt={env:{...env,GC_UNIT_SOURCE_ROOT:root,GC_UNIT_OUT:dir,CJC:bin,CANGJIE_HOME:sdk,
    GC_UNIT_CJC_RUNTIME_LIB_DIR:hostRuntime,GCV2_RUNTIME_LIB_DIR:library,GCV2_RUNTIME_OUTPUT_ROOT:sdk+'/runtime',
    GCV2_RUNTIME_BUILD_DIR:runtime+'/CMakebuild',SIGNAL_TEST_OUTPUT:dir+'/so-reentry'}};
  // Use the installed compiler and tuple for the legacy source payloads. The
  // pinned helper expects a producer workspace that is absent after unpacking.
  const scripts=dir+'/payloads';
  await fs.cp(unit,scripts,{recursive:true,filter:f=>path.basename(f)!=='language_toolchain.sh'});
  await fs.writeFile(scripts+'/language_toolchain.sh',[
    'gc_unit_language_admit() { test -x "$CJC" && test -f "$GCV2_RUNTIME_LIB_DIR/libcangjie-runtime.so"; }',
    'gc_unit_language_environment() { export CJC_BIN="$CJC"; }',
    'gc_unit_language_compile() { local rc=0; "$CJC" "$@" || rc=$?; echo "$rc" >> "$GC_UNIT_OUT/compile.rc"; return "$rc"; }',
  ].join('\n')+'\n');
  run('bash',[scripts+'/run_finalizer_trigger.sh'],opt);run('bash',[scripts+'/run_phase_entry_trigger.sh'],opt);
  if(status.SO_REENTRY_BOUNDED_CAN_RUN==='1')run('bash',[unit+'/run_so_reentry_bounded.sh'],opt);
  if(status.SEGMENTED_ARRAY_MANAGED_CAN_RUN==='1'){
    await fs.copyFile(runtime+'/CMakebuild/cj_gc_unit',dir+'/cj_gc_unit');
    run('bash',[scripts+'/run_segmented_array_managed.sh','both'],opt);
  }
}


async function test(a,work) {
  const sdk=path.resolve(a.sdk),p=sdkPlatform(a.platform),platform=p.platform,env=cleanSdkEnvironment(sdk,p.key);
  if(p.os==='win32')env.cjStackSize='64MB';
  const cjc=path.join(sdk,'bin/cjc'+p.exe),cjpm=path.join(sdk,'tools/bin/cjpm'+p.exe);
  const python=await resolveHostPython(sdk),opts={cwd:work,env};
  if(a.mode==='smoke'){
    for(const [file,source] of Object.entries(smokeSources)){
      const f=path.join(work,file);ensureDir(path.dirname(f));await fs.writeFile(f,source);
    }
    const expected=['hello from cjcj','42 hi 7','30','12.560000 3','7'];
    for(const [i,file] of Object.keys(smokeSources).filter(n=>n.startsWith('0')).entries()){
      const binary=path.join(work,path.basename(file,'.cj')+p.exe);
      run(cjc,[file,'-o',binary],opts);assert.equal(runCapture(binary,[],opts).trim(),expected[i],file);
      console.log('PASS smoke '+file);
    }
    const macros=work+'/macro_demo',app=macros+'/app/sample'+p.exe;
    run(cjc,['--compile-macro','def.cj'],{cwd:macros+'/mymacros',env});
    run(cjc,['main.cj','--import-path',macros,'-o',app],{cwd:macros+'/app',env});
    assert.equal(runCapture(app,[],opts).trim().replaceAll('\r\n','\n'),'tick\ntick');
    console.log('PASS smoke 06_macro');
    run(python,['test/store_strength/test_checker.py'],{cwd:repo});
    run(process.execPath,['--test','runtime_shim/tests/compiler_heap_defaults.test.mjs'],{cwd:repo});
  }else if(a.mode==='installed'){
    await fs.writeFile(work+'/hello.cj','main() { println("Hello, Cangjie") }\n');
    const bin=work+'/hello'+p.exe;run(cjc,['hello.cj','-o',bin],opts);
    assert.equal(runCapture(bin,[],opts).trim(),'Hello, Cangjie');
    ensureDir(work+'/src');await fs.writeFile(work+'/src/main.cj','package sdk_hello\nmain() { println("Hello, Cangjie") }\n');
    await fs.writeFile(work+'/cjpm.toml','[package]\nname="sdk_hello"\nversion="1.0.0"\ncjc-version="1.3.0"\noutput-type="executable"\nsrc-dir="src"\ntarget-dir="target"\n');
    run(cjpm,['build','-j',jobs],opts);assert.equal(runCapture(work+'/target/release/bin/main'+p.exe,[],opts).trim(),'Hello, Cangjie');
    await macroInstall({sdk,work,platform});if(sync.existsSync(sdk+'/stdx'))await precompiledStdxMacros({sdk,work,platform});
    if(p.os==='linux'){
      await verifyInstalledRegex({sdk,work,platform});
      if(a['language-inputs'])await installedLanguage(a['language-inputs'],sdk,p,work,env);
    }
    if(p.key==='linux-x64'&&env.JAVA_HOME&&sync.existsSync(sdk+'/lib/library-loader.jar')&&/^javac 17(?:\.|$)/.test(runCapture(env.JAVA_HOME+'/bin/javac',['-version']).trim()))
      await verifyInstalledJava(sdk,work,env.JAVA_HOME);
    const cjdb=sdk+'/tools/bin/cjdb'+p.exe;
    if(sync.existsSync(cjdb)){
      const clean={...env};delete clean.PYTHONHOME;delete clean.PYTHONPATH;
      const observed=runCapture(cjdb,['--batch','--no-lldbinit','-o','script import sys,os; print("VERSION="+str(sys.version_info[:2])); print("PREFIX="+os.path.realpath(sys.prefix))'],{cwd:work,env:clean});
      assert.match(observed,/^VERSION=\(3, 11\)\r?$/m);
      assert.equal(await fs.realpath(/^PREFIX=([^\r\n]+)$/m.exec(observed.replaceAll('\r',''))?.[1]),await fs.realpath(sdk+'/third_party/python'));
    }
    if(p.os==='win32'){
      run(process.execPath,[repo+'/tests/windows_linker_response/linker-response.mjs',cjc,work+'/linker-response'],opts);
      if(sync.existsSync(sdk+'/tools/bin/LSPServer.exe'))await consumeInstalledLspMacro({sdk,work,platform,env});
      if(sync.existsSync(sdk+'/tools/bin/cjlint.exe'))await consumeWindowsLint(sdk,work,env);
      if(sync.existsSync(sdk+'/tools/bin/cjprof.exe'))await consumeWindowsProfiler(sdk,work,env);
    }
    if(a.repo){
      const packages=path.resolve(a.repo,'packages'),imports=sdk+'/share/cjcj/cjo';
      const compile=(args,cwd=work)=>run(cjc,args,{cwd,env,timeout:900000});
      for(const pkg of 'option conditional_compilation mangle frontend_tool incremental_compilation modules driver meta_transformation lex ast frontend cjc basic codegen macro'.split(' ')){
        const manifest=packages+'/'+pkg+'/cjpm.toml';
        compile([...packageCompileOptions(await fs.readFile(manifest,'utf8'),manifest),'--package',packages+'/'+pkg+'/src','--module-name','cjcj','--import-path',imports,'--output-type=staticlib','-o',work+'/'+pkg+'.a']);
      }
      const src=packages+'/conditional_compilation/src',dir=work+'/selfdet';
      const once=async()=>{rmrf(dir);ensureDir(dir);compile(['--emit-chir=raw','--output-type=staticlib','--package',src,'--module-name','cjcj','--import-path',imports,'--trimpath='+src,'-o',dir+'/repeat.a'],dir);
        const files=(await fs.readdir(dir)).filter(n=>n.endsWith('.cjo'));assert.equal(files.length,1);const bytes=await fs.readFile(path.join(dir,files[0]));assert.ok(bytes.length);return bytes;};
      assert.ok((await once()).equals(await once()),'repeated CJO bytes differ');
    }
  }else if(a.mode==='packages'){
    const tree=path.resolve(a.repo||repo),fixture=work+'/objc',producer=sdk+'/libexec/compiler/cjcj-stage1'+p.exe;
    env.OBJC_PREAMBLE_PRODUCER=producer;env.OBJC_PREAMBLE_IMPORTS=fixture+'/imports';Object.assign(env,compilerHeap(p,env));
    run(python,[tree+'/scripts/objc_preamble_unit.py','--prepare-only','--build-tree',tree,'--sdk',sdk,'--producer',producer,'--out',fixture],{cwd:tree,env});
    run(cjpm,['test','-j',jobs,'--no-color','--report-format=xml','--report-path='+work+'/reports','--target-dir',work+'/target'],{cwd:tree,env});
  }else throw Error('unknown test mode '+a.mode);
}
const args=parseCliArgs(),work=await fs.mkdtemp(path.join(os.tmpdir(),'cjcj-tests-'));
try{await test(args,work);rmrf(work);}catch(error){console.error('Test files: '+work);throw error;}
