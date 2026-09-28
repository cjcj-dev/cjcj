import {compilerLlvmName} from '../../../build/lib/compiler-loader.mjs';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {writeComponentProvenance, verifyComponentProvenance} from '../../../build/lib/release-component-provenance.mjs';

export const FINAL_COMPILER_PROVENANCE = 'FINAL-COMPILER-PROVENANCE.json';
export const fileSha256 = async file => crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex');

// Use the full installed std payload, including its producer manifest. The same
// snapshot is checked at the producer and immediately before package selection.
export async function stdIdentity(root, layoutRoot = root) {
  const entries = [];
  async function walk(directory) {
    for (const item of (await fs.readdir(directory, {withFileTypes: true})).sort((a, b) => a.name.localeCompare(b.name))) {
      const file = path.join(directory, item.name);
      const relative = path.relative(layoutRoot, file).split(path.sep).join('/');
      const installed = path.join(root, relative);
      if (item.isDirectory()) await walk(file);
      else if (item.isSymbolicLink()) entries.push([relative, 'link', await fs.readlink(installed)]);
      else if (item.isFile()) entries.push([relative, 'file', await fileSha256(installed)]);
    }
  }
  await fs.stat(path.join(root, 'PROVENANCE.txt'));
  await walk(layoutRoot);
  return crypto.createHash('sha256').update(JSON.stringify(entries)).digest('hex');
}

export async function produceFinalCompiler({binary, outdir, platform, repository, commit, runId, runAttempt, std, lineage, llvmLibrary}) {
  if (!runId || !runAttempt || !lineage?.compilerSha256 || !lineage?.parentSha256) {
    throw new Error('final compiler requires producer run and parent identity');
  }
  if (await fileSha256(binary) !== lineage.compilerSha256) throw new Error('final compiler producer binary mismatch');
  if (await stdIdentity(std) !== lineage.stdSha256) throw new Error('final compiler producer std mismatch');
  await fs.mkdir(outdir, {recursive: true});
  const installed = path.join(outdir, platform === 'windows-x64' ? 'cjc.exe' : 'cjc');
  await fs.copyFile(binary, installed);
  await fs.chmod(installed, 0o755);
  const destination = path.join(outdir, FINAL_COMPILER_PROVENANCE);
  const value = await writeComponentProvenance({component: 'compiler', binary: installed, destination, platform, repository, commit});
  value.production = {runId, runAttempt, ...lineage};
  if (llvmLibrary) {
    const name = compilerLlvmName(platform);
    if (!name || path.basename(llvmLibrary) !== name) throw new Error('final compiler LLVM platform mismatch');
    const destination = path.join(outdir, 'compiler-llvm', name);
    await fs.mkdir(path.dirname(destination), {recursive: true});
    await fs.copyFile(llvmLibrary, destination);
    value.production.compilerLlvm = {name, sha256: await fileSha256(destination)};
  }
  await fs.writeFile(destination, `${JSON.stringify(value, null, 2)}\n`);
  return installed;
}

export async function consumeFinalCompiler({directory, platform, repository, commit, runId, runAttempt, std, llvmManifest}) {
  const artifactName = platform === 'windows-x64' ? 'cjc.exe' : 'cjc';
  const binary = path.join(directory, artifactName);
  const value = await verifyComponentProvenance({component: 'compiler', artifactName, binary,
    sidecar: path.join(directory, FINAL_COMPILER_PROVENANCE), platform,
    expectedRepository: repository, expectedCommit: commit});
  if (value.production?.runId !== runId || value.production?.runAttempt !== runAttempt
    || value.production?.stdSha256 !== await stdIdentity(std)) {
    throw new Error('final compiler run/std mismatch');
  }
  if (llvmManifest && value.production?.llvmManifestSha256 !== await fileSha256(llvmManifest)) {
    throw new Error('final compiler LLVM tuple mismatch');
  }
  await checkedCompilerLlvm(directory, platform, value);
  return binary;
}

async function checkedCompilerLlvm(directory, platform, value) {
  const llvm = value.production?.compilerLlvm;
  if (!llvm) return undefined;
  if (llvm.name !== compilerLlvmName(platform)) throw new Error('final compiler LLVM platform mismatch');
  const source = path.join(directory, 'compiler-llvm', llvm.name);
  if (await fileSha256(source) !== llvm.sha256) throw new Error('final compiler LLVM SHA-256 mismatch');
  return source;
}

export async function installFinalCompilerLlvm({directory, sdk, platform}) {
  const value = JSON.parse(await fs.readFile(path.join(directory, FINAL_COMPILER_PROVENANCE), 'utf8'));
  const source = await checkedCompilerLlvm(directory, platform, value);
  if (!source) return;
  const destination = path.join(sdk, 'lib/cjc', path.basename(source));
  await fs.mkdir(path.dirname(destination), {recursive: true});
  await fs.copyFile(source, destination);
}
