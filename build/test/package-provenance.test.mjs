import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {
  BASE_SDK_PROVENANCE,
  BASE_SDK_SOURCE_REASON,
  CJPM_PROVENANCE,
  SOURCE_PROVENANCE_NOT_APPLICABLE,
  SOURCE_PROVENANCE_RESOLVED,
  baseSdkDownload,
  writeBaseSdkProvenance,
  writeCjpmProvenance,
} from '../lib/release-component-provenance.mjs';
import {
  GATE_APPARATUS_COMPONENT,
  GATE_APPARATUS_PROVENANCE,
  REVIEWED_GATE_HOST_TOOLCHAIN,
  writeGateApparatusProvenance,
} from '../lib/release-gate-apparatus.mjs';
import {
  CJDB_PYTHON_MODULES,
  CJDB_PYTHON_UNIX_MODULES,
  RELEASE_PYTHON_SOURCE_SHA256,
  RELEASE_PYTHON_SOURCE_URL,
  RELEASE_PYTHON_VERSION,
} from '../lib/python-bundle.mjs';
import {parsePackagedLlvmToolsManifest} from '../../ci/llvm-tools-manifest.mjs';

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
  const result = runRaw(command, args, options);
  assert.equal(result.status, 0, `${command} failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
  return result;
}

function runRaw(command, args, options = {}) {
  return spawnSync('timeout', ['90s', 'nice', '-n', '15', command, ...args], {
    encoding: 'utf8',
    ...options,
  });
}

async function sha256(file) {
  return crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex');
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
  const llvmFixtureSource = await write(root, 'llvm-tool.c', [
    '#include <stdio.h>',
    '#include <string.h>',
    'int main(int argc, char **argv) {',
    '  if (argc > 1 && strcmp(argv[1], "--help") == 0) {',
    '    puts("--export-bc=file --lto-newpm-passes=value --mllvm=value --visible-pkgs=value");',
    '    return 0;',
    '  }',
    '  puts("LLVM version 15.0.4");',
    '  return 0;',
    '}',
    '',
  ].join('\n'));
  const llvmFixture = path.join(root, 'llvm-tool');
  run('cc', [llvmFixtureSource, '-o', llvmFixture]);
  for (const tool of ['llc', 'opt', 'ld.lld', 'llvm-objcopy']) {
    const destination = path.join(sdk, 'third_party', 'llvm', 'bin', tool);
    await fs.mkdir(path.dirname(destination), {recursive: true});
    await fs.copyFile(llvmFixture, destination);
    await fs.chmod(destination, 0o755);
  }
  await fs.appendFile(path.join(sdk, 'third_party/llvm/bin/llc'), `\0CJLLVM-COMMIT:${LLVM_SHA}\0`);
  await fs.appendFile(path.join(sdk, 'third_party/llvm/bin/opt'), `\0CJLLVM-COMMIT:${LLVM_SHA}\0`);
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
    `LLC_SOURCE=tuple:${LLVM_SHA}`,
    'LLC_VERSION=LLVM version 15.0.4',
    `LLC_SHA256=${await sha256(path.join(sdk, 'third_party/llvm/bin/llc'))}`,
    `OPT_SOURCE=tuple:${LLVM_SHA}`,
    'OPT_VERSION=LLVM version 15.0.4',
    `OPT_SHA256=${await sha256(path.join(sdk, 'third_party/llvm/bin/opt'))}`,
    'LLD_TOOL=ld.lld',
    `LLD_SOURCE=tuple:${LLVM_SHA}`,
    'LLD_VERSION=LLVM version 15.0.4',
    `LLD_SHA256=${await sha256(path.join(sdk, 'third_party/llvm/bin/ld.lld'))}`,
    '',
  ].join('\n'));
  const baseSdkId = REVIEWED_GATE_HOST_TOOLCHAIN;
  const baseArchive = await write(root, baseSdkDownload('linux-x64', baseSdkId).archive,
    'fixture official SDK archive');
  const baseSidecar = path.join(root, BASE_SDK_PROVENANCE);
  const baseProvenance = await writeBaseSdkProvenance({
    archive: baseArchive,
    destination: baseSidecar,
    platform: 'linux-x64',
    toolchain: baseSdkId,
  });
  const gateHostSource = await write(root, 'gate-host-runtime.c', [
    '__attribute__((visibility("default"))) int fixture_gate_host_runtime(void) {',
    '  return 0;',
    '}',
    '',
  ].join('\n'));
  const gateHostRuntime = path.join(root, 'gate-host-runtime.so');
  run('cc', ['-shared', '-fPIC', gateHostSource, '-o', gateHostRuntime]);
  const gateSidecar = path.join(root, GATE_APPARATUS_PROVENANCE);
  const gateProvenance = await writeGateApparatusProvenance({
    runtime: gateHostRuntime,
    runtimePath: `runtime/lib/${TUPLE}/libcangjie-runtime.so`,
    destination: gateSidecar,
    platform: 'linux-x64',
    toolchain: baseSdkId,
    baseSdkProvenance: baseProvenance,
  });
  const cjpmSidecar = path.join(root, CJPM_PROVENANCE);
  await writeCjpmProvenance({
    binary: cjpm,
    destination: cjpmSidecar,
    platform: 'linux-x64',
    repository: 'https://github.com/cjcj-dev/cangjie-tools.git',
    commit: CJPM_SHA,
  });

  const packageArgs = [path.resolve('scripts/package_sdk.mjs'),
    '--sdk', sdk,
    '--binary', binary,
    '--allow-stock-runtime',
    '--std-dir', std,
    '--llvm-manifest', llvmManifest,
    '--python-bundle', pythonBundle,
    '--base-sdk-id', baseSdkId,
    '--base-sdk-archive', baseArchive,
    '--base-sdk-provenance', baseSidecar,
    '--gate-host-runtime', gateHostRuntime,
    '--gate-apparatus-provenance', gateSidecar,
    '--cjcj-source-sha', CJCJ_SHA,
    '--runtime-source-sha', RUNTIME_SHA,
    '--std-source-repo', 'https://github.com/cjcj-dev/cangjie-runtime.git',
    '--cjpm-provenance', cjpmSidecar,
    '--cjpm-source-repo', 'https://github.com/cjcj-dev/cangjie-tools.git',
    '--cjpm-source-sha', CJPM_SHA,
    '--version', 'fixture',
    '--platform', 'linux-x64',
    '--outdir', out,
  ];
  const packaged = run('zx', packageArgs, {cwd: path.resolve('.')});
  assert.match(packaged.stdout, /DONE: .*cjcj-fixture-linux-x64\.tar\.gz/);

  const packageName = 'cjcj-fixture-linux-x64';
  const manifestFile = path.join(out, `${packageName}.RELEASE-MANIFEST.jsonl`);
  const manifestText = await fs.readFile(manifestFile, 'utf8');
  const rows = manifestText.trim().split('\n').map(JSON.parse);
  assert.equal(rows.length, 9);
  const apparatus = rows.find(row => row.component === GATE_APPARATUS_COMPONENT).acceptance_apparatus;
  assert.equal(apparatus.gate_host_toolchain, REVIEWED_GATE_HOST_TOOLCHAIN);
  assert.equal(apparatus.host_runtime.sha256, gateProvenance.host_runtime.sha256);
  assert.equal(apparatus.host_runtime.g_cjLoadBadMask_count, 0);
  assert.match(apparatus.known_apparatus_limitations.text, /PostTraceBarrier::ReadReference/);
  assert.equal(rows.find(row => row.component === 'llvm-opt').embedded_stamp,
    `CJLLVM-COMMIT:${LLVM_SHA}`);
  assert.equal(rows.find(row => row.component === 'python').source.commit, RELEASE_PYTHON_VERSION);
  assert.equal(rows.find(row => row.component === 'base-sdk').source.version,
    REVIEWED_GATE_HOST_TOOLCHAIN.replace(/^nightly-/, ''));
  assert.equal(rows.find(row => row.component === 'base-sdk').source.status,
    SOURCE_PROVENANCE_NOT_APPLICABLE);
  assert.equal(rows.find(row => row.component === 'base-sdk').source.commit,
    SOURCE_PROVENANCE_NOT_APPLICABLE);
  assert.equal(rows.find(row => row.component === 'base-sdk').source.reason,
    BASE_SDK_SOURCE_REASON);
  assert.match(rows.find(row => row.component === 'base-sdk').artifact.sha256, /^[0-9a-f]{64}$/);
  assert.equal(rows.find(row => row.component === 'cjpm').source.status,
    SOURCE_PROVENANCE_RESOLVED);
  assert.equal(rows.find(row => row.component === 'cjpm').source.commit, CJPM_SHA);
  assert.match(rows.find(row => row.component === 'cjpm').artifact.sha256, /^[0-9a-f]{64}$/);
  const listing = run('tar', ['-tzf', path.join(out, `${packageName}.tar.gz`)]).stdout;
  assert.match(listing, new RegExp(`${packageName}/PROVENANCE\\.txt`));
  assert.match(listing, new RegExp(`${packageName}/RELEASE-MANIFEST\\.jsonl`));
  assert.match(listing, new RegExp(`${packageName}/${BASE_SDK_PROVENANCE}`));
  assert.match(listing, new RegExp(`${packageName}/${CJPM_PROVENANCE}`));
  assert.match(listing, new RegExp(`${packageName}/${GATE_APPARATUS_PROVENANCE}`));
  assert.match(listing, new RegExp(`${packageName}/llvm-tools\.manifest`));
  const packagedLlvmManifest = parsePackagedLlvmToolsManifest(
    await fs.readFile(path.join(out, packageName, 'llvm-tools.manifest'), 'utf8'),
  );
  const toolRows = new Map(packagedLlvmManifest.tools.map(row => [row.tool, row]));
  assert.equal(toolRows.get('llc').source, `tuple:${LLVM_SHA}`);
  assert.equal(toolRows.get('opt').source, `tuple:${LLVM_SHA}`);
  assert.equal(toolRows.get('ld.lld').source, `tuple:${LLVM_SHA}`);
  assert.equal(toolRows.get('llvm-objcopy').source, `base-sdk:${baseProvenance.artifact.sha256}`);
  assert.equal(toolRows.get('llvm-ar').present, 'no');
  console.log(`PACKAGER-OUTPUT-BEGIN\n${packaged.stdout.trim()}\nPACKAGER-OUTPUT-END`);
  console.log(`ARCHIVE-PROVENANCE-BEGIN\n${listing.split('\n').filter(line =>
    /PROVENANCE|RELEASE-MANIFEST/.test(line)).join('\n')}\nARCHIVE-PROVENANCE-END`);
  console.log(`RELEASE-MANIFEST-BEGIN\n${manifestText.trim()}\nRELEASE-MANIFEST-END`);

  const originalLlvmManifest = await fs.readFile(llvmManifest, 'utf8');
  await fs.writeFile(llvmManifest, originalLlvmManifest.replace(/^OPT_SHA256=.*$/m, `OPT_SHA256=${'0'.repeat(64)}`));
  const changedLlvm = runRaw('zx', packageArgs, {cwd: path.resolve('.')});
  assert.notEqual(changedLlvm.status, 0, 'changing one LLVM tool sha must fail closed');
  assert.match(`${changedLlvm.stdout}\n${changedLlvm.stderr}`, /opt: packaged sha256 .* does not match tuple manifest/);
  console.log(`NEGATIVE-CHANGE-LLVM RC=${changedLlvm.status}\n${changedLlvm.stderr.trim()}`);
  await fs.writeFile(llvmManifest, originalLlvmManifest);

  await fs.writeFile(llvmManifest, originalLlvmManifest.replace(/^LLD_SHA256=.*$/m, `LLD_SHA256=${'0'.repeat(64)}`));
  const changedLld = runRaw('zx', packageArgs, {cwd: path.resolve('.')});
  assert.notEqual(changedLld.status, 0, 'changing the LTO linker sha must fail closed');
  assert.match(`${changedLld.stdout}\n${changedLld.stderr}`, /ld\.lld: packaged sha256 .* does not match tuple manifest/);
  console.log(`NEGATIVE-CHANGE-LLD RC=${changedLld.status}\n${changedLld.stderr.trim()}`);
  await fs.writeFile(llvmManifest, originalLlvmManifest);

  await fs.rm(gateSidecar);
  const missingGateApparatus = runRaw('zx', packageArgs, {cwd: path.resolve('.')});
  assert.equal(missingGateApparatus.status, 2, 'missing gate apparatus sidecar must fail closed with RC=2');
  console.log(`NEGATIVE-MISSING-GATE-APPARATUS RC=${missingGateApparatus.status}\n${missingGateApparatus.stderr.trim()}`);
  await writeGateApparatusProvenance({
    runtime: gateHostRuntime,
    runtimePath: `runtime/lib/${TUPLE}/libcangjie-runtime.so`,
    destination: gateSidecar,
    platform: 'linux-x64',
    toolchain: baseSdkId,
    baseSdkProvenance: baseProvenance,
  });

  const changedGateRuntimeSha = `${gateProvenance.host_runtime.sha256[0] === '0' ? '1' : '0'}${
    gateProvenance.host_runtime.sha256.slice(1)}`;
  const changedGateSidecar = (await fs.readFile(gateSidecar, 'utf8'))
    .replace(gateProvenance.host_runtime.sha256, changedGateRuntimeSha);
  await fs.writeFile(gateSidecar, changedGateSidecar);
  const changedGateApparatus = runRaw('zx', packageArgs, {cwd: path.resolve('.')});
  assert.equal(changedGateApparatus.status, 1, 'one-byte gate apparatus change must fail closed with RC=1');
  console.log(`NEGATIVE-CHANGE-GATE-APPARATUS RC=${changedGateApparatus.status}\n${changedGateApparatus.stderr.trim()}`);
  await writeGateApparatusProvenance({
    runtime: gateHostRuntime,
    runtimePath: `runtime/lib/${TUPLE}/libcangjie-runtime.so`,
    destination: gateSidecar,
    platform: 'linux-x64',
    toolchain: baseSdkId,
    baseSdkProvenance: baseProvenance,
  });

  await fs.rm(baseSidecar);
  const deleted = runRaw('zx', packageArgs, {cwd: path.resolve('.')});
  assert.notEqual(deleted.status, 0, 'deleting the base SDK sidecar must fail closed');
  console.log(`NEGATIVE-DELETE-SIDECAR RC=${deleted.status}\n${deleted.stderr.trim()}`);
  await writeBaseSdkProvenance({
    archive: baseArchive,
    destination: baseSidecar,
    platform: 'linux-x64',
    toolchain: baseSdkId,
  });

  const emptyBaseReason = JSON.parse(await fs.readFile(baseSidecar, 'utf8'));
  emptyBaseReason.source.reason = '';
  await fs.writeFile(baseSidecar, `${JSON.stringify(emptyBaseReason, null, 2)}\n`);
  const missingBaseReason = runRaw('zx', packageArgs, {cwd: path.resolve('.')});
  assert.notEqual(missingBaseReason.status, 0, 'empty base SDK not-applicable reason must fail closed');
  assert.match(`${missingBaseReason.stdout}\n${missingBaseReason.stderr}`,
    /base SDK provenance\.source\.reason is empty/);
  console.log(`NEGATIVE-EMPTY-BASE-REASON RC=${missingBaseReason.status}\n${missingBaseReason.stderr.trim()}`);
  await writeBaseSdkProvenance({
    archive: baseArchive,
    destination: baseSidecar,
    platform: 'linux-x64',
    toolchain: baseSdkId,
  });

  await fs.rm(cjpmSidecar);
  const missingCjpm = runRaw('zx', packageArgs, {cwd: path.resolve('.')});
  assert.equal(missingCjpm.status, 2, 'deleting the cjpm sidecar must fail closed with RC=2');
  assert.match(`${missingCjpm.stdout}\n${missingCjpm.stderr}`, /cjpm provenance not found:/);
  console.log(`NEGATIVE-DELETE-CJPM-SIDECAR RC=${missingCjpm.status}\n${missingCjpm.stderr.trim()}`);
  await writeCjpmProvenance({
    binary: cjpm,
    destination: cjpmSidecar,
    platform: 'linux-x64',
    repository: 'https://github.com/cjcj-dev/cangjie-tools.git',
    commit: CJPM_SHA,
  });

  const changedCjpmSha = `f${CJPM_SHA.slice(1)}`;
  const changedSidecar = (await fs.readFile(cjpmSidecar, 'utf8')).replace(CJPM_SHA, changedCjpmSha);
  await fs.writeFile(cjpmSidecar, changedSidecar);
  const changed = runRaw('zx', packageArgs, {cwd: path.resolve('.')});
  assert.notEqual(changed.status, 0, 'changing one byte in the cjpm sidecar must fail closed');
  console.log(`NEGATIVE-CHANGE-SIDECAR RC=${changed.status}\n${changed.stderr.trim()}`);
});
