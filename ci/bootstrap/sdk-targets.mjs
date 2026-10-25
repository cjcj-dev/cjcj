// The eight public bootstrap phases are an ordinary target dependency table.
import path from 'node:path';
import fs from 'node:fs/promises';
import {relative} from './sdk-flow.mjs';
import {isDeepStrictEqual} from 'node:util';
import {fileURLToPath} from 'node:url';
import {sdkPlatform} from './sdk-platform.mjs';
import {readHostToolchainPin} from '../host-toolchain-pin.mjs';
export const BOOTSTRAP_PHASES=Object.freeze(['stage0','stage0-run','std-bootstrap','stage1-initial','stage1-std','stage2','stage3-std','stage3']);
import {readSourcePins} from '../native-llvm-inputs.mjs';
// SDK defaults consume the same source pins as the workflow producers.
const pins=readSourcePins();
export const FIXED_INPUTS=Object.freeze({llvm:pins.llvm.LLVM_SHA,
  compiler:pins.source.COMPILER_REF,bounds:pins.source.BOUNDS_REF,
  runtime:pins.runtime.RUNTIME_REF,flatbuffers:pins.llvm.FLATBUFFERS_SHA,
  h1:'83901791548856f0458f3e3e38c4c1ab7ac496c5',host:readHostToolchainPin().replace(/^nightly-/, '')});
