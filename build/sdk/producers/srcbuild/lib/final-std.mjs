// Layout mirrors cangjie_runtime/stdlib/build_std_zh.md:47-54 and
// AddCangjieSource.cmake:296-301,376-399. In particular desktop Darwin does
// not emit LTO bitcode, while native Linux does.

import fs from 'node:fs/promises';
import path from 'node:path';

async function exists(target, kind = 'file') {
  try {
    const stat = await fs.stat(target);
    return kind === 'dir' ? stat.isDirectory() : stat.isFile();
  } catch {
    return false;
  }
}

export async function countFinalStd(root, target) {
  const {runtimeTuple: tuple, sharedLibrarySuffix} = target.spec;
  const modulesTop = path.join(root, 'modules', tuple);
  const modulesStd = path.join(modulesTop, 'std');
  const staticDir = path.join(root, 'lib', tuple);
  const sharedDir = path.join(root, 'runtime', 'lib', tuple);
  for (const directory of [modulesTop, modulesStd, staticDir, sharedDir]) {
    if (!await exists(directory, 'dir')) throw new Error(`final std directory missing: ${directory}`);
  }
  const [topModules, modules, staticLibs, sharedLibs] = await Promise.all([
    fs.readdir(modulesTop),
    fs.readdir(modulesStd),
    fs.readdir(staticDir),
    fs.readdir(sharedDir),
  ]);
  const escapedSuffix = sharedLibrarySuffix.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return {
    cjos: modules.filter(name => /^std\..+\.cjo$/.test(name)).length
      + Number(topModules.includes('std.cjo')),
    bitcode: modules.filter(name => /^libstd\..+\.bc$/.test(name)).length
      + Number(topModules.includes('libstd.bc')),
    staticLibs: staticLibs.filter(name => /^libcangjie-std(?:-|\.)?.*\.a$/.test(name) && !name.endsWith('FFI.a')).length,
    ffiStaticLibs: staticLibs.filter(name => /^libcangjie-std.*FFI\.a$/.test(name)).length,
    sharedLibs: sharedLibs.filter(name => new RegExp(`^libcangjie-std(?:-|\\.)?.*${escapedSuffix}$`).test(name)).length,
  };
}

export async function assertFinalStd(root, target, {dryRun = false} = {}) {
  const counts = await countFinalStd(root, target);
  const expected = dryRun
    ? {cjos: 1, bitcode: target.spec.expectedStdArtifacts.bitcode === 0 ? 0 : 1, staticLibs: 1, ffiStaticLibs: 1, sharedLibs: 1}
    : target.spec.expectedStdArtifacts;
  for (const [kind, count] of Object.entries(counts)) {
    if (count !== expected[kind]) throw new Error(`final std ${kind}: expected ${expected[kind]}, found ${count}`);
  }
  const provenance = path.join(root, 'PROVENANCE.txt');
  if (!await exists(provenance)) throw new Error(`final std provenance missing: ${provenance}`);
  console.log(
    `STAGE3_FINAL_STD_ASSERT_PASS target=${target.spec.key} tuple=${target.spec.runtimeTuple}`
      + ` cjos=${counts.cjos} bitcode=${counts.bitcode} static=${counts.staticLibs}`
      + ` ffi_static=${counts.ffiStaticLibs} shared=${counts.sharedLibs}${dryRun ? ' FAKE=1' : ''}`,
  );
  return counts;
}
