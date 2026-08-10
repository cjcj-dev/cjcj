import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';

const root = path.resolve(import.meta.dirname, '..', '..', '..');
const readWorkflow = name => fs.readFile(path.join(root, '.github/workflows', name), 'utf8');

// ops/design/DRYRUN_EXECUTION_POLICY.md §3. The order is the policy's, not a
// preference: each phase is placed by observed failure-prefix cost, cheapest
// information first, so a stop at phase N has not yet paid for phases N+1…5.
const PHASES = ['linux-x64', 'linux-aarch64', 'windows-x64', 'darwin-arm64', 'darwin-x64'];

const uncommented = text => text.split('\n').map(line => line.replace(/(^|\s)#.*$/, '$1')).join('\n');

function jobs(text) {
  const body = uncommented(text).split('\njobs:\n')[1];
  assert.ok(body !== undefined, 'workflow declares no jobs');
  const parsed = new Map();
  let current;
  for (const line of body.split('\n')) {
    const header = line.match(/^ {2}([A-Za-z0-9_-]+):\s*$/);
    if (header) parsed.set(current = header[1], []);
    else if (current) parsed.get(current).push(line);
  }
  return new Map([...parsed].map(([name, lines]) => [name, lines.join('\n')]));
}

const scalar = (text, key) => text?.match(new RegExp(String.raw`^\s*${key}:\s*(.+?)\s*$`, 'm'))?.[1];

function needsOf(job) {
  const raw = scalar(job, 'needs');
  if (raw === undefined) return [];
  return raw.startsWith('[') ? raw.slice(1, -1).split(',').map(entry => entry.trim()).filter(Boolean) : [raw];
}

// Every `if:` on a job, including the folded `>-` form release.yml uses for publish.
function jobCondition(job) {
  const inline = job.match(/^\s*if:\s*(?!>)(.+?)\s*$/m);
  if (inline) return inline[1];
  const folded = job.match(/^\s*if:\s*>[-+]?\s*\n([\s\S]*?)(?=\n\s*[a-z_-]+:\s|\n?$)/m);
  return folded ? folded[1].replace(/\s+/g, ' ').trim() : undefined;
}

// A job is skipped when a job it needs fails or is skipped -- unless its own
// condition opts out of that. These are the only forms that opt out.
const OVERRIDES = /\b(always|cancelled|failure)\s*\(/;

// Which phase a job belongs to, by the platform named in its `with:` block or name.
function phaseOf(job) {
  for (const [index, platform] of PHASES.entries()) {
    if (new RegExp(String.raw`(^|[^\w-])${platform}([^\w-]|$)`).test(job)) return index + 1;
  }
  return 0;
}

async function artifactUploads(name) {
  const text = uncommented(await readWorkflow(name));
  const found = [];
  const lines = text.split('\n');
  for (const [index, line] of lines.entries()) {
    if (!/uses:\s*actions\/upload-artifact@/.test(line)) continue;
    for (const next of lines.slice(index + 1, index + 8)) {
      const artifact = next.match(/^\s*name:\s*(.+?)\s*$/);
      if (artifact) { found.push([artifact[1], name]); break; }
      if (/^\s*- /.test(next)) break;
    }
  }
  return found;
}

test('policy contract 1: the five package phases run in the policy order, one after another', {todo: 'release.yml still runs the five packages as one fail-fast:false matrix; turning this on is the acceptance criterion for the phase chain'}, async () => {
  const release = jobs(await readWorkflow('release.yml'));
  const packages = [...release].filter(([, job]) => /uses:\s*\.\/\.github\/workflows\/build-release-package\.yml/.test(job));
  assert.equal(packages.length, PHASES.length,
    `expected one package job per phase, found ${packages.length}: ${packages.map(([n]) => n)}`);
  const byPhase = new Map(packages.map(([name, job]) => [phaseOf(job), name]));
  for (const [index, platform] of PHASES.entries()) {
    assert.ok(byPhase.has(index + 1), `no package job for phase ${index + 1} (${platform})`);
  }
  // Phase N reaches queued only after phase N-1 reported GO, which is what a
  // needs: edge means and a matrix cannot express.
  for (let phase = 2; phase <= PHASES.length; phase += 1) {
    const job = release.get(byPhase.get(phase));
    assert.ok(needsOf(job).includes(byPhase.get(phase - 1)),
      `phase ${phase} (${byPhase.get(phase)}) does not need phase ${phase - 1} (${byPhase.get(phase - 1)})`);
  }
});

test('policy contract 2: source producers are gated by the same phases, not all at once', {todo: 'srcbuild.yml has no target-selection input, so one call builds all four targets at once'}, async () => {
  const release = jobs(await readWorkflow('release.yml'));
  const sources = [...release].filter(([, job]) => /uses:\s*\.\/\.github\/workflows\/srcbuild\.yml/.test(job));
  assert.ok(sources.length > 1,
    'a single srcbuild call builds every target at once, so four expensive source jobs start before phase 1 reports');
  const byPhase = new Map(sources.map(([name, job]) => [phaseOf(job), name]));
  for (let phase = 2; phase <= PHASES.length; phase += 1) {
    if (!byPhase.has(phase)) continue;
    const job = release.get(byPhase.get(phase));
    assert.ok(needsOf(job).length > 0, `source job for phase ${phase} has no gate`);
  }
});

test('policy contract 3: Windows work waits for the Windows phase', {todo: 'windows-runtime and windows-fixed-llvm-tuple start with no gate'}, async () => {
  const release = jobs(await readWorkflow('release.yml'));
  const windowsJobs = [...release].filter(([name, job]) =>
    /windows/i.test(name) && !/uses:\s*\.\/\.github\/workflows\/srcbuild\.yml/.test(job));
  assert.ok(windowsJobs.length > 0, 'no Windows jobs found');
  for (const [name, job] of windowsJobs) {
    assert.ok(needsOf(job).length > 0,
      `${name} starts with no gate, so Windows runtime/tuple work begins before the Windows phase`);
  }
});

test('policy contract 4: a STOP leaves later phases skipped, with no condition that overrides it', {todo: 'release.yml:79 carries if: always() on the package matrix, which is the hole itself'}, async () => {
  // Actions skips a job whose needs did not succeed. That is the stop-loss, and
  // always()/cancelled()/failure() are the three ways to lose it -- release.yml
  // uses always() on the package matrix today, which is exactly the hole.
  const release = jobs(await readWorkflow('release.yml'));
  const offenders = [];
  for (const [name, job] of release) {
    if (name === 'publish') continue; // publish is allowed to report on a stopped run
    const condition = jobCondition(job);
    if (condition && OVERRIDES.test(condition)) offenders.push(`${name}: if: ${condition.slice(0, 60)}`);
  }
  assert.deepEqual(offenders, [],
    `these jobs run even when what they need did not succeed:\n  ${offenders.join('\n  ')}`);
});

test('policy contract 5: each artifact name has exactly one producer in the run', async () => {
  const produced = [];
  for (const workflow of ['release.yml', 'srcbuild.yml', 'build-release-package.yml',
    'platform-tuples.yml', 'build-cjpm.yml', 'build-windows-runtime.yml']) {
    produced.push(...await artifactUploads(workflow));
  }
  const counts = new Map();
  for (const [artifact, source] of produced) {
    counts.set(artifact, [...(counts.get(artifact) || []), source]);
  }
  const duplicated = [...counts].filter(([, sources]) => sources.length > 1);
  assert.deepEqual(duplicated, [],
    `upload-artifact rejects a name already uploaded in the same run: ${JSON.stringify(duplicated)}`);
});
