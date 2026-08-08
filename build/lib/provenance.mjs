import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';

const CJCJ_MARKER = Buffer.from('CJCJ-COMMIT:');
const PROVENANCE_FILE = 'PROVENANCE.txt';

function commandOutput(command, args, cwd) {
  const result = spawnSync(command, args, {cwd, encoding: 'utf8'});
  return result.status === 0 ? result.stdout.trim() : '';
}

function validCommitByte(byte) {
  return (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) ||
    (byte >= 97 && byte <= 122) || byte === 45 || byte === 46 || byte === 95;
}

function validateCommit(value, label) {
  if (!/^[0-9A-Za-z._-]+$/.test(value)) {
    throw new Error(`${label} contains unsupported characters: ${JSON.stringify(value)}`);
  }
  return value;
}

export function sourceCommit(sourceDir, injected = process.env.CJSTD_COMMIT || '') {
  let commit = injected.trim();
  if (!commit) commit = commandOutput('git', ['rev-parse', 'HEAD'], sourceDir);
  if (!commit) commit = 'unknown';
  const status = commandOutput('git', ['status', '--porcelain'], sourceDir);
  if (status && !commit.endsWith('-dirty')) commit += '-dirty';
  return validateCommit(commit, 'CJSTD_COMMIT');
}

export async function compilerCommit(compiler) {
  const binary = await fs.readFile(compiler);
  const values = new Set();
  let offset = 0;
  while (offset < binary.length) {
    const marker = binary.indexOf(CJCJ_MARKER, offset);
    if (marker < 0) break;
    const begin = marker + CJCJ_MARKER.length;
    let end = begin;
    while (end < binary.length && validCommitByte(binary[end])) end += 1;
    if (end > begin) values.add(binary.subarray(begin, end).toString('ascii'));
    offset = begin;
  }
  if (values.size > 1) {
    throw new Error(`compiler has conflicting CJCJ-COMMIT stamps: ${[...values].join(', ')}`);
  }
  return values.size === 1 ? [...values][0] : 'unknown';
}

async function artifactFiles(root, directory = root) {
  const files = [];
  const entries = await fs.readdir(directory, {withFileTypes: true});
  for (const entry of entries) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...await artifactFiles(root, file));
    } else if (entry.isFile() && path.relative(root, file) !== PROVENANCE_FILE) {
      files.push(file);
    }
  }
  return files;
}

async function sha256(file) {
  const hash = createHash('sha256');
  hash.update(await fs.readFile(file));
  return hash.digest('hex');
}

export async function writeStdProvenance({sourceDir, installPrefix, compiler, now = new Date()}) {
  const stdCommit = sourceCommit(sourceDir);
  const builtBy = await compilerCommit(compiler);
  const files = (await artifactFiles(installPrefix))
    .sort((left, right) => path.relative(installPrefix, left).localeCompare(path.relative(installPrefix, right)));
  if (!files.length) throw new Error(`std install prefix has no artifacts: ${installPrefix}`);

  const lines = [
    `CJSTD-COMMIT:${stdCommit} BUILT-BY:${builtBy}`,
    `BUILD-TIME-UTC:${now.toISOString()}`,
    'ARTIFACT-SHA256:',
  ];
  for (const file of files) {
    lines.push(`${await sha256(file)}  ${path.relative(installPrefix, file)}`);
  }
  const destination = path.join(installPrefix, PROVENANCE_FILE);
  await fs.writeFile(destination, `${lines.join('\n')}\n`);
  return destination;
}
