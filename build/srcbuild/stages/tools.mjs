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
import {prepareNativeToolDependencies} from '../native-tool-dependencies.mjs';
import {TOOL_NAMES,TOOL_DIRECTORIES,requireToolProducer,toolBuildProduct} from '../tool-layout.mjs';
import {installHleDependencies} from '../hle-dependencies.mjs';
import {installPath as mingwInstallPath} from '../../toolchain/mingw.mjs';
import path from 'node:path';
import {BuildError} from '../../lib/errors.mjs';
import {fetchSource, assertSourceIdentity} from '../../lib/git.mjs';
import {stage} from '../../lib/logging.mjs';
import {run as runCommand} from '../../lib/runner.mjs';
import {applyTextPatch, baseEnv, consumerSdk, requireFile, runBuildPy, explicitBuildJobs} from './common.mjs';

// cjcov and cjtrace-recover are Cangjie-written SDK tools that upstream
// cangjie-build does not drive, so shipping the base SDK's copies would leave
// them compiled by a foreign toolchain. Both expose the same clean/build/install
// verbs as the four ported tools.
const TOOL_PATHS = TOOL_NAMES.map(name=>[name,TOOL_DIRECTORIES[name]?path.join(TOOL_DIRECTORIES[name],'build'):null]);
// cjtrace-recover is a CMake project: an install without --prefix resolves to
// CMAKE_INSTALL_PREFIX (/usr/local by default), so it must be pointed at a
// directory inside the repo, mirroring the dist/ the other tools produce.
const CJTRACE_DIST = path.join('cjtrace-recover', 'dist');
const CJPM_NEEDLE = '/opt/buildtools/llvm-mingw-w64';
const CJPM_EDITS = [[
  '-L /opt/buildtools/llvm-mingw-w64/x86_64-w64-mingw32/lib',
  "-L {os.path.join(os.environ['MINGW_PATH'], 'x86_64-w64-mingw32', 'lib')}",
]];

function readCjpmPin(config) {
  const {url,tag:ref}=config.repo('cjpm');
  if(!url||!/^[0-9a-f]{40}$/.test(ref??''))throw new BuildError('tools.cjpm.source','fixed cjpm source required');
  return {url,ref};
}

async function checkoutPinnedCjpm(config,toolsRoot) {
  const {url, ref} = readCjpmPin(config);
  await fetchSource(url, ref, {cwd: toolsRoot, stage: 'tools.cjpm.fetch'});
  const fetched = await runCommand(['git', 'rev-parse', 'FETCH_HEAD'], {
    cwd: toolsRoot, stage: 'tools.cjpm.pin', capture: true, logOutput: false,
  });
  if (process.env.CANGJIE_BUILD_DRY_RUN !== '1' && fetched.stdout.trim() !== ref) {
    throw new BuildError('tools.cjpm.pin', `fetched ${fetched.stdout.trim() || '<empty>'}, expected ${ref}`);
  }
  await runCommand(['git', 'restore', '--source', ref, '--staged', '--worktree', '--', 'cjpm'], {cwd: toolsRoot, stage: 'tools.cjpm.checkout'});
}

function buildArgsFor(name, config, jobs) {
  const dependencies=['cjlint','cjprof'].includes(name)?['--dependencies',config.toolsDependencies]
    :name==='cjcompat'?['--sdk',consumerSdk(config)]:[];
  if (config.target.spec.crossCompile) {
    const args=['build', '-t', config.crossBuildType, '--target', 'windows-x86_64'];
    if(name==='cjtrace-recover')args.push('--target-sysroot',mingwInstallPath(config.buildRoot),'--cangjie-sdk',consumerSdk(config));
    if(['cjpm','cjfmt','lsp','cjlint','cjprof','cjcompat'].includes(name))args.push('--jobs',String(jobs));
    return [...args,...dependencies];
  }
  const toolsBuildType = config.buildType === 'relwithdebinfo' ? 'release' : config.buildType;
  const args = ['build', '-t', toolsBuildType];
  if(name==='cjlint' && config.toolsGccToolchain)args.push('--gcc-toolchain',config.toolsGccToolchain);
  if (name === 'cjpm' && config.target.spec.rpathOrigin) {
    args.push(
      '--set-rpath',
      `${config.target.spec.rpathOrigin}/../../runtime/lib/${config.target.runtimeLibSubdir(config.buildType)}`,
    );
  }
  if(['cjpm','cjfmt','lsp','cjlint','cjprof','cjcompat'].includes(name))args.push('--jobs',String(jobs));
  return [...args,...dependencies];
}

