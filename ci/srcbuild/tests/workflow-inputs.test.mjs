import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';

// A caller passing an input the callee never declared is rejected by Actions at
// dispatch, and a callee reading an input it never declared silently gets the
// empty string -- which is how `targets` came to exist in release.yml, be read in
// srcbuild.yml, and be declared nowhere: every phase asked for its own target and
// every phase would have built all four. actionlint catches both, and it already
// runs in ci.yml, but nothing here treated it as a judge. These two assertions
// are the same rule, close enough to the contracts to fail with them.

const root = path.resolve(import.meta.dirname, '..', '..', '..');
const dir = path.join(root, '.github/workflows');
const uncommented = text => text.split('\n').map(line => line.replace(/(^|\s)#.*$/, '$1')).join('\n');

function section(text, header, indent) {
  const lines = text.split('\n');
  const start = lines.findIndex(line => line === `${' '.repeat(indent)}${header}:`);
  if (start < 0) return '';
  const body = [];
  for (const line of lines.slice(start + 1)) {
    if (line.trim() && line.match(/^ */)[0].length <= indent) break;
    body.push(line);
  }
  return body.join('\n');
}

// Inputs a workflow declares, per trigger that can carry them.
function declaredInputs(text) {
  const on = section(text, 'on', 0);
  const declared = {call: new Set(), any: new Set()};
  for (const trigger of ['workflow_call', 'workflow_dispatch']) {
    const inputs = section(section(on, trigger, 2), 'inputs', 4);
    for (const [, name] of inputs.matchAll(/^ {6}([A-Za-z0-9_-]+):\s*$/gm)) {
      if (trigger === 'workflow_call') declared.call.add(name);
      declared.any.add(name);
    }
  }
  return declared;
}

function jobs(text) {
  const body = text.split('\njobs:\n')[1] || '';
  const parsed = new Map();
  let current;
  for (const line of body.split('\n')) {
    const header = line.match(/^ {2}([A-Za-z0-9_-]+):\s*$/);
    if (header) parsed.set(current = header[1], []);
    else if (current) parsed.get(current).push(line);
  }
  return new Map([...parsed].map(([name, lines]) => [name, lines.join('\n')]));
}

async function workflows() {
  const loaded = new Map();
  for (const name of (await fs.readdir(dir)).filter(entry => entry.endsWith('.yml'))) {
    loaded.set(name, uncommented(await fs.readFile(path.join(dir, name), 'utf8')));
  }
  return loaded;
}

test('every input a caller passes is declared by the workflow it calls', async () => {
  const loaded = await workflows();
  const offenders = [];
  for (const [caller, text] of loaded) {
    for (const [jobName, job] of jobs(text)) {
      const used = job.match(/uses:\s*\.\/\.github\/workflows\/(\S+\.yml)/);
      if (!used) continue;
      const callee = loaded.get(used[1]);
      assert.ok(callee, `${caller}/${jobName} calls ${used[1]}, which does not exist`);
      const declared = declaredInputs(callee).call;
      const withBlock = section(job, 'with', 4);
      for (const [, key] of withBlock.matchAll(/^ {6}([A-Za-z0-9_-]+):/gm)) {
        if (!declared.has(key)) offenders.push(`${caller}/${jobName} passes "${key}" to ${used[1]}, which declares ${[...declared].sort().join(', ')}`);
      }
    }
  }
  assert.deepEqual(offenders, [], `\n  ${offenders.join('\n  ')}`);
});

test('every input a workflow reads is one it declares', async () => {
  // The direction that fails quietly: an undeclared inputs.X reads as empty, so a
  // `|| 'default'` fallback turns a selector into "always everything".
  const loaded = await workflows();
  const offenders = [];
  for (const [name, text] of loaded) {
    const declared = declaredInputs(text).any;
    for (const [, used] of text.matchAll(/\$\{\{\s*inputs\.([A-Za-z0-9_-]+)/g)) {
      if (!declared.has(used)) offenders.push(`${name} reads inputs.${used}, declaring only ${[...declared].sort().join(', ') || '<none>'}`);
    }
  }
  assert.deepEqual([...new Set(offenders)], [], `\n  ${[...new Set(offenders)].join('\n  ')}`);
});

test('actionlint stays in the chain, and stays fatal', async () => {
  // It found this bug before any test here did, and it is the only judge in the
  // set that understands the reusable-workflow input contract natively. If it
  // ever gets dropped or softened, the chain loses its strongest member quietly.
  //
  // Run it locally before handing anything over -- CI should not be the first
  // filter:  bash <(curl -fsSL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash) && ./actionlint
  const ci = uncommented(await fs.readFile(path.join(dir, 'ci.yml'), 'utf8'));
  assert.match(ci, /download-actionlint\.bash/, 'ci.yml no longer installs actionlint');
  assert.match(ci, /^\s*\.\/actionlint\b(?!.*\|\|)/m,
    'ci.yml no longer runs actionlint, or lets it fail without failing the step');
});
