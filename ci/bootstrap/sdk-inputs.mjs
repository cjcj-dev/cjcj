#!/usr/bin/env zx
import {embeddedStamp} from '../../build/lib/toolchain-identity.mjs';
import {rejectPrivateTools} from './deploy-native-tools.mjs';
import {readInstalledNativeShim,compilerNativeShim} from './native-shim-inputs.mjs';
import {nativeSymbolRows} from './std-runtime-colour.mjs';
// Turn received native installations and real Git objects into build inputs.
// The descriptor contains locations, not producer receipts or SDK authorities.
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify, isDeepStrictEqual} from 'node:util';
import {randomUUID} from 'node:crypto';
import {atomicJson, readJson, privateRoot, fileDigest} from './sdk-flow.mjs';
import {FIXED_INPUTS,backendArtifactPath} from './sdk-targets.mjs';
import {h1HeapDefaultsBuild} from './sdk-native-stage.mjs';
import {sdkPlatform,stdxChirMembers} from './sdk-platform.mjs';
import {javaInteropInput} from './sdk-java-interop.mjs';
import {stage2Input} from './sdk-stage2-input.mjs';
import {receiveNativeRuntime} from './native-runtime-input.mjs';
import {languageSourceInputs} from '../../build/srcbuild/installed-language-source.mjs';
import {hostPlatform, readHostToolchainPin, hostToolchainFromCjcVersion} from '../host-toolchain-pin.mjs';
import {runtimeSourceRepository} from '../../build/lib/runtime-source-inputs.mjs';
import {checkoutSourceRepository} from './checkout-source.mjs';
import {readInstalledNativeAst} from './installed-native-ast.mjs';
import {installPath as mingwInstallPath} from '../../build/toolchain/mingw.mjs';
import {installationSelection,resolveSources,bootstrapH1Commit} from './native-source-selection.mjs';
import {stdBuildType,flag,selectedStdAst,checkStdAstOutput} from './sdk-std-resume.mjs';
import {nativePair} from '../runtime-pin.mjs';
import {stdDependencyInputs} from './stdlib-build.mjs';
import {compilerChirSchema,compilerChirAttributes,compilerChirGenerated,compilerChirFlatc,
  compilerChirCommand,wireAttributeHeader} from './compiler-chir-interface.mjs';
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
// R's native AST archive is the selected support archive plus ast_api.cpp.o.
// Ninja folds the compiler depfile into .ninja_deps. Inspect that object, and
// compare the installed archive with the result of R's deterministic append:
// a matching build.py argv alone cannot identify what the object included.
async function matchesFinalStdAst(build, install, input, ast) {
  const decline=reason=>{console.log('Final std AST reuse declined: '+reason);return false;};
  const args=build.argv.slice(build.argv.indexOf('build.py')+2);
  const includes=args.filter(arg=>arg==='-I' || arg==='--include' || arg.startsWith('--include=') || /^-I./.test(arg));
  const include=flag(args,'--include')??flag(args,'-I')??includes[0]?.match(/^-I(.+)$/)?.[1];
  if(includes.length!==1 || include!==ast.include ||
      build.argv.includes('--local_mode_api')!==(input.stdLocalModeApi===true))return decline('build.py arguments');
  const dir=path.join(build.cwd,'build/build'), src=path.dirname(build.cwd);
  const cache=await fs.readFile(path.join(dir,'CMakeCache.txt'),'utf8');
  const cached=key=>cache.split(/\r?\n/).find(l=>l.startsWith(key+':'))?.split('=').slice(1).join('=');
  if(cached('CMAKE_GENERATOR')!=='Ninja' || cached('CANGJIE_INCLUDE')!==ast.include)return decline('CMake selection');
  const ninja=cached('CMAKE_MAKE_PROGRAM');
  if(!ninja)return decline('Ninja not recorded');
  const target='libs/std/ast/native/CMakeFiles/cangjie-std-astFFI-objs.dir/ast_api.cpp';
  const obj=target+(sdkPlatform(input.platform).os==='win32'?'.obj':'.o');
  const {stdout}=await execute(ninja,['-t','deps',obj],{cwd:dir});
  const deps=stdout.trimEnd().split(/\r?\n/);
  if(!deps.shift()?.endsWith('(VALID)'))return decline('missing object dependencies');
  const files=deps.map(line=>path.resolve(dir,line.trim()));
  const astHeaders=files.filter(f=>f.split(path.sep).includes('cangjie') && f.includes(path.sep+'include'+path.sep+'cangjie'+path.sep));
  if(!files.includes(path.join(ast.include,'cangjie/CHIR/IR/AttributeInfo.h')) ||
      !files.includes(path.join(ast.include,'cangjie/AST/Node.h')) ||
      astHeaders.some(f=>!f.startsWith(ast.include+path.sep)))return decline('object header dependencies');
  await checkStdAstOutput({source:src,output:install,platform:input.platform});
  const tmp=await fs.mkdtemp(path.join(os.tmpdir(),'std-ast-compare-'));
  try {
    const copy=path.join(tmp,'ffi.a');
    await fs.copyFile(ast.library,copy);
    const ar=sdkPlatform(input.platform).os==='linux'?'ar':cached('CMAKE_AR');
    if(!ar)return decline('no archiver');
    await execute(ar,['qD',copy,path.join(dir,obj)]);
    return await fileDigest(copy)===await fileDigest(path.join(dir,'libcangjie-std-astFFI.a')) || decline('archive contents');
  } finally {await fs.rm(tmp,{recursive:true,force:true});}
}
// Reuse a completed native std producer through its existing command log and
// provenance. Keep final std distinct from the compiler's bootstrap libraries.
export async function installedFinalStd(supplied, input) {
  if (!supplied?.install || !supplied.commands || !input.stage2) throw Error('FINAL_STD_REUSE_INPUT');
  const install = await privateRoot(supplied.install), commands = path.resolve(supplied.commands);
  const rows = await readJson(commands);
  const built = rows.findIndex(row => row.argv?.includes('build.py') && row.argv.includes('build')
    && row.rc === 0 && !row.signal);
  const installed = rows.findIndex((row, index) => index > built && row.argv?.includes('build.py')
    && row.argv.includes('install') && row.argv[row.argv.indexOf('--prefix') + 1] === install
    && row.cwd === rows[built]?.cwd && row.rc === 0 && !row.signal);
  if (built < 0 || installed < 0) throw Error('FINAL_STD_REUSE_PRODUCER');
  const producedType = flag(rows[built].argv,'-t') ?? flag(rows[built].argv,'--build-type');
  if (producedType === undefined || stdBuildType(producedType) !== stdBuildType(input.stdBuildType))
    throw Error('FINAL_STD_REUSE_BUILD_TYPE');
  const provenance = await fs.readFile(path.join(install, 'PROVENANCE.txt'), 'utf8');
  const field = name => provenance.split('\n').find(line => line.startsWith(name+' = '))?.slice(name.length+3).trim();
  if (field('STD_SOURCE_COMMIT') !== input.stdlib.commit
      || field('BUILT_BY_CJC') !== input.stage2.compilerCommit || field('COLOURED') !== 'true')
    throw Error('FINAL_STD_REUSE_SOURCE');
  const native = sdkPlatform(input.platform);
  await installation(install, ['modules/'+native.tuple+'/std/std.core.cjo',
    'lib/'+native.tuple+'/libcangjie-std-core.a']);
  const ast=selectedStdAst(input);
  if(ast){
    const attempts=rows.filter(row=>row.argv?.includes('build.py') &&
      (row.argv.includes('build')||row.argv.includes('install')));
    if(attempts.length!==2 || attempts[0]!==rows[built] || attempts[1]!==rows[installed])return undefined;
    try {
      if(!await matchesFinalStdAst(rows[built],install,input,ast))return undefined;
    } catch(error){
      // An imported installation need not retain its build directory or tools.
      if(!['ENOENT','ENOTDIR'].includes(error.code) && typeof error.code!=='number' &&
          !['STD_AST_FFI_INSTALL_MISMATCH','STD_AST_MODULE'].includes(error.message))throw error;
      console.log('Final std AST reuse declined: '+error.message);
      return undefined;
    }
  }
  return {install, commands};
}
const MACRO_SOURCE='packages/macro/src/InvokeUtil.cj';
// Git blob of MACRO_SOURCE at FIXED_INPUTS.h1 (8390179).
export const FIXED_H1_MACRO_BLOB='2d51c6f26491adc07fed754bc94b64ca8a7c8430';
// Check source compatibility before opening installations, and again when a
// saved build graph is consumed. Ordinary CJPM has no H1 execution node.
async function validateSourceTrees(input, env) {
  if (input.runtime.sourceRepository !== undefined &&
      await checkoutSourceRepository('runtime',input.runtime.repository,input.runtime.commit,env) !== input.runtime.sourceRepository)
    throw Error('NATIVE_SOURCE_SELECTION runtime');
  const expectedMacro=await fs.readFile(new URL('../../packages/macro/src/InvokeUtil.cj',import.meta.url),'utf8');
  const workingText=text=>process.platform==='win32'?text.replaceAll('\r\n','\n'):text;
  for(const [name,row] of Object.entries({llvm:input.llvm,runtime:input.runtime,stdlib:input.stdlib??input.runtime,ast:input.ast,h1:input.h1,compiler:input.compiler})) {
    const actual=await gitInput(row.repository,row.commit);
    if(actual.tree!==row.tree)throw new Error('NATIVE_SOURCE_TREE '+name);
    // An ordinary CJPM producer has no H1 parent or H1 execution node. Its
    // installed compiler still must satisfy the current macro source contract;
    // normal bootstrap and historical C2 retain their H1 compatibility check.
    if(name==='compiler'||name==='h1'&&input.stage2?.mode!=='ordinary-cjpm') {
      // The approved fixed H1 predates the current macro runtime contract and
      // only runs the transitional stages, which never serve as a macro SDK
      // (sdk-targets.mjs macroSdk 'UNSUPPORTED'). Its macro source is bound to
      // its own approved blob; every other H1 and every compiler must carry
      // the candidate's macro source byte for byte.
      if(name==='h1'&&row.commit===FIXED_INPUTS.h1) {
        const {stdout}=await execute('git',['-C',row.repository,'rev-parse',row.commit+':'+MACRO_SOURCE]);
        if(stdout.trim()!==FIXED_H1_MACRO_BLOB)throw new Error('NATIVE_MACRO_SOURCE '+name);
        continue;
      }
      const {stdout}=await execute('git',['-C',row.repository,'show',row.commit+':'+MACRO_SOURCE]);
      if(workingText(stdout)!==workingText(expectedMacro))throw new Error('NATIVE_MACRO_SOURCE '+name);
    }
  }
}
// Validate the actual selected source objects, including an explicit inputs file.
// The compiler's macro consumer must be this paired source, not an older C tree.
export async function validateSourceInputs(input) {
  await validateSourceTrees(input,process.env);
  await validateInstalledInputs(input);
}
async function validateInstalledInputs(input) {
  if(input.compiler.shimInstall)await compilerNativeShim({install:input.compiler.shimInstall,
    nativeInstall:input.llvm.install,compilerCommit:input.compiler.commit});
  if(input.stdLocalModeApi!==undefined && typeof input.stdLocalModeApi!=='boolean')throw Error('STD_LOCAL_MODE_API_SELECTION');
  if(input.stdDependencies&&!isDeepStrictEqual(await stdDependencyInputs(input.stdDependencies),input.stdDependencies))throw Error('STD_DEPENDENCY_INPUT_CHANGED');
  if(input.stage2?.mode==='ordinary-cjpm') {
    const native=sdkPlatform(input.platform);
    const observed=await execute(path.join(input.host.install,'bin/cjc'+native.exe),['--version']);
    if(hostToolchainFromCjcVersion(observed.stdout)!=='nightly-'+input.host.version)
      throw Error('NATIVE_COMPONENT_ACTUAL_HOST');
  }
  if (input.nativePair) await receiveNativeRuntime({root:input.runtime.install,sourceRoot:input.runtime.sourceRoot,
    sourceRepository:input.runtime.sourceRepository??await runtimeSourceRepository(input.runtime.repository),configuration:input.runtime.configuration,
    platform:input.platform,llvmCommit:input.llvm.commit,runtimeCommit:input.runtime.commit,
    hostVersion:input.host.version,work:input.work});
  if(input.stage2) {
    const actual = await stage2Input(input.stage2,input);
    if(!isDeepStrictEqual(actual,input.stage2))throw new Error('C2_REUSE_INPUT_CHANGED');
  }
  if(input.reuseFinalStd && !isDeepStrictEqual(await installedFinalStd(input.reuseFinalStd,input),input.reuseFinalStd))
    throw Error('FINAL_STD_REUSE_INPUT_CHANGED');
}
// Linux and Darwin build H1 with the public producer, which takes the
// prepare-native shim when that shim was built from H1's own commit. Windows
// H1 selects the compiler shim in the graph instead.
export function h1ShimInstall(platform,{compilerCommit,h1Commit,shimInstall}) {
  return sdkPlatform(platform).os!=='win32'&&compilerCommit===h1Commit?shimInstall:undefined;
}
async function installedH1(reused,{h1,host,llvm,platform,tools,windowsShimInstall}) {
  if(!reused.product||!reused.buildInputs||!reused.buildResult)throw Error('H1_REUSE_LOCATIONS_REQUIRED');
  const native=sdkPlatform(platform), product=path.resolve(reused.product), buildResult=path.resolve(reused.buildResult);
  const facts=await readJson(reused.buildInputs), commands=await readJson(buildResult);
  const mismatch=detail=>{throw Error('H1_REUSE_PRODUCER_MISMATCH '+detail);};
  if(facts.source!==h1.commit||facts.host!==host.install||facts.native!==llvm.install
    ||!facts.sourceChanges||facts.sha256!==await fileDigest(product)
    ||path.resolve(reused.buildInputs)!==path.join(path.dirname(product),'build-inputs.json'))
    mismatch('product inputs');
  if(native.os==='win32') {
    const shim=await compilerNativeShim({install:windowsShimInstall,nativeInstall:llvm.install,compilerCommit:h1.commit});
    if(facts.producer!=='sdk-native-stage:windows-h1'||!isDeepStrictEqual(facts.nativeShim,shim)
      ||!path.isAbsolute(facts.sourceRoot||'')||!Array.isArray(commands)||commands.length!==2
      ||commands.some(row=>row.cwd!==facts.sourceRoot||row.rc!==0||row.signal||row.error||row.cancelled)
      ||commands[0].argv?.at(-1)!==path.join(facts.sourceRoot,'runtime_shim/build_shim.mjs')
      ||commands[1].argv?.[0]!==path.join(host.install,'tools/bin/cjpm.exe')||commands[1].argv[1]!=='build')
      mismatch('Windows commands');
    return {product,configuration:facts,buildResult};
  }
  // Linux and Darwin share the public cjpm H1 producer below; the retired
  // private Darwin command shape is never accepted.
  rejectPrivateTools(tools);

  const hostRuntimeFile=path.join(host.install,'runtime/lib',native.tuple,'libcangjie-runtime'+native.shared);
  const hostRuntimeSupportsConfigV1=(await nativeSymbolRows(hostRuntimeFile,{platform,runtime:true,defined:true})).includes('CJ_MRT_CjRuntimeInitWithConfigV1');
  const llvmLibraryFile=path.join(llvm.install,'third_party/llvm',native.llvmDirectory,native.llvmLibrary);
  const shim=h1.shimInstall?await compilerNativeShim({install:h1.shimInstall,nativeInstall:llvm.install,compilerCommit:h1.commit})
    :await readInstalledNativeShim({install:llvm.install});
  if(facts.producer!=='sdk-native-stage:h1'||!path.isAbsolute(facts.sourceRoot||'')
    ||!facts.sourceChanges?.['packages/cjc/cjpm.toml']
    ||!isDeepStrictEqual(facts.startupConfiguration,{hostRuntimeFile,hostRuntimeSupportsConfigV1,llvmLibraryFile})
    ||!isDeepStrictEqual(facts.nativeShim,shim))mismatch('startup inputs');

  // The interface producer depends on a schema in the pinned H1 source.
  // Neither the number of rows nor leftover files may pick the legacy shape.
  const git=(...args)=>execute('git',['-C',h1.repository,...args]).then(result=>result.stdout);
  const chirInterface=Boolean((await git('ls-tree',h1.commit,'--',compilerChirSchema)).trim());
  // The heap-default object is compiled exactly where the producer compiles it:
  // when the pinned H1 manifests name it (sdk-native-stage.mjs h1HeapDefaultsBuild).
  const heapBuilt=h1HeapDefaultsBuild({workspaceText:await git('show',h1.commit+':cjpm.toml'),
    packageText:await git('show',h1.commit+':packages/cjc/cjpm.toml'),platform,
    sourcePresent:Boolean((await git('ls-tree',h1.commit,'--','runtime_shim/cjc_heap_defaults.c')).trim())});
  if(!Array.isArray(commands)||commands.length!==2+Number(heapBuilt)+Number(chirInterface)
    ||commands.some(row=>row?.rc!==0||row.signal||row.error||row.cancelled
      ||row.cwd!==facts.sourceRoot||!Array.isArray(row.argv)||row.argv.some(arg=>typeof arg!=='string')))
    mismatch('command results');

  const argvs=commands.map(row=>row.argv);
  const config=argvs.shift(), heap=heapBuilt?argvs.shift():undefined, [cjpm,generate]=argvs;
  const shimDir=path.join(facts.sourceRoot,'runtime_shim');
  const compile=(name,defines)=>['-std=c11','-O2','-fPIC',...defines,
    '-c',path.join(shimDir,name+'.c'),'-o',path.join(shimDir,name+'.o')];
  const compilerArgs=(argv,args)=>{
    // The producer permits a configurable C compiler and one optional launcher.
    const prefix=argv.length-args.length;
    return (prefix===1||prefix===2)&&argv.slice(0,prefix).every(arg=>arg&&!arg.startsWith('-'))
      &&isDeepStrictEqual(argv.slice(prefix),args);
  };
  if(!compilerArgs(config,compile('cjc_runtime_config',['-D_POSIX_C_SOURCE=200809L','-DCJCJ_COMMIT="'+h1.commit+'"']))
    ||heapBuilt&&(!compilerArgs(heap,compile('cjc_heap_defaults',hostRuntimeSupportsConfigV1?[]:['-DCJCJ_LEGACY_HOST_RUNTIME']))
      ||config[0]!==heap[0]||config[1]!==heap[1])
    ||cjpm[0]!==path.join(host.install,'tools/bin/cjpm')||cjpm[1]!=='build'||!/^-j[1-9]\d*$/.test(cjpm.at(-1))
    ||!(cjpm.length===3||cjpm.length===5&&cjpm[2]==='--target-dir'&&path.isAbsolute(cjpm[3])))
    mismatch('compiler commands');

  if(chirInterface) {
    const root=path.dirname(path.dirname(product));
    if(product!==path.join(root,'bin/cjcj-stage1'))mismatch('compiler interface prefix');
    const flatc=await compilerChirFlatc(llvm.install,shim);
    if(!isDeepStrictEqual(generate,compilerChirCommand(flatc,root)))mismatch('flatc command');
    const schema=await git('show',h1.commit+':'+compilerChirSchema);
    const attributes=wireAttributeHeader(await git('show',h1.commit+':packages/chir/src/Enums.cj'));
    const installed=async member=>{
      const file=path.join(root,member), stat=await fs.lstat(file);
      if(!stat.isFile()||!stat.size)mismatch(member);
      return fs.readFile(file);
    };
    if(!(await installed(compilerChirSchema)).equals(Buffer.from(schema)))mismatch(compilerChirSchema);
    if(!(await installed(compilerChirAttributes)).equals(Buffer.from(attributes)))mismatch(compilerChirAttributes);
    const generated=await installed(compilerChirGenerated);
    // Compare with what the selected generator emits for the installed schema.
    // Use a private directory and leave the producer's prefix untouched.
    const tmp=await fs.mkdtemp(path.join(os.tmpdir(),'h1-flatc-'));
    try {
      await execute(flatc,['--no-warnings','-c','-o',tmp,path.join(root,compilerChirSchema)],{cwd:root,
        env:{...process.env,LD_LIBRARY_PATH:'',LD_PRELOAD:'',LD_AUDIT:'',[native.loader]:''}});
      if(!generated.equals(await fs.readFile(path.join(tmp,path.basename(compilerChirGenerated)))))
        mismatch(compilerChirGenerated);
    } finally {await fs.rm(tmp,{recursive:true,force:true});}
  }
  return {product,configuration:facts,buildResult,...(chirInterface?{chirInterface}: {})};
}
export async function prepareNativeInputs(descriptor, env = process.env) {
  const platform = descriptor.platform || hostPlatform(), native = sdkPlatform(platform);
  if (platform !== hostPlatform()) throw new Error('NATIVE_RUNNER_REQUIRED ' + platform);
  const work = await privateRoot(descriptor.work), install = await privateRoot(descriptor.install);
  const {sources, installations, tools: suppliedTools = {}} = descriptor;
  const tools = {...suppliedTools};
  if (!sources || !installations) throw new Error('NATIVE_INPUT_LOCATIONS_REQUIRED');
  // Resolve all source choices before validating or preparing any installation.
  // The local checkout is a transport location; repository is the source identity.
  const compilerDefault=(await execute('git',['-C',sources.compiler,'rev-parse','HEAD'])).stdout.trim();
  const commits={compiler:descriptor.compilerCommit??compilerDefault,
    runtime:descriptor.runtimeCommit??descriptor.sourceSelection?.runtime?.commit??FIXED_INPUTS.runtime,llvm:descriptor.llvmCommit??FIXED_INPUTS.llvm,
    ast:descriptor.astCommit??FIXED_INPUTS.compiler,h1:bootstrapH1Commit(env,descriptor.h1Commit??descriptor.sourceSelection?.h1?.commit)};
  const separateStd=descriptor.stdlibCommit!==undefined||sources.stdlib!==undefined||descriptor.sourceSelection?.stdlib!==undefined;
  if(separateStd) {
    if(!sources.stdlib||!(descriptor.stdlibCommit??descriptor.sourceSelection?.stdlib?.commit))throw Error('NATIVE_STDLIB_SOURCE_REQUIRED');
    commits.stdlib=descriptor.stdlibCommit??descriptor.sourceSelection.stdlib.commit;
  }
  const defaults={};
  for(const [name,commit]of Object.entries(commits))defaults[name]={repository:await checkoutSourceRepository(name,sources[name],commit,env),commit};
  const sourceSelection=resolveSources(defaults,descriptor.sourceSelection);
  const rows={},verifications={};
  for(const [name,row]of Object.entries(sourceSelection)) {
    const explicitCommit=descriptor[name+'Commit'];
    if(explicitCommit&&explicitCommit!==row.commit)throw Error('NATIVE_SOURCE_SELECTION '+name);
    if(row.repository!==defaults[name].repository)throw Error('NATIVE_SOURCE_SELECTION '+name);
    rows[name]={...await gitInput(sources[name],row.commit),sourceRepository:row.repository};
  }
  const {compiler:{commit:compilerCommit},runtime:{commit:runtimeCommit},llvm:{commit:llvmCommit},ast:{commit:astCommit},h1:{commit:h1Commit}}=rows;
  await validateSourceTrees({...rows,stage2:installations.stage2},env);
  const stdlib=rows.stdlib;
  // An imported normal producer carries its actual bootstrap host selection.
  // It need not relabel that existing SDK with today's bootstrap default pin.
  const ordinary=installations.stage2?.mode==='ordinary-cjpm';
  const version = descriptor.nativePair?.hostVersion ?? (ordinary ? descriptor.host.version
    : readHostToolchainPin(platform).replace(/^nightly-/, ''));
  if(!/^\d+\.\d+\.\d+-alpha\.\d+$/.test(version||''))throw Error('NATIVE_HOST_VERSION');
  if (descriptor.nativePair && (descriptor.nativePair.llvm !== llvmCommit || descriptor.nativePair.runtime !== runtimeCommit))
    throw new Error('NATIVE_COMPONENT_PAIR_CONFLICT');
  if (descriptor.host.version !== version) throw new Error('NATIVE_HOST_VERSION');
  const host = {...descriptor.host, install:await installation(descriptor.host.install,
    ['bin/cjc'+native.exe, 'tools/bin/cjpm'+native.exe, 'modules/'+native.tuple+'/std/std.core.cjo'])};
  if (descriptor.nativePair || ordinary) {
    const observed = await execute(path.join(host.install,'bin/cjc'+native.exe),['--version']);
    if (hostToolchainFromCjcVersion(observed.stdout) !== 'nightly-'+version) throw new Error('NATIVE_COMPONENT_ACTUAL_HOST');
  }
  const shapes = {
    runtime:['runtime/lib/'+native.tuple+'/libcangjie-runtime'+native.shared,
      'runtime/lib/'+native.tuple+'/libboundscheck'+native.shared, 'lib/'+native.tuple+'/libcangjie-runtime.a'],
    llvm:['third_party/llvm/bin/llc'+native.exe, 'third_party/llvm/bin/llvm-as'+native.exe,
      'third_party/llvm/bin/llvm-dis'+native.exe, 'third_party/llvm/'+native.llvmDirectory+'/'+native.llvmLibrary,
      'third_party/llvm/fixed-llc/cjselfhost_llvmshim.o', 'tools/bin/cjdb'+native.exe],
    ast:['libcangjie-ast-support.a', 'schema/StdAstFormat.fbs', 'include/flatbuffers/StdAstFormat_generated.h', ...stdxChirMembers,
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
      ...(name==='runtime' && descriptor.nativePair ? {component:true} : {}),
      ...(astInstallation?{astInstallation}:{}),
      ...(name==='llvm'&&facts.windowsToolchain?{windowsToolchain:facts.windowsToolchain}:{}),
      install:await installation(supplied.install, required),
      ...(supplied.sourceRoot ? {sourceRoot:await privateRoot(supplied.sourceRoot)} : {})};
    if(name==='runtime'&&native.os==='linux') {
      rows[name].sourceRoot=rows[name].sourceRoot||await privateRoot(path.join(rows[name].install,'share/runtime-build'));
      rows[name].gateStatus=supplied.gateStatus||path.join(rows[name].sourceRoot,'runtime/CMakebuild/gc-unit.status');
      languageSourceInputs(path.join(rows[name].sourceRoot,'runtime'),
        {installed:rows[name].sourceRoot===path.join(rows[name].install,'share/runtime-build')});
      for(const member of ['runtime/CMakebuild/compile_commands.json','runtime/CMakebuild/runtime-staging/include/schedule.h'])
        await fs.access(path.join(rows[name].sourceRoot,member));
      await fs.access(rows[name].gateStatus);
    }
  }
  if(installations.shim) {
    if(!installations.shim.install)throw Error('NATIVE_SHIM_INSTALL_REQUIRED');
    rows.compiler.shimInstall=await privateRoot(installations.shim.install);
    const h1Shim=h1ShimInstall(platform,{compilerCommit,h1Commit,shimInstall:rows.compiler.shimInstall});
    if(h1Shim)rows.h1.shimInstall=h1Shim;
  }
  // Optional reuse is an original H1 producer, not a copied flow directory.
  // A new candidate/configuration gets a new work domain while retaining the
  // fixed H1 input. Never relabel an old flow's COMPLETE as this configuration.
  if (installations.h1) {
    rows.h1={...rows.h1,...await installedH1(installations.h1,{h1:rows.h1,host,llvm:rows.llvm,
      platform,tools,windowsShimInstall:rows.compiler.shimInstall})};
  }
  // No host consumes private tools: Linux and Darwin build H1 through the
  // public in-repo cjpm path, Windows through its own public producer.
  rejectPrivateTools(tools);
  const inputs = {work, install, platform, host, runtimeCommit, llvmCommit, astCommit, h1Commit,
    ...(descriptor.stdLocalModeApi!==undefined?{stdLocalModeApi:descriptor.stdLocalModeApi}:{}),
    ...(descriptor.stdDependencies?{stdDependencies:await stdDependencyInputs(descriptor.stdDependencies)}:{}),
    ...(descriptor.stdBuildType === undefined ? {} : {stdBuildType:stdBuildType(descriptor.stdBuildType)}),
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
  if(descriptor.reuseFinalStd){
    const reused=await installedFinalStd(descriptor.reuseFinalStd,inputs);
    if(reused)inputs.reuseFinalStd=reused;
    else console.log('Selected AST build inputs not established for final std; building stage3-std');
  }
  await validateInstalledInputs(inputs);
  const file = path.join(work, 'sdk-inputs.json');
  await atomicJson(file, inputs);
  // Standalone descriptors may deliberately select a work directory outside the CI workspace.
  if (env.GITHUB_ENV && (!env.CANGJIE_WORKSPACE || work !== path.resolve(env.CANGJIE_WORKSPACE, 'native-bootstrap')))
    await fs.appendFile(env.GITHUB_ENV, 'CJCJ_SDK_INPUTS='+file+'\n');
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
  if(config.nativeRuntime) {
    const observed=await execute(path.join(bootstrapHost.install,'bin','cjc'+sdkPlatform(host).exe),['--version']);
    bootstrapHost.version=config.nativeRuntime.hostVersion;
    if(hostToolchainFromCjcVersion(observed.stdout)!=='nightly-'+bootstrapHost.version)throw Error('INSTALL_COMPONENT_HOST');
  }
  const component=name=>({...selected[name],install,platform});
  const compiler={...component('compiler'),product:path.join(install,'bin','cjc'+config.target.spec.exeSuffix),
    configuration:{producer:'build.py build/install',buildType:config.buildType}};
  const selection=installationSelection({platform,hostPlatform:host,bootstrapHost,
    compilerExecution:{role:'target',stage:'source-build',platform,
      compiler,...Object.fromEntries(['runtime','std','llvm'].map(name=>[name,component(name==='std'?'runtime':name)]))},
    targetComponents:{compiler,runtime:{...component('runtime'),...(config.nativeRuntime?{component:true,buildResult:path.join(install,'NATIVE-INPUTS.json')}:{})},std:component('runtime'),
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
      layout:'native-output',buildJavaInterop:platform==='linux_x86_64'&&!config.target.spec.crossCompile,javaJdk:config.toolsJniHome,tools:{launcher:env.CMAKE_CXX_COMPILER_LAUNCHER,
        ...(config.target.spec.needsMingw?{targetToolchain:path.join(mingwInstallPath(config.buildRoot),'bin')}:{})}}});
}

// A completed component build may resume run-all at SDK installation. Take
// its original native products, never the previously assembled SDK or Java.
export async function resumeSourceComponents(config,file) {
  const {status,selection}=await readJson(path.resolve(file));
  if(status!=='COMPLETE'||selection?.compilerExecution?.stage!=='stage3'
    ||selection.platform!==config.target.spec.llvmPlatform||selection.platform!==hostPlatform()
    ||selection.bootstrapHost.install!==config.officialSdkRoot)throw Error('SOURCE_COMPONENT_RESUME_SELECTION');
  const {runtime,llvm}=selection.targetComponents;
  if(runtime.commit!==config.sources.runtime.commit||llvm.commit!==config.sources.llvm.commit
    ||runtime.configuration.buildType!==config.buildType||runtime.configuration.version!==config.cangjieVersion)
    throw Error('SOURCE_COMPONENT_RESUME_CONFIGURATION');
  for(const component of Object.values(selection.targetComponents)) {
    const actual=await gitInput(component.repository,component.commit);
    if(component.tree!==actual.tree)throw Error('SOURCE_COMPONENT_RESUME_TREE '+component.repository);
  }
  return {...config,installInputs:{work:path.join(config.workspace,'build/sdk-install'),
    install:config.consumerSdk??path.join(config.softwareDir,'cangjie'),selection,
    buildJavaInterop:selection.platform==='linux_x86_64',javaJdk:config.toolsJniHome,
    tools:{launcher:process.env.CMAKE_CXX_COMPILER_LAUNCHER}}};
}

// A completed H1 can be installed for front-end consumers without claiming
// that N has a debugger or that R and target std have been built. Use the
// original producer's H execution and N library; do not accept an SDK overlay.
async function prepareH1FrontendInstall(descriptor,platform) {
  const {host:hostInput,sources,installations}=descriptor;
  const native=sdkPlatform(platform);
  if(!sources?.h1||!hostInput?.install||!installations?.llvm?.install||!installations.h1
    ||!descriptor.stdCoreInterface||descriptor.selection||descriptor.production||descriptor.archive)
    throw Error('INSTALL_H1_FRONTEND_INPUTS');
  const h1={...await gitInput(sources.h1,descriptor.h1Commit),
    ...(installations.shim?{shimInstall:await privateRoot(installations.shim.install)}:{})};
  const host={...hostInput,platform,install:await installation(hostInput.install,
    ['tools/bin/cjpm','runtime/lib/'+native.tuple+'/libcangjie-runtime'+native.shared])};
  const llvm={install:path.resolve(installations.llvm.install),platform};
  const product=await installedH1(installations.h1,{h1,host,llvm,platform,tools:{}});
  const shim=product.configuration.nativeShim;
  // A partial N prefix must still bind the actual libLLVM to this compiler.
  // The independent shim carries that hash; an ordinary N install carries it
  // in its producer facts.
  const library=shim.configuration?.llvmLibrary??(await readJson(path.join(llvm.install,'BUILD-INPUTS.json'))).llvmLibrary;
  const relative=path.posix.join('third_party/llvm',native.llvmDirectory,native.llvmLibrary);
  if(library?.file!==relative||library.sha256!==await fileDigest(path.join(llvm.install,relative)))
    throw Error('INSTALL_H1_FRONTEND_LLVM');
  // The public compiler resolves std.core within modules/<tuple>. Admit a
  // separately selected front-end module, without treating it as a std build.
  const core=await fs.realpath(descriptor.stdCoreInterface);
  const coreStat=await fs.stat(core);
  if(!coreStat.isFile()||!coreStat.size)throw Error('INSTALL_H1_FRONTEND_STD_CORE');
  const compiler={...h1,...product,platform,sourceRepository:await runtimeSourceRepository(h1.repository)};
  const selection={platform,hostPlatform:platform,bootstrapHost:host,
    compilerExecution:{role:'separate',stage:'h1-frontend',platform,compiler,runtime:host,
      llvm:{...llvm,commit:shim.llvm.commit,library}},
    targetComponents:{compiler},frontendStdCore:{file:core,sha256:await fileDigest(core)}};
  return {work:await privateRoot(descriptor.work),install:await privateRoot(descriptor.install),selection};
}

// Installation of existing native products uses the same inputs and recipe,
// without constructing the bootstrap graph or requiring private stage1 tools.
export async function prepareInstallInputs(descriptor) {
  const frontend=descriptor.layout==='h1-frontend';
  const selection=frontend?undefined:await componentSelection(descriptor);
  const host=hostPlatform(),{platform:frontendPlatform=host}=descriptor;
  const platform=frontend?frontendPlatform:selection.platform;
  // Cross installations execute on their native runner. A descriptor cannot
  // override the relationship between the selected target and this process.
  const cross=platform!==host;
  if(frontend&&(cross||sdkPlatform(platform).os!=='linux'))throw Error('INSTALL_H1_FRONTEND_PLATFORM');
  if(Object.hasOwn(descriptor,'cross')&&descriptor.cross!==cross)throw Error('INSTALL_CROSS_PLATFORM_CONFLICT');
  const prepared=frontend?await prepareH1FrontendInstall(descriptor,platform):await prepareComponentInstall(descriptor,selection);
  return {...descriptor,...prepared,platform,cross};
}

async function componentSelection(descriptor) {
  const supplied=structuredClone(descriptor.selection), members=supplied?.targetComponents;
  const work=await privateRoot(descriptor.work);
  // A locations-only component install consumes the upstream selection; never
  // interpret a target or a checkout's current HEAD as a request for a pin.
  if (supplied?.platform==='linux_x86_64' && descriptor.layout!=='native-output' && members
    && ['runtime','std','llvm'].every(name=>members[name] && !Object.hasOwn(members[name],'commit'))) {
    const pair=nativePair(process.env);
    if(!pair)throw Error('INSTALL_COMPONENT_SELECTION_REQUIRED');
    const {runtime,std,llvm}=members;
    for(const [row,ref] of [[runtime,pair.runtime],[std,pair.runtime],[llvm,pair.llvm]])
      Object.assign(row,await gitInput(row.repository,ref));
    const host=supplied.bootstrapHost;
    const observed=await execute(path.join(host.install,'bin','cjc'),['--version']);
    if((host.version && host.version!==pair.hostVersion)
      || hostToolchainFromCjcVersion(observed.stdout)!=='nightly-'+pair.hostVersion)throw Error('INSTALL_COMPONENT_HOST');
    host.version=pair.hostVersion;
    runtime.sourceRepository=await runtimeSourceRepository(runtime.repository);
    Object.assign(runtime,await receiveNativeRuntime({root:runtime.install,sourceRepository:runtime.sourceRepository,
      platform:supplied.platform,llvmCommit:llvm.commit,runtimeCommit:runtime.commit,
      hostVersion:host.version,work}));
    runtime.gateStatus=path.join(runtime.sourceRoot,'runtime','CMakebuild','gc-unit.status');
    const commands=await readJson(std.install+'.commands.json');
    const actions=commands.filter(row=>row.argv?.includes('build.py'));
    const accepted=commands.findLast(row=>row.argv?.[0]==='resume-accepted' && row.rc===0);
    const [build,installed]=accepted?[accepted.build,accepted.install]:actions.slice(-2).map(row=>row.argv);
    if(commands.some(row=>Object.hasOwn(row,'rc') && (row.rc!==0||row.signal||row.cancelled||row.error))
      || (!accepted && (actions.length<2 || actions.slice(-2).some(row=>row.rc!==0)))
      || flag(build??[],'-t')!==runtime.configuration.buildType || !build.includes('build')
      || !installed?.includes('install') || path.resolve(flag(installed,'--prefix')??'.')!==path.resolve(std.install))
      throw Error('INSTALL_COMPONENT_STD_BUILD');
    const provenance=await fs.readFile(path.join(std.install,'PROVENANCE.txt'),'utf8');
    if(provenance.match(/^STD_SOURCE_COMMIT = ([a-f0-9]{40})$/m)?.[1]!==std.commit
      || provenance.match(/^BUILT_BY_CJC = ([a-f0-9]{40})$/m)?.[1]!==members.compiler?.commit)
      throw Error('INSTALL_COMPONENT_STD');
    const facts=await readJson(llvm.buildResult??path.join(llvm.install,'BUILD-INPUTS.json'));
    if(facts.platform!==supplied.platform || facts.commits?.llvm!==llvm.commit)throw Error('INSTALL_COMPONENT_LLVM');
  }
  return installationSelection(supplied);
}

async function prepareComponentInstall(descriptor,selection) {
  const {platform,targetComponents:target,compilerExecution:execution}=selection,native=sdkPlatform(platform);
  const work=await privateRoot(descriptor.work),install=await privateRoot(descriptor.install);
  // An optional backend is a normal CMake component install, independent of
  // N's libLLVM/clang/CJDB/AST installation. Record the actual selected binaries
  // in the existing installation selection, without rewriting either producer.
  if(target.backend) {
    if(descriptor.layout==='native-output')throw Error('INSTALL_BACKEND_LAYOUT');
    const backend=target.backend;
    const tools=['llc','opt'].map(name=>'bin/'+name+native.exe);
    let recorded;
    if(backend.installed) {
      // The build directory is a cache that may since have been configured for
      // another prefix. A backend that a completed installation already
      // consumed is identified by that installation's record and by the
      // binaries themselves.
      backend.installed=await fs.realpath(backend.installed);
      const stage=await readJson(path.join(backend.installed,'STAGE-INPUTS.json'));
      const row=stage.selection?.targetComponents?.backend;
      if(!row||row.commit!==backend.commit||row.repository!==backend.repository||row.platform!==platform
        ||stage.sources?.backend?.commit!==backend.commit||stage.sources?.backend?.repository!==backend.repository
        ||path.resolve(backend.install)!==row.install
        ||(backend.build&&await fs.realpath(backend.build).catch(()=>path.resolve(backend.build))!==row.build)
        ||!row.configuration?.sourceRoot||!/^[a-f0-9]{40}$/.test(row.configuration.tree||'')
        ||!isDeepStrictEqual(row.artifacts?.map(item=>item.path),tools))
        throw Error('INSTALL_BACKEND_RECORD');
      backend.build=row.build;backend.configuration=row.configuration;recorded=row.artifacts;
    } else {
      backend.install=await fs.realpath(backend.install);
      backend.build=await fs.realpath(backend.build);
      const cache=await fs.readFile(path.join(backend.build,'CMakeCache.txt'),'utf8');
      const value=name=>new RegExp('^'+name+':[^=]+=(.*)$','m').exec(cache)?.[1]?.trim();
      if(!value('CMAKE_HOME_DIRECTORY')||!value('CMAKE_INSTALL_PREFIX')
        ||await fs.realpath(value('CMAKE_INSTALL_PREFIX'))!==backend.install)
        throw Error('INSTALL_BACKEND_CMAKE');
      const source=await gitInput(value('CMAKE_HOME_DIRECTORY'),backend.commit);
      if((await execute('git',['-C',source.repository,'rev-parse','HEAD'])).stdout.trim()!==backend.commit)
        throw Error('INSTALL_BACKEND_SOURCE');
      backend.configuration={sourceRoot:source.repository,tree:source.tree,
        buildType:value('CMAKE_BUILD_TYPE'),generator:value('CMAKE_GENERATOR')};
    }
    backend.artifacts=[];
    for(const [index,rel] of tools.entries()) {
      const name=['llc','opt'][index],file=backendArtifactPath(backend,rel);
      if(recorded&&!(await fs.lstat(file)).isFile())throw Error('INSTALL_BACKEND_RECORD '+name);
      if(!recorded) {
        const manifest=await fs.readFile(path.join(backend.build,'install_manifest_'+name+'.txt'),'utf8');
        if(!manifest.split(/\r?\n/).some(row=>path.resolve(row)===file))throw Error('INSTALL_BACKEND_COMPONENT '+name);
      }
      const bytes=await fs.readFile(file);
      if(!isDeepStrictEqual(embeddedStamp(bytes,'CJLLVM-COMMIT'),[backend.commit]))throw Error('INSTALL_BACKEND_SOURCE '+name);
      const sha256=await fileDigest(file);
      if(recorded&&recorded[index].sha256!==sha256)throw Error('INSTALL_BACKEND_RECORD '+name);
      backend.artifacts.push({path:rel,sha256});
    }
  }
  let dependencyRoot,compilerSha256;
  const executionPlatform=platform;
  if(descriptor.layout==='native-output') {
    // build.py installs the compiler and its linked inputs into one native
    // output. An install-only caller cannot replace just that compiler.
    const product=path.join(target.compiler.install,'bin','cjc'+native.exe);
    if(await fs.realpath(product)!==await fs.realpath(target.compiler.product))throw Error('INSTALL_NATIVE_COMPILER_PRODUCT');
    dependencyRoot=target.compiler.install;
  } else {
    const facts=await readJson(path.join(target.compiler.install,'compiler-inputs.json'));
    compilerSha256=await fileDigest(target.compiler.product);
    if(facts.commit!==target.compiler.commit||compilerSha256!==facts.compilerSha256)
      throw Error('INSTALL_COMPILER_PRODUCT');
    dependencyRoot=path.join(target.compiler.install,'.compiler-exec');
    if(await fileDigest(path.join(dependencyRoot,'lib',native.tuple,'libcangjie-std-core.a'))!==facts.stdCoreSha256)
      throw Error('INSTALL_COMPILER_STD_INPUT');
  }
  // Dependency locations belong to the compiler producer. The target program
  // and the package-manager host retain their independent selections. In
  // particular, an explicit old-but-existing execution tuple cannot override
  // these produced inputs.
  Object.assign(execution,{role:'separate',platform:executionPlatform,compiler:{...target.compiler},
    ...Object.fromEntries(['runtime','std','llvm'].map(name=>[name,{install:dependencyRoot,platform:executionPlatform}]))});
  const execNative=sdkPlatform(executionPlatform);
  const required=[
    target.compiler.product,
    target.std.install+'/modules/'+native.tuple+'/std/std.core.cjo',
    target.std.install+'/lib/'+native.tuple+'/libcangjie-std-core.a',
    target.runtime.install+'/runtime/lib/'+native.tuple+'/libcangjie-runtime'+native.shared,
    target.llvm.install+'/third_party/llvm/bin/llc'+native.exe,
    ...['runtime','std','llvm'].map(name=>dependencyRoot+(name==='runtime'
      ?'/runtime/lib/'+execNative.tuple+'/libcangjie-runtime'+execNative.shared:name==='std'
        ?'/lib/'+execNative.tuple+'/libcangjie-std-core.a':'/third_party/llvm/'+execNative.llvmDirectory+'/'+execNative.llvmLibrary)),
  ];
  for(const file of required)if(!(await fs.stat(file)).isFile())throw Error('INSTALL_INPUT_FILE '+file);
  console.log('INSTALL_COMPILER_EXECUTION_FROM_PRODUCER '+JSON.stringify({compiler:target.compiler.product,dependencyRoot,platform:executionPlatform}));
  // Cross installation is allowed, execution belongs to its native runner.
  const cross=platform!==hostPlatform();
  if(descriptor.javaInterop!==undefined)compilerSha256??=await fileDigest(target.compiler.product);
  const javaInterop=await javaInteropInput(descriptor.javaInterop,{platform,cross,compilerSha256,runtimeCommit:target.runtime.commit});
  return {work,install,selection,javaInterop};
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { await prepareNativeInputs(await readJson(process.argv[2] || process.env.CJCJ_NATIVE_INPUTS)); }
  catch (error) { console.error(error.stack); process.exitCode=1; }
}
