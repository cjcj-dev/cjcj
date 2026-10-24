import assert from 'node:assert/strict';
import {test} from 'node:test';
import fs from 'node:fs';
import {exportBranches, inventory, expandInputs} from './g1-entry-branches.mjs';

test('G1 parser keeps foreign here-doc guards out of the shell inventory', () => {
  const rows = exportBranches("cat <<'PY'\nif token not in text:\n print('if fake; then')\nPY\nif test -n \"$bad\"; then exit 2; fi\n");
  assert.equal(rows.filter(row => row.kind === 'condition').length, 1);
  assert.equal(rows.find(row => row.kind === 'condition').line, 5);
  assert.equal(rows.filter(row => row.kind === 'exit').length, 1);
});

test('G1 parser preserves expansions in an unquoted here-doc', () => {
  const rows = exportBranches('cat <<EOF\n${OPTION:-default}\nEOF\n').filter(row => row.kind === 'parameter');
  assert.equal(rows.length, 1);
  assert.equal(rows[0].variable, 'OPTION');
  assert.equal(rows[0].fallback[0].text, 'default');
});

test('G1 parser preserves the complete nested fallback expression', () => {
  const source = 'runtime_pin=${7:-${CJCJ_BOOTSTRAP_RUNTIME_PIN:-$repo/ci/runtime_pin.env}}\n';
  const rows = exportBranches(source);
  assert.equal(rows.length, 2);
  assert.equal(rows[0].position, 7);
  assert.equal(rows[0].fallback[0].type, 'expansion');
  assert.equal(rows[0].fallback[0].text, '${CJCJ_BOOTSTRAP_RUNTIME_PIN:-$repo/ci/runtime_pin.env}');
  assert.equal(rows[1].variable, 'CJCJ_BOOTSTRAP_RUNTIME_PIN');
  assert.equal(rows[1].fallback[0].text, '$repo/ci/runtime_pin.env');
});

test('G1 parser derives case arms and rejects invalid Bash', () => {
  const source = 'case "$x" in a|b) echo a;; *) exit 1;; esac\n';
  const rows = exportBranches(source);
  assert.deepEqual(rows.filter(row => row.kind === 'case').map(row => row.patterns.map(p => p.text)), [['a', 'b'], ['*']]);
  assert.throws(() => exportBranches('if true; then\n'), SyntaxError);
});

test('G1 deletion of a real optional source branch removes only its own decisions', () => {
  const source = fs.readFileSync(new URL('./fixtures/g1/test-llvm-tuple-layout.bash.txt', import.meta.url), 'utf8');
  const rows = exportBranches(source);
  const branch = rows.find(row => row.kind === 'condition');
  assert.equal(branch.condition[0].text, '[[ -n ${2:-} ]]');
  // Replace the whole syntactically valid if by its actual fallback body.
  const fallbackStart = source.indexOf('\nelse\n', branch.start) + '\nelse\n'.length;
  const fallbackEnd = source.lastIndexOf('\nfi', branch.end);
  const cut = source.slice(0, branch.start) + source.slice(fallbackStart, fallbackEnd) + source.slice(branch.end);
  const expected = rows.filter(row => row.start < branch.start || row.start >= branch.end ||
    (row.start >= fallbackStart && row.end <= fallbackEnd));
  const identity = row => [row.kind, row.source];
  assert.deepEqual(exportBranches(cut).map(identity), expected.map(identity));
  assert.ok(exportBranches(cut).some(row => row.kind === 'required'));
  assert.deepEqual(exportBranches(source), rows);
});

test('G1 inventories all seven frozen entries with explicit execution gaps', () => {
  const rows = inventory();
  assert.equal(new Set(rows.map(row => row.entry)).size, 7);
  assert.ok(rows.every(row => row.source && row.outcomes.length));
  assert.ok(rows.some(row => row.kind === 'short-circuit'));
  assert.ok(rows.some(row => row.kind === 'loop'));
  const table = expandInputs(rows, {});
  assert.equal(table.length, rows.reduce((count, row) => count + row.outcomes.length, 0));
  assert.ok(table.every(row => row.status === 'NOT_RUN' && row.reason));
});

test('G1 expansion uses caller inputs and keeps function-local parameters separate', () => {
  const entry = 'ci/example.mjs';
  const rows = exportBranches('work=${1:?work}\nrun() { local arm=${1:-green}; }\n').map(row => ({entry, ...row}));
  const table = expandInputs(rows, {[entry]: {args: ['/prepared/evidence'], env: {LC_ALL: 'C'}}});
  assert.deepEqual(table.filter(row => row.status === 'READY').map(row => row.args), [[], [''], ['/prepared/evidence']]);
  assert.ok(table.filter(row => row.kind === 'parameter').every(row => row.status === 'NOT_RUN'));
});

test('G1 nested environment input clears the enclosing positional override', () => {
  const entry = 'ci/example.mjs';
  const rows = exportBranches('pin=${2:-${PIN:-/default}}\n').map(row => ({entry, ...row}));
  const table = expandInputs(rows, {[entry]: {args: ['/work', '/explicit'], env: {PIN: '/environment'}}});
  const nested = table.filter(row => row.start > rows[0].start);
  assert.deepEqual(nested.map(row => row.args), [['/work'], ['/work'], ['/work']]);
  assert.deepEqual(nested.map(row => row.env), [{}, {PIN: ''}, {PIN: '/environment'}]);
  assert.deepEqual(nested[0].unsetEnv, ['PIN']);
});

test('G1 optional guards share actual positional input expansion', () => {
  const entry = 'ci/example.mjs';
  const rows = exportBranches('bad=${2:-}\nif [[ -n $bad ]]; then echo bad; fi\n')
    .map(row => ({entry, ...row}));
  const table = expandInputs(rows, {[entry]: {args: ['/work', '/bad-tool'], env: {}}});
  const guards = table.filter(row => row.kind === 'condition');
  assert.deepEqual(guards.map(row => row.args), [['/work', '/bad-tool'], ['/work', '']]);
});

test('G1 inventory exposes command and redirection failures instead of dropping set-e exits', () => {
  const rows = exportBranches('set -e\nvalue=$(cat missing)\ncp "$value" output >log\n');
  assert.ok(rows.some(row => row.kind === 'command' && row.name === 'cat' && row.outcomes.includes('failure')));
  assert.ok(rows.some(row => row.kind === 'command' && row.name === 'cp' && row.outcomes.includes('failure')));
  assert.ok(rows.some(row => row.kind === 'redirection' && row.source === '>log'));
});
