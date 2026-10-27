#!/usr/bin/env zx
// Read the ordinary producer/install facts for each public tool. No receipt,
// selector relabelling, or successful --help can qualify inherited host bytes.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {isDeepStrictEqual} from 'node:util';
import {fileDigest,readJson,relative} from '../bootstrap/sdk-flow.mjs';
import {sdkPlatform,entryPlatformName} from '../bootstrap/sdk-platform.mjs';
import {TOOL_NAMES,TOOL_PUBLIC_NAMES,TOOL_DIRECTORIES,nativeToolLibraries,toolName} from '../../build/srcbuild/tool-layout.mjs';
// These are the SDK edges of the actual source producers, not the entire SDK
// snapshot recorded for diagnostics. cjprof links its own prof/JNI payload and
// a source-built demangler. cjcompat imports CJO through cangjie-lsp.
// Cangjie cjfmt follows the selected compiler/std/runtime producer inputs. cjlint DOES
// execute cjc --compile-macro and initialize RuntimeInit; LSP enables macro
// expansion. Those two therefore retain compiler/std/runtime pairing, including
// the compiler's separately installed execution runtime when recorded.
const nativeSdkInputs={cjprof:[],cjcompat:['nativeAst'],
  cjlint:['nativeAst','compiler','stdCore','runtime'],lsp:['nativeAst','compiler','stdCore','runtime']};
// These tools load/execute the selected SDK at use time. Their linked native
// AST remains a build dependency. Installing into another SDK does not by
// itself establish that the macro/runtime consumer works with that selection.
export const toolRuntimeInputs=name=>['cjlint','lsp'].includes(toolName(name))
  ?['compiler','stdCore','runtime','compilerEntry','executionRuntime']:[];
