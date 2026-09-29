// Install the isolated fixed LLVM tuple into a release package stage.
//
// The official host SDK is never overwritten: ci/setup_sdk.mjs publishes the
// source-built llc/opt/lld tuple into an independent directory and exports
// CJCJ_PATCHED_LLVM_BIN. The published cjcj SDK is a different consumer of the
// same tuple -- it must ship the coloured backend that its own coloured runtime
// and self-built std were produced with -- so the packager copies the tuple into
// the stage it just cloned from the official SDK. That copy is the only place
// the coloured tools are allowed to live.
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';

const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');

// `llc`/`opt`/`ld.lld` on every platform, keyed by the manifest field that
// carries each tool's expected digest. Physical suffixes are the packager's
// concern, not the producer's: the isolated directory publishes bare names.
export function tupleToolPlan(lldTool) {
  return [
    {tool: 'llc', field: 'LLC_SHA256'},
    {tool: 'opt', field: 'OPT_SHA256'},
    {tool: lldTool, field: 'LLD_SHA256'},
  ];
}

export async function installIsolatedLlvmTuple({
  tupleBin, packagedLlvmBin, lldTool, manifestValues, exeSuffix = '', verify,
}) {
  if (typeof tupleBin !== 'string' || !tupleBin) {
    throw new Error('isolated LLVM tuple directory is required to package a coloured release SDK');
  }
  if (typeof verify !== 'function') throw new Error('tuple install verifier is required');
  const plan = tupleToolPlan(lldTool);
  const installed = [];
  for (const {tool, field} of plan) {
    const expected = manifestValues.get(field) || '';
    if (!/^[0-9a-f]{64}$/.test(expected)) {
      throw new Error(`${field} missing from the fixed LLVM manifest; refusing to guess ${tool}`);
    }
    const source = path.join(tupleBin, tool);
    const payload = await fs.readFile(source).catch(error => {
      throw new Error(`isolated ${tool} unreadable at ${source}: ${error.message}`);
    });
    const actual = hash(payload);
    if (actual !== expected) {
      throw new Error(`isolated ${tool} sha256 ${actual} does not match manifest ${expected}`);
    }
    const destination = path.join(packagedLlvmBin, `${tool}${exeSuffix}`);
    await fs.copyFile(source, `${destination}.new`);
    if (exeSuffix) {
      // The staged copy replaces a byte-identical official tool, so the mode the
      // SDK shipped it with is already right; only restore the bit on non-Windows.
      if (process.platform !== 'win32') await fs.chmod(`${destination}.new`, 0o755);
    }
    await fs.rename(`${destination}.new`, destination);
    if (hash(await fs.readFile(destination)) !== expected) {
      throw new Error(`staged ${tool} sha mismatch after install`);
    }
    await verify(tool, destination, expected);
    installed.push({tool, destination, sha256: expected});
  }
  return installed;
}
