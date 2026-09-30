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
  SOURCE_PROVENANCE_NOT_APPLICABLE,
  baseSdkDownload,
} from '../lib/release-component-provenance.mjs';
import {
  GATE_APPARATUS_PROVENANCE,
  REVIEWED_GATE_HOST_TOOLCHAIN,
  gateApparatusCoverageWarning,
  validateGateApparatusProvenance,
  verifyGateApparatusProvenance,
} from '../lib/release-gate-apparatus.mjs';

test('gate apparatus records actual host bytes separately from its review coverage', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'gate-apparatus-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const sdk = path.join(root, 'sdk');
  const runtime = path.join(sdk, 'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so');
  const source = path.join(root, 'runtime.c');
  await fs.mkdir(path.dirname(runtime), {recursive: true});
  await fs.writeFile(source, '__attribute__((visibility("default"))) int fixture_runtime(void) { return 0; }\n');
  const compiled = spawnSync('cc', ['-shared', '-fPIC', source, '-o', runtime], {encoding: 'utf8'});
  assert.equal(compiled.status, 0, compiled.stderr);

  const archive = path.join(root, baseSdkDownload('linux-x64', REVIEWED_GATE_HOST_TOOLCHAIN).archive);
  await fs.writeFile(archive, 'fixture SDK archive\n');
  const baseSidecar = path.join(root, BASE_SDK_PROVENANCE);
  const baseDownload = baseSdkDownload('linux-x64', REVIEWED_GATE_HOST_TOOLCHAIN);
  const archiveBytes = await fs.readFile(archive);
  await fs.writeFile(baseSidecar, `${JSON.stringify({
    schema: 1,
    component: 'base-sdk',
    platform: 'linux-x64',
    source: {
      status: SOURCE_PROVENANCE_NOT_APPLICABLE,
      reason: BASE_SDK_SOURCE_REASON,
    },
    release: {
      repository: baseDownload.releaseRepository,
      version: baseDownload.version,
      download_url: baseDownload.url,
    },
    artifact: {
      path: baseDownload.archive,
      size: archiveBytes.length,
      sha256: crypto.createHash('sha256').update(archiveBytes).digest('hex'),
    },
  }, null, 2)}\n`);
  const githubEnv = path.join(root, 'github.env');
  const currentHost = 'nightly-unreviewed-control';

  const capture = ({toolchain, name}) => {
    const output = path.join(root, name);
    const childEnv = {...process.env, GITHUB_ENV: githubEnv};
    delete childEnv.NODE_TEST_CONTEXT;
    const captured = spawnSync(process.execPath, [
      path.resolve('ci/release/prepare_gate_apparatus.mjs'),
      '--sdk', sdk,
      '--platform', 'linux-x64',
      '--actual-host-toolchain', toolchain,
      '--base-sdk-sidecar', baseSidecar,
      '--outdir', output,
    ], {encoding: 'utf8', env: childEnv});
    return {captured, output};
  };

  await t.test('a different actual host is retained with a visible not-covered warning', async () => {
    const {captured, output} = capture({toolchain: currentHost, name: 'uncovered'});
    assert.equal(captured.status, 0, captured.stderr);
    const sidecar = JSON.parse(await fs.readFile(path.join(output, GATE_APPARATUS_PROVENANCE), 'utf8'));
    assert.equal(sidecar.gate_host_toolchain, currentHost, 'TARGET producer retains the actual host');
    assert.match(captured.stderr, /WARNING: Gate apparatus does not cover this host configuration/);
    assert.equal(sidecar.reviewed_against, REVIEWED_GATE_HOST_TOOLCHAIN);
    assert.equal(sidecar.coverage, 'not-covered');
    assert.equal(sidecar.coverage_warning, gateApparatusCoverageWarning(currentHost));
    assert.match(sidecar.host_runtime.sha256, /^[0-9a-f]{64}$/);
    assert.equal(sidecar.host_runtime.g_cjLoadBadMask_count, 0);
  });

  await t.test('the reviewed host is covered and carries no warning', async () => {
    const {captured, output} = capture({toolchain: REVIEWED_GATE_HOST_TOOLCHAIN, name: 'covered'});
    assert.equal(captured.status, 0, captured.stderr);
    assert.doesNotMatch(captured.stderr, /WARNING:/);
    const sidecar = JSON.parse(await fs.readFile(path.join(output, GATE_APPARATUS_PROVENANCE), 'utf8'));
    assert.equal(sidecar.gate_host_toolchain, REVIEWED_GATE_HOST_TOOLCHAIN);
    assert.equal(sidecar.reviewed_against, REVIEWED_GATE_HOST_TOOLCHAIN);
    assert.equal(sidecar.coverage, 'covered');
    assert.ok(!Object.hasOwn(sidecar, 'coverage_warning'));
  });

  await t.test('coverage rejects values outside the closed set', async () => {
    const {captured, output} = capture({toolchain: REVIEWED_GATE_HOST_TOOLCHAIN, name: 'invalid'});
    assert.equal(captured.status, 0, captured.stderr);
    const sidecar = JSON.parse(await fs.readFile(path.join(output, GATE_APPARATUS_PROVENANCE), 'utf8'));
    sidecar.coverage = 'unknown';
    assert.throws(() => validateGateApparatusProvenance(sidecar, {platform: 'linux-x64'}),
      /outside the closed set/);
  });

  await t.test('a changed actual host cannot inherit covered status', async () => {
    const {captured, output} = capture({toolchain: REVIEWED_GATE_HOST_TOOLCHAIN, name: 'changed-host'});
    assert.equal(captured.status, 0, captured.stderr);
    const sidecar = JSON.parse(await fs.readFile(path.join(output, GATE_APPARATUS_PROVENANCE), 'utf8'));
    sidecar.gate_host_toolchain = currentHost;
    assert.throws(() => validateGateApparatusProvenance(sidecar, {platform: 'linux-x64'}),
      /coverage mismatch/, 'TARGET actual host and coverage remain coupled');
  });

  for (const field of ['archive', 'runtime']) {
    await t.test(`the retained apparatus rejects a changed ${field} digest`, async () => {
      const {captured, output} = capture({toolchain: REVIEWED_GATE_HOST_TOOLCHAIN, name: `changed-${field}`});
      assert.equal(captured.status, 0, captured.stderr);
      const sidecarPath = path.join(output, GATE_APPARATUS_PROVENANCE);
      const sidecar = JSON.parse(await fs.readFile(sidecarPath, 'utf8'));
      if (field === 'archive') sidecar.base_sdk.archive_sha256 = '0'.repeat(64);
      else sidecar.host_runtime.sha256 = '0'.repeat(64);
      await fs.writeFile(sidecarPath, JSON.stringify(sidecar));
      await assert.rejects(verifyGateApparatusProvenance({
        runtime: path.join(output, 'gate-host-runtime.so'), sidecar: sidecarPath,
        platform: 'linux-x64', expectedToolchain: REVIEWED_GATE_HOST_TOOLCHAIN,
        expectedBaseSdkArchiveSha256: crypto.createHash('sha256').update(archiveBytes).digest('hex'),
      }), field === 'archive' ? /base SDK SHA-256 mismatch/ : /host runtime SHA-256 mismatch/,
      `TARGET ${field} digest must match retained bytes`);
    });
  }

  const environment = await fs.readFile(githubEnv, 'utf8');
  assert.match(environment, /^GATE_HOST_RUNTIME=.+gate-host-runtime\.so$/m);
  assert.match(environment, /^GATE_APPARATUS_PROVENANCE=.+GATE-APPARATUS\.json$/m);
});
