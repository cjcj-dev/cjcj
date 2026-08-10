import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import {
  DEFERRED,
  DISCOVERY_FLOOR,
  GATING,
  GATING_FLOOR,
  discoverTestFiles,
  repoRoot,
} from './test-manifest.mjs';

// The judge that makes the manifest worth having. Without it the manifest is just
// a longer version of the literal file list in ci.yml, and forgetting to add an
// entry stays as quiet as forgetting to add an argument.

const workflowDir = path.join(repoRoot, '.github/workflows');
const uncommented = text => text.split('\n').map(line => line.replace(/(^|\s)#.*$/, '$1')).join('\n');

async function workflows() {
  const loaded = new Map();
  for (const name of (await fs.readdir(workflowDir)).filter(entry => entry.endsWith('.yml'))) {
    loaded.set(name, uncommented(await fs.readFile(path.join(workflowDir, name), 'utf8')));
  }
  return loaded;
}

// The body of one `- name: <label>` step, up to the next step at that indent.
function step(text, label) {
  const lines = text.split('\n');
  const start = lines.findIndex(line => line.trim() === `- name: ${label}`);
  if (start < 0) return '';
  const indent = lines[start].match(/^ */)[0].length;
  const body = [lines[start]];
  for (const line of lines.slice(start + 1)) {
    if (line.trim().startsWith('- name:') && line.match(/^ */)[0].length <= indent) break;
    body.push(line);
  }
  return body.join('\n');
}

// Every literal test file a workflow hands to `node --test`.
function literalTestArguments(text) {
  const named = [];
  for (const [, tail] of text.matchAll(/node --test\s+([^\n]*)/g)) {
    for (const token of tail.split(/\s+/)) {
      if (token.endsWith('.test.mjs')) named.push(token);
    }
  }
  return named;
}

test('the manifest covers every test file in the repository', () => {
  const discovered = discoverTestFiles();
  // A scan that found nothing would make "every discovered file is registered"
  // vacuously true, so say so with the count rather than with a set difference.
  assert.ok(discovered.length >= DISCOVERY_FLOOR,
    `discovery found ${discovered.length} test files, floor is ${DISCOVERY_FLOOR}; `
    + 'either a test was deleted (lower DISCOVERY_FLOOR in the same commit) or discovery is broken');

  const registered = [...GATING, ...DEFERRED.map(entry => entry.file)];
  assert.equal(new Set(registered).size, registered.length,
    `a test file is registered twice: ${registered.filter((file, index) => registered.indexOf(file) !== index).join(', ')}`);

  const unregistered = discovered.filter(file => !registered.includes(file));
  assert.deepEqual(unregistered, [],
    `these test files exist but no workflow will ever run them; add each to GATING, or to DEFERRED with a reason:\n  ${unregistered.join('\n  ')}`);

  const phantom = registered.filter(file => !discovered.includes(file));
  assert.deepEqual(phantom, [],
    `the manifest names test files that are not in the repository:\n  ${phantom.join('\n  ')}`);
});

test('the gating set does not silently shrink', () => {
  assert.ok(GATING.length >= GATING_FLOOR,
    `GATING lists ${GATING.length} files, floor is ${GATING_FLOOR}; removing a test from CI must be a deliberate edit to both`);
  assert.ok(GATING.includes('ci/test-manifest.test.mjs'),
    'the manifest test must itself be gating, or none of these assertions run in CI');
});

test('every deferred entry says what it needs and what it did when run', () => {
  for (const entry of DEFERRED) {
    assert.ok(entry.needs && entry.needs.length > 20, `${entry.file}: DEFERRED entry must state what CI would have to provide`);
    assert.ok(entry.verified && entry.verified.length > 20, `${entry.file}: DEFERRED entry must record what the invocation in "needs" produced`);
  }
});

test('ci.yml runs the manifest rather than a literal file list', async () => {
  // The exact mechanism that failed: four steps naming eight files, and twenty
  // test files that no workflow referenced. Naming files here again would restore
  // it, and the coverage assertion above would not notice -- a file can be in
  // GATING and still not be handed to node if ci.yml has its own list.
  const ci = (await workflows()).get('ci.yml');
  assert.ok(ci, 'ci.yml is missing');
  assert.match(ci, /ci\/test-manifest\.mjs list/,
    'ci.yml no longer drives its test step from the manifest');
  assert.deepEqual(literalTestArguments(ci), [],
    'ci.yml names test files literally again; drive the list from ci/test-manifest.mjs instead');
  // Without it a hanging test spends the job's whole timeout-minutes and the
  // failure names no test. package-std-integrity.test.mjs hangs in about 8% of
  // batch runs on the shared box, cause unknown, and it is in this list.
  assert.match(step(ci, 'Test build and release contracts'), /--test-timeout=\d+/,
    'the test step lost its timeout; a hang would go unattributed for the whole job');
});

test('ci.yml discovers the shell scripts it lints instead of listing them', async () => {
  // The same failure as the test list, in the same file, found the same week:
  // a literal list named two scripts, and all seven others were added after
  // that list was last edited. One commit even widened the .mjs check to a find
  // and left the .sh list literal, so the two live side by side as a worked
  // example of which one rots.
  const ci = (await workflows()).get('ci.yml');
  const body = step(ci, 'Run ShellCheck');
  assert.ok(body, 'ci.yml has no Run ShellCheck step');
  assert.match(body, /git ls-files '\*\.sh'/, 'the shellcheck step no longer discovers its own script list');
  const literals = body.split(/\s+/).filter(token => /[\w./-]\.sh$/.test(token));
  assert.deepEqual(literals, [], `the shellcheck step names scripts literally again: ${literals.join(', ')}`);
  // An empty discovery would pass while checking nothing.
  assert.match(body, /-ge \d+/, 'the shellcheck step has no floor on how many scripts it found');
  // SC2086, unquoted expansion, is an info-level check. error and warning both
  // look straight past the class this gate exists to catch.
  assert.doesNotMatch(body, /--severity=(error|warning)\b/,
    'shellcheck is back above info, where SC2086 is invisible');
});

test('no workflow runs a test file the manifest does not gate', async () => {
  const offenders = [];
  for (const [name, text] of await workflows()) {
    for (const file of literalTestArguments(text)) {
      if (!GATING.includes(file)) offenders.push(`${name} runs ${file}, which is not in GATING`);
    }
  }
  assert.deepEqual(offenders, [], `\n  ${offenders.join('\n  ')}`);
});
