import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {buildConfig} from '../lib/config.mjs';
import {run} from '../lib/runner.mjs';
import {baseEnv} from '../srcbuild/stages/common.mjs';
import * as packageStage from '../srcbuild/stages/package.mjs';
import {shouldRunGcUnitLanguageTests} from '../srcbuild/stages/stdlib.mjs';
import {parseArguments, runSdkUsability, STATES} from '../../scripts/check_sdk_usable.mjs';
import {
  VERIFIER_DIAGNOSTIC_MARKER,
  assertNoVerifierReportArtifacts,
  markDiagnosticWorkspace,
  writeDiagnosticInventory,
} from '../../scripts/verifier_artifact_gate.mjs';

const repoRoot = path.resolve('.');
const srcbuildPath = path.join(repoRoot, 'tools', 'srcbuild_kkk2.sh');
const srcbuild = fs.readFileSync(srcbuildPath, 'utf8');

function shellFunction(name) {
  const match = srcbuild.match(new RegExp(`^${name}\\(\\) \\{[\\s\\S]*?^\\}$`, 'm'));
  assert.ok(match, `missing shell function ${name}`);
  return match[0];
}

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'verifier-report-mode-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  return root;
}

async function withEnvironment(values, action) {
  const saved = new Map(Object.keys(values).map(name => [name, process.env[name]]));
  for (const [name, value] of Object.entries(values)) {
    if (value === undefined) delete process.env[name];
    else process.env[name] = value;
  }
  try { return await action(); } finally {
    for (const [name, value] of saved) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
  }
}

test('formal source-build children force strict mode and delete a residual report path', async t => {
  const root = fixture(t);
  const config = buildConfig({workspace: root, buildRoot: path.join(root, 'build')});
  await withEnvironment({
    CANGJIE_BUILD_DRY_RUN: '1',
    CJ_IR_VERIFIER_MODE: 'report',
    CJ_IR_VERIFIER_REPORT: '/residual/report.tsv',
    CJCJ_SRCBUILD_VERIFIER_REPORT_ACTIVE: undefined,
  }, async () => {
    const env = baseEnv(config);
    assert.equal(env.CJ_IR_VERIFIER_MODE, 'strict');
    assert.equal(env.CJ_IR_VERIFIER_REPORT, null);
  });

  await withEnvironment({
    CANGJIE_BUILD_DRY_RUN: '1',
    CJCJ_SRCBUILD_VERIFIER_REPORT_ACTIVE: reportPath(root),
  }, async () => {
    const env = baseEnv(config);
    assert.equal(env.CJ_IR_VERIFIER_MODE, 'report');
    assert.equal(env.CJ_IR_VERIFIER_REPORT, reportPath(root));
  });

  await withEnvironment({
    CANGJIE_BUILD_DRY_RUN: undefined,
    CJ_IR_VERIFIER_MODE: 'report',
    CJ_IR_VERIFIER_REPORT: '/residual/report.tsv',
  }, async () => {
    const observed = path.join(root, 'observed-env');
    await run([
      process.execPath, '-e',
      'require("node:fs").writeFileSync(process.argv[1], `${process.env.CJ_IR_VERIFIER_MODE}|${process.env.CJ_IR_VERIFIER_REPORT ?? "absent"}`)',
      observed,
    ], {
      envOverlay: {CJ_IR_VERIFIER_MODE: 'strict', CJ_IR_VERIFIER_REPORT: null},
      capture: true,
      logOutput: false,
    });
    assert.equal(fs.readFileSync(observed, 'utf8'), 'strict|absent');
  });
});

function reportPath(root) {
  return path.join(root, 'verifier.tsv');
}

