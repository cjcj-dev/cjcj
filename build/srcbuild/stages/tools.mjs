// Port of cangjie-build/src/cangjie_build/stages/tools.py.

import fs from 'node:fs';
import os from 'node:os';
import {getLogger} from '../../lib/logging.mjs';
import {readHleDependencies} from '../../../ci/bootstrap/hle-input.mjs';
import {helloInstall} from '../../../ci/bootstrap/sdk-hello.mjs';
import {command,copyOutputs} from '../../../ci/bootstrap/sdk-flow.mjs';
import {toolConsumerCopies} from '../../../ci/bootstrap/sdk-targets.mjs';
import {cleanSdkEnvironment} from '../../../ci/bootstrap/sdk-platform.mjs';
import {installSourceTools,sourceToolOutputs} from '../install-tools.mjs';
import {beginToolBuild,finishToolBuild,toolBuildInputs,finishToolInstall} from '../tool-build-inputs.mjs';
import {TOOL_NAMES,TOOL_DIRECTORIES,requireToolProducer,toolBuildProduct,cjprofBuildDirectory,cjlintBuildDirectory,hleBuildDirectory,toolProducerDirectory} from '../tool-layout.mjs';
import {installHleDependencies,installIndependentHle} from '../hle-dependencies.mjs';
import {installPath as mingwInstallPath} from '../../toolchain/mingw.mjs';
import path from 'node:path';
import {BuildError} from '../../lib/errors.mjs';
import {assertSourceIdentity} from '../../lib/git.mjs';
import {stage} from '../../lib/logging.mjs';
import {baseEnv, bootstrapHostSdk, consumerSdk, requireFile, runBuildScript, explicitBuildJobs} from './common.mjs';

// All selected packages are built through the cjcj-tools public entry.
const TOOL_PATHS = TOOL_NAMES.map(name=>[name,TOOL_DIRECTORIES[name]]);
// The selected cjcj-tools commit owns all ten packages, including CJPM.
// Never overlay a second repository into an otherwise fixed tools checkout.
function toolArgv(config,name,args) {
  const native=[...args];
  const phase=name==='lsp'?native.splice(native.indexOf('--phase'),2)[1]:native.shift();
  let prefix;
  const prefixKey=name==='lsp'?'--install':'--prefix',i=native.indexOf(prefixKey);
  if(i>=0)prefix=native.splice(i,2)[1];
  return [process.execPath,path.join(config.repoPath('tools'),'build.mjs'),phase,'--tool',name,
    '--build-root',config.buildRoot,...(prefix?['--prefix',prefix]:[]),'--',...native];
}
const runTool=(config,name,cwd,args,options)=>runBuildScript(config,config.repoPath('tools'),toolArgv(config,name,args).slice(2),{...options,script:'build.mjs'});

