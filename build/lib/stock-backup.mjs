import fs from 'node:fs/promises';
import path from 'node:path';

// Where a replaced stock binary is kept.
//
// It used to sit next to its replacement in tools/bin, which envsetup.sh puts on
// PATH, so `hle-stock` was one word away from running a binary we have measured
// dying with rc=139 against the packaged std. Keeping the fallback is worth it
// during stabilisation; keeping it on PATH is not.
export const STOCK_DIRECTORY = path.join('tools', 'stock');

const README = `These are the binaries the release replaced, kept so a broken
source-built tool can be swapped back by hand.

This directory is deliberately NOT on PATH: envsetup.sh exports
"$CANGJIE_HOME/bin" and "$CANGJIE_HOME/tools/bin", and nothing else. A stock
binary matches the std it was built against, not the std this package ships, so
running one by accident is a crash rather than a fallback. Use it by full path,
knowingly.
`;

/**
 * Preserve the currently installed binary before it is replaced. Keeps the first
 * one it sees, so re-running an install does not overwrite the original stock
 * copy with an already-replaced one.
 *
 * @returns {Promise<string>} path of the preserved copy
 */
export async function preserveStock({sdk, installed, name}) {
  const directory = path.join(path.resolve(sdk), STOCK_DIRECTORY);
  await fs.mkdir(directory, {recursive: true});
  await fs.writeFile(path.join(directory, 'README.txt'), README);
  const stock = path.join(directory, name);
  try {
    await fs.access(stock);
  } catch {
    await fs.copyFile(installed, stock);
  }
  return stock;
}