test('diagnostic request targeting removed stdlib step 19 is rejected', t => {
  const root = fixture(t);
  const report = path.join(root, 'rejects.tsv');
  const validation = `${shellFunction('validate_verifier_report_request')}\n`
    + 'validate_verifier_report_request "$1" "$2" "$3"\n';
  const acceptedEmpty = spawnSync('bash', ['-c', validation, 'bash', '', '2', '14'], {encoding: 'utf8'});
  assert.equal(acceptedEmpty.status, 0, acceptedEmpty.stderr);
  const rejected = spawnSync('bash', ['-c', validation, 'bash', report, '2', '19'], {encoding: 'utf8'});
  assert.notEqual(rejected.status, 0);
  assert.match(rejected.stderr, /removed stdlib step 19/);
  assert.equal(shouldRunGcUnitLanguageTests({}), true);
  assert.equal(shouldRunGcUnitLanguageTests({CJCJ_SRCBUILD_VERIFIER_REPORT_ACTIVE: report}), false);

  const rejectMarked = `${shellFunction('reject_diagnostic_workspace')}\n`
    + 'reject_diagnostic_workspace "$1" "step 20"\n';
  const cleanWorkspace = spawnSync('bash', ['-c', rejectMarked, 'bash', path.join(root, 'absent-marker')], {
    encoding: 'utf8',
  });
  assert.equal(cleanWorkspace.status, 0, cleanWorkspace.stderr);
  const marker = path.join(root, VERIFIER_DIAGNOSTIC_MARKER);
  fs.writeFileSync(marker, '{}\n');
  const markedWorkspace = spawnSync('bash', ['-c', rejectMarked, 'bash', marker], {encoding: 'utf8'});
  assert.equal(markedWorkspace.status, 5, markedWorkspace.stderr);
  assert.match(markedWorkspace.stderr, /refusing step 20 in workspace marked diagnostic/);
});

test('artifact lineage gate inventories report metadata and rejects it or its diagnostic marker', t => {
  const root = fixture(t);
  const generated = path.join(root, 'generated');
  const source = path.join(root, 'source');
  fs.mkdirSync(generated);
  fs.mkdirSync(source);
  const clean = path.join(generated, 'clean.bc');
  const marked = path.join(generated, 'marked.bc');
  const markedObject = path.join(generated, 'marked.o');
  const incompatibleSourceFixture = path.join(source, 'invalid.ll.bc');
  fs.writeFileSync(clean, 'clean fixture');
  fs.writeFileSync(marked, Buffer.from([0x42, 0x43, 0xc0, 0xde, 0x01]));
  fs.writeFileSync(markedObject, Buffer.from([0x42, 0x43, 0xc0, 0xde, 0x01]));
  fs.writeFileSync(incompatibleSourceFixture, Buffer.from([0x42, 0x43, 0xc0, 0xde, 0x01]));
  const llvmDis = path.join(root, 'llvm-dis');
  fs.writeFileSync(llvmDis, [
    '#!/usr/bin/env bash',
    'if [[ $(basename "$1") == invalid.ll.bc ]]; then exit 1; fi',
    'if [[ $(basename "$1") == marked.bc || $(basename "$1") == marked.o ]]; then',
    "  printf '%s\\n' '!cj.verifier.mode = !{!7}' '!7 = !{!\"report\"}'",
    'else',
    "  printf '%s\\n' '; clean module'",
    'fi',
    '',
  ].join('\n'));
  fs.chmodSync(llvmDis, 0o755);
  const report = path.join(root, 'rejects.tsv');
  const inventory = path.join(root, 'artifacts.tsv');
  const result = writeDiagnosticInventory({workspace: root, report, inventory, artifactRoots: [generated], llvmDis});
  assert.deepEqual(result.matches.map(match => path.basename(match.path)), ['marked.bc', 'marked.o']);
  assert.match(fs.readFileSync(inventory, 'utf8'), /marked\.bc/);
  assert.match(fs.readFileSync(inventory, 'utf8'), /marked\.o/);
  assert.throws(
    () => assertNoVerifierReportArtifacts([generated], {llvmDis, checkAncestors: false}),
    /rejected 2 file.*cj\.verifier\.mode=report/,
  );

  fs.rmSync(marked);
  fs.rmSync(markedObject);
  fs.rmSync(path.join(root, VERIFIER_DIAGNOSTIC_MARKER));
  assert.throws(
    () => assertNoVerifierReportArtifacts([source], {llvmDis}),
    /llvm-dis could not inspect.*invalid\.ll\.bc/,
  );
  assert.equal(assertNoVerifierReportArtifacts([generated], {llvmDis}).matches.length, 0);
  assert.equal(assertNoVerifierReportArtifacts([clean], {llvmDis, checkAncestors: false}).matches.length, 0);
  markDiagnosticWorkspace({workspace: root, report, inventory});
  assert.throws(() => assertNoVerifierReportArtifacts([root], {llvmDis}), /workspace is not a formal artifact source/);
});

