#!/usr/bin/env zx
// Consumer of a complete installed SDK. All production remains in srcbuild.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {isMain, cliArgs} from '../entry-common.mjs';
import {parseArgs} from 'node:util';
import {assertNativeReleaseInputs} from './native-release-inputs.mjs';
import {readJson, inventory, command} from '../bootstrap/sdk-flow.mjs';
import {selectInstalledColourSdk, colourEnvironment} from '../prepare-colour-sdk.mjs';
import {crossStdArguments} from './cross-std-arguments.mjs';
import {verifyCrossRuntime} from './cross-runtime.mjs';
import {readInstalledStdxInputs} from '../../build/lib/installed-stdx-inputs.mjs';
import {installedInputs} from '../srcbuild/lib/installed-inputs.mjs';
import {verifyInstalledReleaseManifest} from '../../build/lib/release-manifest.mjs';
import {assertSdkCompilerRuntimeAbi} from '../../build/lib/runtime-split.mjs';
import {assertNoVerifierReportArtifacts} from '../../scripts/verifier_artifact_gate.mjs';

async function compareSubtree(reference, sdk, relative) {
  const expected = await inventory(path.join(reference, relative));
  if (!Object.keys(expected).length) throw new Error(`NATIVE_RELEASE_EMPTY_PAYLOAD ${relative}`);
  const actual = await inventory(path.join(sdk, relative));
  for (const [name, value] of Object.entries(expected)) {
    if (JSON.stringify(actual[name]) !== JSON.stringify(value))
      throw new Error(`NATIVE_RELEASE_PAYLOAD_MISMATCH ${relative}/${name}`);
  }
}
export async function verifyNativeRelease(options, env = process.env) {
  const {sdk, platform, version, sourceSha, runtimeRef, releaseKey = '', std, crossRoot, work} = options;
  const {target, release, toolApplicability} = await assertNativeReleaseInputs(options);
  assertNoVerifierReportArtifacts([sdk]);
  assertSdkCompilerRuntimeAbi({sdk, target});
  await verifyInstalledReleaseManifest({stage:sdk,platform:target.spec.llvmPlatform,...await installedInputs(sdk,target.spec.llvmPlatform)});
  // The independently delivered final std remains the content/count oracle.
  if (!std) throw new Error('NATIVE_RELEASE_STD_REQUIRED');
  await command([process.execPath, fileURLToPath(new URL('../../scripts/check_packaged_std.mjs', import.meta.url)),
    '--sdk', sdk, '--std', std, '--platform', platform], {signal: AbortSignal.timeout(120000)});
  const args = crossStdArguments(env.CROSS_STD_ARTIFACTS || '[]', crossRoot || '',
    {artifact: env.CROSS_STD_ARTIFACT, tuple: env.CROSS_STD_TUPLE});
  const rows = args.filter((_, i) => i % 2 === 1).filter((_, i) => args[i * 2] === '--cross-std-dir')
    .map(text => {const at = text.indexOf('='); return {tuple: text.slice(0, at), root: text.slice(at + 1)};});
  if (JSON.stringify(rows.map(row => row.tuple).sort()) !== JSON.stringify([...release.crossTuples].sort()))
    throw new Error('NATIVE_RELEASE_CROSS_INPUTS');
  for (const {tuple, root} of rows) {
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
  await readInstalledStdxInputs({sdk,platform:target.spec.llvmPlatform,requireFull:true});
  await selectInstalledColourSdk(sdk, {...env, CJCJ_NATIVE_RUNTIME_REF: runtimeRef});
  const installedEnv = await colourEnvironment('run', {...env, CJCJ_NATIVE_RUNTIME_REF: runtimeRef});
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
  await command([process.execPath, path.join(root, 'scripts/verify_packaged_cjdb.mjs'), sdk], {env: installedEnv});
  await command(['npx', '--yes', 'zx@8', path.join(root, 'ci/smoke/run_smoke.mjs'),
    path.join(sdk, 'bin/cjc' + target.spec.exeSuffix), path.join(work, 'smoke')],
  {env: {...installedEnv, CJCJ_OFFICIAL_SDK_HOME: path.join(sdk, '.host')}});
  // Compiler smoke is not a lint/LSP macro consumer. Preserve this missing
  // business gate after the independent installed consumers, rather than
  // preventing them from running or promoting a copied installation to PASS.
  const pending=Object.entries(toolApplicability).filter(([,row])=>row.applicability?.status==='NOT_CONSUMED').map(([name])=>name);
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
