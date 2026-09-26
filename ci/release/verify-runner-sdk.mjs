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
// environment. A third arm disconnects that export and re-probes, so the export
// line is a load-bearing product point rather than an assumed one.
const VARIABLE = {'android-ndk': 'ANDROID_NDK_ROOT', 'ohos-sdk': 'OHOS_SDK_HOME', 'xcode-ios': 'DEVELOPER_DIR'}[requirement];
const installer = fs.readFileSync(path.join(root, 'ci/release/install-runner-sdk.py'), 'utf8');
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
const exportArm = (async () => {
const exportTree = path.join(evidence, 'cut-export');
fs.mkdirSync(path.join(exportTree, 'ci/release'), {recursive: true});
const cutInstaller = path.join(exportTree, 'ci/release/install-runner-sdk.py');
fs.writeFileSync(cutInstaller, installer.replace(exportLine, ''));
const cutRoot = path.join(exportTree, 'sdk');
const cutEnv = path.join(exportTree, 'github-env');
fs.writeFileSync(cutEnv, '');
const install = await new Promise((resolve, reject) => {
  const child = spawn('python3', [cutInstaller, requirement, '--root', cutRoot],
    {env: {...process.env, GITHUB_ENV: cutEnv}});
  let stdout = '', stderr = '';
  child.stdout.setEncoding('utf8').on('data', chunk => { stdout += chunk; });
  child.stderr.setEncoding('utf8').on('data', chunk => { stderr += chunk; });
  child.on('error', reject);
  child.on('close', status => resolve({status, stdout, stderr}));
});
// The disconnected installer must still have produced a working SDK, otherwise
// a red probe would only prove the install broke, not that the export carries it.
const sdkBinary = cutRoot / 'sdk/native/llvm/bin' / (process.platform === 'win32' ? 'clang.exe' : 'clang');
const toolCheck = requirement === 'ohos-sdk'
  ? await new Promise(resolve => {
    const child = spawn(sdkBinary, ['--version']);
    let stdout = '';
    child.stdout.setEncoding('utf8').on('data', chunk => { stdout += chunk; });
    child.on('error', () => resolve({status: -1, stdout}));
    child.on('close', status => resolve({status, stdout}));
  })
  : {status: 0, stdout: `${requirement} needs no native tool binary`};
const exported = Object.fromEntries(fs.readFileSync(cutEnv, 'utf8').split('\n').filter(Boolean)
  .map(line => [line.slice(0, line.indexOf('=')), line.slice(line.indexOf('=') + 1)]));
const withoutExport = {...process.env};
delete withoutExport[VARIABLE];
const cutRun = await probeWith({...withoutExport, ...exported});
const controlRun = await probeWith(process.env);
const exportRecord = {
  arm: 'cut-export',
  requirement,
  installerRc: install.status,
  installerSha256: createHash('sha256').update(fs.readFileSync(cutInstaller)).digest('hex'),
  cutInstallerSha256: createHash('sha256').update(cutInstaller).digest('hex'),
  exportedVariable: VARIABLE,
  exportedByCutInstaller: exported[VARIABLE] ?? null,
  toolCheckRc: toolCheck.status,
  toolCheckOut: toolCheck.stdout.trim().split('\n')[0] ?? '',
  rc: cutRun.status,
  stdout: cutRun.stdout,
  controlRc: controlRun.status,
  controlStdout: controlRun.stdout,
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
const present = run => run.stdout?.startsWith(`PRESENT ${requirement}:`) === true;
// The export is load-bearing only where losing it loses the capability. Where
// the runner supplies the same SDK by another route (xcode-select's default
// toolchain), the arm records that fact instead of claiming a red it cannot see.
exportRecord.exportLoadBearing = present(controlRun) && !present(cutRun);
assert.equal(present(controlRun), true, 'control arm: the installed SDK is present');
assert.equal(install.status, 0, 'cut-export: the installer still succeeded');
assert.equal(exportRecord.targetAssertionRc, exportRecord.exportLoadBearing ? 1 : 0,
  'cut-export: unchanged target assertion verdict');
fs.writeFileSync(path.join(exportTree, 'results.json'), `${JSON.stringify(exportRecord, null, 2)}\n`);
fs.writeFileSync(path.join(evidence, 'export-arm.json'), `${JSON.stringify(exportRecord, null, 2)}\n`);
fs.writeFileSync(path.join(evidence, 'results.json'), `${JSON.stringify(results, null, 2)}\n`);
for (const {arm, rc, expected, targetAssertionRc, stdout} of results) {
  assert.equal(rc, expected, `${arm}: target capability exit status`);
  assert.equal(targetAssertionRc, expected, `${arm}: unchanged target assertion verdict`);
  assert.match(stdout, new RegExp(`^${arm === 'cut-producer' ? 'MISSING' : 'PRESENT'} ${requirement}:`), `${arm}: target capability result`);
}
assert.equal(results[0].sha256, results[3].sha256);
for (const cut of results.slice(1, 3)) assert.notEqual(cut.sha256, results[0].sha256);
console.log(`SDK_PROBE_CAUSAL_CHECK requirement=${requirement} arms=${results.length} exportLoadBearing=${exportRecord.exportLoadBearing}`);
