#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {
  RELEASE_PYTHON_VERSION,
  RELEASE_PYTHON_DIR,
  verifyPythonImports,
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
const manifestPath = path.join(sdk, RELEASE_MANIFEST);
await requireFile(manifestPath);
const rows = (await fs.readFile(manifestPath, 'utf8')).split(/\r?\n/).filter(Boolean).map(JSON.parse);
const platforms = new Set(rows.map(row => row.platform));
if (platforms.size !== 1) throw new Error(`manifest has inconsistent platforms: ${[...platforms].join(',')}`);
const platform = [...platforms][0];
const runtimeDirs = new Map([
  ['linux-x64', 'linux_x86_64_cjnative'],
  ['linux-aarch64', 'linux_aarch64_cjnative'],
  ['darwin-x64', 'darwin_x86_64_cjnative'],
  ['darwin-arm64', 'darwin_aarch64_cjnative'],
  ['windows-x64', 'windows_x86_64_cjnative'],
]);
const runtimeDir = runtimeDirs.get(platform);
if (!runtimeDir) throw new Error(`unsupported packaged platform: ${platform}`);
const imported = verifyPythonImports(
  pythonArtifact,
  pythonRoot,
  platform,
  path.join(sdk, 'third_party', 'llvm', 'lib', 'python3.11', 'site-packages'),
  [
    path.join(sdk, 'third_party', 'llvm', 'lib'),
    path.join(sdk, 'tools', 'lib'),
    path.join(sdk, 'runtime', 'lib', runtimeDir),
  ],
);
console.log(`CJDB-IMPORTS-PASS count=${imported.length} modules=${imported.join(',')}`);

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
const version = output.match(/^CJCJ_CJDB_PYTHON=([^\r\n]+)$/m)?.[1]?.trim() || '';
const prefix = output.match(/^CJCJ_CJDB_PREFIX=([^\r\n]+)$/m)?.[1]?.trim() || '';
if (version !== RELEASE_PYTHON_VERSION) {
  throw new Error(`cjdb used Python ${version || '<unknown>'}, expected ${RELEASE_PYTHON_VERSION}`);
}
if (comparable(prefix) !== comparable(pythonRoot)) {
  throw new Error(`cjdb Python prefix escaped package: expected ${pythonRoot}, got ${prefix || '<unknown>'}`);
}

if (!rows.every(row => row.signature_policy === RELEASE_SIGNATURE_POLICY)) {
  throw new Error(`manifest signature_policy is not uniformly ${RELEASE_SIGNATURE_POLICY}`);
}
const pythonRows = rows.filter(row => row.component === 'python');
if (pythonRows.length !== 1) throw new Error(`manifest must have exactly one python row, got ${pythonRows.length}`);
const [pythonRow] = pythonRows;
if (pythonRow.source?.commit !== RELEASE_PYTHON_VERSION ||
    comparable(path.join(sdk, pythonRow.artifact?.path || '')) !== comparable(pythonArtifact) ||
    pythonRow.embedded_stamp !== `PYTHON-VERSION:${RELEASE_PYTHON_VERSION}` ||
    !/^https:\/\/www\.python\.org\//.test(pythonRow.source?.download_url || '') ||
    !/^[0-9a-f]{64}$/.test(pythonRow.source?.archive_sha256 || '') ||
    typeof pythonRow.build?.configure_args !== 'string' || pythonRow.build.configure_args.length === 0 ||
    typeof pythonRow.build?.configure_environment !== 'string' || pythonRow.build.configure_environment.length === 0) {
  throw new Error(`malformed Python manifest row: ${JSON.stringify(pythonRow)}`);
}
const digest = crypto.createHash('sha256').update(await fs.readFile(pythonArtifact)).digest('hex');
if (pythonRow.artifact.sha256 !== digest) {
  throw new Error(`Python artifact SHA-256 mismatch: manifest=${pythonRow.artifact.sha256} actual=${digest}`);
}
const provenanceArtifact = path.join(sdk, pythonRow.build.provenance_path);
await requireFile(provenanceArtifact);
const provenanceDigest = crypto.createHash('sha256').update(await fs.readFile(provenanceArtifact)).digest('hex');
if (pythonRow.build.provenance_sha256 !== provenanceDigest) {
  throw new Error(`Python provenance SHA-256 mismatch: manifest=${pythonRow.build.provenance_sha256} actual=${provenanceDigest}`);
}

console.log(`CJDB-BUNDLE-PASS version=${version} prefix=${prefix} sha256=${digest}`);
