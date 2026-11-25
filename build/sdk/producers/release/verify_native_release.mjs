#!/usr/bin/env zx
// Consumer of a complete installed SDK. All production remains in srcbuild.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {isMain, cliArgs} from '../../../../ci/entry-common.mjs';
import {nativePair} from '../../../../ci/runtime-pin.mjs';
import {spawnSync} from 'node:child_process';
import {parseArgs} from 'node:util';
import {assertNativeReleaseInputs, releaseSelection} from './native-release-inputs.mjs';
import {readJson, inventory, command} from '../../../../ci/bootstrap/sdk-flow.mjs';
import {selectInstalledColourSdk, colourEnvironment} from '../../../../ci/prepare-colour-sdk.mjs';
import {consumeInstalledLspMacro} from './installed-lsp-macro.mjs';
import {consumeWindowsProfiler} from './windows-profiler.mjs';
import {crossStdArguments} from './cross-std-arguments.mjs';
import {verifyCrossRuntime} from './cross-runtime.mjs';
import {readInstalledStdxInputs} from '../../../lib/installed-stdx-inputs.mjs';
import {installedInputs} from '../srcbuild/lib/installed-inputs.mjs';
import {verifyInstalledReleaseManifest} from '../../../lib/release-manifest.mjs';
import {assertSdkCompilerRuntimeAbi} from '../../../lib/runtime-split.mjs';
import {assertNoVerifierReportArtifacts} from '../package/verifier_artifact_gate.mjs';

async function compareSubtree(reference, sdk, relative) {
  const expected = await inventory(path.join(reference, relative));
  if (!Object.keys(expected).length) throw new Error(`NATIVE_RELEASE_EMPTY_PAYLOAD ${relative}`);
  const actual = await inventory(path.join(sdk, relative));
  for (const [name, value] of Object.entries(expected)) {
    if (JSON.stringify(actual[name]) !== JSON.stringify(value))
      throw new Error(`NATIVE_RELEASE_PAYLOAD_MISMATCH ${relative}/${name}`);
  }
}
// Exercise the public lint launcher with its own installed rules and analysis
// modules. The control must lose precisely the mutable-variable diagnostic.
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

