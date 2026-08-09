import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {
  BASE_SDK_PROVENANCE,
  CJPM_PROVENANCE,
  baseSdkDownload,
  writeBaseSdkProvenance,
  writeCjpmProvenance,
} from '../lib/release-component-provenance.mjs';
import {
  CJDB_PYTHON_MODULES,
  CJDB_PYTHON_UNIX_MODULES,
  RELEASE_PYTHON_SOURCE_SHA256,
  RELEASE_PYTHON_SOURCE_URL,
  RELEASE_PYTHON_VERSION,
} from '../lib/python-bundle.mjs';

const TUPLE = 'linux_x86_64_cjnative';
const CJCJ_SHA = 'a'.repeat(40);
const RUNTIME_SHA = 'b'.repeat(40);
const LLVM_SHA = 'c'.repeat(40);
const STD_SHA = 'd'.repeat(40);
const CJPM_SHA = 'e'.repeat(40);

async function write(root, relative, contents, mode) {
  const file = path.join(root, relative);
  await fs.mkdir(path.dirname(file), {recursive: true});
  await fs.writeFile(file, contents, mode ? {mode} : undefined);
  return file;
}

function run(command, args, options = {}) {
  const result = spawnSync('timeout', ['90s', 'nice', '-n', '15', command, ...args], {
    encoding: 'utf8',
    ...options,
  });
  assert.equal(result.status, 0, `${command} failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
  return result;
}

async function writePythonBundle(root) {
  const bundle = path.join(root, 'python-bundle');
  await write(bundle, 'bin/python3.11', [
    '#!/bin/sh',
    'case "$3" in',
    ...[...CJDB_PYTHON_MODULES, ...CJDB_PYTHON_UNIX_MODULES]
      .map(name => `  *'name = "${name}"'*) printf 'CJDB-PYTHON-IMPORT=${name}\\n'; exit 0 ;;`),
    'esac',
    `printf '${RELEASE_PYTHON_VERSION}\\n%s\\n' "$PYTHONHOME"`,
    '',
  ].join('\n'), 0o755);
  await write(bundle, 'lib/libpython3.11.so.1.0', 'fixture libpython\n');
  await fs.symlink('libpython3.11.so.1.0', path.join(bundle, 'lib', 'libpython3.11.so'));
  await write(bundle, 'lib/python3.11/os.py', '# fixture stdlib\n');
  await write(bundle, 'LICENSE.txt', 'PSF LICENSE AGREEMENT fixture\n');
  await write(bundle, 'PYTHON-BUNDLE.json', `${JSON.stringify({
    schema: 1,
    platform: 'linux-x64',
    version: RELEASE_PYTHON_VERSION,
    source_type: 'python.org-source-native',
    source_url: RELEASE_PYTHON_SOURCE_URL,
    source_sha256: RELEASE_PYTHON_SOURCE_SHA256,
    configure_args: '--prefix=<bundle> --enable-shared --without-ensurepip',
    configure_environment: 'LDFLAGS=-Wl,-rpath,$ORIGIN/../lib',
    required_modules: [...CJDB_PYTHON_MODULES],
    required_unix_modules: [...CJDB_PYTHON_UNIX_MODULES],
  }, null, 2)}\n`);
  return bundle;
}

test('package_sdk archives std provenance and an honest complete manifest', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'package-provenance-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const sdk = path.join(root, 'sdk');
  const std = path.join(root, 'std');
  const out = path.join(root, 'dist');
  await fs.mkdir(out);
  const pythonBundle = await writePythonBundle(root);

  const binary = path.join(root, 'cjc');
  await fs.copyFile('/bin/true', binary);
  await fs.appendFile(binary, `\0CJCJ-COMMIT:${CJCJ_SHA}\0`);
  await fs.chmod(binary, 0o755);
  await write(sdk, 'envsetup.sh', '# fixture SDK\n', 0o755);
  await write(sdk, `runtime/lib/${TUPLE}/libcangjie-runtime.so`,
    `fixture-runtime\0CJRT-COMMIT:${RUNTIME_SHA}\0`);
  await write(sdk, 'third_party/llvm/bin/llc', `fixture-llc\0CJLLVM-COMMIT:${LLVM_SHA}\0`, 0o755);
  await write(sdk, 'third_party/llvm/bin/opt', 'fixture-opt-with-stamp-removed', 0o755);
  const cjpm = await write(sdk, 'tools/bin/cjpm', 'fixture source-built cjpm', 0o755);
  await fs.mkdir(path.join(sdk, 'bin'), {recursive: true});
  await fs.mkdir(path.join(sdk, 'lib', TUPLE), {recursive: true});
  await fs.mkdir(path.join(sdk, 'modules', TUPLE, 'std'), {recursive: true});

  const source = await write(root, 'std-core.c', [
    'extern long g_cjLoadBadMask;',
    '__attribute__((used)) long _CNat6String7indexOfHRNatY0_E(void) {',
    '  return g_cjLoadBadMask;',
    '}',
    '',
  ].join('\n'));
  const object = path.join(root, 'std-core.o');
  run('cc', ['-O0', '-fPIC', '-c', source, '-o', object]);
  const archive = path.join(root, 'std.core.a');
  run('ar', ['rcs', archive, object]);
  await fs.mkdir(path.join(std, 'modules', TUPLE, 'std'), {recursive: true});
  await fs.mkdir(path.join(std, 'lib', TUPLE), {recursive: true});
  await fs.copyFile(archive, path.join(std, 'modules', TUPLE, 'std', 'std.core.a'));
  await fs.copyFile(archive, path.join(std, 'lib', TUPLE, 'libcangjie-std-core.a'));
  await write(std, `runtime/lib/${TUPLE}/libcangjie-std-core.so`, 'fixture shared std\n');
  await write(std, 'PROVENANCE.txt', [
    `CJSTD-COMMIT:${STD_SHA} BUILT-BY:${CJCJ_SHA}`,
    `STD_SOURCE_COMMIT = ${STD_SHA}`,
    'ARTIFACT-SHA256:',
    '',
  ].join('\n'));
  const llvmManifest = await write(root, 'llvm-tools.manifest', [
    `LLVM_SHA=${LLVM_SHA}`,
    `LLC_SHA256=${'1'.repeat(64)}`,
    `OPT_SHA256=${'2'.repeat(64)}`,
    '',
  ].join('\n'));
  const baseSdkId = 'nightly-fixture';
  const baseArchive = await write(root, baseSdkDownload('linux-x64', baseSdkId).archive,
    'fixture official SDK archive');
  const baseSidecar = path.join(root, BASE_SDK_PROVENANCE);
  await writeBaseSdkProvenance({
    archive: baseArchive,
    destination: baseSidecar,
    platform: 'linux-x64',
    toolchain: baseSdkId,
  });
  const cjpmSidecar = path.join(root, CJPM_PROVENANCE);
  await writeCjpmProvenance({
    binary: cjpm,
    destination: cjpmSidecar,
    platform: 'linux-x64',
    repository: 'https://github.com/cjcj-dev/cangjie-tools.git',
    commit: CJPM_SHA,
  });

  const packaged = run('zx', [path.resolve('scripts/package_sdk.mjs'),
    '--sdk', sdk,
    '--binary', binary,
    '--allow-stock-runtime',
    '--std-dir', std,
    '--llvm-manifest', llvmManifest,
    '--python-bundle', pythonBundle,
    '--base-sdk-id', baseSdkId,
    '--base-sdk-archive', baseArchive,
    '--base-sdk-provenance', baseSidecar,
    '--cjcj-source-sha', CJCJ_SHA,
    '--runtime-source-sha', RUNTIME_SHA,
    '--std-source-repo', 'https://github.com/cjcj-dev/cangjie-runtime.git',
    '--cjpm-provenance', cjpmSidecar,
    '--cjpm-source-repo', 'https://github.com/cjcj-dev/cangjie-tools.git',
    '--cjpm-source-sha', CJPM_SHA,
    '--version', 'fixture',
    '--platform', 'linux-x64',
    '--outdir', out,
  ], {cwd: path.resolve('.')});
  assert.match(packaged.stdout, /DONE: .*cjcj-fixture-linux-x64\.tar\.gz/);

  const packageName = 'cjcj-fixture-linux-x64';
  const manifestFile = path.join(out, `${packageName}.RELEASE-MANIFEST.jsonl`);
  const manifestText = await fs.readFile(manifestFile, 'utf8');
  const rows = manifestText.trim().split('\n').map(JSON.parse);
  assert.equal(rows.length, 8);
  assert.equal(rows.find(row => row.component === 'llvm-opt').embedded_stamp, 'no-stamp');
  assert.equal(rows.find(row => row.component === 'python').source.commit, RELEASE_PYTHON_VERSION);
  assert.equal(rows.find(row => row.component === 'base-sdk').source.version, 'fixture');
  assert.match(rows.find(row => row.component === 'base-sdk').artifact.sha256, /^[0-9a-f]{64}$/);
  assert.equal(rows.find(row => row.component === 'cjpm').source.commit, CJPM_SHA);
  assert.match(rows.find(row => row.component === 'cjpm').artifact.sha256, /^[0-9a-f]{64}$/);
  const listing = run('tar', ['-tzf', path.join(out, `${packageName}.tar.gz`)]).stdout;
  assert.match(listing, new RegExp(`${packageName}/PROVENANCE\\.txt`));
  assert.match(listing, new RegExp(`${packageName}/RELEASE-MANIFEST\\.jsonl`));
  assert.match(listing, new RegExp(`${packageName}/${BASE_SDK_PROVENANCE}`));
  assert.match(listing, new RegExp(`${packageName}/${CJPM_PROVENANCE}`));
  console.log(`PACKAGER-OUTPUT-BEGIN\n${packaged.stdout.trim()}\nPACKAGER-OUTPUT-END`);
  console.log(`ARCHIVE-PROVENANCE-BEGIN\n${listing.split('\n').filter(line =>
    /PROVENANCE|RELEASE-MANIFEST/.test(line)).join('\n')}\nARCHIVE-PROVENANCE-END`);
  console.log(`RELEASE-MANIFEST-BEGIN\n${manifestText.trim()}\nRELEASE-MANIFEST-END`);
});