test('source-build package entry rejects a diagnostic workspace before archiving', async t => {
  const root = fixture(t);
  const workspace = path.join(root, 'workspace');
  fs.mkdirSync(path.join(workspace, 'cangjie_compiler', 'output'), {recursive: true});
  const report = path.join(root, 'report.tsv');
  markDiagnosticWorkspace({workspace, report, inventory: `${report}.artifacts.tsv`});
  const config = buildConfig({workspace, buildRoot: path.join(root, 'build')});
  await assert.rejects(() => packageStage.run(config), /workspace is not a formal artifact source/);
});

test('release package entry rejects a diagnostic SDK before constructing its stage', t => {
  const root = fixture(t);
  const sdk = path.join(root, 'sdk');
  const pythonBundle = path.join(root, 'python');
  fs.mkdirSync(path.join(sdk, 'bin'), {recursive: true});
  fs.mkdirSync(pythonBundle);
  const makeFile = name => {
    const file = path.join(root, name);
    fs.writeFileSync(file, 'fixture');
    return file;
  };
  const report = path.join(root, 'report.tsv');
  markDiagnosticWorkspace({workspace: sdk, report, inventory: `${report}.artifacts.tsv`});
  const zxProbe = spawnSync('sh', ['-c', 'command -v zx'], {encoding: 'utf8'});
  const command = zxProbe.status === 0 ? zxProbe.stdout.trim() : 'npx';
  const prefix = zxProbe.status === 0 ? [] : ['--yes', 'zx@8'];
  const result = spawnSync(command, [...prefix, path.join(repoRoot, 'scripts', 'package_sdk.mjs'),
    '--sdk', sdk,
    '--binary', makeFile('cjc'),
    '--version', 'fixture',
    '--platform', 'linux-x64',
    '--outdir', path.join(root, 'out'),
    '--python-bundle', pythonBundle,
    '--llvm-manifest', makeFile('llvm.manifest'),
    '--base-sdk-archive', makeFile('base.tar'),
    '--base-sdk-provenance', makeFile('base.json'),
    '--gate-host-runtime', makeFile('runtime.so'),
    '--gate-apparatus-provenance', makeFile('gate.json'),
    '--cjpm-provenance', makeFile('cjpm.json'),
    '--cjpm-source-repo', 'https://example.invalid/cjpm.git',
    '--cjpm-source-sha', 'a'.repeat(40),
  ], {encoding: 'utf8', timeout: 300_000});
  assert.notEqual(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stderr, /diagnostic verifier workspace is not a formal artifact source/);
  assert.equal(fs.existsSync(path.join(root, 'out')), false);
});

test('SDK usability entry records verifier diagnostic rejection before running probes', t => {
  const sdk = fixture(t);
  const report = path.join(sdk, 'report.tsv');
  markDiagnosticWorkspace({workspace: sdk, report, inventory: `${report}.artifacts.tsv`});
  const result = runSdkUsability(parseArguments(['--sdk', sdk]));
  assert.equal(result.results[0].id, 'U0_VERIFIER_ARTIFACTS');
  assert.equal(result.results[0].state, STATES.FAIL);
  assert.match(result.results[0].detail, /workspace is not a formal artifact source/);
  assert.ok(result.results.slice(1).every(entry => entry.state === STATES.UNKNOWN));
});

test('performance entry rejects a compiler from a diagnostic SDK before creating workload output', t => {
  const root = fixture(t);
  const sdk = path.join(root, 'sdk');
  const compiler = path.join(sdk, 'bin', 'cjc');
  const work = path.join(root, 'work');
  fs.mkdirSync(path.dirname(compiler), {recursive: true});
  fs.writeFileSync(compiler, '#!/usr/bin/env bash\nexit 0\n');
  fs.chmodSync(compiler, 0o755);
  const report = path.join(root, 'report.tsv');
  markDiagnosticWorkspace({workspace: sdk, report, inventory: `${report}.artifacts.tsv`});
  const result = spawnSync('bash', [path.join(repoRoot, 'scripts', 'perfincr_cycle_smoke.sh'), compiler, work, '1'], {
    encoding: 'utf8',
  });
  assert.notEqual(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stderr, /diagnostic verifier workspace is not a formal artifact source/);
  assert.equal(fs.existsSync(work), false);
});
