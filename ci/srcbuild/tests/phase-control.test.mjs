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

test('policy contract 1: the five package phases run in the policy order, one after another', async () => {
  const release = jobs(await readWorkflow('release.yml'));
  const packages = [...release].filter(([, job]) => /uses:\s*\.\/\.github\/workflows\/build-release-package\.yml/.test(job));
  assert.equal(packages.length, PHASES.length,
    `expected one package job per phase, found ${packages.length}: ${packages.map(([n]) => n)}`);
  const byPhase = new Map(packages.map(([name, job]) => [phaseOf(job), name]));
  for (const [index, platform] of PHASES.entries()) {
    assert.ok(byPhase.has(index + 1), `no package job for phase ${index + 1} (${platform})`);
  }
  // Phase N reaches queued only after phase N-1 reported GO. Reachability, not a
  // direct edge: a phase legitimately hangs off its own source job, which hangs
  // off the previous package, and needs-semantics-probe.yml measured that
  // skipping travels down a chain like that (d-needs-b came back skipped when b
  // was skipped because a failed). Demanding the direct edge would reject a
  // correct graph.
  const reaches = (from, to, seen = new Set()) => needsOf(release.get(from) || '').some(need =>
    need === to || (!seen.has(need) && (seen.add(need), reaches(need, to, seen))));
  for (let phase = 2; phase <= PHASES.length; phase += 1) {
    assert.ok(reaches(byPhase.get(phase), byPhase.get(phase - 1)),
      `phase ${phase} (${byPhase.get(phase)}) cannot reach phase ${phase - 1} (${byPhase.get(phase - 1)}) through needs:`);
  }
});

test('policy contract 2: source producers are gated by the same phases, not all at once', async () => {
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

test('policy contract 3: Windows work waits for the Windows phase', async () => {
  const release = jobs(await readWorkflow('release.yml'));
  const windowsJobs = [...release].filter(([name, job]) =>
    /windows/i.test(name) && !/uses:\s*\.\/\.github\/workflows\/srcbuild\.yml/.test(job));
  assert.ok(windowsJobs.length > 0, 'no Windows jobs found');
  for (const [name, job] of windowsJobs) {
    assert.ok(needsOf(job).length > 0,
      `${name} starts with no gate, so Windows runtime/tuple work begins before the Windows phase`);
  }
});

test('policy contract 4: a STOP leaves later phases skipped, with no condition that overrides it', async () => {
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

  // Counting upload steps in files misses the way phase control reintroduces the
  // collision: one workflow called several times in the same run uploads its
  // names once per call. Each repeated call has to differ in what it is asked to
  // produce, or two of them race for the same artifact name.
  const release = jobs(await readWorkflow('release.yml'));
  const callers = new Map();
  for (const [name, job] of release) {
    const used = job.match(/uses:\s*(\.\/\.github\/workflows\/\S+)/);
    if (used) callers.set(name, used[1]);
  }
  const byWorkflow = new Map();
  for (const [name, workflow] of callers) {
    byWorkflow.set(workflow, [...(byWorkflow.get(workflow) || []), name]);
  }
  for (const [workflow, jobNames] of byWorkflow) {
    if (jobNames.length < 2) continue;
    const selectors = jobNames.map(name => {
      const withBlock = release.get(name).split(/\n\s*with:\s*\n/)[1] || '';
      return withBlock.split('\n').filter(line => /^\s{6}\S/.test(line)).sort().join('|');
    });
    assert.equal(new Set(selectors).size, jobNames.length,
      `${workflow} is called ${jobNames.length} times (${jobNames}) with inputs that do not distinguish them`);
  }
});

// The other half of EXECUTION_BLOCKED_BY_PHASE_CONTROL_AND_FAILURE_CAPTURE: a
// phase that dies has to leave something to read, or the stop-loss buys a stop
// with no diagnosis.
test('policy failure capture: a package cell that dies leaves evidence behind', async () => {
  const text = uncommented(await readWorkflow('build-release-package.yml'));
  assert.match(text, /if:\s*failure\(\)\s*\n\s*uses:\s*actions\/upload-artifact@/,
    'no failure-only upload: the pkg-* upload runs only after everything before it succeeded');
  // srcbuild names its per-cell diagnosis this way; two cells uploading the same
  // name would collide under contract 5.
  assert.match(text, /name:\s*pkg-diagnosis-\$\{\{\s*inputs\.platform\s*\}\}/,
    'failure diagnostics must be named per platform');
});

test('policy failure capture: smoke workspaces survive the failure that needs them', async () => {
  const text = uncommented(await readWorkflow('build-release-package.yml'));
  // `trap '... rm -rf ...' EXIT` fires on the failure path too, so the evidence
  // is gone before any upload step can see it.
  const unconditional = [...text.matchAll(/trap\s+'([^']*)'\s+EXIT/g)]
    .map(match => match[1])
    .filter(handler => /\brm\s+-rf/.test(handler));
  assert.deepEqual(unconditional, [],
    `these EXIT traps delete the smoke workspace whatever happened: ${JSON.stringify(unconditional)}`);
});
