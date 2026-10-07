#!/usr/bin/env zx
// Reuse the already produced, independently pinned std. Never build or publish.
import fs from 'node:fs';
import path from 'node:path';
import {acquire} from './bootstrap_store.mjs';
import {verifyDarwinStd} from './darwin_std.mjs';
import {digest} from './colour_runtime.mjs';
import {execute} from '../bootstrap/host_tools.mjs';
export async function prepareDarwinStdInput(runtime, platform, work) {
  const release = JSON.parse(fs.readFileSync(new URL('../colour-runtime/release.json', import.meta.url)));
  const pin = release.platforms?.[platform]?.std;
  const runtimeSha = digest(path.join(runtime, 'manifest.json'));
  // A caller-supplied combined input is consumed intact and never repaired.
  if (fs.existsSync(path.join(runtime, 'std-manifest.json'))) {
    verifyDarwinStd(runtime, platform, pin, runtimeSha);
    return runtime;
  }
  const scratch = fs.mkdtempSync(path.join(work, 'darwin-std-input-'));
  const std = process.env.CJCJ_BOOTSTRAP_DARWIN_STD;
  let prefix = std;
  if (!std) {
    if (!pin?.transport) throw new Error(`COLOUR_RT_STD_PROVENANCE_MISSING: ${platform}`);
    const transport = path.join(scratch, 'transport');
    await acquire(pin.transport, transport);
    prefix = path.join(scratch, 'std'); fs.mkdirSync(prefix);
    execute('tar', ['-xzf', path.join(transport, pin.archive), '-C', prefix]);
  }
  verifyDarwinStd(prefix, platform, pin, runtimeSha);
  const combined = path.join(scratch, 'combined');
  fs.cpSync(runtime, combined, {recursive:true,preserveTimestamps:true,verbatimSymlinks:true});
  const manifest = JSON.parse(fs.readFileSync(path.join(prefix, 'std-manifest.json')));
  for (const relative of [...Object.keys(manifest.files), 'std-manifest.json']) {
    const target = path.join(combined, relative);
    fs.mkdirSync(path.dirname(target), {recursive:true});
    fs.copyFileSync(path.join(prefix, relative), target);
  }
  verifyDarwinStd(combined, platform, pin, runtimeSha);
  return combined;
}
