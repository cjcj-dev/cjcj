#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {
  RELEASE_PYTHON_VERSION,
  RELEASE_PYTHON_DIR,
} from '../build/lib/python-bundle.mjs';
import {
  RELEASE_MANIFEST,
  RELEASE_SIGNATURE_POLICY,
} from '../build/lib/release-manifest.mjs';

const sdk = path.resolve(process.argv[2] || '');
if (!process.argv[2]) throw new Error('usage: verify_packaged_cjdb.mjs <unpacked-sdk-root>');
const isWindows = process.platform === 'win32';
const pythonRoot = path.join(sdk, RELEASE_PYTHON_DIR);
const pythonArtifact = isWindows
  ? path.join(pythonRoot, 'python.exe')
  : path.join(pythonRoot, 'bin', 'python3.11');
const launcher = path.join(sdk, 'tools', 'bin', isWindows ? 'cjdb.cmd' : 'cjdb');
const license = path.join(pythonRoot, 'LICENSE.txt');

async function requireFile(file) {
  if (!(await fs.stat(file, {throwIfNoEntry: false}))?.isFile()) throw new Error(`required file is missing: ${file}`);
}

function comparable(file) {
  const resolved = path.resolve(file);
  return isWindows ? resolved.toLowerCase() : resolved;
}

await Promise.all([pythonArtifact, launcher, license].map(requireFile));
const env = {...process.env};
delete env.PYTHONHOME;
delete env.PYTHONPATH;
if (!isWindows) env.PATH = '/usr/bin:/bin';
const probe = [
  'import os,platform,sys',
  'print("CJCJ_CJDB_PYTHON=" + platform.python_version())',
  'print("CJCJ_CJDB_PREFIX=" + os.path.realpath(sys.prefix))',
].join('; ');
const session = spawnSync(launcher, [
  '--batch', '--no-lldbinit', '-o', `script ${probe}`, '-o', 'settings show prompt', '-o', 'quit',
], {encoding: 'utf8', env, shell: isWindows});
if (session.status !== 0) {
  throw new Error(`packaged cjdb session failed with ${session.status}:\n${session.stdout}\n${session.stderr}`);
}
const output = `${session.stdout}\n${session.stderr}`;
const version = output.match(/CJCJ_CJDB_PYTHON=([^\r\n]+)/)?.[1]?.trim() || '';
const prefix = output.match(/CJCJ_CJDB_PREFIX=([^\r\n]+)/)?.[1]?.trim() || '';
if (version !== RELEASE_PYTHON_VERSION) {
  throw new Error(`cjdb used Python ${version || '<unknown>'}, expected ${RELEASE_PYTHON_VERSION}`);
}
if (comparable(prefix) !== comparable(pythonRoot)) {
  throw new Error(`cjdb Python prefix escaped package: expected ${pythonRoot}, got ${prefix || '<unknown>'}`);
}

const manifestPath = path.join(sdk, RELEASE_MANIFEST);
await requireFile(manifestPath);
const rows = (await fs.readFile(manifestPath, 'utf8')).split(/\r?\n/).filter(Boolean).map(JSON.parse);
if (!rows.every(row => row.signature_policy === RELEASE_SIGNATURE_POLICY)) {
  throw new Error(`manifest signature_policy is not uniformly ${RELEASE_SIGNATURE_POLICY}`);
}
const pythonRows = rows.filter(row => row.component === 'python');
if (pythonRows.length !== 1) throw new Error(`manifest must have exactly one python row, got ${pythonRows.length}`);
const [pythonRow] = pythonRows;
if (pythonRow.source?.commit !== RELEASE_PYTHON_VERSION ||
    comparable(path.join(sdk, pythonRow.artifact?.path || '')) !== comparable(pythonArtifact) ||
    pythonRow.embedded_stamp !== `PYTHON-VERSION:${RELEASE_PYTHON_VERSION}`) {
  throw new Error(`malformed Python manifest row: ${JSON.stringify(pythonRow)}`);
}
const digest = crypto.createHash('sha256').update(await fs.readFile(pythonArtifact)).digest('hex');
if (pythonRow.artifact.sha256 !== digest) {
  throw new Error(`Python artifact SHA-256 mismatch: manifest=${pythonRow.artifact.sha256} actual=${digest}`);
}

console.log(`CJDB-BUNDLE-PASS version=${version} prefix=${prefix} sha256=${digest}`);
