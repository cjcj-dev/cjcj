// Bind a prepared full runtime root to the SDK actually consumed by stage3.
// This checks the shared pair and archive, not the rebuilt std's compatibility.
import path from 'node:path';
import fs from 'node:fs';
import {resolveRuntimeSource} from '../runtime-pin.mjs';
import {verifyRuntime, runtimeFiles, digest} from '../release/colour_runtime.mjs';
import {run} from '../../build/lib/runner.mjs';

export async function verifyBootstrapRuntimeSdk(sdk, tuple, env = process.env, sourceRoot) {
  const selection = await resolveRuntimeSource(env);
  if (sourceRoot) {
    const source = await run(['git', '-C', sourceRoot, 'rev-parse', 'HEAD'], {capture: true});
    if (source.stdout.trim().toLowerCase() !== selection.runtimeRef.toLowerCase()) {
      throw new Error('BOOTSTRAP_RUNTIME_SOURCE_MISMATCH');
    }
  }
  const root = verifyRuntime({...env, RUNTIME_REF: selection.runtimeRef});
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json'), 'utf8'));
  const lock = JSON.parse(fs.readFileSync(path.join(sdk, 'SDK.lock.json'), 'utf8'));
  if (lock.components?.runtime?.commit?.toLowerCase() !== selection.runtimeRef.toLowerCase()) {
    throw new Error('BOOTSTRAP_SDK_RUNTIME_LOCK_MISMATCH: commit');
  }
  for (const rel of runtimeFiles) {
    const installed = rel.replace('linux_x86_64_cjnative', tuple);
    if (digest(path.join(sdk, installed)) !== manifest.files[rel]) {
      throw new Error(`BOOTSTRAP_SDK_RUNTIME_MISMATCH: ${installed}`);
    }
    if (lock.files?.[installed]?.sha256 !== manifest.files[rel]) {
      throw new Error(`BOOTSTRAP_SDK_RUNTIME_LOCK_MISMATCH: ${installed}`);
    }
  }
  await run(['python3', new URL('./sdk_verify.py', import.meta.url).pathname,
    '--sdk', sdk, '--role', 'target', '--runtime-pin', env.CJCJ_BOOTSTRAP_RUNTIME_PIN || new URL('../runtime_pin.env', import.meta.url).pathname,
    '--target-tuple', tuple]);
  console.log(`BOOTSTRAP_SDK_RUNTIME_VERIFIED runtime=${selection.runtimeRef} manifest=${digest(path.join(root, 'manifest.json'))}`);
}
