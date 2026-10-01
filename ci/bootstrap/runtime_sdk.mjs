// Bind a prepared full runtime root to the SDK actually consumed by stage3.
// This checks the shared pair and archive, not the rebuilt std's compatibility.
import path from 'node:path';
import fs from 'node:fs';
import {resolveRuntimeSource} from '../runtime-pin.mjs';
import {verifyRuntime, runtimeFiles, digest} from '../release/colour_runtime.mjs';
import {run} from '../../build/lib/runner.mjs';

export async function verifyBootstrapRuntimeSdk(sdk, tuple, env = process.env, sourceRoot, assemblyLockSha) {
  const selection = await resolveRuntimeSource(env);
  if (sourceRoot, assemblyLockSha) {
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
  if (lock.components?.runtime?.commit?.toLowerCase() !== selection.runtimeRef.toLowerCase()) {
    throw new Error('BOOTSTRAP_SDK_RUNTIME_LOCK_MISMATCH: commit');
  }
  for (const rel of runtimeFiles) {
    const installed = rel.replace('linux_x86_64_cjnative', tuple);
    if (digest(path.join(sdk, installed)) !== manifest.files[rel]) {
      throw new Error(`BOOTSTRAP_SDK_RUNTIME_MISMATCH: ${installed}`);
    }
    const stamps = [...new Set(fs.readFileSync(path.join(sdk, installed)).toString('latin1')
      .match(/CJRT-COMMIT:[A-Za-z0-9_-]+/g) || [])];
    if (stamps.length !== 1 || stamps[0] !== `CJRT-COMMIT:${selection.runtimeRef}`) {
      throw new Error(`BOOTSTRAP_SDK_RUNTIME_STAMP_MISMATCH: ${installed}`);
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