function installArgsFor(name, toolsRoot) {
  if (['cjlint','cjprof','cjcompat'].includes(name))return ['install','--prefix',path.join(toolsRoot,name,'dist')];
  if (name !== 'cjtrace-recover') return ['install'];
  return ['install', '--prefix', path.join(toolsRoot, CJTRACE_DIST)];
}

export function toolsFor(config) { return TOOL_PATHS; }

export function targetToolsEnv(config) {
  const env = baseEnv(config);
  const targetHome = consumerSdk(config);
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
  const buildType=config.buildType==='relwithdebinfo'?'release':config.buildType;
  for(const [build,source]of [['cjpm/cpp/build','cjpm/cpp'],['cjfmt/build/build','cjfmt'],
    ['cangjie-language-server/build-lsp','cangjie-language-server'],['cjtrace-recover/cmake-build','cjtrace-recover']]) {
    const cache=path.join(root,build,'CMakeCache.txt');
    if(!fs.existsSync(cache))continue;
    const text=fs.readFileSync(cache,'utf8');
    const value=key=>text.split('\n').find(line=>line.startsWith(key+':'))?.split('=').slice(1).join('=');
    if(value('CMAKE_HOME_DIRECTORY')!==path.join(root,source)||value('CMAKE_BUILD_TYPE')?.toLowerCase()!==(source==='cjpm/cpp'?'release':buildType))
      throw new BuildError('tools.incremental','source/configuration mismatch: '+cache);
  }
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
    const wide=names.filter(name=>['cjfmt','lsp','cjtrace-recover','cjlint','cjprof','cjcompat'].includes(name));
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
    const pending=config.toolsPhase==='install'?[]:selected?allTools.filter(([name])=>selected.has(name)):allTools;
    // Independent native tools retain their original build facts and install
    // through upstream build.py into separate prefixes, without publishing an SDK.
    if(config.toolsInstallPrefix) {
      const independent=allTools.filter(([name])=>selected.has(name));
      if(config.target.spec.crossCompile || independent.some(([name])=>!['cjfmt','lsp','cjlint','cjprof','cjcompat','cjtrace-recover'].includes(name)))
        throw new BuildError('tools.install','independent install requires native tools');
      await assertSourceIdentity(config.repo('tools'),toolsRoot);
      for(const [name,subpath]of independent) {
        if(process.env.CANGJIE_BUILD_DRY_RUN!=='1') {
          requireFile(path.join(toolsRoot,subpath,'build.py'),{stage:'tools.'+name+'.source'});
          const facts=await toolBuildInputs(config,name,toolBuildProduct(config,name));
          if(facts.source.status!=='resolved')throw new BuildError('tools.install','original build inputs required: '+name);
        }
      }
      const env=targetToolsEnv(config);
      if(process.env.CANGJIE_BUILD_DRY_RUN!=='1')fs.mkdirSync(config.toolsInstallPrefix);
      for(const [name,subpath]of independent) {
        const prefix=path.join(config.toolsInstallPrefix,name);
        const destination=name==='lsp'?path.join(prefix,'bin'):prefix;
        if(process.env.CANGJIE_BUILD_DRY_RUN!=='1') {
          fs.mkdirSync(prefix,{recursive:false});
          if(name==='lsp')fs.mkdirSync(destination);
        }
        const argv=['install','--prefix',destination];
        await runBuildPy(config,path.join(toolsRoot,subpath),argv,{stageName:'tools.'+name+'.install',extraEnv:env});
        await finishToolInstall(config,name,path.join(prefix,'bin',(name==='lsp'?'LSPServer':name)+suffix),
          ['python3','build.py',...argv],{prefix});
      }
      return;
    }

    // Missing ninth producer must fail before fetching or shared installation.
    for(const [name]of config.toolsPhase==='build'?pending:allTools) {
      const directory=requireToolProducer(name);
      if(process.env.CANGJIE_BUILD_DRY_RUN!=='1')requireFile(path.join(toolsRoot,directory,'build/build.py'),{stage:'tools.'+name+'.source'});
    }
    await assertSourceIdentity(config.repo('tools'), toolsRoot);
    await checkoutPinnedCjpm(config,toolsRoot);
    const cjpmBuildPy = path.join(toolsRoot, 'cjpm', 'build', 'build.py');
    if (fs.readFileSync(cjpmBuildPy, 'utf8').includes(CJPM_NEEDLE)) {
      applyTextPatch(cjpmBuildPy, CJPM_EDITS, {stage: 'tools.cjpm.patch'});
    }
    await prepareNativeToolDependencies(config,pending.map(([name])=>name));
    const toolEnv = targetToolsEnv(config);
    let dependencies;
    if(process.env.CANGJIE_BUILD_DRY_RUN!=='1' && (config.toolsPhase!=='build'||pending.some(([name])=>name==='hle'))) {
      const dependencyFile=process.env.CJCJ_HLE_DEPENDENCIES;
      const input=dependencyFile?await readHleDependencies(dependencyFile,config.target.spec.llvmPlatform):null;
      if(config.toolsPhase==='build') {
        if(!input)throw new BuildError('tools.hle.dependencies','HLE_DEPENDENCIES_REQUIRED');
        const installed=JSON.parse(fs.readFileSync(path.join(consumerSdk(config),'tools/dtsparser/DEPENDENCIES.json'),'utf8'));
        for(const key of ['node','modules','cjbind'])for(const field of ['source','version','path'])
          if(installed[key]?.[field]!==input[key]?.[field])throw new BuildError('tools.hle.dependencies','installed input mismatch: '+key+'.'+field);
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
        const producerEnv={...toolEnv,CANGJIE_BUILD_JOBS:String(jobs),CMAKE_BUILD_PARALLEL_LEVEL:String(jobs),MAKEFLAGS:'-j'+jobs};
        try {
          if(config.toolsBuildMode!=='incremental')await runBuildPy(config, cwd, ['clean'], {stageName:`tools.${name}.clean`, extraEnv:producerEnv,cpuSet});
          const output=outputs.find(row=>row.name===({lsp:'LSPServer'}[name]??name)+suffix);
          // These upstream Python mains discard a returned error. Preserve a
          // prior final executable so a failed rebuild cannot masquerade as it.
          if(config.toolsBuildMode==='incremental'&&['cjpm','hle','cjcov'].includes(name)
            &&process.env.CANGJIE_BUILD_DRY_RUN!=='1'&&fs.existsSync(output.from)) {
            const saved=fs.mkdtempSync(path.join(path.dirname(output.from),'.previous-build-'));
            fs.renameSync(output.from,path.join(saved,path.basename(output.from)));
          }
          // The pinned native LSP entry owns first and incomplete dependency
          // preparation, consuming the same --jobs as its final CMake build.
          const argv=buildArgsFor(name,config,jobs);
          const facts=await beginToolBuild(config,name,{cjpmPin:readCjpmPin(config),argv:['python3','build.py',...argv],env:producerEnv,sdk:consumerSdk(config)});
          await runBuildPy(config, cwd, argv, {stageName:`tools.${name}.build`, extraEnv:producerEnv,cpuSet});
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
      const argv=installArgsFor(name,toolsRoot);
      // Native install reads the build tree; preserve old dist separately so
      // removed configuration/JNI members cannot survive as new output.
      if(['cjlint','cjprof','cjcompat'].includes(name)&&process.env.CANGJIE_BUILD_DRY_RUN!=='1') {
        const dist=path.join(toolsRoot,name,'dist');
        if(fs.existsSync(dist))fs.renameSync(dist,dist+'.previous-'+Date.now());
      }
      await runBuildPy(config, path.join(toolsRoot,subpath), argv, {
        stageName:`tools.${name}.install`, extraEnv:installEnv,
      });
      await finishToolInstall(config,name,outputs.find(row=>row.producer===name).from,['python3','build.py',...argv]);
    }
    requireFile(path.join(toolsRoot, 'cjpm', 'dist', `cjpm${suffix}`), {stage: 'tools.cjpm.verify'});
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
        await command([process.execPath,path.join(toolsRoot,'cjpm/tests/public/test-cache-errors.mjs'),
          path.join(installed,'tools/bin/cjpm'),out,'candidate'],{cwd:toolsRoot,env});
      }
      }});
    }
  });
}
