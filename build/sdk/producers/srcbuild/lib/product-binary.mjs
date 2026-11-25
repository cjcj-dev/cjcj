// The unqualified cjc package has a portable name; older producers qualified it.
// Require exactly one so a stale product from another stage cannot be selected.

import fs from 'node:fs/promises';
import path from 'node:path';

/** Names cjpm is known to give the selfhost compiler, in no significant order. */
export const PRODUCT_NAMES = ['cjc', 'cjc@cjcj', 'cjcj::cjc'];

const isFile = async (target) => {
  try {
    return (await fs.stat(target)).isFile();
  } catch {
    return false;
  }
};

/**
 * Resolve the one compiler cjpm produced in `binDir`.
 *
 * Throws with the directory listing when there is no match: `cjpm build
 * success` plus a missing binary does not say whether the build produced
 * nothing or produced something under a name this list does not have, and a CI
 * round trip to find out costs hours.
 *
 * @param {string} binDir directory to search, usually target/release/bin
 * @param {string} phase  caller name, used in the error message
 * @returns {Promise<string>} absolute path to the product
 */
export async function resolveProductBinary(binDir, phase = 'product', {windows = false} = {}) {
  const names = windows ? [...PRODUCT_NAMES.map(name => `${name}.exe`), 'cjcj.exe'] : PRODUCT_NAMES;
  const found = [];
  for (const name of names) {
    const candidate = path.join(binDir, name);
    if (await isFile(candidate)) found.push(candidate);
  }
  if (found.length === 1) return found[0];

  let listing;
  try {
    listing = (await fs.readdir(binDir)).sort();
  } catch (error) {
    listing = `<${binDir} unreadable: ${error.code || error.message}>`;
  }
  if (found.length === 0) {
    throw new Error(
      `${phase}: none of ${names.join(', ')} exist in ${binDir}.\n` +
      `${binDir} contains: ${JSON.stringify(listing)}`,
    );
  }
  throw new Error(
    `${phase}: expected exactly one of ${names.join(', ')} in ${binDir}, found ${found.length}: ` +
    `${JSON.stringify(found.map((f) => path.basename(f)))}`,
  );
}
