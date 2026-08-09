#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';

import {RELEASE_MANIFEST} from '../build/lib/release-manifest.mjs';

const PLATFORMS = [
  'linux-x64',
  'linux-aarch64',
  'darwin-x64',
  'darwin-arm64',
  'windows-x64',
];

const REQUIRED_MANIFEST_ROWS = 7;
const LEDGER = 'EVIDENCE_SHA256SUMS';
const INDEX = 'ARCHIVE_INDEX.json';

function usage() {
  return [
    'Usage:',
    '  node scripts/archive_release_evidence.mjs collect --source DIR --destination DIR --version VERSION',
    '  node scripts/archive_release_evidence.mjs verify --archive DIR [--version VERSION]',
    '',
    'collect source layout:',
    '  run.json       GitHub REST workflow-run response',
    '  jobs.json      GitHub REST workflow-jobs response (or --paginate --slurp pages)',
    '  run.log        unmodified combined workflow log',
    '  artifacts/**   downloaded pkg-* artifacts containing five manifests and checksums',
  ].join('\n');
}

function parseArgs(argv) {
  const mode = argv.shift();
  if (!['collect', 'verify'].includes(mode)) throw new Error(usage());

  const values = {};
  while (argv.length > 0) {
    const key = argv.shift();
    if (!key?.startsWith('--') || argv.length === 0) throw new Error(usage());
    if (Object.hasOwn(values, key)) throw new Error(`duplicate argument: ${key}`);
    values[key] = argv.shift();
  }

  const allowed = mode === 'collect'
    ? new Set(['--source', '--destination', '--version'])
    : new Set(['--archive', '--version']);
  for (const key of Object.keys(values)) {
    if (!allowed.has(key)) throw new Error(`unknown argument for ${mode}: ${key}`);
  }

  const required = mode === 'collect'
    ? ['--source', '--destination', '--version']
    : ['--archive'];
  for (const key of required) {
    if (!values[key]) throw new Error(`${key} is required\n${usage()}`);
  }
  return {mode, values};
}

function assertPersistent(location, label) {
  const resolved = path.resolve(location);
  if (resolved === '/tmp' || resolved.startsWith('/tmp/')) {
    throw new Error(`${label} must be persistent and must not be under /tmp: ${resolved}`);
  }
  return resolved;
}

async function readJson(file, label) {
  let text;
  try {
    text = await fs.readFile(file, 'utf8');
  } catch (error) {
    throw new Error(`missing ${label}: ${file} (${error.code || error.message})`);
  }
  try {
    return JSON.parse(text);
  } catch (error) {
    throw new Error(`invalid ${label}: ${file} (${error.message})`);
  }
}

function requireString(value, label) {
  if (typeof value !== 'string' || value.length === 0) throw new Error(`${label} must be a non-empty string`);
  return value;
}

function validateRun(run) {
  if (!Number.isInteger(Number(run.id)) || Number(run.id) <= 0) throw new Error('run.id must be a positive integer');
  if (!Number.isInteger(Number(run.run_attempt)) || Number(run.run_attempt) <= 0) {
    throw new Error('run.run_attempt must be a positive integer');
  }
  const url = requireString(run.html_url, 'run.html_url');
  if (!/^https:\/\/github\.com\/[^/]+\/[^/]+\/actions\/runs\/\d+$/.test(url)) {
    throw new Error(`run.html_url is not a GitHub Actions run URL: ${url}`);
  }
  if (!/^[0-9a-f]{40}$/.test(requireString(run.head_sha, 'run.head_sha'))) {
    throw new Error('run.head_sha must be a full 40-character commit');
  }
  if (run.status !== 'completed' || run.conclusion !== 'success') {
    throw new Error(`dry-run is not successful: status=${run.status} conclusion=${run.conclusion}`);
  }
}

function normalizeJobs(document) {
  const pages = Array.isArray(document) ? document : [document];
  const jobs = [];
  for (const page of pages) {
    if (!page || !Array.isArray(page.jobs)) throw new Error('jobs.json must contain a jobs array');
    jobs.push(...page.jobs);
  }
  const total = pages[0]?.total_count;
  if (Number.isInteger(total) && total !== jobs.length) {
    throw new Error(`jobs.json is incomplete: total_count=${total} archived=${jobs.length}`);
  }
  return jobs;
}

