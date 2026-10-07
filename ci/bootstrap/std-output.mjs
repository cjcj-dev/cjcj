#!/usr/bin/env zx
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';

const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const fileHash = async file => hash(await fs.readFile(file));
const recordName = 'bootstrap-std-output.json';

// Include all entries, link targets, dereferenced bytes and permissions. This
// authenticates the whole installed prefix, not just the statically linked core.
async function prefixHash(prefix) {
  const entries = [];
  async function visit(relative = '') {
    for (const name of (await fs.readdir(path.join(prefix, relative))).sort()) {
      const rel = path.join(relative, name);
      const file = path.join(prefix, rel);
      const stat = await fs.lstat(file);
      if (stat.isDirectory()) {
        entries.push([rel, 'directory', stat.mode & 0o777]);
        await visit(rel);
      } else if (stat.isFile() || stat.isSymbolicLink()) {
        const resolved = await fs.realpath(file);
        if (!resolved.startsWith(`${prefix}${path.sep}`)) throw new Error('BOOTSTRAP_STD_EXTERNAL_LINK');
        entries.push([rel, stat.isSymbolicLink() ? await fs.readlink(file) : 'file',
          stat.mode & 0o777, await fileHash(file)]);
      } else throw new Error('BOOTSTRAP_STD_UNSUPPORTED_ENTRY');
    }
  }
  await visit();
  return hash(JSON.stringify(entries));
}

async function identities({work, prefix, compiler, tuple}) {
  work = await fs.realpath(work);
  if (!path.isAbsolute(prefix) || !prefix.startsWith(`${work}${path.sep}`)
    || await fs.realpath(prefix) !== prefix) throw new Error('BOOTSTRAP_STD_PREFIX_MISMATCH');
  if (!/^[A-Za-z0-9_]+$/.test(tuple)) throw new Error('BOOTSTRAP_STD_TUPLE_MISMATCH');
  compiler = await fs.realpath(compiler);
  if (compiler !== await fs.realpath(path.join(work, 'cjcj-stage1'))) {
    throw new Error('BOOTSTRAP_STD_COMPILER_PATH_MISMATCH');
  }
  const producer = JSON.parse(await fs.readFile(path.join(prefix, 'std-producer.json'), 'utf8'));
  const compilerSha256 = await fileHash(compiler);
  if (producer.compiler_sha256 !== compilerSha256) throw new Error('BOOTSTRAP_STD_COMPILER_MISMATCH');
  return {version: 1, prefix, tuple, compiler, compilerSha256,
    stage2: path.join(work, 'cjcj-stage2'), stage2Sha256: await fileHash(path.join(work, 'cjcj-stage2')),
    producerSha256: await fileHash(path.join(prefix, 'std-producer.json')),
    coreSha256: await fileHash(path.join(prefix, 'lib', tuple, 'libcangjie-std-core.a')),
    prefixSha256: await prefixHash(prefix)};
}

export async function publishBootstrapStdOutput(options) {
  const identity = await identities(options);
  const record = path.join(options.work, recordName);
  await fs.writeFile(`${record}.tmp`, `${JSON.stringify(identity, null, 2)}\n`);
  await fs.rename(`${record}.tmp`, record);
  console.log(`BOOTSTRAP_STD_OUTPUT_PUBLISHED prefix=${identity.prefix} sha256=${identity.prefixSha256}`);
  return identity;
}

export async function readBootstrapStdOutput({work, tuple}) {
  const record = JSON.parse(await fs.readFile(path.join(work, recordName), 'utf8'));
  if (record.version !== 1 || record.tuple !== tuple) throw new Error('BOOTSTRAP_STD_RECORD_MISMATCH');
  const actual = await identities({work, tuple, prefix: record.prefix, compiler: record.compiler});
  for (const key of Object.keys(actual)) {
    if (record[key] !== actual[key]) throw new Error(`BOOTSTRAP_STD_IDENTITY_MISMATCH: ${key}`);
  }
  console.log(`BOOTSTRAP_STD_OUTPUT_VERIFIED prefix=${actual.prefix} sha256=${actual.prefixSha256}`);
  return actual;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [work, prefix, compiler, tuple] = process.argv.slice(2);
  if (!work || !prefix || !compiler || !tuple) throw new Error('usage: std-output.mjs WORK PREFIX COMPILER TUPLE');
  await publishBootstrapStdOutput({work, prefix, compiler, tuple});
}
