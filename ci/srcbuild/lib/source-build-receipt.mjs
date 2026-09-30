import {execFileSync} from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileSha256} from './final-compiler.mjs';

const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const git = (directory, ...args) => execFileSync('git', ['-C', directory, ...args], {maxBuffer: 64 * 1024 * 1024});

// Capture the actual checkout, not CJSTD_COMMIT or a workflow label. Build-time
// version injection may change tracked files; bind that delta separately.
export function sourceIdentity(directory) {
  const commit = git(directory, 'rev-parse', 'HEAD').toString().trim();
  if (!/^[0-9a-f]{40}$/.test(commit)) throw new Error('source receipt requires a commit SHA');
  const root = git(directory, 'rev-parse', '--show-toplevel').toString().trim();
  const scope = path.relative(root, path.resolve(directory)) || '.';
  const untracked = git(root, 'ls-files', '--others', '--exclude-standard', '--', scope).toString().trim();
  if (untracked) throw new Error(`source receipt has untracked inputs: ${untracked}`);
  return {commit, scope, tree: git(root, 'rev-parse', `${commit}^{tree}`).toString().trim(),
    diffSha256: hash(git(root, 'diff', '--binary', 'HEAD', '--', scope))};
}

export async function captureBuildInputs({source, files, recipe}) {
  const inputs = {};
  for (const [role, file] of Object.entries(files)) inputs[role] = await fileSha256(file);
  return {schema: 1, source: sourceIdentity(source), inputs, recipe};
}

export async function finishBuildReceipt({source, captured, output, artifacts}) {
  if (JSON.stringify(sourceIdentity(source)) !== JSON.stringify(captured.source)) {
    throw new Error('source changed during build');
  }
  const products = {};
  for (const [role, file] of Object.entries(artifacts)) products[role] = await fileSha256(file);
  const receipt = {...captured, products};
  await fs.writeFile(output, `${JSON.stringify(receipt, null, 2)}\n`);
  return receipt;
}
