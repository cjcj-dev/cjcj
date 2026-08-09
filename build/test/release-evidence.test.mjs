import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

const VERSION = '0.0.2';
const RUN_ID = 42420002;
const PLATFORMS = [
  'linux-x64',
  'linux-aarch64',
  'darwin-x64',
  'darwin-arm64',
  'windows-x64',
];
const COMPONENTS = ['base-sdk', 'cjcj', 'runtime', 'llvm-llc', 'llvm-opt', 'std', 'cjpm'];
const SCRIPT = path.resolve('scripts/archive_release_evidence.mjs');

function persistentTestRoot() {
  const configured = process.env.RELEASE_EVIDENCE_TEST_ROOT;
  assert.ok(configured, 'RELEASE_EVIDENCE_TEST_ROOT is required; use a persistent path outside /tmp');
  const root = path.resolve(configured);
  assert.ok(root !== '/tmp' && !root.startsWith('/tmp/'), `test evidence root must not be under /tmp: ${root}`);
  return root;
}

function run(args) {
  return spawnSync(process.execPath, [SCRIPT, ...args], {encoding: 'utf8'});
}

function manifest(platform) {
  const rows = COMPONENTS.map(component => ({
    schema: 1,
    platform,
    component,
    source: {
      repository: `https://example.invalid/${component}.git`,
      commit: '0123456789abcdef0123456789abcdef01234567',
    },
    artifact: {
      path: `${component}/fixture`,
      sha256: 'a'.repeat(64),
    },
    embedded_stamp: 'no-stamp',
  }));
  return `${rows.map(row => JSON.stringify(row)).join('\n')}\n`;
}

test('archives all five release cells and rejects a missing evidence class', async () => {
  const root = persistentTestRoot();
  await fs.mkdir(root, {recursive: true});
  const work = await fs.mkdtemp(path.join(root, 'fixture-'));
  const source = path.join(work, 'source');
  const archive = path.join(work, 'archive');
  const missingLogs = path.join(work, 'archive-missing-logs');
  await fs.mkdir(path.join(source, 'artifacts'), {recursive: true});

  const runMetadata = {
    id: RUN_ID,
    run_attempt: 1,
    status: 'completed',
    conclusion: 'success',
    html_url: `https://github.com/cjcj-dev/cjcj/actions/runs/${RUN_ID}`,
    head_sha: '0123456789abcdef0123456789abcdef01234567',
  };
  const jobs = PLATFORMS.map((platform, index) => ({
    id: RUN_ID * 10 + index,
    name: `${platform} / Build release / ${platform} / Build release package`,
    conclusion: 'success',
    html_url: `https://github.com/cjcj-dev/cjcj/actions/runs/${RUN_ID}/job/${RUN_ID * 10 + index}`,
  }));
  jobs.push({
    id: RUN_ID * 10 + PLATFORMS.length,
    name: 'Publish release',
    conclusion: 'skipped',
    html_url: `https://github.com/cjcj-dev/cjcj/actions/runs/${RUN_ID}/job/${RUN_ID * 10 + PLATFORMS.length}`,
  });
  await fs.writeFile(path.join(source, 'run.json'), `${JSON.stringify(runMetadata, null, 2)}\n`);
  await fs.writeFile(path.join(source, 'jobs.json'), `${JSON.stringify({total_count: jobs.length, jobs}, null, 2)}\n`);
  await fs.writeFile(path.join(source, 'run.log'), 'fixture raw GitHub Actions log\n');

  for (const platform of PLATFORMS) {
    const artifact = path.join(source, 'artifacts', `pkg-${platform}`);
    await fs.mkdir(artifact, {recursive: true});
    const packageName = `cjcj-${VERSION}-${platform}`;
    const archiveName = `${packageName}.${platform === 'windows-x64' ? 'zip' : 'tar.gz'}`;
    await fs.writeFile(path.join(artifact, `${packageName}.RELEASE-MANIFEST.jsonl`), manifest(platform));
    await fs.writeFile(path.join(artifact, `${archiveName}.sha256`), `${'b'.repeat(64)}  ${archiveName}\n`);
  }

  const collected = run(['collect', '--source', source, '--destination', archive, '--version', VERSION]);
  console.log('POSITIVE_CONTROL_OUTPUT_BEGIN');
  process.stdout.write(collected.stdout);
  process.stderr.write(collected.stderr);
  console.log(`POSITIVE_CONTROL_RC=${collected.status}`);
  console.log('POSITIVE_CONTROL_OUTPUT_END');
  assert.equal(collected.status, 0, collected.stderr);
  assert.match(collected.stdout, /ARCHIVE_EVIDENCE_OK mode=collect/);

  await fs.cp(archive, missingLogs, {recursive: true, errorOnExist: true});
  await fs.rm(path.join(missingLogs, 'logs'), {recursive: true});
  const rejected = run(['verify', '--archive', missingLogs, '--version', VERSION]);
  console.log('NEGATIVE_CONTROL_OUTPUT_BEGIN');
  process.stdout.write(rejected.stdout);
  process.stderr.write(rejected.stderr);
  console.log(`NEGATIVE_CONTROL_RC=${rejected.status}`);
  console.log('NEGATIVE_CONTROL_OUTPUT_END');
  assert.notEqual(rejected.status, 0);
  assert.match(rejected.stderr, /missing raw workflow log/);
  console.log(`EVIDENCE_FIXTURE_ROOT=${work}`);
});