function validateJobs(jobs) {
  if (jobs.length === 0) throw new Error('jobs.json contains no jobs');
  const ids = new Set();
  const urls = new Set();
  for (const job of jobs) {
    if (!Number.isInteger(Number(job.id)) || Number(job.id) <= 0) throw new Error('job.id must be a positive integer');
    if (ids.has(String(job.id))) throw new Error(`duplicate job id: ${job.id}`);
    ids.add(String(job.id));
    requireString(job.name, `job ${job.id} name`);
    const url = requireString(job.html_url, `job ${job.id} html_url`);
    if (!/^https:\/\/github\.com\/[^/]+\/[^/]+\/actions\/runs\/\d+\/job\/\d+$/.test(url)) {
      throw new Error(`job ${job.id} has an invalid GitHub Actions URL: ${url}`);
    }
    if (urls.has(url)) throw new Error(`duplicate job URL: ${url}`);
    urls.add(url);
    if (!['success', 'skipped'].includes(job.conclusion)) {
      throw new Error(`job did not succeed: ${job.name} conclusion=${job.conclusion}`);
    }
  }

  for (const platform of PLATFORMS) {
    const packageJobs = jobs.filter(job => job.name.includes(platform) && job.name.includes('Build release package'));
    if (packageJobs.length !== 1 || packageJobs[0].conclusion !== 'success') {
      throw new Error(`${platform} package grid is not exactly one success (found ${packageJobs.length})`);
    }
  }

  const publishJobs = jobs.filter(job => job.name === 'Publish release');
  if (publishJobs.length !== 1 || publishJobs[0].conclusion !== 'skipped') {
    throw new Error('dry-run must contain exactly one skipped Publish release job');
  }
}

async function walkFiles(root) {
  const files = [];
  async function visit(directory) {
    for (const entry of await fs.readdir(directory, {withFileTypes: true})) {
      const file = path.join(directory, entry.name);
      if (entry.isDirectory()) await visit(file);
      else if (entry.isFile()) files.push(file);
    }
  }
  try {
    await visit(root);
  } catch (error) {
    if (error.code === 'ENOENT') throw new Error(`missing artifact directory: ${root}`);
    throw error;
  }
  return files.sort();
}

function manifestName(version, platform) {
  return `cjcj-${version}-${platform}.${RELEASE_MANIFEST}`;
}

function checksumName(version, platform) {
  const archive = platform === 'windows-x64' ? 'zip' : 'tar.gz';
  return `cjcj-${version}-${platform}.${archive}.sha256`;
}

function findExactlyOne(files, basename, label) {
  const matches = files.filter(file => path.basename(file) === basename);
  if (matches.length !== 1) throw new Error(`${label}: expected exactly one ${basename}, found ${matches.length}`);
  return matches[0];
}

async function validateManifest(file, platform) {
  const text = await fs.readFile(file, 'utf8');
  const lines = text.split(/\r?\n/).filter(line => line.length > 0);
  if (lines.length !== REQUIRED_MANIFEST_ROWS) {
    throw new Error(`${platform} manifest must contain ${REQUIRED_MANIFEST_ROWS} JSONL rows, found ${lines.length}`);
  }
  const components = new Set();
  for (const [index, line] of lines.entries()) {
    let row;
    try { row = JSON.parse(line); } catch (error) {
      throw new Error(`${platform} manifest row ${index + 1} is invalid JSON: ${error.message}`);
    }
    if (row.schema !== 1) throw new Error(`${platform} manifest row ${index + 1} schema is not 1`);
    if (row.platform !== platform) throw new Error(`${platform} manifest row ${index + 1} platform=${row.platform}`);
    const component = requireString(row.component, `${platform} row ${index + 1} component`);
    if (components.has(component)) throw new Error(`${platform} manifest repeats component ${component}`);
    components.add(component);
    requireString(row.source?.repository, `${platform}.${component}.source.repository`);
    requireString(row.source?.commit, `${platform}.${component}.source.commit`);
    requireString(row.artifact?.path, `${platform}.${component}.artifact.path`);
    requireString(row.artifact?.sha256, `${platform}.${component}.artifact.sha256`);
    requireString(row.embedded_stamp, `${platform}.${component}.embedded_stamp`);
  }
}

async function validateChecksum(file, version, platform) {
  const archiveName = checksumName(version, platform).replace(/\.sha256$/, '');
  const text = await fs.readFile(file, 'utf8');
  const match = text.match(/^([0-9a-f]{64})  ([^\r\n]+)\r?\n?$/);
  if (!match || match[2] !== archiveName) {
    throw new Error(`${platform} checksum must be "<64 lowercase hex>  ${archiveName}"`);
  }
}

async function sha256(file) {
  const hash = crypto.createHash('sha256');
  hash.update(await fs.readFile(file));
  return hash.digest('hex');
}

function relative(root, file) {
  return path.relative(root, file).split(path.sep).join('/');
}

function urlTable(run, jobs) {
  const clean = value => String(value).replaceAll('\t', ' ').replaceAll('\r', ' ').replaceAll('\n', ' ');
  const rows = [
    ['kind', 'id', 'name', 'conclusion', 'url'],
    ['run', run.id, 'Release dry-run', run.conclusion, run.html_url],
    ...jobs.map(job => ['job', job.id, clean(job.name), job.conclusion, job.html_url]),
  ];
  return `${rows.map(row => row.join('\t')).join('\n')}\n`;
}

