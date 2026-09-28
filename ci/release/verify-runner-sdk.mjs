#!/usr/bin/env node
// Real-input acceptance: invoke the installed SDK probe, then disconnect its
// producer and exit-status consumer in private source copies. No SDK is changed.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {RELEASE_REQUIREMENTS} from '../../build/lib/targets.mjs';

const [requirement, destination] = process.argv.slice(2);
assert.ok(Object.hasOwn(RELEASE_REQUIREMENTS, requirement), 'known SDK requirement');
assert.ok(destination, 'evidence directory required');
const root = path.resolve(import.meta.dirname, '../..');
const evidence = path.resolve(destination);
fs.mkdirSync(evidence, {recursive: true});
// A product artifact is identified by what it contains, never by where it sits:
// contentSha() reads the file, and textSha() is only ever fed text already in
// hand. The identity record below carries both so a path string can never be
// mistaken for a content hash.
const contentSha = (file) => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const textSha = (text) => createHash('sha256').update(text).digest('hex');
const original = fs.readFileSync(path.join(root, 'ci/release/platform-matrix.mjs'), 'utf8');
const producer = requirement === 'xcode-ios'
  ? "return {present: true, detail: found.join(', ')};"
  : 'return {present: true, detail: `${variable}=${root}`};';
const consumer = 'return result.present ? 0 : 1;';
assert.ok(original.includes(producer), 'producer cut must match the product source');
assert.ok(original.includes(consumer), 'consumer cut must match the product source');
const arms = {
  candidate: original,
  'cut-producer': original.replace(producer, producer.replace('present: true', 'present: false')),
  'cut-consumer': original.replace(consumer, 'return result.present ? 1 : 0;'),
  restored: original,
};
// The installer, not this harness, is what puts the SDK location into the job
// environment. Two more arms walk that same line from both sides: one deletes it
// from a private installer copy, one runs an untouched copy, so the export line
// is a load-bearing product point rather than an assumed one.
const VARIABLE = {'android-ndk': 'ANDROID_NDK_ROOT', 'ohos-sdk': 'OHOS_SDK_HOME', 'xcode-ios': 'DEVELOPER_DIR'}[requirement];
const installerPath = path.join(root, 'ci/release/install-runner-sdk.py');
const installer = fs.readFileSync(installerPath, 'utf8');
// Read back from the file the runner will execute, before any arm runs.
const candidateInstallerSha256 = contentSha(installerPath);
const exportLine = new RegExp(`^\\s*export\\('${VARIABLE}'.*$`, 'm');
const exportMatch = installer.match(exportLine);
assert.ok(exportMatch, 'export cut must match the product installer');

function probeWith(env) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [path.join(root, 'ci/release/platform-matrix.mjs'),
      'probe', '--requirement', requirement], {env});
    let stdout = '', stderr = '';
    child.stdout.setEncoding('utf8').on('data', chunk => { stdout += chunk; });
    child.stderr.setEncoding('utf8').on('data', chunk => { stderr += chunk; });
    child.on('error', reject);
    child.on('close', status => resolve({status, stdout, stderr}));
  });
}