function buildArgsFor(name, config, jobs) {
  if(['lsp','cjhead'].includes(name)) {
    if(config.target.spec.llvmPlatform!=='linux_x86_64'||config.target.spec.crossCompile)throw new BuildError('tools.'+name,'Cangjie analysis tools currently support Linux x86-64');
    for(const key of ['toolsCompilerLibs','toolsRuntimeConfig','toolsLlvmShim','toolsLlvmLibrary'])if(!config[key])throw new BuildError('tools.'+name,key+' is required');
    const sdk=consumerSdk(config),build=toolProducerDirectory(config,name);
    if(name==='lsp') {
      if(!config.toolsJsonBuild)throw new BuildError('tools.lsp','toolsJsonBuild is required');
      return ['--phase','build','--sdk',sdk,'--cjpm',path.join(bootstrapHostSdk(config),'tools/bin/cjpm'),'--build',build,'--server','stdio','--jobs',String(jobs),
        '--frontend-packages',config.toolsCompilerLibs,'--runtime-config',config.toolsRuntimeConfig,'--json-build',config.toolsJsonBuild,
        '--llvm-shim',config.toolsLlvmShim,'--llvm-library',config.toolsLlvmLibrary];
    }
    if(!config.toolsFrontendRef)throw new BuildError('tools.cjhead','toolsFrontendRef is required');
    return ['build','--cjc',path.join(sdk,'bin/cjc'),'--frontend-dir',config.toolsCompilerLibs,
      '--shim',config.toolsLlvmShim,'--runtime-config',config.toolsRuntimeConfig,'--llvm-lib',config.toolsLlvmLibrary,
      '--frontend-commit',config.toolsFrontendRef,'--source-commit',config.repo('tools').tag,
      '--runtime-dir',path.join(sdk,'runtime/lib/linux_x86_64_cjnative'),'--build-dir',build,'--jobs',String(jobs)];
  }
  if(name==='hle')return ['build','-t',config.buildType==='relwithdebinfo'?'release':config.buildType,'--build-dir',hleBuildDirectory(config),...(config.target.spec.crossCompile?['--target','windows-x86_64']:[])];
  if(name==='cjlint') {
    if(config.target.spec.os!=='linux'||config.target.spec.crossCompile||config.target.spec.llvmPlatform!=='linux_x86_64')throw new BuildError('tools.cjlint','selected Cangjie producer supports Linux x86-64');
    for(const key of ['toolsAnalysisSdk','toolsFrontendSource','toolsFrontendRef','toolsCompilerLibs','toolsRuntimeConfig','toolsLlvmShim','toolsLlvmLibrary'])if(!config[key])throw new BuildError('tools.cjlint',key+' is required');
    return ['build','--sdk',consumerSdk(config),'--cjpm-sdk',bootstrapHostSdk(config),'--analysis-sdk',config.toolsAnalysisSdk,
      '--frontend-source',config.toolsFrontendSource,'--frontend-ref',config.toolsFrontendRef,
      '--frontend-artifacts',config.toolsCompilerLibs,'--frontend-runtime-object',config.toolsRuntimeConfig,
      '--llvm-shim',config.toolsLlvmShim,'--llvm-library',config.toolsLlvmLibrary,
      '--build-dir',cjlintBuildDirectory(config),'--jobs',String(jobs)];
  }
  if(name==='cjprof') {
    if(config.target.spec.os!=='linux'||config.target.spec.crossCompile||config.target.spec.llvmPlatform!=='linux_x86_64')throw new BuildError('tools.cjprof','selected Cangjie producer supports Linux x86-64');
    for(const key of ['toolsJniHome','toolsRuntimeHeader','toolsLombokJar'])if(!config[key])throw new BuildError('tools.cjprof',key+' is required');
    return ['build','--sdk',consumerSdk(config),'--jni-home',config.toolsJniHome,'--runtime-header',config.toolsRuntimeHeader,'--lombok-jar',config.toolsLombokJar,'--build-dir',cjprofBuildDirectory(config)];
  }
  if(name==='cjcompat') {
    const source=config.repoPath('compiler'),sdk=consumerSdk(config);
    return ['build','--build-dir',toolProducerDirectory(config,name),'--type',config.buildType==='relwithdebinfo'?'release':config.buildType,
      '--sdk',sdk,'--compiler-source',source,'--compiler-libs',config.toolsCompilerLibs??path.join(source,'target/release'),
      '--runtime-config',config.toolsRuntimeConfig??path.join(source,'runtime_shim/cjc_runtime_config.o'),
      '--shim',config.toolsLlvmShim??path.join(sdk,'third_party/llvm/fixed-llc/cjselfhost_llvmshim.o'),
      '--llvm',config.toolsLlvmLibrary??path.join(sdk,'third_party/llvm/lib',config.target.spec.hostLlvmLibrary),
      '--jobs',String(jobs),'--tools-revision',config.repo('tools').tag];
  }
  if (name === 'cjtrace-recover') {
    // The sole producer is now the Cangjie module/CLI graph. The compiler
    // source input is explicit; no native demangler or Python fallback.
    const origin=config.target.spec.rpathOrigin;
    // Standalone install keeps the producer's CJTRACE_BUNDLE_RUNTIME=ON lib/.
    // The SDK recipe already supplies its selected target runtime; the retained
    // tool body can also resolve that runtime without copying an official H.
    const rpath=origin ? `${origin}/../lib`+(config.target.spec.os==='linux'?`:${origin}/../../../runtime/lib/${config.target.runtimeLibSubdir(config.buildType)}`:'') : '';
    return ['build','--build-dir',toolProducerDirectory(config,name),'-t',config.buildType==='relwithdebinfo'?'release':config.buildType,
      '--cangjie-sdk',consumerSdk(config),'--mangle-source',config.toolsMangleSource,
      ...(rpath?['--set-rpath',rpath]:[]),
      ...(config.target.spec.crossCompile?['--target','windows-x86_64','--target-sysroot',mingwInstallPath(config.buildRoot)]:[])];
  }
  // The initial component SDK has no CJPM until target tools are installed.
  // Its public cjc launcher still selects the compiler's target execution libraries.
  const dependencies=name==='cjfmt'?['--cjpm-sdk',bootstrapHostSdk(config)]:[];
  if (config.target.spec.crossCompile) {
    const args=['build','--build-dir',toolProducerDirectory(config,name), '-t', config.crossBuildType, '--target', 'windows-x86_64'];
    if(['cjpm','cjfmt','lsp','cjlint','cjprof','cjcompat'].includes(name))args.push('--jobs',String(jobs));
    return [...args,...dependencies];
  }
  const toolsBuildType = config.buildType === 'relwithdebinfo' ? 'release' : config.buildType;
  const args = ['build', '--build-dir',toolProducerDirectory(config,name),'-t', toolsBuildType];
  if (name === 'cjpm' && config.target.spec.rpathOrigin) {
    args.push(
      '--set-rpath',
      `${config.target.spec.rpathOrigin}/../../runtime/lib/${config.target.runtimeLibSubdir(config.buildType)}`,
    );
  }
  if(['cjpm','cjfmt','lsp','cjlint','cjprof','cjcompat'].includes(name))args.push('--jobs',String(jobs));
  return [...args,...dependencies];
}

