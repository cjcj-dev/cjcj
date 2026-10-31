#!/usr/bin/env zx
import {readInstalledNativeShim} from './native-shim-inputs.mjs';
// Turn received native installations and real Git objects into build inputs.
// The descriptor contains locations, not producer receipts or SDK authorities.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify, isDeepStrictEqual} from 'node:util';
import {randomUUID} from 'node:crypto';
import {atomicJson, readJson, privateRoot, fileDigest} from './sdk-flow.mjs';
import {FIXED_INPUTS} from './sdk-targets.mjs';
import {sdkPlatform} from './sdk-platform.mjs';
import {stage2Input} from './sdk-stage2-input.mjs';
import {receiveNativeRuntime} from './native-runtime-input.mjs';
import {languageSourceInputs} from '../../build/srcbuild/installed-language-source.mjs';
import {hostPlatform, readHostToolchainPin, hostToolchainFromCjcVersion} from '../host-toolchain-pin.mjs';
import {runtimeSourceRepository} from '../../build/lib/runtime-source-inputs.mjs';
import {readInstalledNativeAst} from './installed-native-ast.mjs';
import {installPath as mingwInstallPath} from '../../build/toolchain/mingw.mjs';
import {installationSelection,resolveSources} from './native-source-selection.mjs';
const execute = promisify(execFile);