export async function verifyNativeRelease(options, env = process.env) {
  const {sdk, platform, version, sourceSha, runtimeRef, releaseKey = '', std, crossRoot, work} = options;
  // Check the received target payloads before starting any host SDK consumers.
  const {release} = releaseSelection(platform, releaseKey);
  const args = crossStdArguments(env.CROSS_STD_ARTIFACTS || '[]', crossRoot || '');
  const rows = args.filter((_, i) => i % 2 === 1).filter((_, i) => args[i * 2] === '--cross-std-dir')
    .map(text => {const at = text.indexOf('='); return {tuple: text.slice(0, at), root: text.slice(at + 1)};});
  for (const {tuple, root} of rows) {
    if (!release.crossTuples.includes(tuple)) throw new Error('NATIVE_RELEASE_CROSS_INPUTS');
    for (const relative of ['modules/' + tuple, 'lib/' + tuple, 'runtime/lib/' + tuple])
      await compareSubtree(root, sdk, relative);
    const runtimeAt = args.findIndex((arg, i) => arg === '--cross-runtime-dir' && args[i + 1].startsWith(tuple + '='));
    if (runtimeAt >= 0) {
      const runtimeRoot = args[runtimeAt + 1].slice(tuple.length + 1);
      const record = await verifyCrossRuntime({root: runtimeRoot, tuple, runtimeRef});
      if (record.tuple !== tuple || record.runtimeRef !== runtimeRef) throw new Error('NATIVE_RELEASE_CROSS_RUNTIME');
      for (const relative of ['lib/' + tuple, 'runtime/lib/' + tuple]) await compareSubtree(runtimeRoot, sdk, relative);
    }
  }
  if (rows.length) console.log('NATIVE_RELEASE_CROSS_VERIFIED ' + rows.map(row => row.tuple).join(','));
  const {target, toolApplicability} = await assertNativeReleaseInputs(options,env);
  if (platform==='windows-x64') {
    const pair=nativePair(env),stage=await readJson(path.join(sdk,'STAGE-INPUTS.json'));
    if(!pair || stage.selection?.targetComponents?.llvm?.commit!==pair.llvm
      || stage.selection?.bootstrapHost?.version!==pair.hostVersion || pair.runtime!==runtimeRef)
      throw Error('WINDOWS_PACKAGE_SOURCE_PAIR');
  }
  assertNoVerifierReportArtifacts([sdk]);
  assertSdkCompilerRuntimeAbi({sdk, target});
  await verifyInstalledReleaseManifest({stage:sdk,platform:target.spec.llvmPlatform,...await installedInputs(sdk,target.spec.llvmPlatform)});
  // The independently delivered final std remains the content/count oracle.
  if (!std) throw new Error('NATIVE_RELEASE_STD_REQUIRED');
  await command([process.execPath, fileURLToPath(new URL('../package/check_packaged_std.mjs', import.meta.url)),
    '--sdk', sdk, '--std', std, '--platform', platform], {signal: AbortSignal.timeout(120000)});
  // crossStdArguments rejects duplicates; every delivered row belongs to this
  // release. Require the complete set alongside the mandatory host std.
  if (rows.length !== release.crossTuples.length) throw new Error('NATIVE_RELEASE_CROSS_INPUTS');
  await readInstalledStdxInputs({sdk,platform:target.spec.llvmPlatform,requireFull:true});
  await selectInstalledColourSdk(sdk, {...env, CJCJ_NATIVE_RUNTIME_REF: runtimeRef});
  const installedEnv = await colourEnvironment('run', {...env, CJCJ_NATIVE_RUNTIME_REF: runtimeRef});
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..');
  await command([process.execPath, path.join(root, 'build/sdk/producers/package/verify_packaged_cjdb.mjs'), sdk], {env: installedEnv});
  await command([process.execPath, path.join(root, 'ci/smoke/run_smoke.mjs'),
    path.join(sdk, 'bin/cjc' + target.spec.exeSuffix), path.join(work, 'smoke')],
  {env: {...installedEnv, CJCJ_OFFICIAL_SDK_ROOT: path.join(sdk, '.host')}});
  // The installed compiler passes an oversized final link to ld.lld through a
  // response file on Windows (!2161); this runs again from the relocated archive.
  if (target.spec.os === 'windows')
    await command([process.execPath, path.join(root, 'tests/upstream_compiler_1120/linker-response.mjs'),
      path.join(sdk, 'bin/cjc' + target.spec.exeSuffix), path.join(work, 'linker-response')], {env: installedEnv});
  if(target.spec.os==='windows'){
    await consumeInstalledLspMacro({sdk,work,platform:target.spec.llvmPlatform,env:installedEnv});
    await consumeWindowsLint(sdk,work,installedEnv);
    await consumeWindowsProfiler(sdk,work,installedEnv);
  }
  // Semantic success does not excuse mismatched producer or installation facts.
  const pending=Object.entries(toolApplicability).filter(([,row])=>row.applicability?.status==='NOT_CONSUMED'||(platform==='windows-x64'&&!row.ready)).map(([name])=>name);
  if(pending.length)throw new Error('NATIVE_RELEASE_TOOL_CONSUMPTION_NOT_RUN '+pending.join(','));
  console.log(`NATIVE_RELEASE_CONSUMED platform=${platform} version=${version} source=${sourceSha}`);
}
export function releaseArguments(args = cliArgs) {
  const names = ['sdk', 'platform', 'version', 'source-sha', 'runtime-ref', 'release-key', 'std', 'cross-root', 'work'];
  const {values} = parseArgs({args, options: Object.fromEntries(names.map(name => [name, {type: 'string'}]))});
  for (const key of ['sdk', 'platform', 'version', 'source-sha', 'runtime-ref', 'std', 'work'])
    if (!values[key]) throw new Error('--' + key + ' required');
  return {...values, sourceSha: values['source-sha'], runtimeRef: values['runtime-ref'],
    releaseKey: values['release-key'], crossRoot: values['cross-root']};
}
if (isMain(import.meta.url)) {
  try { await verifyNativeRelease(releaseArguments()); }
  catch (error) { console.error(error.stack); process.exitCode = error.rc || error.exitCode || 1; }
}
