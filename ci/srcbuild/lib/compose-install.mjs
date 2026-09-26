import fs from 'node:fs/promises';
import path from 'node:path';
import {fileSha256} from './final-compiler.mjs';

export const COMPOSE_COMPILER_NAMES = [
  'cjc',
  'cjc-frontend',
  'cjc-upstream-oracle',
  'cjc-oracle',
  'cjcj-stage1',
  'cjcj-stage2',
  'cjcj',
];

export async function installStage3Compiler({sdk, product, lineage}) {
  if (!lineage?.compilerSha256) throw new Error('compose stage3 lineage missing compilerSha256');
  if (await fileSha256(product) !== lineage.compilerSha256) {
    throw new Error('compose stage3 producer mismatch');
  }
  const bin = path.join(sdk, 'bin');
  await fs.mkdir(bin, {recursive: true});
  for (const name of COMPOSE_COMPILER_NAMES) await fs.rm(path.join(bin, name), {force: true});
  // The executable basename participates in frontend dispatch. The two public
  // entries must resolve to the managed compiler's local native filename.
  const native = path.join(bin, 'cjcj-stage1');
  await fs.copyFile(product, native);
  await fs.chmod(native, 0o755);
  for (const entry of ['cjc', 'cjc-frontend']) await fs.symlink('cjcj-stage1', path.join(bin, entry));
  const installed = path.join(bin, 'cjc');
  if (await fileSha256(installed) !== lineage.compilerSha256) {
    throw new Error('compose stage3 installed compiler mismatch');
  }
  return installed;
}
