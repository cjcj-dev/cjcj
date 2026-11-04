import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {stdInstallFiles} from '../../bootstrap/sdk-platform.mjs';
import {writeComponentProvenance, verifyComponentProvenance} from '../../../build/lib/release-component-provenance.mjs';

export const FINAL_COMPILER_PROVENANCE = 'FINAL-COMPILER-PROVENANCE.json';
export const fileSha256 = async file => crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex');

// Use the full installed std payload, including its producer manifest. The same
// snapshot is checked at the producer and immediately before package selection.
export async function stdIdentity(root, layoutRoot = root, {sourceSdk = root} = {}) {
  const provenance = await fs.stat(path.join(root, 'PROVENANCE.txt')).catch(error => {
    if (error.code === 'ENOENT') return null;
    throw error;
  });
  if (!provenance) {
    // Ordinary component installation records its source/configuration in the
    // existing STAGE-INPUTS. It never produced PROVENANCE.txt. Consume those
    // facts and the normal std interface files, not an inventory of the SDK.
    const stage = JSON.parse(await fs.readFile(path.join(sourceSdk, 'STAGE-INPUTS.json'), 'utf8'));
    const selected = stage.selection?.targetComponents?.std, source = stage.sources?.std;
    if (!source?.repository || !/^[a-f0-9]{40}$/.test(source.commit || '')
        || selected?.repository !== source.repository || selected?.commit !== source.commit
        || selected?.platform !== stage.platform || stage.configuration?.platform !== stage.platform)
      throw Error('STD_INPUT_SOURCE');
    if (path.resolve(root) !== path.resolve(sourceSdk)
        && (!selected.install || await fs.realpath(root) !== await fs.realpath(selected.install)))
      throw Error('STD_INPUT_INSTALL');
    const entries = [];
    for (const relative of stdInstallFiles(stage.platform)) {
      const digest = await fileSha256(path.join(root, relative));
      if (path.resolve(root) !== path.resolve(sourceSdk)
          && digest !== await fileSha256(path.join(sourceSdk, relative)))
        throw Error('STD_INPUT_PAYLOAD ' + relative);
      entries.push([relative, digest]);
    }
    return crypto.createHash('sha256').update(JSON.stringify({source: {
      repository: source.repository, commit: source.commit}, configuration: stage.configuration, entries})).digest('hex');
  }
  // Keep the pre-existing final-std lineage format for producers that actually
  // wrote PROVENANCE. Do not synthesize that file for ordinary installations.
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
  await walk(layoutRoot);
  return crypto.createHash('sha256').update(JSON.stringify(entries)).digest('hex');
}

export async function produceFinalCompiler({binary, outdir, platform, repository, commit, runId, runAttempt, std, lineage}) {
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
  return binary;
}
