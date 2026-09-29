import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {
  BASE_SDK_SOURCE_REASON,
  SOURCE_PROVENANCE_NOT_APPLICABLE,
  SOURCE_PROVENANCE_RESOLVED,
} from '../lib/release-component-provenance.mjs';
import {
  GATE_APPARATUS_COMPONENT,
  KNOWN_GATE_APPARATUS_LIMITATIONS,
  REVIEWED_GATE_HOST_TOOLCHAIN,
} from '../lib/release-gate-apparatus.mjs';

const VERSION = '0.0.2';
const RUN_ID = 42420002;
const PLATFORMS = [
  'linux-x64',
  'linux-aarch64',
  'darwin-x64',
  'darwin-arm64',
  'windows-x64',
  'linux-x64-android',
  'darwin-arm64-android',
  'win32-x64-android',
];
const HOSTS = {'linux-x64-android': 'linux-x64', 'darwin-arm64-android': 'darwin-arm64', 'win32-x64-android': 'windows-x64'};
const hostFor = platform => HOSTS[platform] || platform;
const COMPONENTS = [
  'base-sdk', GATE_APPARATUS_COMPONENT, 'cjcj', 'runtime', 'llvm-llc', 'llvm-opt', 'std', 'cjpm', 'python',
];
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
  const runtimePaths = {
    'linux-x64': 'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so',
    'linux-aarch64': 'runtime/lib/linux_aarch64_cjnative/libcangjie-runtime.so',
    'darwin-x64': 'runtime/lib/darwin_x86_64_cjnative/libcangjie-runtime.dylib',
    'darwin-arm64': 'runtime/lib/darwin_aarch64_cjnative/libcangjie-runtime.dylib',
    'windows-x64': 'runtime/lib/windows_x86_64_cjnative/libcangjie-runtime.dll',
  };
  const symbolProbes = {
    'linux-x64': 'nm -D --defined-only',
    'linux-aarch64': 'nm -D --defined-only',
    'darwin-x64': 'nm -gU',
    'darwin-arm64': 'nm -gU',
    'windows-x64': 'nm -g --defined-only',
  };
  const rows = COMPONENTS.map(component => ({
    schema: 1,
    platform: hostFor(platform),
    component,
    source: [GATE_APPARATUS_COMPONENT, 'base-sdk'].includes(component) ? {
      status: SOURCE_PROVENANCE_NOT_APPLICABLE,
      repository: SOURCE_PROVENANCE_NOT_APPLICABLE,
      commit: SOURCE_PROVENANCE_NOT_APPLICABLE,
      reason: BASE_SDK_SOURCE_REASON,
      release_repository: 'https://example.invalid/nightly-build',
      version: 'fixture',
      download_url: `https://example.invalid/${platform}/sdk.archive`,
    } : {
      status: SOURCE_PROVENANCE_RESOLVED,
      repository: `https://example.invalid/${component}.git`,
      commit: component === 'python' ? '3.11.9' : '0123456789abcdef0123456789abcdef01234567',
    },
    artifact: {
      path: `${component}/fixture`,
      sha256: 'a'.repeat(64),
    },
    embedded_stamp: 'no-stamp',
    ...(component === GATE_APPARATUS_COMPONENT ? {
      acceptance_apparatus: {
        gate_host_toolchain: REVIEWED_GATE_HOST_TOOLCHAIN,
        host_runtime: {
          path: runtimePaths[hostFor(platform)],
          sha256: 'c'.repeat(64),
          g_cjLoadBadMask_count: 0,
          symbol_probe: symbolProbes[hostFor(platform)],
        },
        known_apparatus_limitations: KNOWN_GATE_APPARATUS_LIMITATIONS,
      },
    } : {}),
  }));
  return `${rows.map(row => JSON.stringify(row)).join('\n')}\n`;
}

