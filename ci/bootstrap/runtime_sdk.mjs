// Bind a prepared full runtime root to the SDK actually consumed by stage3.
// This checks the shared pair and archive, not the rebuilt std's compatibility.
import path from 'node:path';
import fs from 'node:fs';
import {resolveRuntimeSource} from '../runtime-pin.mjs';
import {verifyRuntime, runtimeFiles, digest} from '../release/colour_runtime.mjs';
import {run} from '../../build/lib/runner.mjs';
import {objectId, execute} from './sdk-manifest.mjs';

export async function verifyBootstrapRuntimeSdk(sdk, tuple, env = process.env, sourceRoot, assemblyLockSha, producerManifest) {
  if (producerManifest) {
    // A new local producer has an actual source/completion receipt rather than
    // a GitHub artifact run. Preserve the existing pair/archive consumer checks
    // and bind them to that receipt; never invent an artifact id or source SHA.
    if (producerManifest.schema !== 'toolchain-sdk-resolved-v1' || producerManifest.status !== 'complete'
      || producerManifest.rc !== 0 || producerManifest.role !== 'target') throw new Error('BOOTSTRAP_RUNTIME_PRODUCER_MANIFEST');
    const lockFile = path.join(sdk, 'SDK.lock.json');
    if (!assemblyLockSha || digest(lockFile) !== assemblyLockSha) throw new Error('BOOTSTRAP_SDK_RUNTIME_LOCK_MISMATCH: assembly lock');
    const lock = JSON.parse(fs.readFileSync(lockFile, 'utf8'));
    if (lock.manifest_sha256 !== objectId(producerManifest) || lock.plan_sha256 !== producerManifest.planSha256
      || digest(path.join(sdk, 'SDK.manifest.json')) !== lock.manifest_sha256) throw new Error('BOOTSTRAP_RUNTIME_PRODUCER_MANIFEST_BINDING');
    const runtimeRef = lock.components?.runtime?.commit;
    if (!/^[0-9a-f]{40}$/.test(runtimeRef || '') || lock.role !== 'target') throw new Error('BOOTSTRAP_RUNTIME_PRODUCER_MANIFEST');
    const pair = producerManifest.files?.[runtimeFiles[0].replace('linux_x86_64_cjnative', tuple)];
    for (const base of runtimeFiles) {
      const rel = base.replace('linux_x86_64_cjnative', tuple), row = producerManifest.files?.[rel];
      const component = producerManifest.components?.[row?.component];
      if (!row || row.type !== 'file' || row.component !== pair?.component || row.buildId !== pair?.buildId
        || row.receiptSha256 !== pair?.receiptSha256 || component?.status !== 'complete' || component?.rc !== 0
        || component.source?.kind !== 'git' || component.execution?.source?.commit !== component.source.commit
        || component.execution?.source?.tree !== component.source.tree
        || component.source.commit !== runtimeRef || row.buildId !== component.buildId || row.receiptSha256 !== component.receiptSha256
        || lock.files?.[rel]?.sha256 !== row.sha256 || digest(path.join(sdk, rel)) !== row.sha256) {
        throw new Error(`BOOTSTRAP_SDK_RUNTIME_MISMATCH: ${rel}`);
      }
      if (path.basename(rel).startsWith('libcangjie-runtime.')) {
        if (component.source.commit !== runtimeRef) throw new Error(`BOOTSTRAP_SDK_RUNTIME_SOURCE_MISMATCH: ${rel}`);
        const stamps = [...new Set(fs.readFileSync(path.join(sdk, rel)).toString('latin1').match(/CJRT-COMMIT:[A-Za-z0-9_-]+/g) || [])];
        if (stamps.length !== 1 || stamps[0] !== `CJRT-COMMIT:${runtimeRef}`) throw new Error(`BOOTSTRAP_SDK_RUNTIME_STAMP_MISMATCH: ${rel}`);
      }
    }
    const shared = path.join(sdk, 'runtime/lib', tuple, 'libcangjie-runtime.so');
    const archive = path.join(sdk, 'lib', tuple, 'libcangjie-runtime.a');
    const masks = text => text.split('\n').filter(line => /\bg_cjLoadBadMask(?:@@?\S+)?$/.test(line)).length;
    const sharedMasks = masks((await execute('nm', ['-D', '--defined-only', shared])).stdout);
    const archiveMasks = masks((await execute('nm', ['--defined-only', archive])).stdout);
    if (sharedMasks !== 1 || archiveMasks < 1) {
      throw new Error(`BOOTSTRAP_SDK_RUNTIME_COLOUR_PAIR_MISMATCH: shared_masks=${sharedMasks} archive_masks=${archiveMasks}`);
    }
    console.log(`BOOTSTRAP_RUNTIME_PRODUCER_CONSUMER_VERIFIED runtime=${runtimeRef} plan=${producerManifest.planSha256}`);
    return;
  }
  const selection = await resolveRuntimeSource(env);
  if (sourceRoot) {
    const source = await run(['git', '-C', sourceRoot, 'rev-parse', 'HEAD'], {capture: true});
    if (source.stdout.trim().toLowerCase() !== selection.runtimeRef.toLowerCase()) {
      throw new Error('BOOTSTRAP_RUNTIME_SOURCE_MISMATCH');
    }
  }
  const root = verifyRuntime({...env, RUNTIME_REF: selection.runtimeRef});
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json'), 'utf8'));
  const lockFile = path.join(sdk, 'SDK.lock.json');
  if (assemblyLockSha && digest(lockFile) !== assemblyLockSha) {
    throw new Error('BOOTSTRAP_SDK_RUNTIME_LOCK_MISMATCH: assembly lock');
  }
  const lock = JSON.parse(fs.readFileSync(lockFile, 'utf8'));
  if (lock.role !== 'target') throw new Error('BOOTSTRAP_SDK_RUNTIME_LOCK_MISMATCH: role');
  if (lock.components?.runtime?.commit?.toLowerCase() !== selection.runtimeRef.toLowerCase()) {
    throw new Error('BOOTSTRAP_SDK_RUNTIME_LOCK_MISMATCH: commit');
  }
  if (lock.components?.runtime?.so_sha256 !== manifest.files[runtimeFiles[0]]) {
    throw new Error('BOOTSTRAP_SDK_RUNTIME_LOCK_MISMATCH: runtime SO');
  }
  for (const rel of runtimeFiles) {
    const installed = rel.replace('linux_x86_64_cjnative', tuple);
    if (digest(path.join(sdk, installed)) !== manifest.files[rel]) {
      throw new Error(`BOOTSTRAP_SDK_RUNTIME_MISMATCH: ${installed}`);
    }
    // Runtime provenance is linked into the shared/static runtime, not the
    // boundscheck target (runtime/CMakeLists.txt:470,792). The latter is bound
    // by its authenticated full-root and assembly-lock hashes.
    if (path.basename(installed).startsWith('libcangjie-runtime.')) {
      const stamps = [...new Set(fs.readFileSync(path.join(sdk, installed)).toString('latin1')
        .match(/CJRT-COMMIT:[A-Za-z0-9_-]+/g) || [])];
      if (stamps.length !== 1 || stamps[0] !== `CJRT-COMMIT:${selection.runtimeRef}`) {
        throw new Error(`BOOTSTRAP_SDK_RUNTIME_STAMP_MISMATCH: ${installed}`);
      }
    }
    if (lock.files?.[installed]?.sha256 !== manifest.files[rel]) {
      throw new Error(`BOOTSTRAP_SDK_RUNTIME_LOCK_MISMATCH: ${installed}`);
    }
  }
  // The assembly lock predates host-runner installation and promotion. Full
  // SDK verification remains at sdk_build/bootstrap's assembly boundary.
  // This admission proves only the actual runtime consumer's identity.
  console.log(`BOOTSTRAP_RUNTIME_CONSUMER_VERIFIED runtime=${selection.runtimeRef} manifest=${digest(path.join(root, 'manifest.json'))}`);
}