// Runs concurrently with the four probe arms below; only the assertions at
// the end depend on its result.
const exportTree = path.join(evidence, 'cut-export');
const restoredExportTree = path.join(evidence, 'restored-export');
function runInstaller(script, tree) {
  const env = path.join(tree, 'github-env');
  fs.writeFileSync(env, '');
  return new Promise((resolve, reject) => {
    const child = spawn('python3', [script, requirement, '--root', path.join(tree, 'sdk')],
      {env: {...process.env, GITHUB_ENV: env}});
    let stdout = '', stderr = '';
    child.stdout.setEncoding('utf8').on('data', chunk => { stdout += chunk; });
    child.stderr.setEncoding('utf8').on('data', chunk => { stderr += chunk; });
    child.on('error', reject);
    child.on('close', status => resolve({status, stdout, stderr, env}));
  });
}
function readExports(file) {
  // A GITHUB_ENV line is `NAME=VALUE`; Python writes it in the platform's text
  // mode, so on Windows the separator is CRLF and the carriage return belongs to
  // the line, not to the value.
  return Object.fromEntries(fs.readFileSync(file, 'utf8').split(/\r?\n/).filter(Boolean)
    .map(line => [line.slice(0, line.indexOf('=')), line.slice(line.indexOf('=') + 1)]));
}
const exportArm = (async () => {
fs.mkdirSync(path.join(exportTree, 'ci/release'), {recursive: true});
const cutInstaller = path.join(exportTree, 'ci/release/install-runner-sdk.py');
fs.writeFileSync(cutInstaller, installer.replace(exportLine, ''));
// Each arm's identity is taken from its own file, before that file is executed,
// so the record cannot drift from what actually ran.
const cutInstallerSha256 = contentSha(cutInstaller);
const install = await runInstaller(cutInstaller, exportTree);
// The disconnected installer must still have produced a working SDK, otherwise
// a red probe would only prove the install broke, not that the export carries it.
const sdkBinary = path.join(exportTree, 'sdk/sdk/native/llvm/bin', process.platform === 'win32' ? 'clang.exe' : 'clang');
const toolCheck = requirement === 'ohos-sdk'
  ? await new Promise(resolve => {
    const child = spawn(sdkBinary, ['--version']);
    let stdout = '';
    child.stdout.setEncoding('utf8').on('data', chunk => { stdout += chunk; });
    child.on('error', () => resolve({status: -1, stdout}));
    child.on('close', status => resolve({status, stdout}));
  })
  : {status: 0, stdout: `${requirement} needs no native tool binary`};
const exported = readExports(install.env);
const withoutExport = {...process.env};
delete withoutExport[VARIABLE];
const cutRun = await probeWith({...withoutExport, ...exported});
// The restored arm runs an untouched copy of the product installer: the pair
// differs from the cut arm by exactly the one deleted export line.
fs.mkdirSync(path.join(restoredExportTree, 'ci/release'), {recursive: true});
const restoredInstaller = path.join(restoredExportTree, 'ci/release/install-runner-sdk.py');
fs.writeFileSync(restoredInstaller, installer);
const restoredInstallerSha256 = contentSha(restoredInstaller);
const restoredInstall = await runInstaller(restoredInstaller, restoredExportTree);
const restoredExports = readExports(restoredInstall.env);
const restoredRun = await probeWith({...withoutExport, ...restoredExports});
const controlRun = await probeWith(process.env);
const exportRecord = {
  arm: 'cut-export',
  requirement,
  installerRc: install.status,
  // Content hashes of the three files that were about to run, each with the
  // hash of its own path alongside it: a path string is never an identity.
  installerIdentity: {
    candidate: {path: installerPath, sha256: candidateInstallerSha256, pathStringSha256: textSha(installerPath)},
    cut: {path: cutInstaller, sha256: cutInstallerSha256, pathStringSha256: textSha(cutInstaller)},
    restored: {path: restoredInstaller, sha256: restoredInstallerSha256, pathStringSha256: textSha(restoredInstaller)},
  },
  restoredInstallerRc: restoredInstall.status,
  exportedVariable: VARIABLE,
  exportedByCutInstaller: exported[VARIABLE] ?? null,
  exportedByRestoredInstaller: restoredExports[VARIABLE] ?? null,
  toolCheckRc: toolCheck.status,
  toolCheckOut: toolCheck.stdout.trim().split('\n')[0] ?? '',
  rc: cutRun.status,
  stdout: cutRun.stdout,
  restoredRc: restoredRun.status,
  restoredStdout: restoredRun.stdout,
  controlRc: controlRun.status,
  controlStdout: controlRun.stdout,
  // The export is load-bearing only where losing it loses the capability. Where
  // the runner supplies the same SDK by another route (xcode-select's default
  // toolchain), the arm records that fact instead of claiming a red it cannot see.
  exportLoadBearing: controlRun.stdout?.startsWith(`PRESENT ${requirement}:`) === true
    && cutRun.stdout?.startsWith(`PRESENT ${requirement}:`) !== true,
};
try {
  assert.deepEqual({rc: cutRun.status, present: cutRun.stdout?.startsWith(`PRESENT ${requirement}:`)},
    {rc: 0, present: true}, 'installed SDK capability reaches a successful CLI result');
  exportRecord.targetAssertionRc = 0;
} catch (error) {
  exportRecord.targetAssertionRc = 1;
  exportRecord.targetAssertionFailure = error.message;
}
console.log(JSON.stringify(exportRecord));
fs.writeFileSync(path.join(exportTree, 'output.log'), `${install.stdout}${install.stderr}`);
fs.writeFileSync(path.join(restoredExportTree, 'output.log'), `${restoredInstall.stdout}${restoredInstall.stderr}`);
return exportRecord;
})();