async function fixture() {
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
  const recorded = JSON.parse(await fs.readFile(new URL('./fixtures/release-evidence/run-36311262568.jobs.json', import.meta.url)));
  const jobs = recorded.jobs.filter(job => !job.name.includes('-ohos / Build release package')).map(job => ({...job}));
  for (const job of jobs) {
    if (job.name.endsWith(' / Build release package')) {
      const platform = job.name.split(' / ')[0].replace(/^phase \d+ · /, '');
      job.name += ` / ${hostFor(platform)} / Build release package`;
    }
    if (job.name !== 'Publish release' && !job.name.endsWith(' / in-process-dylib') &&
        !job.name.endsWith(' / Publish static colour LLVM tuple')) job.conclusion = 'success';
  }
  await fs.writeFile(path.join(source, 'run.json'), `${JSON.stringify(runMetadata, null, 2)}\n`);
  await fs.writeFile(path.join(source, 'jobs.json'), `${JSON.stringify({total_count: jobs.length, jobs}, null, 2)}\n`);
  await fs.writeFile(path.join(source, 'run.log'), 'fixture raw GitHub Actions log\n');

  for (const platform of PLATFORMS) {
    const artifact = path.join(source, 'artifacts', `pkg-${platform}`);
    await fs.mkdir(artifact, {recursive: true});
    const packageName = `cjcj-${VERSION}-${platform}`;
    const archiveName = `${packageName}.${hostFor(platform) === 'windows-x64' ? 'zip' : 'tar.gz'}`;
    await fs.writeFile(path.join(artifact, `${packageName}.RELEASE-MANIFEST.jsonl`), manifest(platform));
    await fs.writeFile(path.join(artifact, `${archiveName}.sha256`), `${'b'.repeat(64)}  ${archiveName}\n`);
  }

  return {source, archive, missingLogs, work, jobs};
}

async function writeJobs(source, jobs) {
  await fs.writeFile(path.join(source, 'jobs.json'), JSON.stringify({total_count: jobs.length, jobs}));
}

function collect(source, archive) {
  return run(['collect', '--source', source, '--destination', archive, '--version', VERSION]);
}

function rejected(result, message) {
  console.log(`TARGET_REJECTION rc=${result.status} stderr=${result.stderr.trim()}`);
  assert.notEqual(result.status, 0, 'target must reject invalid evidence');
  assert.ok(result.stderr.includes(message), `expected ${message}: ${result.stderr}`);
}

// Mutate a sealed archive without making the integrity ledger the reason for rejection.
async function resealJobs(archive, jobs) {
  await writeJobs(archive, jobs);
  const urlsFile = path.join(archive, 'urls.tsv');
  const lines = (await fs.readFile(urlsFile, 'utf8')).trimEnd().split('\n');
  const conclusions = new Map(jobs.map(job => [String(job.id), job.conclusion]));
  await fs.writeFile(urlsFile, lines.map(line => {
    const fields = line.split('\t');
    if (fields[0] === 'job') fields[3] = conclusions.get(fields[1]);
    return fields.join('\t');
  }).join('\n') + '\n');
  const ledger = path.join(archive, 'EVIDENCE_SHA256SUMS');
  let text = await fs.readFile(ledger, 'utf8');
  for (const file of ['jobs.json', 'urls.tsv']) {
    const hash = crypto.createHash('sha256').update(await fs.readFile(path.join(archive, file))).digest('hex');
    text = text.split('\n').map(line => line.endsWith(`  ${file}`) ? `${hash}  ${file}` : line).join('\n');
  }
  await fs.writeFile(ledger, text);
}

test('archives and verifies all eight release cells with optional skips', async () => {
  const {source, archive, missingLogs} = await fixture();
  const collected = collect(source, archive);
  assert.equal(collected.status, 0, collected.stderr);
  const verified = run(['verify', '--archive', archive, '--version', VERSION]);
  console.log(`TARGET_EIGHT_VERIFY rc=${verified.status} ${verified.stdout.trim()}`);
  assert.equal(verified.status, 0, verified.stderr);
  assert.match(verified.stdout, /manifests=8 checksums=8/);
  const index = JSON.parse(await fs.readFile(path.join(archive, 'ARCHIVE_INDEX.json')));
  assert.deepEqual(index.platforms.map(p => p.name).sort(), [...PLATFORMS].sort());
  await fs.cp(archive, missingLogs, {recursive: true});
  await fs.rm(path.join(missingLogs, 'logs'), {recursive: true});
  rejected(run(['verify', '--archive', missingLogs]), 'missing raw workflow log');
});

