import {spawnSync} from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

// windows-2022 (kernel 20348): the msys2 mingw64 gcc 16 exits 1 on ANY compile
// with both streams empty while --version works, and the identical package
// works on windows-2025 (kernel 26100) — R27 probe evidence. The wrapper is
// plain C, so probe the installed compilers with a trivial source and use the
// first one that actually produces an executable.
//
// The runtime build requires the MINGW64/MSVCRT clang (build_runtime.mjs). On
// GitHub runners msys2/setup-msys2 installs MSYS2 under the runner temp
// directory (D:\a\_temp\msys64), not C:\msys64, and native-windows-tools
// exports that actual MINGW64 bin directory as CJCJ_NATIVE_LLVM_BIN. Probe it
// right after an explicit CC so the fixed C:\ locations are only fallbacks.
export const WINDOWS_RUNTIME_CC = /[\\/]mingw64[\\/]bin[\\/]clang\.exe$/i;
export function defaultWindowsCandidates(env = process.env, join = path.join) {
  return [
    env.CC,
    env.CJCJ_NATIVE_LLVM_BIN ? join(env.CJCJ_NATIVE_LLVM_BIN, 'clang.exe') : null,
    'C:\\msys64\\mingw64\\bin\\clang.exe',
    'C:\\mingw64\\bin\\clang.exe',
    'C:\\msys64\\mingw64\\bin\\gcc.exe',
    'C:\\mingw64\\bin\\gcc.exe',
    'C:\\msys64\\clang64\\bin\\clang.exe',
    'clang',
  ].filter(Boolean);
}
export async function pickWindowsCC(candidates = defaultWindowsCandidates()) {
  const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'cc-probe-'));
  const src = path.join(temp, 'probe.c');
  await fs.writeFile(src, 'int main(void) { return 0; }\n');
  const results = [];
  try {
    for (const cc of candidates) {
      const out = path.join(temp, `probe-${results.length}.exe`);
      const r = spawnSync(cc, [src, '-o', out], {encoding: 'utf8'});
      const produced = await fs.access(out).then(() => true, () => false);
      results.push(`${cc}: status=${r.status} error=${r.error ? r.error.code : 'none'} produced=${produced}`);
      if (r.status === 0 && produced) {
        console.log(`windows C compiler probe picked ${cc}\n${results.join('\n')}`);
        return cc;
      }
    }
  } finally {
    await fs.rm(temp, {recursive: true, force: true});
  }
  throw new Error(`no working C compiler on this runner:\n${results.join('\n')}`);
}