function installArgsFor(name, toolsRoot, config, prefix) {
  const target=prefix??path.join(toolsRoot,TOOL_DIRECTORIES[name],'dist');
  if(name==='lsp')return ['--phase','install','--build',toolProducerDirectory(config,name),'--install',target];
  return ['install','--prefix',target,'--build-dir',toolProducerDirectory(config,name),
    ...(name==='cjlint'?['--analysis-sdk',config.toolsAnalysisSdk]:[])];
}

export function toolsFor(config) { return TOOL_PATHS; }

export function targetToolsEnv(config) {
  const env = baseEnv(config);
  const targetHome = consumerSdk(config);
  // Native tool development may consume an already installed matching stdx
  // prefix without modifying the selected read-only host SDK.
  if(!config.target.spec.crossCompile && process.env.CANGJIE_STDX_PATH) {
    const selected=process.env.CANGJIE_STDX_PATH;
    if(!path.isAbsolute(selected)||!fs.statSync(selected,{throwIfNoEntry:false})?.isDirectory())
      throw new BuildError('tools.stdx','CANGJIE_STDX_PATH must be an existing absolute directory: '+selected);
    env.CANGJIE_STDX_PATH=selected;
  }
  // Common flags use Clang's debug compilation directory option. Native
  // subprojects must not silently choose the host's default GCC instead.
  if(config.target.spec.nodePlatform==='linux') {
    env.CC ??= path.join(config.target.spec.llvmBinDir,'clang');
    env.CXX ??= path.join(config.target.spec.llvmBinDir,'clang++');
  }
  if(config.target.spec.crossCompile) {
    const targetStdx=path.join(config.repoPath('stdx'),'target',config.target.stdxTargetSubdir(),'static','stdx');
    if(process.env.CANGJIE_BUILD_DRY_RUN!=='1' && !fs.statSync(targetStdx,{throwIfNoEntry:false})?.isDirectory())throw new BuildError('tools.stdx','missing target stdx: '+targetStdx);
    env.CANGJIE_STDX_PATH=targetStdx;
  }
  const targetPaths = [path.join(targetHome, 'bin'), path.join(targetHome, 'tools', 'bin')];
  const remainingPaths = String(env.PATH || '').split(path.delimiter)
    .filter(entry => entry && !targetPaths.includes(entry));
  // Driver.cpp:49-52 derives the link SDK from the resolved cjc executable.
  // Keep baseEnv's plain-host loader, but select the target SDK's cjc so its
  // products use the target cjstart.o, built-in libraries, and runtime.
  env.PATH = [...targetPaths, ...remainingPaths].join(path.delimiter);
  return env;
}

