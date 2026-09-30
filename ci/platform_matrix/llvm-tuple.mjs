import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import zlib from 'node:zlib';
import {spawnSync} from 'node:child_process';

async function isFile(target) {
  try { return (await fs.stat(target)).isFile(); } catch { return false; }
}
function sha256(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

export async function activateLlvmTuple(fixedTools, {sdkToolPath, manifest, platform = process.platform}) {
  for (const tool of fixedTools) {
    tool.sdk = await sdkToolPath(tool.name);
    tool.expectedSha = manifest.get(tool.manifestKey) || '';
    if (!/^[0-9a-f]{64}$/.test(tool.expectedSha)) {
      throw new Error(`${tool.manifestKey} missing from fixed LLVM manifest`);
    }
    tool.payload = zlib.gunzipSync(await fs.readFile(tool.archive));
    const artifactSha = sha256(tool.payload);
    if (artifactSha !== tool.expectedSha) {
      throw new Error(`fixed ${tool.name} artifact sha mismatch (${artifactSha})`);
    }
    tool.tuple = path.join(`${tool.sdk}.tuple-stage`, path.basename(tool.sdk));
    await fs.mkdir(path.dirname(tool.tuple), {recursive: true});
    tool.rollback = `${tool.sdk}.tuple.rollback`;
    await fs.writeFile(tool.tuple, tool.payload);
    if (platform !== 'win32') await fs.chmod(tool.tuple, 0o755);
  }

  // The Windows tuple llc links against MinGW runtime DLLs (libstdc++-6.dll,
  // libwinpthread-1.dll; round-13/14 exit 127 = loader failure even with PATH
  // appended). Same-directory DLL resolution always wins on Windows, so copy the
  // runtime DLLs next to the tools; probe via spawnSync for a discriminating error.
  if (platform === 'win32') {
    process.env.PATH = `${process.env.PATH};C:\\mingw64\\bin`;
    const llvmBin = path.dirname(fixedTools[0].sdk);
    for (const dll of ['libstdc++-6.dll', 'libwinpthread-1.dll', 'libgcc_s_seh-1.dll']) {
      for (const dir of ['C:\\mingw64\\bin', 'C:\\msys64\\mingw64\\bin', 'C:\\Program Files\\Git\\mingw64\\bin']) {
        const cand = path.join(dir, dll);
        if (await isFile(cand)) {
          await fs.copyFile(cand, path.join(llvmBin, dll));
          for (const tool of fixedTools) await fs.copyFile(cand, path.join(path.dirname(tool.tuple), dll));
          console.log(`staged ${dll} from ${dir}`);
          break;
        }
      }
    }
  }

  function probeLlvmTool(tool, phase, expectedVersion) {
    const probe = spawnSync(tool, ['--version'], {encoding: 'utf8'});
    console.log(`${phase} ${path.basename(tool)} probe: status=${probe.status} error=${probe.error ? probe.error.code : 'none'}`);
    if (probe.stdout) console.log(probe.stdout.slice(0, 400));
    if (probe.stderr) console.error(probe.stderr.slice(0, 400));
    if (probe.status !== 0) throw new Error(`${phase} LLVM tool probe failed: ${tool}`);
    const reportedVersion = probe.stdout.split(/\r?\n/).map(line => line.trim())
      .find(line => /LLVM version |^LLD /.test(line)) || '';
    if (reportedVersion !== expectedVersion) {
      throw new Error(`${phase} LLVM tool version mismatch: ${tool} (${reportedVersion} != ${expectedVersion})`);
    }
  }

  // Validate the complete tuple before changing any SDK binary.
  for (const tool of fixedTools) probeLlvmTool(tool.tuple, 'tuple', manifest.get(tool.versionKey));

  for (const tool of fixedTools) {
    if (!(await isFile(`${tool.sdk}.orig`))) await fs.copyFile(tool.sdk, `${tool.sdk}.orig`);
    await fs.rm(tool.rollback, {force: true});
    await fs.copyFile(tool.sdk, tool.rollback);
  }
  try {
    for (const tool of fixedTools) {
      await fs.rm(tool.sdk, {force: true});
      await fs.rename(tool.tuple, tool.sdk);
    }
    for (const tool of fixedTools) {
      const installedSha = sha256(await fs.readFile(tool.sdk));
      if (installedSha !== tool.expectedSha) {
        throw new Error(`installed ${tool.name} sha mismatch (${installedSha})`);
      }
      probeLlvmTool(tool.sdk, 'installed', manifest.get(tool.versionKey));
      console.log(`SDK ${tool.name} -> source-built fixed LLVM (${installedSha})`);
    }
  } catch (error) {
    for (const tool of fixedTools) {
      if (await isFile(tool.rollback)) {
        await fs.rm(tool.sdk, {force: true});
        await fs.rename(tool.rollback, tool.sdk);
      }
    }
    throw error;
  }
  for (const tool of fixedTools) await fs.rm(tool.rollback, {force: true});
  for (const tool of fixedTools) await fs.rm(path.dirname(tool.tuple), {recursive: true, force: true});
}
