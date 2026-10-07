import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {exportBranches} from './llvm-runtime-branches.mjs';
import {fixture, originalSource} from './llvm-runtime-fixture.mjs';

const source = originalSource();
const table = exportBranches(source);
test('branch exporter loses exactly the removed source case arm', () => {
  const arm = /^\s*\*\) reject '[^']+' ;;\n/m.exec(source);
  assert.ok(arm, 'source contains the default environment case arm');
  const modified = source.replace(arm[0], '\n');
  const reduced = exportBranches(modified);
  console.log(`ASSERT_REACHED exporter rows=${table.rows.length} removed=${reduced.rows.length}`);
  assert.equal(reduced.rows.length, table.rows.length - 1);
  assert.deepEqual(reduced.rows.filter(row => row.kind === 'case-arm').map(row => row.source),
    table.rows.filter(row => row.kind === 'case-arm' && !row.source.startsWith('*)')).map(row => row.source));
});

for (const [name, select] of [
  ['private SHA guard rejects uppercase at the real entry', row => row.source.includes('complete lowercase')],
  ['private mixed-mode guard preserves explicit empty environment inputs', row => row.source.includes('do not mix')],
  ['private checkout consumer rejects mismatched HEAD', row => row.source.includes('HEAD differs')],
]) {
  test(name, t => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'llvm-runtime-input-'));
    t.after(() => fs.rmSync(root, {recursive: true, force: true}));
    const product = fixture(root, table);
    const row = table.rows.find(select);
    assert.ok(row, 'source-derived branch exists');
    // The uppercase guard witness is selected by its derived alphabet, not by
    // a parallel handcrafted argument list.
    const inputs = name.includes('uppercase') ? row.inputs.filter(input => /[A-F]/.test(input.env[table.shaVariable] || '')) : row.inputs;
    assert.ok(inputs.length);
    inputs.forEach((input, i) => {
      const result = product.execute(input, i);
      const message = /reject '([^']+)'/.exec(row.source)[1];
      console.log(`ASSERT_REACHED ${name} entry=${result.entrySha256} rc=${result.rc} stderr=${JSON.stringify(result.stderr)}`);
      assert.deepEqual({rc: result.rc, stdout: result.stdout, stderr: result.stderr},
        {rc: 1, stdout: '', stderr: `LLVM_RUNTIME_INPUT_ERROR: ${message}\n`}, name);
    });
  });
}
