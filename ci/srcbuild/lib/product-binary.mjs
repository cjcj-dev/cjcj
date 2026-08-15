// Where the selfhost compiler lands after `cjpm build`.
//
// cjpm has emitted it under two names during this campaign -- `cjc@cjcj` and
// `cjcj::cjc` -- and which one appears depends on the cjpm in the SDK doing the
// build, not on anything the step controls. Every consumer therefore has to
// accept both.
//
// The 2026-08-15 release run is why this is a shared module rather than a list
// copied into each step. build-stage3 already knew about both names;
// build-stage1 and compose-sdk knew only `cjcj::cjc`. cjpm built the compiler
// successfully, named it `cjc@cjcj`, and stage 1 declared it missing seven
// hours into a five-platform run, taking every downstream phase with it. The
// list existed in the repository the whole time, one file over.
//
// Exactly-one is the contract, not first-match. Two products in the bin
// directory means a previous stage left one behind, and silently picking either
// would make the rest of the pipeline test an artifact nobody chose.

import fs from 'node:fs/promises';
import path from 'node:path';

/** Names cjpm is known to give the selfhost compiler, in no significant order. */
export const PRODUCT_NAMES = ['cjc@cjcj', 'cjcj::cjc'];

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
export async function resolveProductBinary(binDir, phase = 'product') {
  const found = [];
  for (const name of PRODUCT_NAMES) {
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
      `${phase}: none of ${PRODUCT_NAMES.join(', ')} exist in ${binDir}.\n` +
      `${binDir} contains: ${JSON.stringify(listing)}`,
    );
  }
  throw new Error(
    `${phase}: expected exactly one of ${PRODUCT_NAMES.join(', ')} in ${binDir}, found ${found.length}: ` +
    `${JSON.stringify(found.map((f) => path.basename(f)))}`,
  );
}
