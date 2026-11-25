// Only these fetch-owned inputs need materializing, even for the LLVM checkout.
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {prepareWindowsLlvmSource} from '../../../srcbuild/stages/fetch.mjs';

const windowsLlvm = ['llvm/include/llvm/IR/ConstantFolder.h', 'llvm/include/llvm/IR/NoFolder.h',
  'llvm/include/llvm/Analysis/InstSimplifyFolder.h', 'llvm/include/llvm/Demangle/ItaniumDemangle.h',
  'llvm/tools/sancov/sancov.cpp', 'lldb/source/Plugins/Process/gdb-remote/GDBRemoteCommunicationServerLLGS.cpp'];

export function fetchPatchRecipe(checkout, target) {
  if (target === 'windows-x64' && checkout === '.srcbuild/workspace/cangjie_compiler/third_party/llvm-project')
    return {files: windowsLlvm, apply: prepareWindowsLlvmSource};
}

// git cat-file --filters gives HEAD as it would be checked out (in particular
// CRLF on Windows). Never decode the blob or seed replay with producer bytes.
function pinnedInputs(dir, recipe) {
  const tree = spawnSync('git', ['-C', dir, 'ls-tree', '-z', 'HEAD', '--', ...recipe.files], {encoding: 'utf8'});
  if (tree.status !== 0) throw new Error('handoff cannot list pinned patch inputs: ' + dir);
  const modes = new Map(tree.stdout.split('\0').filter(Boolean).map(entry => [entry.split('\t')[1], entry.split(' ')[0]]));
  return recipe.files.map(rel => {
    const mode = modes.get(rel);
    if (!['100644', '100755'].includes(mode)) throw new Error('handoff invalid pinned patch input: ' + rel);
    const blob = spawnSync('git', ['-C', dir, 'cat-file', '--filters', 'HEAD:' + rel], {maxBuffer: 16 << 20});
    if (blob.status !== 0) throw new Error('handoff cannot read pinned ' + rel);
    return {rel, bytes: blob.stdout, executable: mode === '100755'};
  });
}

async function matches(file, bytes, executable = false) {
  const stat = await fs.lstat(file).catch(error => { if (error.code !== 'ENOENT') throw error; });
  if (!stat) return false;
  return stat.isFile() && (process.platform === 'win32' || Boolean(stat.mode & 0o100) === executable) &&
    bytes.equals(await fs.readFile(file));
}

export async function deriveFetchPatches(dir, checkout, recipe, dirty) {
  const inputs = pinnedInputs(dir, recipe), rows = [];
  const scratch = await fs.mkdtemp(path.join(os.tmpdir(), 'handoff-fetch-'));
  try {
    for (const {rel, bytes} of inputs) {
      const file = path.join(scratch, rel);
      await fs.mkdir(path.dirname(file), {recursive: true});
      await fs.writeFile(file, bytes);
    }
    recipe.apply(scratch);
    for (const {rel, bytes: original, executable} of inputs) {
      const full = checkout + '/' + rel, bytes = await fs.readFile(path.join(scratch, rel));
      const changed = !original.equals(bytes);
      if ((!changed && dirty.includes(rel)) || !await matches(path.join(dir, rel), bytes, executable))
        throw new Error('handoff modified tracked source: ' + full);
      if (changed) rows.push({kind: 'windows-llvm-fetch-patch', checkout, path: full, sha256: createHash('sha256').update(bytes).digest('hex')});
    }
    return rows;
  } finally {
    await fs.rm(scratch, {recursive: true, force: true});
  }
}

// Verify every input before the
// first write. Git diff alone would normalize a receiver's line endings.
export async function restoreFetchPatches(dir, checkout, recipe, dirty) {
  for (const {rel, bytes, executable} of pinnedInputs(dir, recipe)) {
    const full = checkout + '/' + rel;
    if (dirty.includes(rel) || !await matches(path.join(dir, rel), bytes, executable))
      throw new Error('handoff derivation target is not the pinned file: ' + full);
  }
  recipe.apply(dir);
}