async function writeLedger(root) {
  const files = (await walkFiles(root)).filter(file => path.basename(file) !== LEDGER);
  const rows = [];
  for (const file of files) rows.push(`${await sha256(file)}  ${relative(root, file)}`);
  await fs.writeFile(path.join(root, LEDGER), `${rows.join('\n')}\n`);
}

async function collect({source, destination, version}) {
  const sourceRoot = assertPersistent(source, 'source');
  const archive = assertPersistent(destination, 'destination');
  if (!/^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/.test(version)) {
    throw new Error(`version is not a release version: ${version}`);
  }
  try {
    await fs.lstat(archive);
    throw new Error(`destination already exists: ${archive}`);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }

  const run = await readJson(path.join(sourceRoot, 'run.json'), 'workflow run metadata');
  const jobsDocument = await readJson(path.join(sourceRoot, 'jobs.json'), 'workflow jobs metadata');
  const jobs = normalizeJobs(jobsDocument);
  validateRun(run);
  validateJobs(jobs);

  const rawLog = path.join(sourceRoot, 'run.log');
  let logStat;
  try { logStat = await fs.stat(rawLog); } catch (error) {
    throw new Error(`missing raw workflow log: ${rawLog} (${error.code || error.message})`);
  }
  if (!logStat.isFile() || logStat.size === 0) throw new Error(`raw workflow log is empty: ${rawLog}`);

  const artifactFiles = await walkFiles(path.join(sourceRoot, 'artifacts'));
  const inputs = [];
  for (const platform of PLATFORMS) {
    const manifest = findExactlyOne(artifactFiles, manifestName(version, platform), `${platform} manifest`);
    const checksum = findExactlyOne(artifactFiles, checksumName(version, platform), `${platform} checksum`);
    await validateManifest(manifest, platform);
    await validateChecksum(checksum, version, platform);
    inputs.push({platform, manifest, checksum});
  }

  await fs.mkdir(path.dirname(archive), {recursive: true});
  const staging = await fs.mkdtemp(`${archive}.partial-`);
  try {
    await fs.mkdir(path.join(staging, 'logs'));
    await fs.mkdir(path.join(staging, 'manifests'));
    await fs.mkdir(path.join(staging, 'checksums'));
    await fs.copyFile(path.join(sourceRoot, 'run.json'), path.join(staging, 'run.json'));
    await fs.copyFile(path.join(sourceRoot, 'jobs.json'), path.join(staging, 'jobs.json'));
    await fs.copyFile(rawLog, path.join(staging, 'logs', 'run.log'));
    await fs.writeFile(path.join(staging, 'urls.tsv'), urlTable(run, jobs));

    for (const input of inputs) {
      await fs.copyFile(input.manifest, path.join(staging, 'manifests', path.basename(input.manifest)));
      await fs.copyFile(input.checksum, path.join(staging, 'checksums', path.basename(input.checksum)));
    }

    const index = {
      schema: 1,
      release_version: version,
      archived_at: new Date().toISOString(),
      run: {
        id: Number(run.id),
        attempt: Number(run.run_attempt),
        url: run.html_url,
        head_sha: run.head_sha,
        conclusion: run.conclusion,
      },
      jobs: jobs.length,
      raw_log: 'logs/run.log',
      platforms: inputs.map(input => ({
        name: input.platform,
        manifest: `manifests/${path.basename(input.manifest)}`,
        checksum: `checksums/${path.basename(input.checksum)}`,
      })),
    };
    await fs.writeFile(path.join(staging, INDEX), `${JSON.stringify(index, null, 2)}\n`);
    await writeLedger(staging);
    await fs.rename(staging, archive);
  } catch (error) {
    await fs.rm(staging, {recursive: true, force: true});
    throw error;
  }

  const result = await verify({archive, version});
  console.log(`ARCHIVE_EVIDENCE_OK mode=collect version=${version} run=${run.id} jobs=${jobs.length} manifests=${PLATFORMS.length} checksums=${PLATFORMS.length} files=${result.files}`);
  console.log(`ARCHIVE=${archive}`);
}

