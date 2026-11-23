// Deterministic tar.gz/zip archives, SHA256SUMS, and true relocation: the original install is moved
// away before the archive is unpacked into a fresh directory and verified there.
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {assetFileName, findAsset} from './targets.mjs';
import {sha256} from './verify.mjs';

const EPOCH = process.env.SOURCE_DATE_EPOCH ?? '1700000000';

function tar(argv, cwd) {
  const p = spawnSync('tar', argv, {cwd, encoding: 'utf8', maxBuffer: 64 * 2 ** 20});
  return {rc: p.status, stderr: p.stderr ?? ''};
}

export function packArchive({sdk, asset: assetKey, version, output}) {
  const asset = findAsset(assetKey);
  const name = assetFileName(asset.key, version), file = path.join(output, name);
  fs.mkdirSync(output, {recursive: true});
  if (fs.existsSync(file)) throw new Error(`ARCHIVE_EXISTS ${file}`);
  const parent = path.dirname(path.resolve(sdk)), top = path.basename(path.resolve(sdk));
  if (top !== 'cangjie') throw new Error(`ARCHIVE_ROOT_NAME ${top}`);
  const argv = asset.archive === 'zip' ? ['-a', '-cf', file, top]
    : ['--sort=name', '--owner=0', '--group=0', '--numeric-owner', `--mtime=@${EPOCH}`, '-czf', file, top];
  const p = tar(argv, parent);
  if (p.rc !== 0) { fs.rmSync(file, {force: true}); throw new Error(`ARCHIVE_PACK_FAILED rc=${p.rc} ${p.stderr.slice(0, 400)}`); }
  const digest = sha256(file);
  fs.writeFileSync(`${file}.sha256`, `${digest}  ${name}\n`);
  return {file, name, sha256: digest, bytes: fs.statSync(file).size};
}

export function writeSums(output, entries) {
  const text = entries.map(({name, sha256: digest}) => `${digest}  ${name}`).sort().join('\n') + '\n';
  fs.writeFileSync(path.join(output, 'SHA256SUMS'), text);
  return text;
}

// Check name and digest before touching the archive contents.
export function checkArchive({file, asset: assetKey, version, expectedSha256}) {
  const name = path.basename(file);
  if (name !== assetFileName(assetKey, version)) throw new Error(`ARCHIVE_WRONG_ASSET ${name}`);
  const want = expectedSha256 ?? fs.readFileSync(`${file}.sha256`, 'utf8').split(/\s+/)[0];
  if (!/^[0-9a-f]{64}$/.test(want)) throw new Error('ARCHIVE_BAD_SHA_RECORD');
  const got = sha256(file);
  if (got !== want) throw new Error(`ARCHIVE_SHA_MISMATCH ${got} != ${want}`);
  return got;
}

export function unpackArchive({file, destination}) {
  if (fs.existsSync(destination)) throw new Error(`UNPACK_DESTINATION_EXISTS ${destination}`);
  fs.mkdirSync(destination, {recursive: true});
  const p = tar(['-xf', file], destination);
  if (p.rc !== 0) throw new Error(`ARCHIVE_EXTRACT_FAILED rc=${p.rc} ${p.stderr.slice(0, 400)}`);
  const root = path.join(destination, 'cangjie');
  if (!fs.statSync(root, {throwIfNoEntry: false})?.isDirectory()) throw new Error('ARCHIVE_NO_ROOT');
  return root;
}

// Move the original install aside, verify from a fresh unpack, then always restore the original.
export async function relocateAndVerify({file, asset, version, sdk, work, verify}) {
  checkArchive({file, asset, version});
  const hidden = `${path.resolve(sdk)}.hidden-for-relocation`;
  if (fs.existsSync(hidden)) throw new Error(`RELOCATION_HIDDEN_EXISTS ${hidden}`);
  fs.renameSync(sdk, hidden);
  try {
    const root = unpackArchive({file, destination: path.join(work, 'unpacked')});
    return {root, result: await verify(root)};
  } finally {
    fs.renameSync(hidden, sdk);
  }
}