export async function gitInput(repository, commit) {
  if (!repository || !/^[0-9a-f]{40}$/.test(commit)) throw new Error('NATIVE_SOURCE_REQUIRED');
  const root = path.resolve(repository);
  const git = async value => (await execute('git', ['-C', root, 'rev-parse', '--verify', value])).stdout.trim();
  const actual = await git(commit + '^{commit}'), tree = await git(commit + '^{tree}');
  if (actual !== commit) throw new Error('NATIVE_SOURCE_COMMIT');
  return {repository:root, commit:actual, tree};
}
async function installation(root, required) {
  if (!root) throw new Error('NATIVE_INSTALL_REQUIRED');
  root = path.resolve(root);
  for (const rel of required) if (!(await fs.stat(path.join(root, rel))).isFile())
    throw new Error('NATIVE_INSTALL_FILE ' + rel);
  return root;
}
// Validate the actual selected source objects, including an explicit inputs file.
// The compiler's macro consumer must be this paired source, not an older C tree.
export async function validateSourceInputs(input) {
  if (input.nativePair) await receiveNativeRuntime({root:input.runtime.install,sourceRoot:input.runtime.sourceRoot,
    sourceRepository:input.runtime.sourceRepository??await runtimeSourceRepository(input.runtime.repository),configuration:input.runtime.configuration,
    platform:input.platform,llvmCommit:input.llvm.commit,runtimeCommit:input.runtime.commit,
    hostVersion:input.host.version,work:input.work});
  const expectedMacro=await fs.readFile(new URL('../../packages/macro/src/InvokeUtil.cj',import.meta.url),'utf8');
  for(const [name,row] of Object.entries({llvm:input.llvm,runtime:input.runtime,stdlib:input.stdlib??input.runtime,ast:input.ast,h1:input.h1,compiler:input.compiler})) {
    const actual=await gitInput(row.repository,row.commit);
    if(actual.tree!==row.tree)throw new Error('NATIVE_SOURCE_TREE '+name);
    if(name==='h1'||name==='compiler') {
      const {stdout}=await execute('git',['-C',row.repository,'show',row.commit+':packages/macro/src/InvokeUtil.cj']);
      if(stdout!==expectedMacro)throw new Error('NATIVE_MACRO_SOURCE '+name);
    }
  }
  if(input.stage2) {
    const actual = await stage2Input(input.stage2,input);
    if(!isDeepStrictEqual(actual,input.stage2))throw new Error('C2_REUSE_INPUT_CHANGED');
  }
}
export async function prepareNativeInputs(descriptor, env = process.env) {
  const platform = descriptor.platform || hostPlatform(), native = sdkPlatform(platform);
  if (platform !== hostPlatform()) throw new Error('NATIVE_RUNNER_REQUIRED ' + platform);
  const work = await privateRoot(descriptor.work), install = await privateRoot(descriptor.install);
  const {sources, installations, tools} = descriptor;
  if (!sources || !installations || !tools?.privateRoot) throw new Error('NATIVE_INPUT_LOCATIONS_REQUIRED');
  // Resolve all source choices before validating or preparing any installation.
  // The local checkout is a transport location; repository is the source identity.
  const compilerDefault=(await execute('git',['-C',sources.compiler,'rev-parse','HEAD'])).stdout.trim();
  const commits={compiler:descriptor.compilerCommit??compilerDefault,
    runtime:descriptor.runtimeCommit??FIXED_INPUTS.runtime,llvm:descriptor.llvmCommit??FIXED_INPUTS.llvm,
    ast:descriptor.astCommit??FIXED_INPUTS.compiler,h1:descriptor.h1Commit??FIXED_INPUTS.h1};
  const separateStd=descriptor.stdlibCommit!==undefined||sources.stdlib!==undefined||descriptor.sourceSelection?.stdlib!==undefined;
  if(separateStd) {
    if(!sources.stdlib||!(descriptor.stdlibCommit??descriptor.sourceSelection?.stdlib?.commit))throw Error('NATIVE_STDLIB_SOURCE_REQUIRED');
    commits.stdlib=descriptor.stdlibCommit??descriptor.sourceSelection.stdlib.commit;
  }
  const defaults={};
  for(const [name,commit]of Object.entries(commits))defaults[name]={repository:await runtimeSourceRepository(sources[name]),commit};
  const sourceSelection=resolveSources(defaults,descriptor.sourceSelection);
  const rows={},verifications={};
  for(const [name,row]of Object.entries(sourceSelection)) {
    const explicitCommit=descriptor[name+'Commit'];
    if(explicitCommit&&explicitCommit!==row.commit)throw Error('NATIVE_SOURCE_SELECTION '+name);
    if(row.repository!==defaults[name].repository)throw Error('NATIVE_SOURCE_SELECTION '+name);
    rows[name]={...await gitInput(sources[name],row.commit),sourceRepository:row.repository};
  }
  const {compiler:{commit:compilerCommit},runtime:{commit:runtimeCommit},llvm:{commit:llvmCommit},ast:{commit:astCommit},h1:{commit:h1Commit}}=rows;
  const stdlib=rows.stdlib;
  const version = descriptor.nativePair?.hostVersion ?? readHostToolchainPin(platform).replace(/^nightly-/, '');
  if (descriptor.nativePair && (descriptor.nativePair.llvm !== llvmCommit || descriptor.nativePair.runtime !== runtimeCommit))
    throw new Error('NATIVE_COMPONENT_PAIR_CONFLICT');
  if (descriptor.host.version !== version) throw new Error('NATIVE_HOST_VERSION');
  const host = {...descriptor.host, install:await installation(descriptor.host.install,
    ['bin/cjc'+native.exe, 'tools/bin/cjpm'+native.exe, 'modules/'+native.tuple+'/std/std.core.cjo'])};
  if (descriptor.nativePair) {
    const observed = await execute(path.join(host.install,'bin/cjc'+native.exe),['--version']);
    if (hostToolchainFromCjcVersion(observed.stdout) !== 'nightly-'+version) throw new Error('NATIVE_COMPONENT_ACTUAL_HOST');
  }
  const shapes = {
    llvm:['third_party/llvm/bin/llc'+native.exe, 'third_party/llvm/bin/llvm-as'+native.exe,
      'third_party/llvm/bin/llvm-dis'+native.exe, 'third_party/llvm/'+native.llvmDirectory+'/'+native.llvmLibrary,
      'third_party/llvm/fixed-llc/cjselfhost_llvmshim.o', 'tools/bin/cjdb'+native.exe],
    runtime:['runtime/lib/'+native.tuple+'/libcangjie-runtime'+native.shared,
      'runtime/lib/'+native.tuple+'/libboundscheck'+native.shared, 'lib/'+native.tuple+'/libcangjie-runtime.a'],
    ast:['libcangjie-ast-support.a', 'schema/StdAstFormat.fbs', 'include/flatbuffers/StdAstFormat_generated.h',
      'third_party/flatbuffers/bin/flatc'+native.exe],
  };
  for (const [name, required] of Object.entries(shapes)) {
    const supplied = name === 'runtime' && descriptor.nativePair
      ? await receiveNativeRuntime({root: installations.runtime.install, sourceRoot: installations.runtime.sourceRoot,
        sourceRepository:rows.runtime.sourceRepository,platform, llvmCommit, runtimeCommit, hostVersion: version, work}) : installations[name];
    if (!supplied?.buildResult || !supplied.configuration) throw new Error('NATIVE_BUILD_FACTS_REQUIRED ' + name);
    const facts=await readJson(supplied.buildResult); // Original build output; never synthesize success.
    if (name === 'llvm' && descriptor.astCommit !== undefined && facts.commits?.compiler !== astCommit)
      throw new Error('NATIVE_LLVM_AST_SOURCE_PAIR');
    let astInstallation;
    if(name==='ast'&&(facts.astInstallation||astCommit!==FIXED_INPUTS.compiler)){
      const llvmFacts=await readJson(installations.llvm.buildResult);
      if(llvmFacts.commits?.compiler!==astCommit||llvmFacts.commits?.llvm!==llvmCommit)
        throw new Error('NATIVE_LLVM_AST_SOURCE_PAIR');
      astInstallation=await readInstalledNativeAst({install:supplied.install,facts,platform,commit:astCommit,llvmCommit});
      required[0]=astInstallation.library;
    }
    verifications[name]={...supplied.verification};
    if(name==='llvm'){
      if(facts.nativeShim||facts.configuration?.shimSource)await readInstalledNativeShim({install:supplied.install,facts});
      // Carry the original producer's Python input, including legacy native
      // outputs. Never infer its source from the current Python version/pin.
      const carried=facts.pythonInstallationInput;
      if(carried&&(carried.record!=='third_party/llvm/PYTHON-BUILD-INPUTS.json'||await fileDigest(path.join(supplied.install,carried.record))!==carried.sha256))throw Error('NATIVE_PYTHON_INSTALL_RECORD');
      const original=carried?{record:path.join(supplied.install,carried.record),sha256:carried.sha256}:facts.configuration?.pythonInputs??facts.component?.config?.options?.python;
      const record=original?.record??original?.receipt;
      if(record){
        const python={...verifications[name].python};
        const selectedRecord=python.record||record;
        const originalHash=original.sha256||facts.pythonSource?.build?.originalInputs?.sha256;
        if((selectedRecord!==record&&(!originalHash||await fileDigest(selectedRecord)!==originalHash))
          ||python.sha256&&originalHash&&python.sha256!==originalHash)
          throw new Error('NATIVE_PYTHON_INPUT_CONFLICT');
        verifications[name].python={...python,record:selectedRecord,...(originalHash?{sha256:originalHash}:{})};
      }
    }
    if(name==='llvm'&&facts.llvmLibrary){
      if(facts.platform!==platform||facts.commits?.llvm!==rows.llvm.commit
        ||facts.llvmLibrary.file!=='third_party/llvm/'+native.llvmDirectory+'/'+native.llvmLibrary
        ||!/^[a-f0-9]{64}$/.test(facts.llvmLibrary.sha256||''))throw new Error('NATIVE_LLVM_BUILD_FACTS');
      if(verifications[name].librarySha256&&verifications[name].librarySha256!==facts.llvmLibrary.sha256)throw new Error('NATIVE_LLVM_INPUT_CONFLICT');
      verifications[name].librarySha256=facts.llvmLibrary.sha256;
    }
    rows[name] = {...rows[name], verification:verifications[name], buildResult:supplied.buildResult, configuration:supplied.configuration,
      ...(astInstallation?{astInstallation}:{}),
      ...(name==='llvm'&&facts.windowsToolchain?{windowsToolchain:facts.windowsToolchain}:{}),
      install:await installation(supplied.install, required),
      ...(supplied.sourceRoot ? {sourceRoot:await privateRoot(supplied.sourceRoot)} : {})};
    if(name==='runtime'&&native.os==='linux') {
      rows[name].sourceRoot=rows[name].sourceRoot||await privateRoot(path.join(rows[name].install,'share/runtime-build'));
      languageSourceInputs(path.join(rows[name].sourceRoot,'runtime'),
        {installed:rows[name].sourceRoot===path.join(rows[name].install,'share/runtime-build')});
      for(const member of ['runtime/CMakebuild/compile_commands.json','runtime/CMakebuild/gc-unit.status'])
        await fs.access(path.join(rows[name].sourceRoot,member));
      await fs.access(path.join(rows[name].install,'runtime/include/schedule.h'));
    }
  }
  // Optional reuse is an original H1 producer, not a copied flow directory.
  // A new candidate/configuration gets a new work domain while retaining the
  // fixed H1 input. Never relabel an old flow's COMPLETE as this configuration.
  if (installations.h1) {
    const reused=installations.h1;
    if(!reused.product||!reused.buildInputs||!reused.buildResult)throw new Error('H1_REUSE_LOCATIONS_REQUIRED');
    const product=path.resolve(reused.product);
    const facts=await readJson(reused.buildInputs), commands=await readJson(reused.buildResult);
    if(facts.source!==h1Commit||facts.host!==host.install||facts.native!==rows.llvm.install
      ||!facts.sourceChanges||facts.sha256!==await fileDigest(product)
      ||path.resolve(reused.buildInputs)!==path.join(path.dirname(product),'build-inputs.json')
      ||!Array.isArray(commands)||commands.length!==1||commands[0].rc!==0||commands[0].signal
      ||commands[0].cwd!==rows.h1.repository
      ||commands[0].argv?.[1]!==path.join(path.resolve(tools.privateRoot),'ts/src/sharedbuild/cjcj-stage1.mjs'))
      throw new Error('H1_REUSE_PRODUCER_MISMATCH');
    rows.h1={...rows.h1,product,configuration:facts,buildResult:path.resolve(reused.buildResult)};
  }
  tools.privateRoot = path.resolve(tools.privateRoot);
  for (const rel of ['cjcj-stage1.mjs', 'stage1-transform.mjs'])
    await fs.stat(path.join(tools.privateRoot, 'ts/src/sharedbuild', rel));
  const inputs = {work, install, platform, host, runtimeCommit, llvmCommit, astCommit, h1Commit,
    ...(descriptor.nativePair ? {nativePair:descriptor.nativePair} : {}), ...rows, stdlib:stdlib??rows.runtime,
    ...(separateStd?{stdlibCommit:stdlib.commit}:{}), sourceSelection, tools,
    archive:descriptor.archive, finalStd:descriptor.finalStd, deliveryStage:descriptor.deliveryStage};
  const component=(row)=>({...row,platform});
  inputs.selection={platform,hostPlatform:platform,bootstrapHost:{...host,platform},
    compilerExecution:{role:'bootstrap-host',stage:'stage0',platform,
      compiler:component({...rows.h1,install:host.install}),
      ...Object.fromEntries(['runtime','std','llvm'].map(name=>[name,component({install:host.install})]))},
    targetComponents:{compiler:component(rows.compiler),std:component(stdlib??rows.runtime),runtime:component(rows.runtime),
      llvm:component(rows.llvm),ast:component(rows.ast)}};
  if(installations.stage2)inputs.stage2=await stage2Input(installations.stage2,inputs);
  await validateSourceInputs(inputs);
  const file = path.join(work, 'sdk-inputs.json');
  await atomicJson(file, inputs);
  if (env.GITHUB_ENV) await fs.appendFile(env.GITHUB_ENV, 'CJCJ_SDK_INPUTS='+file+'\n');
  console.log('NATIVE_INPUTS_CONFIGURED '+JSON.stringify({file,platform,commits:Object.fromEntries(
    Object.entries(rows).map(([name,row])=>[name,row.commit])),host:host.version}));
  return file;
}
// Resolve the ordinary source-build invocation once, after normal fetch and
// before any native producer writes. Native compiler output remains a build
// input; only installProducts publishes a consumer SDK.
export async function prepareSourceBuildInputs(config, env=process.env, startStage='compiler') {
  const platform=config.target.spec.llvmPlatform, host=hostPlatform();
  const sources={};
  for(const [name,row]of Object.entries(config.sources)) {
    const repository=config.repoPath(name);
    const commit=(await execute('git',['-C',repository,'rev-parse','--verify',row.commit+'^{commit}'])).stdout.trim();
    const actual=await gitInput(repository,commit);
    if((await execute('git',['-C',repository,'rev-parse','HEAD'])).stdout.trim()!==commit)throw Error('SOURCE_SELECTION_CHECKOUT '+name);
    sources[name]={...actual,repository:row.repository,sourceRoot:repository};
  }
  const selected=resolveSources(sources);
  const install=path.join(config.repoPath('compiler'),config.target.primaryCompilerOutput());
  const hostInstall=config.officialSdkRoot??env.CJCJ_OFFICIAL_SDK_ROOT;
  if(!hostInstall)throw Error('SOURCE_BUILD_BOOTSTRAP_HOST_REQUIRED');
  const bootstrapHost={install:path.resolve(hostInstall),platform:host};
  const component=name=>({...selected[name],install,platform});
  const compiler={...component('compiler'),product:path.join(install,'bin','cjc'+config.target.spec.exeSuffix),
    configuration:{producer:'build.py build/install',buildType:config.buildType}};
  const selection=installationSelection({platform,hostPlatform:host,bootstrapHost,
    compilerExecution:{role:'target',stage:'source-build',platform,
      compiler,...Object.fromEntries(['runtime','std','llvm'].map(name=>[name,component(name==='std'?'runtime':name)]))},
    targetComponents:{compiler,runtime:component('runtime'),std:component('runtime'),
      // Native compiler/build.py consumes the selected LLVM checkout through its
      // existing third_party/llvm-project source input. AST is compiler source.
      llvm:{...component('llvm'),configuration:{producer:'compiler/build.py',component:'third_party/llvm'}},
      ast:{...component('compiler'),configuration:{producer:'compiler/build.py',component:'AST/flatbuffers'}},
      tools:{...selected.tools,platform},stdx:{...selected.stdx,platform}}});
  // This is the existing native command log, not a cache qualification file.
  // Independent CLI processes retain only actual predecessor commands from
  // the same source/configuration. Rebuilding a producer supersedes that
  // producer and its downstream commands, including earlier failed attempts.
  const configuration=JSON.parse(JSON.stringify({platform,hostPlatform:host,target:config.target.spec,
    buildType:config.buildType,crossBuildType:config.crossBuildType,
    version:config.cangjieVersion,buildRoot:config.buildRoot,bootstrapHost,
    nativeRuntime:config.nativeRuntime,
    environment:Object.fromEntries(Object.entries(env).filter(([name])=>
      /^(?:PATH|CC|CXX|AR|AS|LD|NM|RANLIB|STRIP|CFLAGS|CXXFLAGS|ASMFLAGS|LDFLAGS|SDKROOT|MACOSX_DEPLOYMENT_TARGET)$/.test(name)
      || /^(?:CMAKE_|CANGJIE_|CJ_IR_|GC_UNIT_|STDX_HOST_|CJCJ_NATIVE_|CJCJ_SRCBUILD_)/.test(name)).sort(([a],[b])=>a.localeCompare(b)))}));
  const factsFile=path.join(config.workspace,'build/native-build.json');
  const previous=await readJson(factsFile).catch(error=>{if(error.code==='ENOENT')return null;throw error;});
  const predecessors=['compiler','runtime','stdlib'].slice(0,['compiler','runtime','stdlib'].indexOf(startStage));
  const commands=previous&&isDeepStrictEqual(previous.sources,selected)&&isDeepStrictEqual(previous.configuration,configuration)
    ?previous.commands.filter(row=>predecessors.includes(row.stage?.split('.')[0])):[];
  // Keep the original attempt, including its own failures and input identity,
  // before runBuildPy writes the next invocation to native-build.json.
  if(previous)await atomicJson(factsFile+'.previous-'+randomUUID(),previous);
  const production={sources:selected,configuration,commands};
  return Object.freeze({...config,sources:selected,selection,production,producerSdk:install,
    installInputs:{work:path.join(config.workspace,'build','sdk-install'),
      install:config.consumerSdk??path.join(config.softwareDir,'cangjie'),selection,production,
      layout:'native-output',tools:{launcher:env.CMAKE_CXX_COMPILER_LAUNCHER,
        ...(config.target.spec.needsMingw?{targetToolchain:path.join(mingwInstallPath(config.buildRoot),'bin')}:{})}}});
}