async function validateLedger(root, expected) {
  const ledgerFile = path.join(root, LEDGER);
  let text;
  try { text = await fs.readFile(ledgerFile, 'utf8'); } catch (error) {
    throw new Error(`missing integrity ledger: ${ledgerFile} (${error.code || error.message})`);
  }
  const rows = text.split(/\r?\n/).filter(Boolean);
  const entries = new Map();
  for (const row of rows) {
    const match = row.match(/^([0-9a-f]{64})  (.+)$/);
    if (!match) throw new Error(`invalid ${LEDGER} row: ${row}`);
    if (entries.has(match[2])) throw new Error(`duplicate ${LEDGER} path: ${match[2]}`);
    entries.set(match[2], match[1]);
  }
  const actualFiles = (await walkFiles(root))
    .map(file => relative(root, file))
    .filter(file => file !== LEDGER)
    .sort();
  const expectedFiles = [...expected].sort();
  if (JSON.stringify(actualFiles) !== JSON.stringify(expectedFiles)) {
    throw new Error(`archive file set differs: expected=${expectedFiles.join(',')} actual=${actualFiles.join(',')}`);
  }
  if (JSON.stringify([...entries.keys()].sort()) !== JSON.stringify(expectedFiles)) {
    throw new Error(`${LEDGER} file set differs from required evidence`);
  }
  for (const file of expectedFiles) {
    const digest = await sha256(path.join(root, file));
    if (entries.get(file) !== digest) throw new Error(`integrity mismatch: ${file}`);
  }
}

async function verify({archive, version = ''}) {
  const root = assertPersistent(archive, 'archive');
  const index = await readJson(path.join(root, INDEX), 'archive index');
  if (index.schema !== 1) throw new Error(`unsupported archive index schema: ${index.schema}`);
  const releaseVersion = version || requireString(index.release_version, 'index.release_version');
  if (version && index.release_version !== version) {
    throw new Error(`archive version mismatch: index=${index.release_version} expected=${version}`);
  }

  const run = await readJson(path.join(root, 'run.json'), 'workflow run metadata');
  const jobsDocument = await readJson(path.join(root, 'jobs.json'), 'workflow jobs metadata');
  const jobs = normalizeJobs(jobsDocument);
  validateRun(run);
  validateJobs(jobs);
  if (index.run?.id !== Number(run.id) || index.run?.attempt !== Number(run.run_attempt) ||
      index.run?.url !== run.html_url || index.run?.head_sha !== run.head_sha || index.run?.conclusion !== run.conclusion) {
    throw new Error('archive index run identity does not match run.json');
  }
  if (index.jobs !== jobs.length) throw new Error(`archive index job count=${index.jobs}, jobs.json=${jobs.length}`);

  const logFile = path.join(root, 'logs', 'run.log');
  let logStat;
  try { logStat = await fs.stat(logFile); } catch (error) {
    throw new Error(`missing raw workflow log: logs/run.log (${error.code || error.message})`);
  }
  if (!logStat.isFile() || logStat.size === 0) throw new Error('raw workflow log is empty: logs/run.log');
  const expectedUrls = urlTable(run, jobs);
  const actualUrls = await fs.readFile(path.join(root, 'urls.tsv'), 'utf8');
  if (actualUrls !== expectedUrls) throw new Error('urls.tsv does not match run/job metadata');

  const expectedFiles = new Set(['run.json', 'jobs.json', 'urls.tsv', 'logs/run.log', INDEX]);
  if (!Array.isArray(index.platforms) || index.platforms.length !== PLATFORMS.length) {
    throw new Error(`archive index must list ${PLATFORMS.length} platforms`);
  }
  for (const platform of PLATFORMS) {
    const manifest = `manifests/${manifestName(releaseVersion, platform)}`;
    const checksum = `checksums/${checksumName(releaseVersion, platform)}`;
    const entry = index.platforms.find(value => value?.name === platform);
    if (!entry || entry.manifest !== manifest || entry.checksum !== checksum) {
      throw new Error(`archive index is missing canonical ${platform} paths`);
    }
    await validateManifest(path.join(root, manifest), platform);
    await validateChecksum(path.join(root, checksum), releaseVersion, platform);
    expectedFiles.add(manifest);
    expectedFiles.add(checksum);
  }
  await validateLedger(root, expectedFiles);

  const result = {files: expectedFiles.size + 1};
  if (process.argv[2] === 'verify') {
    console.log(`ARCHIVE_EVIDENCE_OK mode=verify version=${releaseVersion} run=${run.id} jobs=${jobs.length} manifests=${PLATFORMS.length} checksums=${PLATFORMS.length} files=${result.files}`);
    console.log(`ARCHIVE=${root}`);
  }
  return result;
}

async function main() {
  const {mode, values} = parseArgs(process.argv.slice(2));
  if (mode === 'collect') {
    await collect({
      source: values['--source'],
      destination: values['--destination'],
      version: values['--version'],
    });
  } else {
    await verify({archive: values['--archive'], version: values['--version'] || ''});
  }
}

main().catch(error => {
  console.error(`ARCHIVE_EVIDENCE_ERROR: ${error.message}`);
  process.exitCode = 1;
});