for (const platform of PLATFORMS) {
  for (const conclusion of ['failure', 'skipped']) {
    test(`rejects ${platform} package ${conclusion} in collect and verify`, async () => {
      const {source, archive, jobs} = await fixture();
      const collected = collect(source, archive);
      assert.equal(collected.status, 0, collected.stderr);
      const job = jobs.find(j => j.name.startsWith(`${platform} / Build release package /`) ||
        j.name.includes(`· ${platform} / Build release package /`));
      job.conclusion = conclusion;
      await writeJobs(source, jobs);
      // collect must reject before creating an archive, not only in its final verify.
      const invalidArchive = `${archive}-invalid`;
      rejected(collect(source, invalidArchive), `${job.name} expected=success actual=${conclusion}`);
      assert.equal(await fs.stat(invalidArchive).then(() => true, () => false), false, 'collect validation precedes archive publication');
      await resealJobs(archive, jobs);
      rejected(run(['verify', '--archive', archive]), `${job.name} expected=success actual=${conclusion}`);
    });
  }
  test(`requires exactly one canonical ${platform} package job`, async () => {
    const {source, archive, jobs} = await fixture();
    const job = jobs.find(j => j.name.startsWith(`${platform} / Build release package /`) ||
      j.name.includes(`· ${platform} / Build release package /`));
    job.name += ' extra';
    await writeJobs(source, jobs);
    rejected(collect(source, archive), `${platform} package grid is not exactly one success (found 0)`);
  });
}

for (const kind of ['optional failure', 'unknown skip', 'producer skip', 'publish success', 'duplicate package']) {
  test(`rejects ${kind}`, async () => {
    const {source, archive, jobs} = await fixture();
    let expected;
    if (kind === 'duplicate package') {
      const job = jobs.find(j => j.name.includes('Build release package'));
      jobs.push({...job, id: 99999, html_url: job.html_url.replace(/job\/\d+$/, 'job/99999')});
      expected = 'package grid is not exactly one success (found 2)';
    } else {
      const job = jobs.find(j => kind === 'publish success' ? j.name === 'Publish release' :
        kind === 'producer skip' ? j.name.endsWith(' / source SDK') : j.name.endsWith(' / in-process-dylib'));
      if (kind === 'unknown skip') job.name = `unrelated / ${job.name}`;
      job.conclusion = kind === 'optional failure' ? 'failure' : kind === 'publish success' ? 'success' : 'skipped';
      expected = `job has the wrong dry-run conclusion: ${job.name}`;
    }
    await writeJobs(source, jobs);
    rejected(collect(source, archive), expected);
  });
}

test('accepts optional LLVM success as well as skipped', async () => {
  const {source, archive, jobs} = await fixture();
  for (const job of jobs) if (job.name !== 'Publish release') job.conclusion = 'success';
  await writeJobs(source, jobs);
  const result = collect(source, archive);
  assert.equal(result.status, 0, result.stderr);
});

for (const platform of ['linux-x64-android', 'darwin-arm64-android', 'win32-x64-android']) {
  test(`requires ${platform} manifest and checksum`, async () => {
    const {source, archive} = await fixture();
    const directory = path.join(source, 'artifacts', `pkg-${platform}`);
    const manifestFile = path.join(directory, `cjcj-${VERSION}-${platform}.RELEASE-MANIFEST.jsonl`);
    const saved = await fs.readFile(manifestFile);
    await fs.rm(manifestFile);
    rejected(collect(source, archive), `${platform} manifest: expected exactly one`);
    await fs.writeFile(manifestFile, saved);
    const checksum = (await fs.readdir(directory)).find(name => name.endsWith('.sha256'));
    await fs.rm(path.join(directory, checksum));
    rejected(collect(source, archive), `${platform} checksum: expected exactly one`);
  });
}

