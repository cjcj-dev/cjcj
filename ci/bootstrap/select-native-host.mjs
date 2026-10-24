// Select the existing native producer's host; do not build or certify an SDK.
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {privateRoot, readJson, fileDigest} from './sdk-flow.mjs';
import {sdkPlatform, cleanSdkEnvironment} from './sdk-platform.mjs';
import {nativePair} from '../runtime-pin.mjs';
import {hostPlatform} from '../host-toolchain-pin.mjs';
import {targetForHost} from '../../build/lib/targets.mjs';
import {verifyOfficialSdkIdentity} from '../../build/lib/official-sdk-identity.mjs';
import {nativeSourceSelection} from './native-source-selection.mjs';
import {nativeInstallationLocations} from './native-installation-locations.mjs';
import {readInstalledNativeAst} from './installed-native-ast.mjs';
import {captureWindowsHostLlvm} from './native-windows-llvm-trace.mjs';
const execute=promisify(execFile);
export async function selectNativeHost(inputRoot, work, env=process.env, signal) {
  signal?.throwIfAborted();
  const pair=nativePair(env);if(!pair)throw new Error('NATIVE_HOST_EXPLICIT_PAIR_REQUIRED');
  const root=await privateRoot(inputRoot), platform=hostPlatform(), native=sdkPlatform(platform);
  const locations=await readJson(path.join(root,'locations.json'));
  if(locations.platform!==platform)throw new Error('NATIVE_HOST_PLATFORM');
  if(!locations.host?.install||!locations.host?.archive||locations.host.version!==pair.hostVersion)
    throw new Error('NATIVE_HOST_ORIGINAL_INPUT_REQUIRED');
  const member=async name=>{
    if(typeof name!=='string'||path.isAbsolute(name)||name.split(/[\\/]/).includes('..'))throw new Error('NATIVE_HOST_MEMBER_PATH');
    const actual=await fs.realpath(path.join(root,name));
    if(!actual.startsWith((await fs.realpath(root))+path.sep))throw new Error('NATIVE_HOST_MEMBER_ESCAPE');
    return actual;
  };
  const host={install:await member(locations.host.install),archive:await member(locations.host.archive),version:pair.hostVersion};
  const {selection,explicitAst}=nativeSourceSelection(env,pair);
  let ast;
  if(explicitAst){
    const installations=await nativeInstallationLocations(root,locations,env);
    const buildResult=installations.llvm?.buildResult;
    const facts=await readJson(buildResult),astResult=installations.ast?.buildResult;
    const astFacts=await readJson(astResult),astInstall=installations.ast?.install;
    if(facts.commits?.compiler!==selection.ast.commit||facts.commits?.llvm!==pair.llvm)throw Error('NATIVE_LLVM_AST_SOURCE_PAIR');
    const installed=await readInstalledNativeAst({install:astInstall,facts:astFacts,platform,commit:selection.ast.commit,llvmCommit:pair.llvm});
    ast={...selection.ast,llvm_commit:pair.llvm,
      build_inputs:{path:buildResult,sha256:await fileDigest(buildResult)},
      ast_inputs:{path:astResult,sha256:await fileDigest(astResult)},
      library:{path:installed.library,sha256:installed.files[installed.library].sha256}};
  }
  const hostSdk=await verifyOfficialSdkIdentity({root:host.install,archive:host.archive,
    version:'nightly-'+host.version,platform:targetForHost().spec.key,selectedHost:true,env});
  const library=await fs.realpath(path.join(host.install,'third_party/llvm',native.llvmDirectory,native.llvmLibrary));
  if(!library.startsWith(host.install+path.sep))throw new Error('NATIVE_HOST_LLVM_ESCAPE');
  const probeEnv=cleanSdkEnvironment(host.install,platform,env);
  if(native.os==='linux')probeEnv.LD_DEBUG='libs';
  else if(native.os==='darwin')probeEnv.DYLD_PRINT_LIBRARIES='1';
  else if(native.os!=='win32')throw new Error('NATIVE_HOST_EXECUTION_PLATFORM_UNSUPPORTED');
  const binary=path.join(host.install,'bin/cjc'+native.exe);
  await fs.mkdir(work,{recursive:true});
  const probe=path.join(work,'host-llvm.cj'), output=path.join(work,'libhostprobe.a');
  await fs.writeFile(probe,'package hostprobe\npublic func hostProbe(): Int64 { 7 }\n');
  async function run(label,argv) {
    try {
      const result=await execute(argv[0],argv.slice(1),{env:probeEnv,signal,maxBuffer:2*1024*1024,timeout:30000});
      await fs.writeFile(path.join(work,label+'.json'),JSON.stringify({argv,rc:0,signal:null,stdout:result.stdout}));
      await fs.writeFile(path.join(work,label+'.stderr'),result.stderr);
      return result;
    } catch(error) {
      await fs.writeFile(path.join(work,label+'.json'),JSON.stringify({argv,rc:error.code,signal:error.signal||null,stdout:error.stdout,stderr:error.stderr}));
      throw error;
    }
  }
  signal?.throwIfAborted();
  const compilerArgv=[binary,probe,'--output-type=staticlib','-o',output];
  await run('compiler',compilerArgv);
  let execution,librarySha256;
  if(native.os==='win32') {
    const system=env.SystemRoot||env.SYSTEMROOT;
    if(!system)throw Error('WINDOWS_TRACE_SYSTEM_ROOT_REQUIRED');
    const traceWork=path.join(work,'windows-llvm-trace');
    const trace=await captureWindowsHostLlvm({host:host.install,work:traceWork,env:probeEnv,
      tools:{logman:path.join(system,'System32/logman.exe'),tracerpt:path.join(system,'System32/tracerpt.exe')}},signal);
    const observed=trace.observation,row=trace.execution;
    // Consume the collector's same-spawn decoded observation. Unknown/raw-only
    // capture remains a rejection; neither a requested path nor a PE import is
    // a substitute for the payload/lifetime/loss checks in the decoder.
    if(trace.captureRc!==0||observed?.status!=='DECODED'||row?.rc!==0||row.signal||row.error
      ||row.cancelled||row.timedOut||!Number.isSafeInteger(row.pid)||row.pid<=0||observed.pid!==row.pid
      ||observed.loss?.events!==0||observed.loss?.buffers!==0||!observed.lifetime?.start||!observed.lifetime?.end
      ||!Array.isArray(row.loaded)||!row.loaded.length||!Array.isArray(observed.loaded)||!observed.loaded.length)
      throw Object.assign(Error('WINDOWS_LLVM_LOAD_EVIDENCE_NOT_DECODED'),{rc:2});
    const same=file=>typeof file==='string'&&path.win32.normalize(file).toLowerCase()===path.win32.normalize(library).toLowerCase();
    if(!same(trace.library?.path)||!row.loaded.every(same)||!observed.loaded.every(same))
      throw Error('NATIVE_HOST_ACTUAL_LLVM');
    execution={...row,executableSha256:trace.executableSha256,
      stdout:await fs.readFile(path.join(traceWork,row.stdout),'utf8'),stderr:path.join(traceWork,row.stderr),
      trace:{record:trace.record,observation:observed}};
    librarySha256=trace.library.sha256;
  } else {
    // cjc does not forward loader tracing to its subprocesses. Measure the
    // original host's LLVM executable separately; do not attribute it to cjc.
    const llvmTool=path.join(host.install,'third_party/llvm/bin/llc'+native.exe);
    const argv=[llvmTool,'--version'];
    const result=await run('host-llvm',argv);
    const lines=result.stderr.split('\n').filter(line=>line.includes('libLLVM')&&(native.os!=='linux'||line.includes('calling init:')));
    const loaded=[];
    for(const line of lines)for(const candidate of line.match(/\/[^\s]*libLLVM[^\s]*/g)||[])
      loaded.push(await fs.realpath(candidate).catch(()=>candidate));
    if(!loaded.includes(library)||loaded.some(file=>file!==library))throw new Error('NATIVE_HOST_ACTUAL_LLVM');
    execution={argv,rc:0,executableSha256:await fileDigest(llvmTool),
      stdout:result.stdout,loaded:[...new Set(loaded)],stderr:path.join(work,'host-llvm.stderr')};
    librarySha256=await fileDigest(library);
  }
  const hostLlvm={path:library,sha256:librarySha256,
    compilerExecution:{argv:compilerArgv,rc:0,output:{path:output,sha256:await fileDigest(output)}},execution};
  console.log('NATIVE_HOST_SELECTED '+JSON.stringify({platform,version:host.version,archive:hostSdk.archive.sha256,
    compiler:hostSdk.compiler,hostLlvm:hostLlvm.sha256,targetRuntime:pair.runtime,targetLlvm:pair.llvm}));
  return {host,hostSdk,hostLlvm,pair,platform,...(ast?{ast}:{})};
}
