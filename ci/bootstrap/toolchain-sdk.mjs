#!/usr/bin/env zx
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {parseArgs} from 'node:util';
import {fileURLToPath} from 'node:url';
import {PLAN_SCHEMA, RESOLVED_SCHEMA, validatePlan, buildIdentities, topological,
  readOutput, resolveFiles, readJson, atomicJson, canonical, objectId, fileDigest,
  physicalPath, reject, withLock, PLATFORMS, execute, relative} from './sdk-manifest.mjs';
import {produceComponent} from './sdk-producers.mjs';
import {verifyBootstrapRuntimeSdk} from './runtime_sdk.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
async function requiredInput(input, label) {
  if (await fileDigest(input.path) !== input.sha256) reject('VERIFICATION_INPUT', label, 'frozen verification input changed');
}
export async function verifyPayload(sdk, manifest) {
  for (const [rel, entry] of Object.entries(manifest.files)) {
    const file = path.join(sdk, rel), stat = await fs.lstat(file);
    if (entry.type === 'symlink') {
      if (!stat.isSymbolicLink() || await fs.readlink(file) !== entry.target) reject('PAYLOAD_TYPE', entry.component, rel);
      const resolved = await fs.realpath(file);
      if (!resolved.startsWith(`${sdk}${path.sep}`)) reject('LINK_ESCAPE', entry.component, rel);
    } else {
      if (!stat.isFile() || stat.isSymbolicLink() || stat.size !== entry.size || (stat.mode & 0o777) !== entry.mode) reject('PAYLOAD_TYPE', entry.component, rel);
    }
    if (await fileDigest(file) !== entry.sha256) reject('PAYLOAD_DIGEST', entry.component, rel);
  }
}
async function copyArtifacts(staging, manifest) {
  // These are the only payload copies. Every destination has exactly one
  // presealed producer source; no baseline directory copy can bypass the list.
  for (const [rel, entry] of Object.entries(manifest.files)) {
    const destination = path.join(staging, rel);
    await fs.mkdir(path.dirname(destination), {recursive: true});
    if (entry.type === 'symlink') {
      const source = path.join(entry.artifacts, entry.source);
      if (!(await fs.lstat(source)).isSymbolicLink() || await fs.readlink(source) !== entry.target) reject('PAYLOAD_TYPE', entry.component, entry.source);
      if (path.isAbsolute(entry.target) || !path.resolve(path.dirname(destination), entry.target).startsWith(`${staging}${path.sep}`)) reject('LINK_ESCAPE', entry.component, rel);
      await fs.symlink(entry.target, destination);
    } else {
      const source = await physicalPath(entry.artifacts, entry.source, entry.component);
      if (!(await fs.lstat(source)).isFile()) reject('PAYLOAD_TYPE', entry.component, entry.source);
      await fs.copyFile(source, destination, fs.constants.COPYFILE_EXCL);
      await fs.chmod(destination, entry.mode);
    }
  }
  // Hash the installed bytes once against producer-time digests. A changing
  // source cannot be blessed by generating a new lock from the copied bytes.
  // sdk_verify hashes these installed bytes against the presealed lock once.
}
async function verifySdk(sdk, plan, manifest) {
  const tuple = PLATFORMS[plan.platform][2];
  // Keep existing colour/ABI/lineage and native loadability checks. The legacy
  // verifier's --write-lock is no longer the authority for payload identity.
  await execute('python3', [path.join(here, 'sdk_verify.py'), '--sdk', sdk, '--role', plan.role,
    '--runtime-pin', plan.verification.runtimePin.path, '--target-tuple', tuple]);
  if (plan.role === 'target' && plan.verification.runtimeManifest) {
    await verifyBootstrapRuntimeSdk(sdk, tuple, {
      ...process.env, RUNTIME_REF: plan.components.find(component => component.roles.includes('runtime') && component.domain === 'target').source.commit,
      COLOUR_RT_ROOT: plan.verification.runtimeManifest.root,
      COLOUR_RT_MANIFEST_SHA256: plan.verification.runtimeManifest.sha256,
      COLOUR_RT_RUN_ID: plan.verification.runtimeManifest.runId,
      COLOUR_RT_RUN_ATTEMPT: plan.verification.runtimeManifest.runAttempt,
    });
  }
  if (!plan.platform.startsWith('linux_')) reject('VERIFIER_PLATFORM', plan.platform, 'native Darwin/Windows colour verifier migration remains required');
  await execute('python3', [path.join(here, 'std_runtime_colour.py'),
    '--colour-runtime', plan.verification.colourRuntime.path, '--host-runtime', plan.verification.hostRuntime.path,
    '--runtime', path.join(sdk, 'runtime/lib', tuple, 'libcangjie-runtime.so'),
    '--std', path.join(sdk, 'lib', tuple, 'libcangjie-std-core.a'), '--source', 'resolved-manifest']);
  const runtime = path.join(sdk, 'runtime/lib', tuple, 'libcangjie-runtime.so');
  const symbols = (await execute('nm', ['-D', '--defined-only', runtime])).stdout;
  const masks = symbols.split('\n').filter(line => /\bg_cjLoadBadMask(?:@@?\S+)?$/.test(line)).length;
  if (masks !== (plan.role === 'target' ? 1 : 0)) reject('RUNTIME_COLOUR', 'runtime', `role=${plan.role} masks=${masks}`);
  const tools = ['third_party/llvm/bin/llc', 'third_party/llvm/bin/opt', 'third_party/llvm/bin/ld.lld', 'tools/bin/cjpm'];
  if (plan.role === 'host') tools.push('bin/cjc');
  for (const rel of tools) {
    if (!manifest.files[rel]) reject('MISSING_ARTIFACT', 'tools', rel);
    const binary = path.join(sdk, rel);
    if (!(await execute('file', ['-bL', binary])).stdout.includes('ELF')) reject('EXECUTABLE_FORMAT', 'tools', rel);
    // envsetup is the existing SDK loading contract. Paths are passed as
    // positional arguments to a constant shell body, never evaluated as code.
    const host = plan.verification.hostRuntimeDir || '';
    const script = 'set -e; source "$1/envsetup.sh"; if [ -n "$2" ]; then export LD_LIBRARY_PATH="$2${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"; fi; exec "${@:3}"';
    const loaded = (await execute('bash', ['-c', script, 'sdk-verify', sdk, host, 'ldd', binary])).stdout;
    if (loaded.includes('not found')) reject('EXECUTABLE_LOAD', 'tools', `${rel}: ${loaded.trim()}`);
    await execute('bash', ['-c', script, 'sdk-verify', sdk, host, binary, '--version']);
  }
}
function installLock(plan, manifest) {
  const components = Object.fromEntries(plan.components.map(component => [component.id, component]));
  // Preserve sdk_verify's semantic classification even for retained official
  // files. Declaring the distribution must not bypass std/compiler pairing.
  const classify = rel => {
    if (/^bin\/(cjc|cjcj-stage1|cjc-frontend)$/.test(rel)) return 'cjc';
    if (rel === 'compiler-lineage.json') return 'sdk-meta';
    if (rel === 'std-producer.json' || rel.startsWith('modules/')) return 'std';
    if (rel.startsWith('tools/bin/cjpm')) return 'cjpm';
    if (rel.startsWith('third_party/llvm/')) return 'llvm';
    if (/\/(?:libcangjie-runtime|libboundscheck)/.test(rel)) return rel.includes('libboundscheck') ? 'boundscheck' : 'runtime';
    if (rel.startsWith('runtime/include/')) return 'runtime';
    if (rel.startsWith('lib/') || rel.startsWith('runtime/lib/')) return 'std';
    return 'official-retain';
  };
  const files = Object.fromEntries(Object.entries(manifest.files).map(([rel, entry]) => [rel, {
    sha256: entry.sha256, size: entry.size, mode: entry.mode, type: entry.type,
    component: classify(rel),
    symlink: entry.type === 'symlink', ...(entry.type === 'symlink' ? {link_target: entry.target} : {}),
    producer: {build_id: entry.buildId, receipt_sha256: entry.receiptSha256, source: components[entry.component].source},
  }]));
  const runtime = plan.components.find(component => component.domain === 'target' && component.roles.includes('runtime'));
  const llvm = plan.components.find(component => component.domain === 'target' && component.roles.includes('llvm-tools'));
  const runtimeFile = manifest.files[`runtime/lib/${PLATFORMS[plan.platform][2]}/libcangjie-runtime.so`];
  return {version: 1, role: plan.role, plan_sha256: objectId(plan), manifest_sha256: objectId(manifest), files,
    official_retain: Object.fromEntries(Object.entries(files).filter(([, row]) => row.component === 'official-retain')
      .map(([rel, row]) => [rel, row.producer.source.reason])),
    components: {runtime: {commit: runtime?.source.commit || null, so_sha256: runtimeFile?.sha256},
      llvm_tuple: {sha256: llvm?.source.commit || null},
      cjc: {sha256: (manifest.files['bin/cjcj-stage1'] || manifest.files['bin/cjc'])?.sha256}}};
}
export async function resolvePlan(plan, {dryRun = false, resumeFailed = false} = {}) {
  validatePlan(plan);
  const identities = buildIdentities(plan), outputs = new Map();
  if (dryRun) return {schema: 'toolchain-sdk-dry-run-v1', planSha256: objectId(plan),
    components: topological(plan).map(component => ({component: component.id, adapter: component.producer.adapter, ...identities.get(component.id)}))};
  for (const [name, input] of Object.entries(plan.verification)) if (input?.path) await requiredInput(input, name);
  for (const component of topological(plan)) {
    const identity = identities.get(component.id);
    await withLock(`${identity.directory}.lock`, async () => {
      let output;
      const directory = component.producer.receipt || identity.directory;
      try { output = await readOutput(directory, component, identity); }
      catch (error) {
        if (error.code !== 'ENOENT') throw error;
        output = await produceComponent(plan, component, identity, outputs, {resumeFailed});
      }
      outputs.set(component.id, output);
      console.log(`SDK_COMPONENT_READY component=${component.id} build_id=${output.buildId} receipt=${output.receiptSha256}`);
    });
  }
  const manifest = {schema: RESOLVED_SCHEMA, status: 'complete', rc: 0, planSha256: objectId(plan), role: plan.role,
    platform: plan.platform, stage: plan.stage,
    components: Object.fromEntries([...outputs].map(([id, output]) => [id, {buildId: output.buildId,
      directory: output.directory, receiptSha256: output.receiptSha256, source: output.component.source,
      config: output.component.config, producer: output.component.producer, dependencies: output.dependencies}])),
    files: resolveFiles(plan, outputs)};
  await fs.mkdir(plan.buildRoot, {recursive: true});
  await atomicJson(path.join(plan.buildRoot, `resolved-${manifest.planSha256}.json`), manifest);
  return manifest;
}
export async function assembleSdk(plan, out, {dryRun = false, resumeFailed = false} = {}) {
  validatePlan(plan);
  // Refuse unsupported verification BEFORE running any producer.
  if (!plan.platform.startsWith('linux_') && !dryRun) reject('VERIFIER_PLATFORM', plan.platform, 'native verifier migration incomplete');
  if (dryRun) return resolvePlan(plan, {dryRun});
  const parent = await fs.realpath(path.dirname(out)); out = path.join(parent, path.basename(out));
  if (out === '/root/sdks' || out.startsWith('/root/sdks/') || out === '/root/.cjv' || out.startsWith('/root/.cjv/')) reject('SHARED_INSTALL', 'sdk', out);
  if (out === plan.buildRoot || out.startsWith(`${plan.buildRoot}${path.sep}`)) reject('INSTALL', 'sdk', 'destination overlaps build root');
  return withLock(`${out}.lock`, async () => {
    try { await fs.lstat(out); reject('DESTINATION_EXISTS', 'sdk', out); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    const result = await resolvePlan(plan, {resumeFailed});
    const staging = `${out}.staging-${crypto.randomUUID()}`; await fs.mkdir(staging);
    try {
      await copyArtifacts(staging, result);
      const lock = installLock(plan, result);
      // Metadata identities are fixed before the existing verifier sees them.
      await atomicJson(path.join(staging, 'SDK.plan.json'), plan);
      await atomicJson(path.join(staging, 'SDK.manifest.json'), result);
      for (const name of ['SDK.plan.json', 'SDK.manifest.json']) lock.files[name] = {
        sha256: await fileDigest(path.join(staging, name)), component: 'sdk-meta', symlink: false,
        producer: {plan_sha256: result.planSha256, manifest_sha256: objectId(result)}};
      await atomicJson(path.join(staging, 'SDK.lock.json'), lock);
      await verifySdk(staging, plan, result);
      for (const [name, input] of Object.entries(plan.verification)) if (input?.path) await requiredInput(input, name);
      await fs.rename(staging, out);
      console.log(`SDK-BUILD-OK role=${plan.role} plan=${result.planSha256} manifest=${objectId(result)} to=${out}`);
      return {out, planSha256: result.planSha256, manifestSha256: objectId(result), lockSha256: await fileDigest(path.join(out, 'SDK.lock.json'))};
    } catch (error) {
      // The unpublished tree and exact failure survive for diagnosis.
      await atomicJson(`${staging}.failure.json`, {status: 'failed', rc: error.code ?? null, error: error.message}); throw error;
    }
  });
}
export async function main(args = process.argv.slice(2)) {
  const {values} = parseArgs({args, strict: true, options: {
    plan: {type: 'string'}, out: {type: 'string'}, 'dry-run': {type: 'boolean', default: false},
    resolve: {type: 'boolean', default: false},
    'resume-failed': {type: 'boolean', default: false},
  }});
  if (!values.plan || (!values.out && !values.resolve && !values['dry-run'])) throw new Error('usage: toolchain-sdk.mjs --plan JSON --out PRIVATE_SDK [--dry-run] [--resolve]');
  const plan = await readJson(values.plan);
  const options = {dryRun: values['dry-run'], resumeFailed: values['resume-failed']};
  const result = values.resolve ? await resolvePlan(plan, options) : await assembleSdk(plan, values.out, options);
  console.log(canonical(result).trim()); return result;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { await main(); } catch (error) { console.error(error.message); process.exitCode = 1; }
}
