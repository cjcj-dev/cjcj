import fs from 'node:fs/promises';
import {embeddedStamp} from '../../build/lib/toolchain-identity.mjs';

export function llvmLibraryNames(native) {
  return native.llvmFoundationLibrary ? [native.llvmLibrary, native.llvmFoundationLibrary] : [native.llvmLibrary];
}

// LLVMSupport owns the stamp: in a split install it lives in Foundation.
// Any additional stamps in the targets DLL must agree with that owner.
export async function inspectLlvmSource(libraries, commit) {
  const stamps = new Set();
  let ownerStamped = false;
  for (const file of libraries) {
    const values = embeddedStamp(await fs.readFile(file), 'CJLLVM-COMMIT');
    for (const value of values) stamps.add(value);
    if (file === libraries.at(-1)) ownerStamped = values.includes(commit);
  }
  return {stamps: [...stamps], matches: ownerStamped && stamps.size === 1};
}
