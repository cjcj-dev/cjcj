import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {
  BASE_SDK_PROVENANCE,
  baseSdkDownload,
  writeBaseSdkProvenance,
} from '../lib/release-component-provenance.mjs';
import {
  GATE_APPARATUS_PROVENANCE,
  REVIEWED_GATE_HOST_TOOLCHAIN,
} from '../lib/release-gate-apparatus.mjs';

test('gate apparatus is captured from the pinned uncoloured host runtime', async t => {
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
  await writeBaseSdkProvenance({
    archive,
    destination: baseSidecar,
    platform: 'linux-x64',
    toolchain: REVIEWED_GATE_HOST_TOOLCHAIN,
  });
  const githubEnv = path.join(root, 'github.env');
  const output = path.join(root, 'out');
  const captured = spawnSync(process.execPath, [
    path.resolve('ci/release/prepare_gate_apparatus.mjs'),
    '--sdk', sdk,
    '--platform', 'linux-x64',
    '--toolchain-pin', path.resolve('ci/cjpm_pin.env'),
    '--base-sdk-sidecar', baseSidecar,
    '--outdir', output,
  ], {encoding: 'utf8', env: {...process.env, GITHUB_ENV: githubEnv}});
  assert.equal(captured.status, 0, captured.stderr);
  assert.match(captured.stdout, new RegExp(`toolchain=${REVIEWED_GATE_HOST_TOOLCHAIN}`));
  assert.match(captured.stdout, /g_cjLoadBadMask=0/);

  const sidecar = JSON.parse(await fs.readFile(path.join(output, GATE_APPARATUS_PROVENANCE), 'utf8'));
  assert.equal(sidecar.gate_host_toolchain, REVIEWED_GATE_HOST_TOOLCHAIN);
  assert.match(sidecar.host_runtime.sha256, /^[0-9a-f]{64}$/);
  assert.equal(sidecar.host_runtime.g_cjLoadBadMask_count, 0);
  const environment = await fs.readFile(githubEnv, 'utf8');
  assert.match(environment, /^GATE_HOST_RUNTIME=.+gate-host-runtime\.so$/m);
  assert.match(environment, /^GATE_APPARATUS_PROVENANCE=.+GATE-APPARATUS\.json$/m);
});
