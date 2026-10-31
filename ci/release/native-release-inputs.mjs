#!/usr/bin/env zx
// Read the producer's installed files; this module never assembles an SDK.
import fs from 'node:fs/promises';
import {toolReadiness,toolSdkInputs,toolRuntimeInputs} from '../cangjie-test/tool-readiness.mjs';
import path from 'node:path';
import {isDeepStrictEqual} from 'node:util';
import {readJson, fileDigest} from '../bootstrap/sdk-flow.mjs';
import {getTarget, getReleasePlatform} from '../../build/lib/targets.mjs';
import {sourceOwnedTools} from '../../build/lib/release-component-provenance.mjs';
import {sourceToolPayloads} from './source-tool-payloads.mjs';
import {retainedToolPath, toolName} from '../../build/srcbuild/tool-layout.mjs';
import {installedStageOutput} from '../srcbuild/lib/installed-stage-output.mjs';

export function releaseSelection(platform, releaseKey = '') {
  const target = getTarget(platform);
  const release = getReleasePlatform(releaseKey || target.spec.packageHost.join('-'));
  if (release.host !== platform || release.excluded || release.crossCompiledHost)
    throw new Error('NATIVE_RELEASE_PLATFORM');
  return {target, release, tools: ['cjpm', ...sourceOwnedTools(target.spec.os === 'windows')]};
}
export async function assertNativeReleaseInputs({sdk, platform, releaseKey = '', version, sourceSha, runtimeRef}) {
  const selection = releaseSelection(platform, releaseKey), {target, tools} = selection;
  if (!/^[a-f0-9]{40}$/.test(sourceSha || '') || !/^[a-f0-9]{40}$/.test(runtimeRef || ''))
    throw new Error('NATIVE_RELEASE_FIXED_SOURCE_REQUIRED');
  const metadata = await readJson(path.join(sdk, 'STAGE-INPUTS.json'));
  if (metadata.compilerCommit !== sourceSha || metadata.runtimeCommit !== runtimeRef
      || metadata.platform !== target.spec.llvmPlatform)
    throw new Error('NATIVE_RELEASE_SOURCE_MISMATCH');
  const facts = await readJson(path.join(sdk, 'BUILD-MANIFEST.json'));
  if (facts.target !== platform || facts.version !== version) throw new Error('NATIVE_RELEASE_PACKAGE_IDENTITY');
  const toolInputs = await readJson(path.join(sdk, 'TOOLS-INPUTS.json'));
  for (const tool of tools) {
    const name = tool + target.spec.exeSuffix, publicPath = 'tools/bin/' + name;
    const retained = retainedToolPath({producer:toolName(tool),name,to:publicPath});
    for (const relative of [publicPath, publicPath + '.entry', retained,
      ...(tool === 'cjpm' ? ['tools/config/cangjie-repo.toml'] : sourceToolPayloads(tool, platform))]) {
      if (!(await fs.stat(path.join(sdk, relative)).catch(() => null)))
        throw new Error(`NATIVE_RELEASE_TOOL_MISSING ${tool} ${relative}`);
    }
    const recipe = (await fs.readFile(path.join(sdk, publicPath + '.entry'), 'utf8')).trimEnd().split('\n');
    if (recipe[0] !== 'cjcj-sdk-entry-v1' || recipe[2] !== retained)
      throw new Error(`NATIVE_RELEASE_TOOL_ENTRY ${tool}`);
    const produced = toolInputs.files?.[publicPath];
    if (produced?.sha256 !== await fileDigest(path.join(sdk, retained)))
      throw new Error(`NATIVE_RELEASE_TOOL_BYTES ${tool}`);
    // Match the installed producer's original facts, never the selector of a
    // later install-only invocation. Old unresolved records remain unresolved.
    const source = produced.producer?.source, build = produced.producer?.build;
    const rows = facts.components?.filter(row => row.component === tool) ?? [];
    if (source?.status !== 'resolved' || !source.repository || !/^[a-f0-9]{40}$/.test(source.commit || '')
        || rows.length !== 1 || !isDeepStrictEqual(rows[0].source, source))
      throw new Error(`NATIVE_RELEASE_TOOL_SOURCE ${tool}`);
    if (build?.rc !== 0 || build.platform !== target.spec.llvmPlatform
        || !Array.isArray(build.argv) || !build.argv.length || !build.environment || !build.inputs
        || !isDeepStrictEqual(rows[0].build, build))
      throw new Error(`NATIVE_RELEASE_TOOL_BUILD ${tool}`);
    // A native macro consumer's installation can select a new runtime without
    // changing its original build history. Readiness below must still reject
    // that combination until its current runtime consumer actually ran.
    const runtimeInputs = toolRuntimeInputs(tool).length
      ? toolInputs.installationInputs ?? build.inputs : build.inputs;
    if (toolSdkInputs(tool).includes('runtime') && runtimeInputs.stage?.runtimeCommit !== runtimeRef)
      throw new Error(`NATIVE_RELEASE_TOOL_RUNTIME ${tool}`);
    const artifact = {path: retained, sha256: produced.sha256};
    const entry = {path: publicPath, sha256: await fileDigest(path.join(sdk, publicPath)),
      recipe: {path: publicPath + '.entry', sha256: await fileDigest(path.join(sdk, publicPath + '.entry'))}};
    // Legacy records had one unchanged artifact. A normal install may rewrite
    // RPATH/install-name; new records bind installed bytes and keep raw intact.
    const install = produced.producer?.install;
    const installedArtifact = install === undefined ? produced.producer?.artifact : install?.artifact;
    if ((install !== undefined && install?.rc !== 0) || installedArtifact?.sha256 !== artifact.sha256
        || !isDeepStrictEqual(produced.artifact, artifact) || !isDeepStrictEqual(rows[0].artifact, artifact)
        || !isDeepStrictEqual(produced.entry, entry) || !isDeepStrictEqual(rows[0].entry, entry))
      throw new Error(`NATIVE_RELEASE_TOOL_INSTALL ${tool}`);
  }
  for (const [relative, row] of Object.entries(toolInputs.payloadFiles ?? {})) {
    if (path.isAbsolute(relative) || relative.includes('\\') || relative.split('/').includes('..')
        || row.sha256 !== await fileDigest(path.join(sdk, relative)))
      throw new Error('NATIVE_RELEASE_TOOL_PAYLOAD ' + relative);
  }
  const original = facts.inputs?.['TOOLS-INPUTS.json'];
  if (original?.path !== 'TOOLS-INPUTS.json' || original.sha256 !== await fileDigest(path.join(sdk, 'TOOLS-INPUTS.json')))
    throw new Error('NATIVE_RELEASE_TOOL_INPUT_RECORD');

  console.log(`NATIVE_RELEASE_TOOL_FACTS tools=${tools.join(',')}`);
  const readiness=await toolReadiness(sdk);
  // Admission to this invocation's tests checks the actual installation. A
  // changed native SDK selection is not a circular prerequisite for running
  // those tests, and availability does not assert their semantic result.
  for(const tool of tools)if(!readiness[tool]?.available)
    throw new Error(`NATIVE_RELEASE_TOOL_DEPENDENCIES ${tool}: ${readiness[tool]?.reason || 'missing producer'}`);

  const output = await installedStageOutput(sdk, metadata.phase);
  if (!['stage2-target-sdk', 'stage3'].includes(metadata.phase)) throw new Error('NATIVE_RELEASE_FINAL_STAGE');
  const compiler = await readJson(path.join(sdk, 'compiler-inputs.json'));
  if (compiler.commit !== sourceSha || compiler.compilerSha256 !== output.lineage.compilerSha256)
    throw new Error('NATIVE_RELEASE_COMPILER_INPUTS');
  console.log(`NATIVE_RELEASE_INPUTS target=${platform} tools=${tools.join(',')} source=${sourceSha}`);
  return {...selection,toolApplicability:readiness};
}