export function toolSdkInputs(publicName) {
  const name=toolName(publicName);
  if(!TOOL_NAMES.includes(name))throw Error('unknown source tool: '+publicName);
  return nativeSdkInputs[name]??['compiler','stdCore','runtime',...(name==='hle'?['hleDependencies']:[])];
}
const sha=value=>/^[0-9a-f]{64}$/.test(value??'');
async function bytes(sdk,rel,expected) {
  relative(rel);
  if(!sha(expected))throw Error('missing recorded bytes: '+rel);
  const actual=await fs.realpath(path.join(sdk,rel));
  if(!actual.startsWith(sdk+path.sep))throw Error('payload escapes SDK: '+rel);
  if(await fileDigest(actual)!==expected)throw Error('installed bytes differ: '+rel);
}
export async function toolReadiness(root) {
  const sdk=await fs.realpath(root),result={};
  let inputs,stage,native;
  try {
    inputs=await readJson(path.join(sdk,'TOOLS-INPUTS.json'));
    stage=await readJson(path.join(sdk,'STAGE-INPUTS.json'));
    native=sdkPlatform(stage.platform);
  }catch(error){
    return Object.fromEntries(TOOL_NAMES.map(name=>[TOOL_PUBLIC_NAMES[name]??name,{ready:false,available:false,reason:error.message}]));
  }
  for(const name of TOOL_NAMES) {
    const publicName=TOOL_PUBLIC_NAMES[name]??name,rel='tools/bin/'+publicName+native.exe;
    let applicability;
    try {
      const row=inputs.files?.[rel],facts=row?.producer;
      if(facts?.source?.status!=='resolved'||!facts.source.repository||!/^[0-9a-f]{40}$/.test(facts.source.commit??''))throw Error('target producer source missing');
      if(facts.build?.rc!==0||facts.build.platform!==stage.platform||facts.install?.rc!==0)throw Error('target build/install not recorded');
      const nativeInputs=nativeSdkInputs[name];
      if(nativeInputs) {
        // A public filename alone cannot establish a native producer. Preserve
        // its recorded source/build directory and actual native configuration.
        if(facts.build.directory!==TOOL_DIRECTORIES[name])throw Error('native producer directory differs');
        if(['cjprof','cjcompat','cjlint'].includes(name)) {
          const config=facts.build.nativeConfiguration?.native?.values;
          if(!config?.CMAKE_BUILD_TYPE||!config.CMAKE_CXX_COMPILER)throw Error('native configuration missing');
        }
      }else if(!isDeepStrictEqual(facts.build.inputs?.stage,stage))throw Error('producer SDK selection differs');
      const sdkInputs=toolSdkInputs(name);
      const compilerLoads=nativeInputs?.includes('compiler')?['compilerEntry','executionRuntime'].filter(key=>facts.build.inputs?.artifacts?.[key]):[];
      const runtimeInputs=toolRuntimeInputs(name),installed=runtimeInputs.length?inputs.installationInputs:undefined;
      const changed=[];
      if(installed)for(const key of ['platform','compilerFile','compilerCommit','runtimeCommit']) {
        if(installed.stage?.[key]!==stage[key])throw Error('installed SDK selection differs: '+key);
      }
      for(const key of [...sdkInputs,...compilerLoads]) {
        const built=facts.build.inputs?.artifacts?.[key];
        if(!built?.sdkRelative)throw Error('producer SDK input missing: '+key);
        const input=installed&&runtimeInputs.includes(key)?installed.artifacts?.[key]:built;
        if(!input?.sdkRelative)throw Error('installed SDK input missing: '+key);
        await bytes(sdk,input.sdkRelative,input.sha256);
        if(input.sdkRelative!==built.sdkRelative||input.sha256!==built.sha256)changed.push(key);
      }
      if(installed)for(const key of runtimeInputs.filter(key=>!sdkInputs.includes(key)&&!compilerLoads.includes(key)&&installed.artifacts?.[key])) {
        const input=installed.artifacts[key];await bytes(sdk,input.sdkRelative,input.sha256);changed.push(key);
      }
      applicability={build:facts.build.inputs?.stage,installation:installed?.stage??facts.build.inputs?.stage,
        changedRuntimeInputs:changed,status:changed.length?'NOT_CONSUMED':'BUILD_INPUTS_MATCH'};
      const retained='.target-tools/'+rel;
      if(row.artifact?.path!==retained||row.entry?.path!==rel||row.entry.recipe?.path!==rel+'.entry'
        ||row.artifact.sha256!==row.sha256||facts.install.artifact?.sha256!==row.sha256)throw Error('target body/entry binding differs');
      await bytes(sdk,retained,row.sha256);await bytes(sdk,rel,row.entry.sha256);await bytes(sdk,rel+'.entry',row.entry.recipe.sha256);
      const recipe=(await fs.readFile(path.join(sdk,rel+'.entry'),'utf8')).trimEnd().split('\n');
      const libraries=['third_party/llvm/'+native.llvmDirectory,'runtime/lib/'+native.tuple,'lib/'+native.tuple,'tools/lib'];
      if(!isDeepStrictEqual(recipe,['cjcj-sdk-entry-v1','2',retained,entryPlatformName(stage.platform),'native-target:'+native.arch,...libraries]))throw Error('target loader recipe differs');
      const payloads=facts.install.payloads;
      if(!payloads||typeof payloads!=='object')throw Error('install payload facts missing');
      const required=name==='cjpm'?['tools/config/cangjie-repo.toml']:name==='cjfmt'?['tools/config/cangjie-format.toml']:[];
      if(['cjlint','cjprof'].includes(name)) {
        const built=facts.build.payloads;
        if(!built||!isDeepStrictEqual(Object.keys(built).sort(),Object.keys(payloads).sort()))throw Error('installed native payload set differs from successful build');
        for(const [rel,row]of Object.entries(payloads)) {
          if(!isDeepStrictEqual(row.build,built[rel]))throw Error('installed native payload lacks build input: '+rel);
          if((rel.includes('/config/')||rel.includes('cjprof-jni'))&&row.sha256!==built[rel].sha256)throw Error('installed copied payload differs from build: '+rel);
        }
        for(const key of name==='cjprof'?['json','httplib','runtime','bounds']:['json']) {
          const dep=facts.build.dependencies?.[key];
          if(!dep?.repo||!/^[0-9a-f]{40}$/.test(dep.commit??'')||!sha(dep.changes_sha256))throw Error('native dependency source missing: '+key);
        }
        if(!facts.build.nativeConfiguration?.native?.values?.CMAKE_BUILD_TYPE)throw Error('native configuration missing');
        if(name==='cjprof') {
          const parent=facts.build.nativeConfiguration.native.values,jni=facts.build.nativeConfiguration.jni?.values;
          if(!jni||jni.CMAKE_BUILD_TYPE!==parent.CMAKE_BUILD_TYPE||!parent.CJPROF_TARGET||jni.CJPROF_TARGET!==parent.CJPROF_TARGET)throw Error('JNI configuration differs');
          const lib=Object.entries(built).find(([rel])=>/\/libcjprof\.(so|dylib)$/.test(rel)||rel==='tools/lib/cjprof.dll')?.[1];
          if(!lib||jni.CJPROF_LIBRARY!==lib.source)throw Error('JNI parent library differs');
        }
        required.push(...nativeToolLibraries(name,native.os).map(row=>row.to));
        if(!Object.keys(payloads).some(rel=>rel.startsWith(name==='cjprof'?'tools/config/static/':'tools/config/')&&(name!=='cjlint'||rel.endsWith('.json'))))throw Error('installed configuration absent');
      }
      if(name==='cjprof')for(const rel of Object.keys(payloads).filter(rel=>rel.startsWith('tools/config/static/')))required.push('.target-tools/'+rel);
      for(const rel of required)if(!payloads[rel])throw Error('required payload absent: '+rel);
      for(const [rel,payload]of Object.entries(payloads)) {
        if(inputs.payloadFiles?.[rel]?.sha256!==payload.sha256||!inputs.payloadFiles[rel].producers?.includes(name))throw Error('payload producer differs: '+rel);
        await bytes(sdk,rel,payload.sha256);
      }
      if(name==='hle') {
        const deps=await readJson(path.join(sdk,'tools/dtsparser/DEPENDENCIES.json'));
        if(deps.platform!==stage.platform)throw Error('HLE dependency platform differs');
        for(const [key,rel]of [['node','tools/bin/node'+native.exe],['cjbind','tools/dtsparser/node_modules/.bin/cjbind'+native.exe]]) {
          if(!deps[key]?.source||!deps[key]?.version)throw Error('HLE dependency source missing: '+key);
          await bytes(sdk,rel,deps[key].sha256);
        }
        const parser=await readJson(path.join(sdk,'tools/dtsparser/package.json'));
        for(const [name,version]of Object.entries(parser.dependencies)) {
          const actual=await readJson(path.join(sdk,'tools/dtsparser/node_modules',name,'package.json'));
          if(actual.name!==name||actual.version!==version.replace(/^npm:[^@]+@/,''))throw Error('HLE module differs: '+name);
        }
      }
      result[publicName]={ready:!changed.length,available:true,
        reason:changed.length?'current native SDK consumer not run: '+changed.join(','):'actual target producer/install inputs and bytes match; semantic probe still required',
        source:facts.source,applicability};
    }catch(error){result[publicName]={ready:false,available:false,reason:error.message,...(applicability?{applicability}:{})};}
  }
  return result;
}
if(process.argv[1]===fileURLToPath(import.meta.url)) {
  try {console.log(JSON.stringify(await toolReadiness(process.argv[2])));}
  catch(error){console.error(error.message);process.exitCode=1;}
}