const results = [];
await Promise.all(Object.entries(arms).map(async ([arm, source], index) => {
  const tree = path.join(evidence, arm);
  fs.mkdirSync(path.join(tree, 'ci/release'), {recursive: true});
  fs.cpSync(path.join(root, 'build/lib'), path.join(tree, 'build/lib'), {recursive: true});
  const script = path.join(tree, 'ci/release/platform-matrix.mjs');
  fs.writeFileSync(script, source);
  const run = await new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [script, 'probe', '--requirement', requirement], {env: process.env});
    let stdout = '', stderr = '';
    child.stdout.setEncoding('utf8').on('data', chunk => { stdout += chunk; });
    child.stderr.setEncoding('utf8').on('data', chunk => { stderr += chunk; });
    child.on('error', reject);
    child.on('close', status => resolve({status, stdout, stderr}));
  });
  fs.writeFileSync(path.join(tree, 'output.log'), `${run.stdout ?? ''}${run.stderr ?? ''}`);
  const expected = arm.startsWith('cut-') ? 1 : 0;
  const record = {arm, requirement, sha256: createHash('sha256').update(source).digest('hex'), rc: run.status, expected};
  // The target assertion is identical in every arm. The outer harness checks
  // that only the disconnected arms fail it; it never rewrites the invariant.
  try {
    assert.deepEqual({rc: run.status, present: run.stdout?.startsWith(`PRESENT ${requirement}:`)},
      {rc: 0, present: true}, 'installed SDK capability reaches a successful CLI result');
    record.targetAssertionRc = 0;
  } catch (error) {
    record.targetAssertionRc = 1;
    record.targetAssertionFailure = error.message;
  }
  results[index] = record;
  // Emit the actual product result before asserting, so an earlier setup error
  // cannot be mistaken for reaching this capability assertion.
  console.log(JSON.stringify({...record, stdout: run.stdout, stderr: run.stderr}));
  record.stdout = run.stdout;
}));
const exportRecord = await exportArm;
// Persist the observation before judging it, so a failing judge still leaves the
// product's own numbers on disk.
fs.writeFileSync(path.join(exportTree, 'results.json'), `${JSON.stringify(exportRecord, null, 2)}\n`);
fs.writeFileSync(path.join(evidence, 'export-arm.json'), `${JSON.stringify(exportRecord, null, 2)}\n`);
fs.writeFileSync(path.join(evidence, 'results.json'), `${JSON.stringify(results, null, 2)}\n`);
assert.match(exportRecord.controlStdout, new RegExp(`^PRESENT ${requirement}:`),
  'control arm: the installed SDK is present');
assert.equal(exportRecord.installerRc, 0, 'cut-export: the installer still succeeded');
assert.equal(exportRecord.toolCheckRc, 0, 'cut-export: the disconnected install still works');
// Identity before verdict: the cut arm is the product installer minus one line,
// the restored arm is the product installer, and neither is identified by path.
for (const [name, one] of Object.entries(exportRecord.installerIdentity)) {
  assert.notEqual(one.sha256, one.pathStringSha256, `${name}: the identity is not the path string`);
  assert.equal(one.sha256, contentSha(one.path), `${name}: the recorded identity is the file content`);
}
assert.equal(exportRecord.installerIdentity.restored.sha256, exportRecord.installerIdentity.candidate.sha256,
  'restored-export: the restored installer is the product installer');
assert.notEqual(exportRecord.installerIdentity.cut.sha256, exportRecord.installerIdentity.candidate.sha256,
  'cut-export: the cut installer differs from the product installer');
assert.equal(exportRecord.restoredInstallerRc, 0, 'restored-export: the untouched installer copy succeeded');
assert.equal(exportRecord.restoredRc, 0, 'restored-export: the export is back');
assert.match(exportRecord.restoredStdout, new RegExp(`^PRESENT ${requirement}:`),
  'restored-export: the target capability is present again');
assert.equal(exportRecord.targetAssertionRc, exportRecord.exportLoadBearing ? 1 : 0,
  'cut-export: unchanged target assertion verdict');
for (const {arm, rc, expected, targetAssertionRc, stdout} of results) {
  assert.equal(rc, expected, `${arm}: target capability exit status`);
  assert.equal(targetAssertionRc, expected, `${arm}: unchanged target assertion verdict`);
  assert.match(stdout, new RegExp(`^${arm === 'cut-producer' ? 'MISSING' : 'PRESENT'} ${requirement}:`), `${arm}: target capability result`);
}
assert.equal(results[0].sha256, results[3].sha256);
for (const cut of results.slice(1, 3)) assert.notEqual(cut.sha256, results[0].sha256);
console.log(`SDK_PROBE_CAUSAL_CHECK requirement=${requirement} arms=${results.length} exportLoadBearing=${exportRecord.exportLoadBearing}`);
