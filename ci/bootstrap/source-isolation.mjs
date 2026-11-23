// A compiler stage builds inside the pinned cjcj checkout, and several stages of
// one SDK chain share that checkout (05b-stage1 and 06e-stage2 both compile
// src.stage2). The checkout is an input, not scratch: runtime_shim/build_shim.mjs
// stamps every compiler with `git status --porcelain` of it, and a final std
// built by a `-dirty` compiler is rejected (STD_PROVENANCE).
//
// The package manager writes two tracked files as a side effect of building:
// the compile-option/trimpath rewrite of cjpm.toml, and cjpm.lock, which cjpm
// rewrites on every `cjpm build` (a 1.3 cjpm turns the committed `version = 0`
// into `version = 1`). Neither is a source change, but left behind they make the
// next stage of the same chain stamp an identity the source never had.
//
// So the build borrows these files and gives back exactly the bytes (or the
// absence) they had before it ran -- not HEAD's. A checkout that was already
// modified before the build stays modified, keeps its `-dirty` stamp and is
// still rejected; only the build's own writes are undone.
import fs from 'node:fs/promises';
import path from 'node:path';

export const COMPILER_BUILD_FILES = Object.freeze(['cjpm.toml', 'cjpm.lock']);

export async function withBuildFilesRestored(source, files, build) {
  const saved = [];
  for (const rel of files) {
    const file = path.join(source, rel);
    saved.push([file, await fs.readFile(file).catch(error => {
      if (error.code === 'ENOENT') return null;
      throw error;
    })]);
  }
  try {
    return await build();
  } finally {
    for (const [file, bytes] of saved) {
      if (bytes === null) await fs.rm(file, {force: true});
      else await fs.writeFile(file, bytes);
    }
  }
}