const stageEntry=fileURLToPath(new URL('./sdk-native-stage.mjs',import.meta.url));
const verifyEntry=fileURLToPath(new URL('./sdk-verify-install.mjs',import.meta.url));
// A tool update's pending consumer needs the compiler and its actual execution
// closure. Copy those dependencies for use, never a backup of the whole SDK.
export async function toolConsumerCopies(sdk,platform) {
  const native=sdkPlatform(platform),recipe=(await fs.readFile(path.join(sdk,'bin/cjcj-stage1'+native.exe+'.entry'),'utf8')).trimEnd().split('\n');
  if(recipe[0]!=='cjcj-sdk-entry-v1')throw Error('TOOL_CONSUMER_COMPILER_ENTRY');
  const paths=new Set(['bin','libexec','runtime','lib','modules','third_party','.native-tools','include','schema','share/cjcj',
    'STAGE-INPUTS.json','compiler-inputs.json','PROVENANCE.txt','RUNTIME-INPUTS.json',
    ...recipe.slice(5).filter(rel=>rel.startsWith('.host/')||rel.startsWith('.compiler-exec/'))]);
  const copies=[];
  for(const rel of paths) {
    relative(rel);
    const from=path.join(sdk,rel);
    try { await fs.lstat(from);copies.push({from,to:rel,owner:'installed tool consumer dependency'}); }
    catch(error) { if(error.code!=='ENOENT')throw error; }
  }
  return copies;
}
// The sole SDK layout recipe. Callers select actual producer artifacts and an
// execution role; they never enumerate loader paths, retained ELF names or aliases.
export function installationRecipe(selection,{compiler:product,std,bootstrap=false,hostObjects=false,final=false,nativeChecks,tools,layout}={}) {
  const {platform,bootstrapHost:host,compilerExecution:execution,targetComponents:target}=selection;
  const native=sdkPlatform(platform),tuple=native.tuple,exe=native.exe;
  const nLib=['third_party/llvm/'+native.llvmDirectory,'runtime/lib/'+tuple,'lib/'+tuple,'tools/lib'];
  if(tools)return {copies:[...tools.rows,...tools.payloads].map(row=>({...row,owner:'source-built tools'})),
    entries:[{directory:'tools/bin',retain:'.target-tools/tools/bin',names:tools.rows.map(row=>row.name),libraries:nLib}],links:{}};
  const {llvm,runtime,ast}=target;
  product??=target.compiler.product;std??=target.std.install;
  const compilerName='bin/cjcj-stage1'+exe;
  const prefix=execution.role==='bootstrap-host'?'.host':execution.role==='separate'?'.compiler-exec':'';
  const executionNative=sdkPlatform(execution.platform??platform),execTuple=executionNative.tuple;
  const executionLibraries=[prefix?prefix+'/runtime/lib/'+execTuple:'runtime/lib/'+execTuple,
    prefix?prefix+'/lib/'+execTuple:'lib/'+execTuple,
    prefix?prefix+'/third_party/llvm/'+executionNative.llvmDirectory:'third_party/llvm/'+executionNative.llvmDirectory,'tools/lib'];
  const hostToolLib=['.host/runtime/lib/'+tuple,'.host/lib/'+tuple,'.host/third_party/llvm/'+native.llvmDirectory,'.host/tools/lib'];
  const copies=[
    ...(bootstrap?[
      {from:host.install,to:'.host',owner:'H',exclude:['SDK.lock.json']},
      {from:host.install,to:'',owner:'H',exclude:['SDK.lock.json','schema','STAGE-INPUTS.json','BUILD-MANIFEST.json','compiler-lineage.json',
        'bin/cjc'+exe,'bin/cjc-frontend'+exe,'third_party/llvm','tools/bin/cjdb'+exe,'tools/bin/chir-dis'+exe,'tools/bin/LSPMacroServer'+exe,'tools/lib',
        ...(hostObjects?['include/cangjie','include/flatbuffers']:['include']),'third_party/flatbuffers',
        ...(llvm.windowsToolchain?.installedFiles.filter(row=>row.path.startsWith('bin/')).map(row=>row.path)||[]),
        ...(hostObjects?[]:['modules','lib','runtime','bin','tools'])]},
    ]:[]),
    {from:llvm.install+'/third_party/llvm',to:'third_party/llvm',owner:'N'},
    {from:llvm.install+'/tools',to:'tools',owner:'N'},
    ...(!hostObjects?[{from:llvm.install+'/lib/'+tuple,to:'lib/'+tuple,owner:'N',exclude:['libcangjie-ast-support.a','libboundscheck-static.a']}]:[]),
    ...(ast?[
      {from:ast.install+'/include',to:'include',owner:'AST'},
      {from:ast.install+'/schema',to:'schema',owner:'schema'},
      {from:ast.install+'/third_party/flatbuffers',to:'third_party/flatbuffers',owner:'AST',...(!hostObjects?{exclude:['modules']}:[])},
      ...(!final||ast.astInstallation?[{from:path.join(ast.install,ast.astInstallation?.library??'libcangjie-ast-support.a'),to:'lib/'+tuple+'/libcangjie-ast-support.a',owner:'AST'}]:[]),
    ]:[]),
    ...(!hostObjects?[
      {from:runtime.install,to:'',owner:'R',exclude:['RUNTIME-INPUTS.json','NATIVE-INPUTS.json','SOURCE_SHA',...(ast?['include']:[])]},
      {from:std,to:'',owner:'std',exclude:['lib/'+tuple+'/libboundscheck'+native.shared,'third_party','schema','include','lib/'+tuple+'/libcangjie-ast-support.a']},
      {from:std+'/third_party/flatbuffers/modules',to:'third_party/flatbuffers/modules',owner:'std'},
    ]:[]),
    ...(!bootstrap&&prefix?[
      {from:execution.runtime.install+'/runtime/lib/'+execTuple,to:prefix+'/runtime/lib/'+execTuple,owner:'compiler execution runtime'},
      {from:execution.std.install+'/lib/'+execTuple,to:prefix+'/lib/'+execTuple,owner:'compiler execution std'},
      {from:execution.llvm.install+'/third_party/llvm/'+executionNative.llvmDirectory,to:prefix+'/third_party/llvm/'+executionNative.llvmDirectory,owner:'compiler execution LLVM'},
    ]:[]),
    ...(bootstrap&&execution.role==='separate'?[
      {from:execution.runtime.install+'/runtime',to:prefix+'/runtime',owner:'compiler execution runtime'},
      {from:execution.std.install+'/lib',to:prefix+'/lib',owner:'compiler execution std'},
      {from:execution.llvm.install+'/third_party/llvm/'+native.llvmDirectory,to:prefix+'/third_party/llvm/'+native.llvmDirectory,owner:'compiler execution LLVM'},
    ]:[]),
    {from:product,to:compilerName,owner:'compiler'},
  ];
  if(layout==='native-output') {
    // The original build.py compiler/runtime/std outputs are internal build
    // inputs. Preserve their native dependency closure, replacing only public
    // compiler entries through the same installer as the bootstrap graph.
    copies.splice(0,copies.length,
      {from:target.compiler.install,to:'',owner:'native compiler/runtime/std producers',
        exclude:['bin/cjc'+exe,'bin/cjc-frontend'+exe,'STAGE-INPUTS.json']},
      ...(!prefix?[]:[
        {from:execution.runtime.install+'/runtime/lib/'+execTuple,to:prefix+'/runtime/lib/'+execTuple,owner:'compiler execution runtime'},
        {from:execution.std.install+'/lib/'+execTuple,to:prefix+'/lib/'+execTuple,owner:'compiler execution std'},
        {from:execution.llvm.install+'/third_party/llvm/'+executionNative.llvmDirectory,to:prefix+'/third_party/llvm/'+executionNative.llvmDirectory,owner:'compiler execution LLVM'}]),
      {from:host.install+'/runtime/lib/'+sdkPlatform(host.platform??platform).tuple,to:'.host/runtime/lib/'+sdkPlatform(host.platform??platform).tuple,owner:'bootstrap host comparison runtime'},
      {from:product,to:compilerName,owner:'compiler'});
  }
  // These repository tools belong to the installation, before pending
  // consumers run. Packaging only archives this same installed directory.
  const scripts=['check_sdk_usable.mjs','verifier_artifact_gate.mjs'];
  for(const copy of copies) {
    if(copy.to===''||copy.to==='tools')copy.exclude=[...(copy.exclude??[]),
      ...scripts.map(name=>(copy.to===''?'tools/':'')+name)];
  }
  copies.push(...scripts.map(name=>({from:fileURLToPath(new URL('../../scripts/'+name,import.meta.url)),
    to:'tools/'+name,owner:'repository SDK tools'})));
  if(nativeChecks)copies.push(
    {from:nativeChecks+'/llvm/native-input-result.json',to:'share/cjcj/build-inputs/native-llvm.json',owner:'native LLVM checks'},
    {from:llvm.buildResult,to:'share/cjcj/build-inputs/native-build.json',owner:'native LLVM build'},
    ...(!hostObjects?[{from:nativeChecks+'/runtime/RUNTIME-INPUTS.json',to:'RUNTIME-INPUTS.json',owner:'runtime inputs'}]:[]),
    ...(ast?.astInstallation&&ast.buildResult!==llvm.buildResult?[{from:ast.buildResult,to:'share/cjcj/build-inputs/native-ast.json',owner:'AST inputs'}]:[]));
  if(llvm.windowsToolchain)copies.push(
    {from:path.join(llvm.install,relative(llvm.windowsToolchain.original.path)),to:relative(llvm.windowsToolchain.original.path),owner:'native toolchain input'},
    ...llvm.windowsToolchain.installedFiles.filter(row=>row.path.startsWith('bin/')).map(row=>({from:path.join(llvm.install,relative(row.path)),to:relative(row.path),owner:'native toolchain runtime'})));
  return {copies,entries:[
    {directory:'bin',retain:'libexec/compiler',names:['cjcj-stage1'+exe],libraries:executionLibraries},
    ...(bootstrap&&hostObjects?[
      {directory:'bin',retain:'.host-tools/bin',exclude:['cjcj-stage1'+exe,...(hostObjects?[]:['cjfilt'+exe]),...(llvm.windowsToolchain?.installedFiles.filter(row=>row.path.startsWith('bin/')).map(row=>path.basename(row.path))||[])],libraries:hostToolLib},
      {directory:'tools/bin',retain:'.host-tools/tools/bin',exclude:['cjdb'+exe,'chir-dis'+exe,'LSPMacroServer'+exe],libraries:hostToolLib},
      ...(!hostObjects?[{directory:'bin',retain:'.native-tools/bin',names:['cjfilt'+exe],libraries:nLib}]:[]),
    ]:[]),
    {directory:'tools/bin',retain:'.native-tools/tools/bin',names:['cjdb'+exe,'chir-dis'+exe,'LSPMacroServer'+exe],libraries:nLib},
    {directory:'third_party/llvm/bin',retain:'.native-tools/third_party/llvm/bin',libraries:nLib,exclude:llvm.windowsToolchain?.installedFiles.filter(row=>row.path.startsWith('third_party/llvm/bin/')).map(row=>path.basename(row.path))||[]},
  ],links:{['bin/cjc'+exe]:'cjcj-stage1'+exe,['bin/cjc-frontend'+exe]:'cjcj-stage1'+exe,
    ['libexec/compiler/cjc'+exe]:'cjcj-stage1'+exe,['libexec/compiler/cjc-frontend'+exe]:'cjcj-stage1'+exe,
    'libexec/runtime':prefix?'../'+prefix+'/runtime':'../runtime'}};
}
export function bootstrapPhases(input) {
  const phases=input.stage2 ? ['stage2','stage3-std','stage3'] : [...BOOTSTRAP_PHASES];
  return input.deliveryStage==='stage2-target-sdk' ? [...phases.slice(0,-1),'stage2-target-sdk'] : phases;
}
export function createBootstrapTargets(input) {
  const {work,install,platform,host,llvm,runtime,ast,h1,compiler,stdlib,tools}=input;
  const finalStage=input.deliveryStage??'stage3';
  if(!['stage3','stage2-target-sdk'].includes(finalStage))throw new Error('TARGET_DELIVERY_STAGE');
  const native=sdkPlatform(platform),tuple=native.tuple,exe=native.exe;
  const runtimeCommit=input.runtimeCommit ?? FIXED_INPUTS.runtime;
  if(typeof runtimeCommit!=='string'||!/^[a-f0-9]{40}$/.test(runtimeCommit))throw new Error('TARGET_SOURCE runtime commit');
  for(const [name,row]of Object.entries({llvm,runtime,ast,h1})) {
    const expected=name==='runtime'?runtimeCommit:name==='llvm'?(input.llvmCommit??FIXED_INPUTS.llvm)
      :name==='ast'?(input.astCommit??FIXED_INPUTS.compiler):FIXED_INPUTS[name];
    if (!/^[a-f0-9]{40}$/.test(expected || '')) throw new Error('TARGET_SOURCE '+name);
    if(row.commit!==expected)throw new Error('TARGET_SOURCE '+name);
  }
  const stdlibCommit=input.stdlibCommit===undefined?runtimeCommit:input.stdlibCommit;
  if(typeof stdlibCommit!=='string'||!/^[a-f0-9]{40}$/.test(stdlibCommit))throw new Error('TARGET_SOURCE stdlib commit');
  if(stdlib.commit!==stdlibCommit||!/^[0-9a-f]{40}$/.test(compiler.commit))throw new Error('TARGET_SOURCE std/compiler');
  if(input.stdlibCommit===undefined&&(stdlib.tree!==runtime.tree || stdlib.repository!==runtime.repository))throw new Error('TARGET_SOURCE std/runtime');
  if(input.nativeTargets)throw new Error('TARGET_NATIVE_OVERRIDE');
  if (input.nativePair && (input.nativePair.llvm !== llvm.commit || input.nativePair.runtime !== runtime.commit
    || !/^\d+\.\d+\.\d+-alpha\.\d+$/.test(input.nativePair.hostVersion || ''))) throw new Error('TARGET_NATIVE_PAIR');
  if(host.version!==(input.nativePair?.hostVersion ?? readHostToolchainPin(platform).replace(/^nightly-/,'')))throw new Error('TARGET_HOST_VERSION');
  const out=id=>'${output.'+id+'}';
  const repo=id=>'${repo.'+id+'}';
  const stageArg=(kind,source,sdk,output,phase,compilerRuntime)=>({argv:[process.execPath,stageEntry,'--kind',kind,'--source',source,
    '--sdk',sdk,'--runtime',runtime.install,'--output',output,'--platform',platform,
    '--commit',kind==='h1'?h1.commit:kind==='std'?stdlib.commit:compiler.commit,
    ...(phase?['--phase',phase,'--std-input',phase==='stage3'?out('stage3-std'):path.join(work,'build/stage1-std/std')]:[]),...(compilerRuntime?['--compiler-runtime',compilerRuntime]:[]),
    ...(kind==='h1'?['--host',host.install,'--private-tools',tools.privateRoot,...(tools.cc?['--cc',tools.cc]:[])]:[]),...(tools.zx?['--zx',tools.zx]:[])]});
  const compilerName='bin/cjcj-stage1'+exe;
  function composed(id,depends,product,std,hostObjects=false,commands=[]) {
    const transitional=['stage0-run','stage1-initial','stage1-std'].includes(id);
    const executionSource=id==='stage2-target-sdk'?out('stage2'):transitional?host.install:null;
    const execution={role:id==='stage2-target-sdk'?'separate':transitional?'bootstrap-host':'target',stage:id,
      ...Object.fromEntries(['compiler','runtime','std','llvm'].map(name=>[name,{install:executionSource||(name==='runtime'?runtime.install:name==='llvm'?llvm.install:std),platform}]))};
    const selection={platform,bootstrapHost:host,compilerExecution:execution,targetComponents:{compiler,std:stdlib,runtime,llvm,ast}};
    const recipe=installationRecipe(selection,{compiler:product,std,hostObjects,final:['stage3','stage2-target-sdk'].includes(id),bootstrap:true,nativeChecks:path.join(work,'native-check')});
    return {id,depends,commands,output:id===finalStage?'${install}':path.join(work,'sdk-'+id),...recipe,
      copies:[...recipe.copies,...(['stage2','stage3'].includes(id)?[
        {from:'${build}/compiler/share/cjcj',to:'share/cjcj',owner:'compiler',exclude:['build-inputs']},
        {from:'${build}/compiler/compiler-inputs.json',to:'compiler-inputs.json',owner:'compiler'}]:[])],
      metadata:{phase:id,platform,compilerRole:hostObjects||['stage1-initial','stage1-std'].includes(id)?'transitional-ordinary-compiler':'r-host-compiler',
        macroSdk:hostObjects||['stage1-initial','stage1-std'].includes(id)?'UNSUPPORTED':'REQUIRES_INSTALLED_GATE',compilerFile:'libexec/compiler/cjcj-stage1'+exe,runtimeCommit:runtime.commit,
        compilerCommit:['stage0-run','stage1-initial','stage1-std'].includes(id)?h1.commit:compiler.commit,stdSource:std,
        sources:{compiler:{repository:['stage0-run','stage1-initial','stage1-std'].includes(id)?h1.repository:compiler.repository,
          commit:['stage0-run','stage1-initial','stage1-std'].includes(id)?h1.commit:compiler.commit},
          std:hostObjects?{status:'unresolved',reason:'host SDK std; see host input'}:{repository:stdlib.repository,commit:stdlib.commit},
          runtime:{repository:runtime.repository,commit:runtime.commit},llvm:{repository:llvm.repository,commit:llvm.commit},
          ...(ast.astInstallation?{ast:{repository:ast.sourceRepository??ast.repository,commit:ast.commit}}:{})},
        configuration:{platform,phase:id,compilerRuntime:hostObjects||['stage1-initial','stage1-std'].includes(id)?'host':'target'}}};
  }
  const repos={};
  for(const [id,row]of Object.entries({h1,compiler2:compiler,compiler3:compiler,std0:stdlib,stdBootstrap:stdlib,std1:stdlib}))
    if(!(id==='h1'&&h1.product))repos[id]={root:row.repository,commit:row.commit,tree:row.tree,checkout:path.join(work,'sources',id)};
  const check=fileURLToPath(new URL('./sdk-native-input-check.mjs',import.meta.url));
  const nativeTargets=Object.entries({llvm,runtime,ast}).map(([name,row])=>({
    id:{llvm:'nativeN',runtime:'nativeR',ast:'nativeAST'}[name],output:row.install,
    reuse:{commit:row.commit,tree:row.tree,configuration:row.configuration,source:row.buildResult,
      ...(name==='llvm'?{targets:native.nativeTargets}:{}),
      ...(name==='runtime'?{target:'runtime build.py build/install'}:{}),
      ...(name==='ast'?{targets:['cangjie-ast-support']}:{})},
    ...(name==='ast'&&!row.astInstallation?{}:{test:{commands:[{argv:[process.execPath,check,JSON.stringify({...row.verification,
      kind:name,install:row.install,commit:row.commit,repository:row.repository,sourceRepository:row.sourceRepository,sourceRoot:row.sourceRoot,configuration:row.configuration,
      ...(name==='ast'?{buildResult:row.buildResult,llvmCommit:llvm.commit}:{}),
      ...(name==='llvm'?{buildResult:row.buildResult}:{}),
      platform,work:path.join(work,'native-check',name)})]}]}})
  }));
  const stages=[...nativeTargets,
    {id:'stage0',depends:nativeTargets.map(s=>s.id),
      ...(h1.product?{reuse:{commit:h1.commit,configuration:h1.configuration,source:h1.buildResult},copies:[{from:h1.product,to:compilerName}]}:
        {commands:[stageArg('h1',repo('h1'),llvm.install,'${output}')]} )},
    composed('stage0-run',['stage0'],out('stage0')+'/'+compilerName,null,true),
    {id:'std-bootstrap',depends:['stage0-run'],commands:[stageArg('std',repo('std0'),out('stage0-run'),'${output}',null,'host')]},
    composed('stage1-initial',['std-bootstrap'],out('stage0')+'/'+compilerName,out('std-bootstrap')),
    composed('stage1-std',['stage1-initial'],out('stage0')+'/'+compilerName,'${build}/std',false,
      [stageArg('std',repo('stdBootstrap'),out('stage1-initial'),'${build}/std',null,'host')]),
    composed('stage2',['stage1-std'], '${build}/compiler/'+compilerName,path.join(work,'build/stage1-std/std'),false,
      [stageArg('compiler',repo('compiler2'),out('stage1-std'),'${build}/compiler','stage2')]),
    {id:'stage3-std',...(input.finalStd?{output:input.finalStd}:{}),depends:['stage2'],commands:[stageArg('std',repo('std1'),out('stage2'),'${output}',null,'target')]},
    composed('stage3',['stage3-std'],'${build}/compiler/'+compilerName,out('stage3-std'),false,
      [stageArg('compiler',repo('compiler3'),out('stage2-target-sdk'),'${build}/compiler','stage3')])];
  if(input.stage2) {
    const reused=input.stage2;
    if(!/^[a-f0-9]{40}$/.test(reused.compilerCommit)||reused.parentCommit!==h1.commit||reused.llvmCommit!==llvm.commit
        ||!reused.compilerInputs||!reused.bootstrapStd||!reused.buildResult)throw new Error('TARGET_C2_REUSE_INPUT');
    const stage=stages.find(s=>s.id==='stage2');
    stage.depends=nativeTargets.map(s=>s.id);
    stage.reuse={...reused};
    delete stage.commands;
    const recipe=installationRecipe({platform,bootstrapHost:host,compilerExecution:{role:'target'},targetComponents:{compiler,std:stdlib,runtime,llvm,ast}},
      {compiler:path.join(reused.install,'libexec/compiler/cjcj-stage1'+exe),std:reused.bootstrapStd,bootstrap:true,nativeChecks:path.join(work,'native-check')});
    stage.copies=[...recipe.copies,
      {from:path.join(reused.install,'share/cjcj'),to:'share/cjcj',owner:'compiler',exclude:['build-inputs']},
      {from:reused.compilerInputs,to:'compiler-inputs.json',owner:'compiler'}];
    stage.metadata={...stage.metadata,compilerCommit:reused.compilerCommit,stdSource:reused.bootstrapStd,
      sources:{...stage.metadata.sources,compiler:{repository:compiler.repository,commit:reused.compilerCommit},
        std:{repository:runtime.repository}},
      compilerOriginRuntimeCommit:reused.bootstrapRuntimeCommit,parentCommit:reused.parentCommit,llvmCommit:reused.llvmCommit};
    for(const id of ['h1','compiler2','std0','stdBootstrap'])delete repos[id];
    for(let i=stages.length-1;i>=0;i--)if(['stage0','stage0-run','std-bootstrap','stage1-initial','stage1-std'].includes(stages[i].id))stages.splice(i,1);
  }
  // One installed C2/target-std composition is both a deliverable and C3's input.
  // C2 executes against its own copied libraries; target modules/libraries stay
  // at the SDK root for compilation. No external runtime symlink or env fallback.
  const c2Target=composed('stage2-target-sdk',['stage2','stage3-std'],out('stage2')+'/libexec/compiler/cjcj-stage1'+exe,out('stage3-std'));
  c2Target.copies.push(
    {from:out('stage2')+'/share/cjcj',to:'share/cjcj',owner:'compiler',exclude:['build-inputs']},
    {from:out('stage2')+'/compiler-inputs.json',to:'compiler-inputs.json',owner:'compiler'});
  c2Target.metadata={...c2Target.metadata,compilerCommit:input.stage2?.compilerCommit??compiler.commit,
    sources:{...c2Target.metadata.sources,compiler:{repository:compiler.repository,commit:input.stage2?.compilerCommit??compiler.commit}},
    compilerPhase:'stage2',compilerExecutionSource:out('stage2')};
  stages.splice(stages.findIndex(s=>s.id==='stage3'),0,c2Target);
  stages.find(s=>s.id==='stage3').depends=['stage2-target-sdk'];
  if(finalStage==='stage2-target-sdk') {
    stages.splice(stages.findIndex(s=>s.id==='stage3'),1);
    delete repos.compiler3;
  }
  stages.find(s=>s.id==='stage3-std').test={commands:[{argv:[process.execPath,
    fileURLToPath(new URL('./sdk-final-std.mjs',import.meta.url)), '--sdk',out('stage2'),
    '--std','${output}','--runtime',runtime.install,'--host',out('stage2')+'/.host',
    '--platform',platform,'--work','${work}/final-std-consumers']}]};
  // The original Linux language obligation consumes the final installed
  // compiler/runtime, after std install and before the source phase handoff.
  // R's normal install carries its actual language scripts and build inputs.
  for(const stage of stages.filter(s=>['stage2-target-sdk','stage3'].includes(s.id))) {
    if(native.os==='linux')stage.test={commands:[{argv:[process.execPath,
      fileURLToPath(new URL('./sdk-installed-language.mjs',import.meta.url)),
      '--sdk','${output}','--platform',platform,'--host','${output}/.host','--work','${work}/'+stage.id+'-language']}]};
  }
  // The first macro consumer is AFTER C2 has been built and installed. H/H1
  // remain ordinary bootstrap tools; no macro gate is a C2 production input.
  for (const id of ['stage2','stage2-target-sdk','stage3'].filter(id=>stages.some(s=>s.id===id))) {
    const stage=stages.find(s=>s.id===id);
    stage.test={...stage.test,commands:[...(stage.test?.commands||[]),
      {argv:[process.execPath,verifyEntry,'--sdk','${output}',
        '--work','${work}/'+id+'-consumers','--platform',platform,'--compiler-only',...(id==='stage2'?[]:['--final-std'])]}]};
  }
  // phase dependencies include their original compiler/std input; no receipt graph.
  if(!input.stage2)stages.find(s=>s.id==='stage2').depends.push('stage1-initial');
  const test={required:[compilerName,'modules/'+tuple+'/std/std.core.cjo',
    'runtime/lib/'+tuple+'/libcangjie-runtime'+native.shared],commands:[{argv:[process.execPath,verifyEntry,'--sdk','${install}',
      '--work','${work}/final-consumers','--platform',platform,'--compiler-only','--final-std']}]};
  return {bootstrapInputs:structuredClone(input),work,install,platform,repos,stages,finalStage,test,tools:{launcher:tools.launcher,cxx:tools.cxx},
    archive:input.archive||path.join(work,'sdk.'+(native.os==='win32'?'zip':'tar.gz')),archiveFormat:native.os==='win32'?'zip':'tar.gz',
    toolchain:host,variables:input.variables||{}};
}

// Explicit target files and generated files use the same recipe and source tuple.
// Checking before buildFlow starts prevents changing a command or dropping a native check.
export function validateBootstrapTargets(config) {
  if(!config.bootstrapInputs)throw new Error('BOOTSTRAP_INPUTS_REQUIRED');
  const expected=createBootstrapTargets(config.bootstrapInputs);
  if(!isDeepStrictEqual(JSON.parse(JSON.stringify(config)),JSON.parse(JSON.stringify(expected))))throw new Error('BOOTSTRAP_TARGET_INPUT_MISMATCH');
}