function checkToolCaches(config, root) {
  if(config.target.spec.crossCompile)throw new BuildError('tools.incremental','incremental tools require a native target');
  // Only trace still uses a native CMake dependency graph. The other tools use
  // their normal CJPM cache or explicit compiler graph, never old C++ caches.
  const cache=path.join(toolProducerDirectory(config,'cjtrace-recover'),'CMakeCache.txt');
  if(!fs.existsSync(cache))return;
  const value=fs.readFileSync(cache,'utf8').split('\n').find(x=>x.startsWith('CMAKE_HOME_DIRECTORY:'))?.split('=').slice(1).join('=');
  if(value!==path.join(root,TOOL_DIRECTORIES['cjtrace-recover']))throw new BuildError('tools.incremental','source/configuration mismatch: '+cache);
}

// Partition CPU capacity, separately from the number of heavy producers.
// Affinity also bounds remaining upstream nested native work and
// nested C2 backends. Native jobs consume the same allocation, not total*jobs.
export function toolCpuPlan(names,totalJobs,workers,allowed) {
  if(!names.length)return {};
  if(!allowed && process.platform==='linux') {
    const list=fs.readFileSync('/proc/self/status','utf8').match(/^Cpus_allowed_list:\s*(.+)$/m)?.[1];
    allowed=list?.split(',').flatMap(part=>{const [a,b=a]=part.split('-').map(Number);return Array.from({length:b-a+1},(_,i)=>a+i);});
  }
  const count=Math.min(totalJobs,allowed?.length??totalJobs);
  const allocation=Object.fromEntries(names.map(name=>[name,1]));
  if(workers===1)for(const name of names)allocation[name]=count;
  else {
    let remaining=count-names.length;
    if(names.includes('cjpm')){const extra=Math.min(3,Math.max(0,remaining));allocation.cjpm+=extra;remaining-=extra;}
    const wide=names.filter(name=>['cjfmt','lsp','cjhead','cjtrace-recover','cjlint','cjprof','cjcompat'].includes(name));
    const recipients=wide.length?wide:names;
    for(let i=0;remaining>0;++i,--remaining)++allocation[recipients[i%recipients.length]];
  }
  let offset=0;
  return Object.fromEntries(names.map(name=>{
    const jobs=allocation[name];
    const cpus=allowed?(workers===1?allowed.slice(0,count):Array.from({length:jobs},(_,i)=>allowed[(offset+i)%count])):null;
    offset+=jobs;
    return [name,{jobs,cpuSet:cpus?.join(',')}];
  }));
}