// Installation of existing native products uses the same inputs and recipe,
// without constructing the bootstrap graph or requiring private stage1 tools.
export async function prepareInstallInputs(descriptor) {
  const selection=installationSelection(descriptor.selection);
  const {platform,targetComponents:target,compilerExecution:execution}=selection,native=sdkPlatform(platform),execNative=sdkPlatform(execution.platform);
  const work=await privateRoot(descriptor.work),install=await privateRoot(descriptor.install);
  const required=[
    target.compiler.product,
    target.std.install+'/modules/'+native.tuple+'/std/std.core.cjo',
    target.std.install+'/lib/'+native.tuple+'/libcangjie-std-core.a',
    target.runtime.install+'/runtime/lib/'+native.tuple+'/libcangjie-runtime'+native.shared,
    target.llvm.install+'/third_party/llvm/bin/llc'+native.exe,
    ...['runtime','std','llvm'].map(name=>execution[name].install+(name==='runtime'
      ?'/runtime/lib/'+execNative.tuple+'/libcangjie-runtime'+execNative.shared:name==='std'
        ?'/lib/'+execNative.tuple+'/libcangjie-std-core.a':'/third_party/llvm/'+execNative.llvmDirectory+'/'+execNative.llvmLibrary)),
  ];
  for(const file of required)if(!(await fs.stat(file)).isFile())throw Error('INSTALL_INPUT_FILE '+file);
  // Cross installation is allowed, execution belongs to its native runner.
  const cross=platform!==hostPlatform();
  return {...descriptor,work,install,platform,selection,cross};
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { await prepareNativeInputs(await readJson(process.argv[2] || process.env.CJCJ_NATIVE_INPUTS)); }
  catch (error) { console.error(error.stack); process.exitCode=1; }
}
