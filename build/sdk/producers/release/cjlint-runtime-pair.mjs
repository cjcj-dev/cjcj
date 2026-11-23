// The Linux cjlint install exposes its private runtime at both loader paths.
import path from 'node:path';
import fs from 'node:fs/promises';
import {safePayloadPath} from '../../../lib/release-component-provenance.mjs';
import {fileDigest} from '../../../../ci/bootstrap/sdk-flow.mjs';

const prefix = '.target-tools/tools/cjlint/';
const library = prefix + 'lib/libcangjie-runtime.so';
export const runtimeAlias = prefix + 'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so';

// Only the original SDK may contain the producer's exact relative alias.
// Never open through the link: use the separately checked regular library.
export async function cjlintRuntimeInput(root, records) {
  const lib = await safePayloadPath(root, library);
  const parent = await safePayloadPath(root, path.posix.dirname(runtimeAlias));
  const alias = path.join(parent, path.posix.basename(runtimeAlias));
  if (!(await fs.lstat(lib)).isFile() || !records?.[library]?.sha256 ||
      records[library].sha256 !== records[runtimeAlias]?.sha256)
    throw Error('CJLINT_RUNTIME_PAIR ' + library);
  const stat = await fs.lstat(alias);
  if (stat.isSymbolicLink() && await fs.readlink(alias) === '../../../lib/libcangjie-runtime.so')
    return library;
  if (!stat.isFile()) throw Error('CJLINT_RUNTIME_ALIAS ' + alias);
  return runtimeAlias;
}

// Transported bytes must already be two ordinary files. Preflight before
// replacing an existing tool, even when the sidecar matches an incomplete tree.
export async function requireCjlintRuntimePair(root) {
  const files = await Promise.all([library, runtimeAlias].map(rel => safePayloadPath(root, rel)));
  for (const file of files) {
    const stat = await fs.lstat(file).catch(error => {
      if (error.code === 'ENOENT') return null;
      throw error;
    });
    if (!stat?.isFile()) throw Error('CJLINT_RUNTIME_PAIR ' + file);
  }
  if (await fileDigest(files[0]) !== await fileDigest(files[1])) throw Error('CJLINT_RUNTIME_PAIR_BYTES');
}