export async function run(config) {
  const toolsRoot = config.repoPath('tools');
  const suffix = config.target.spec.exeSuffix;
  await stage('tools', async () => {
    const allTools=toolsFor(config);
    const selected=config.toolsBuildSet&&config.toolsBuildSet!=='all'?new Set(config.toolsBuildSet.split(',')):null;
    const pending=config.toolsPhase==='install'?[]:selected?allTools.filter(([name])=>!selected||selected.has(name)):allTools;
    if (pending.some(([name])=>name==='cjtrace-recover') && !config.toolsMangleSource)
      throw new BuildError('tools.cjtrace-recover.source','TOOLS_MANGLE_SOURCE_REQUIRED: --tools-mangle-source');
    // Independent native tools retain their original build facts and install
    // through the root tools entry into separate prefixes, without publishing an SDK.
    if(config.toolsInstallPrefix) {
      const independent=allTools.filter(([name])=>!selected||selected.has(name));
      if(config.target.spec.crossCompile)
        throw new BuildError('tools.install','independent install requires native tools');
      await assertSourceIdentity(config.repo('tools'),toolsRoot);
      for(const [name,subpath]of independent) {
        if(process.env.CANGJIE_BUILD_DRY_RUN!=='1') {
          requireFile(path.join(toolsRoot,'build.mjs'),{stage:'tools.'+name+'.source'});
          const facts=await toolBuildInputs(config,name,toolBuildProduct(config,name));
          if(facts.source.status!=='resolved')throw new BuildError('tools.install','original build inputs required: '+name);
        }
      }
      const env=targetToolsEnv(config);
      if(process.env.CANGJIE_BUILD_DRY_RUN!=='1')fs.mkdirSync(config.toolsInstallPrefix,{recursive:true});
      for(const [name,subpath]of independent) {
        const prefix=path.join(config.toolsInstallPrefix,name);
        const destination=name==='hle'?path.join(prefix,'tools'):prefix;
        if(process.env.CANGJIE_BUILD_DRY_RUN!=='1') {
          fs.mkdirSync(prefix,{recursive:false});
        }
        const argv=installArgsFor(name,toolsRoot,config,destination);
        await runTool(config,name,path.join(toolsRoot,subpath),argv,{stageName:'tools.'+name+'.install',extraEnv:env});
        if(name==='hle'&&process.env.CANGJIE_BUILD_DRY_RUN!=='1')await installIndependentHle({toolsRoot,prefix,sdk:consumerSdk(config),platform:config.target.spec.llvmPlatform,build:path.join(config.buildRoot,'hle-entries'),input:await readHleDependencies(process.env.CJCJ_HLE_DEPENDENCIES,config.target.spec.llvmPlatform)});
        await finishToolInstall(config,name,path.join(prefix,name==='hle'?'tools/bin':'bin',(name==='lsp'?'cangjie-lsp':name)+suffix),
          toolArgv(config,name,argv),{prefix});
      }
      return;
    }

    await assertSourceIdentity(config.repo('tools'), toolsRoot);
    if(process.env.CANGJIE_BUILD_DRY_RUN!=='1') {
      requireFile(path.join(toolsRoot,'build.mjs'),{stage:'tools.source'});
      for(const [name]of config.toolsPhase==='build'?pending:allTools)
        requireFile(path.join(toolsRoot,requireToolProducer(name),'build/build.mjs'),{stage:'tools.'+name+'.source'});
    }
    const toolEnv = targetToolsEnv(config);
    let dependencies;
    if(process.env.CANGJIE_BUILD_DRY_RUN!=='1' && (config.toolsPhase!=='build'||pending.some(([name])=>name==='hle'))) {
      const dependencyFile=process.env.CJCJ_HLE_DEPENDENCIES;
      const input=dependencyFile?await readHleDependencies(dependencyFile,config.target.spec.llvmPlatform):null;
      if(config.toolsPhase==='build') {
        if(!input)throw new BuildError('tools.hle.dependencies','HLE_DEPENDENCIES_REQUIRED');
        // Build uses the selected read-only SDK and explicit acquired inputs.
        // Dependency publication belongs to install, never to the shared H.
      } else dependencies=await installHleDependencies({toolsRoot,sdk:consumerSdk(config),platform:config.target.spec.llvmPlatform,input,prepareOnly:true});
    }
    // Each producer writes its own project build/dist tree. Shared HLE inputs
    // are installed above, and the shared SDK is published only after every
    // producer succeeds. Bound outer work; do not multiply it by native -j.
    const outputs=sourceToolOutputs(config);
    if(config.toolsBuildMode==='incremental'&&process.env.CANGJIE_BUILD_DRY_RUN!=='1')checkToolCaches(config,toolsRoot);
    if(selected&&config.toolsPhase!=='build'&&process.env.CANGJIE_BUILD_DRY_RUN!=='1') {
      for(const [name]of allTools.filter(([name])=>!selected.has(name))) {
        const row=outputs.find(row=>row.name===({lsp:'LSPServer'}[name]??name)+suffix);
        requireFile(row.from,{stage:`tools.${name}.reuse-existing-output`});
      }
    }
    const totalJobs=Math.min(config.jobs??Number(explicitBuildJobs(Infinity,os.availableParallelism())[1]),os.availableParallelism());
    const workers=Math.min(pending.length,totalJobs,(config.toolsPackageJobs??4)===4?pending.length:config.toolsPackageJobs);
    const plan=toolCpuPlan(pending.map(([name])=>name),totalJobs,workers);
    getLogger('cangjie_build.tools').info('TOOLS_BUDGET %s',JSON.stringify({totalJobs,heavyProducerLimit:config.toolsPackageJobs??4,workers,plan}));
    const failures = [];
    let next = 0;
    const installEnv={...toolEnv,CMAKE_BUILD_PARALLEL_LEVEL:String(totalJobs),MAKEFLAGS:'-j'+totalJobs};
    await Promise.all(Array.from({length:workers}, async () => {
      while (next < pending.length && failures.length === 0) {
        const [name, subpath] = pending[next++];
        const cwd = path.join(toolsRoot, subpath);
        const {jobs,cpuSet}=plan[name];
        const producerEnv={...toolEnv,...(name==='cjfmt'?{CJFMT_SOURCE_REF:config.repo('tools').tag}:{}),CANGJIE_BUILD_JOBS:String(jobs),CMAKE_BUILD_PARALLEL_LEVEL:String(jobs),MAKEFLAGS:'-j'+jobs};
        try {
          const output=outputs.find(row=>row.name===({lsp:'LSPServer'}[name]??name)+suffix);
          // Preserve the prior producer facts across failed rebuilds. Each
          // package entry owns first and incomplete dependency preparation
          // and consumes the budget selected above.
          const argv=buildArgsFor(name,config,jobs);
          const facts=await beginToolBuild(config,name,{argv:toolArgv(config,name,argv),env:producerEnv,sdk:consumerSdk(config)});
          await runTool(config,name,cwd,argv,{stageName:`tools.${name}.build`,extraEnv:producerEnv,cpuSet});
          const product=toolBuildProduct(config,name);
          if(process.env.CANGJIE_BUILD_DRY_RUN!=='1')requireFile(product,{stage:`tools.${name}.built-output`});
          await finishToolBuild(config,name,facts,product);
        } catch (error) {
          failures.push(error);
        }
      }
    }));
    // Retain responsibility for already-started producers until their exit;
    // a failure prevents new work and all shared publication.
    if (failures.length) throw new AggregateError(failures, 'tool producers failed; SDK was not published');
    if(config.toolsPhase==='build')return;
    // Validate reused outputs before any shared install. Their recorded source
    // may legitimately differ from this invocation's selectors.
    if(process.env.CANGJIE_BUILD_DRY_RUN!=='1')for(const [name]of allTools){
      const product=toolBuildProduct(config,name);
      await toolBuildInputs(config,name,product);
    }
    for (const [name, subpath] of allTools) {
      const argv=installArgsFor(name,toolsRoot,config);
      // Native install reads the build tree; preserve old dist separately so
      // removed configuration/JNI members cannot survive as new output.
      if(['cjfmt','cjlint','cjprof','cjcompat'].includes(name)&&process.env.CANGJIE_BUILD_DRY_RUN!=='1') {
        const dist=path.join(toolsRoot,TOOL_DIRECTORIES[name],'dist');
        if(fs.existsSync(dist))fs.renameSync(dist,dist+'.previous-'+Date.now());
      }
      await runTool(config,name,path.join(toolsRoot,subpath),argv, {
        stageName:`tools.${name}.install`, extraEnv:installEnv,
      });
      await finishToolInstall(config,name,outputs.find(row=>row.producer===name).from,toolArgv(config,name,argv));
    }
    requireFile(path.join(toolsRoot, TOOL_DIRECTORIES.cjpm, 'dist/bin', `cjpm${suffix}`), {stage: 'tools.cjpm.verify'});
    if(process.env.CANGJIE_BUILD_DRY_RUN!=='1') {
      const sdk=consumerSdk(config);
      await installSourceTools(config,sdk,{dependencies,consume:config.target.spec.crossCompile?undefined:async pending=>{
        const sdk=pending;
        await copyOutputs(sdk,await toolConsumerCopies(consumerSdk(config),config.target.spec.llvmPlatform));
      if(!config.target.spec.crossCompile)await helloInstall({sdk,
        work:path.join(config.workspace,'verify-tools'),platform:config.target.spec.llvmPlatform});
      if(!config.target.spec.crossCompile && config.target.spec.nodePlatform==='linux') {
        const installed=path.resolve(sdk);
        const env=cleanSdkEnvironment(installed,config.target.spec.llvmPlatform);
        // command merges overlays with process.env: explicitly keep the clean
        // environment's removals absent instead of inheriting an earlier SDK.
        for(const key of Object.keys(process.env))if(!(key in env))env[key]=undefined;
        env.CJPM_REGRESSION_CASES=undefined;
        // The test owns only this unpublished private SDK while it replaces
        // and restores the selected compiler entry. Keep the public cjpm path.
        env.CJPM_REGRESSION_PRIVATE_SDK=installed;
        const out=fs.mkdtempSync(path.join(config.workspace,'verify-cjpm-'));
        await command([process.execPath,path.join(toolsRoot,'packages/cjpm/tests/public/test-cache-errors.mjs'),
          path.join(installed,'tools/bin/cjpm'),out,'candidate'],{cwd:toolsRoot,env});
      }
      }});
    }
  });
}
