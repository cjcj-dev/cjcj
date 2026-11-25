import path from 'node:path';
import fs from 'node:fs/promises';
import {embeddedStamp} from '../../build/lib/toolchain-identity.mjs';

export function llvmLibraryNames(native) {
  return native.llvmFoundationLibrary ? [native.llvmLibrary, native.llvmFoundationLibrary] : [native.llvmLibrary];
}

// Native compiler links may also consume a monolithic SDK. Keep both the
// linker's resolved file and the installed DLL name for its execution prefix.
export async function compilerLlvmLibraries(sdk,native) {
  const libraries=[];
  for(const name of llvmLibraryNames(native)) {
    const relative=path.posix.join('third_party/llvm',native.llvmDirectory,name);
    try { libraries.push({relative,file:await fs.realpath(path.join(sdk,relative))}); }
    catch(error) { if(name!==native.llvmFoundationLibrary || error.code!=='ENOENT')throw error; }
  }
  return libraries;
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