test('runbook jq accepts exactly the buildable artifact set', async () => {
  const {work} = await fixture();
  const runbook = await fs.readFile('ops/coord/RELEASE_0_0_2_RUNBOOK.md', 'utf8');
  const start = runbook.indexOf('EXPECTED_PACKAGES=$(');
  const endMarker = `' "$RELEASE_DIR/artifacts.review.json"`;
  const end = runbook.indexOf(endMarker, start) + endMarker.length;
  assert.ok(start >= 0 && end > start, 'runbook artifact audit snippet exists');
  const script = runbook.slice(start, end);
  const artifacts = PLATFORMS.map(platform => ({name: `pkg-${platform}`, digest: `sha256:${'a'.repeat(64)}`, expired: false}));
  async function audit(rows) {
    await fs.writeFile(path.join(work, 'artifacts.review.json'), JSON.stringify([{artifacts: rows}]));
    return spawnSync('bash', ['-ec', script], {encoding: 'utf8', env: {...process.env, RELEASE_DIR: work}});
  }
  const good = await audit(artifacts);
  assert.equal(good.status, 0, good.stderr);
  for (const platform of PLATFORMS) {
    assert.notEqual((await audit(artifacts.filter(a => a.name !== `pkg-${platform}`))).status, 0, platform);
  }
  assert.notEqual((await audit([...artifacts, artifacts[0]])).status, 0, 'duplicate');
  assert.notEqual((await audit(artifacts.map((a, i) => i === 0 ? {...a, expired: true} : a))).status, 0, 'expired');
  assert.notEqual((await audit(artifacts.map((a, i) => i === 0 ? {...a, digest: ''} : a))).status, 0, 'digest');
  console.log('TARGET_RUNBOOK eight accepted; eight missing, duplicate, expired, empty digest rejected');
});

for (const [host, phase] of [['linux-x64', 1], ['linux-aarch64', 2], ['darwin-arm64', 4], ['darwin-x64', 5]]) {
  for (const leaf of ['in-process-dylib', 'Publish static colour LLVM tuple']) {
    test(`only optional ${host} ${leaf} may skip`, async () => {
      const {source, archive, jobs} = await fixture();
      const suffix = host === 'linux-x64' ? ' (also cross-builds the Windows std)' : '';
      const name = `phase ${phase} · ${host} / source SDK and final std${suffix} / Build native LLVM tools / ${leaf}`;
      let job = jobs.find(j => j.name === name);
      if (!job) {
        job = {id: 99999, name, conclusion: 'skipped', html_url: `https://github.com/cjcj-dev/cjcj/actions/runs/${RUN_ID}/job/99999`};
        jobs.push(job);
      }
      await writeJobs(source, jobs);
      const result = collect(source, archive);
      assert.equal(result.status, 0, result.stderr);
      job.conclusion = 'failure';
      await writeJobs(source, jobs);
      rejected(collect(source, `${archive}-failure`), `job has the wrong dry-run conclusion: ${name}`);
    });
  }
}

for (const [host, phase] of [['linux-x64', 1], ['linux-aarch64', 2], ['darwin-arm64', 4], ['darwin-x64', 5]]) {
  test(`segmented ${host} permits only its conditional jobs to skip`, async () => {
    const {source, archive, jobs} = await fixture();
    const suffix = host === 'linux-x64' ? ' (also cross-builds the Windows std)' : '';
    const parent = `phase ${phase} · ${host} / source SDK and final std${suffix} / ${host} / source SDK`;
    const optional = ['Build native LLVM tools / in-process-dylib',
      'Build native LLVM tools / Publish static colour LLVM tuple'];
    if (host !== 'linux-x64') optional.push(...['android', 'mingw', 'windows'].map(p => `linux-x64 / source-${p}`));
    let id = 99000;
    const append = (name, conclusion) => {
      id++;
      const job = {id, name: `${parent} / ${name}`, conclusion,
        html_url: `https://github.com/cjcj-dev/cjcj/actions/runs/${RUN_ID}/job/${id}`};
      jobs.push(job);
      return job;
    };
    const conditional = optional.map(name => append(name, 'skipped'));
    await writeJobs(source, jobs);
    assert.equal(collect(source, archive).status, 0);
    for (const job of conditional) {
      job.conclusion = 'failure';
      await writeJobs(source, jobs);
      rejected(collect(source, `${archive}-failure-${job.id}`), `job has the wrong dry-run conclusion: ${job.name}`);
      job.conclusion = 'skipped';
    }
    const required = ['stage0', 'stage1-initial-std', 'stage1-std', 'stage1-compiler', 'stage3'];
    if (host === 'linux-x64') required.push('android', 'mingw', 'windows');
    for (const phaseName of required) {
      const job = append(`${host} / source-${phaseName}`, 'skipped');
      await writeJobs(source, jobs);
      rejected(collect(source, `${archive}-required-${job.id}`), `job has the wrong dry-run conclusion: ${job.name}`);
      jobs.pop();
    }
    const alien = append('alien / source-mingw', 'skipped');
    await writeJobs(source, jobs);
    rejected(collect(source, `${archive}-alien`), `job has the wrong dry-run conclusion: ${alien.name}`);
  });
}
