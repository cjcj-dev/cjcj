#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {exportBranches} from './llvm-runtime-branches.mjs';
import {fixture, originalSource} from './llvm-runtime-fixture.mjs';

const output = path.resolve(process.argv[2]);
fs.mkdirSync(output, {recursive: true});
const source = originalSource();
const table = exportBranches(source);
fs.writeFileSync(path.join(output, 'original.bash'), source);
fs.writeFileSync(path.join(output, 'branches.json'), JSON.stringify(table, null, 2));
const baseline = fixture(path.join(output, 'baseline'), table, {baseline: true});
const candidate = fixture(path.join(output, 'candidate'), table);
const seen = new Map();
const records = [];
for (const row of table.rows) {
  for (const input of row.inputs) {
    const key = JSON.stringify(input);
    if (seen.has(key)) { seen.get(key).branches.push(`${row.kind}:${row.line}`); continue; }
    const index = records.length;
    const left = baseline.execute(input, index);
    const right = candidate.execute(input, index);
    // Each fixture has its own legitimate commit (timestamps/metadata can
    // differ); private request and adjacent pin are mapped to that real HEAD.
    const record = {index, branches: [`${row.kind}:${row.line}`], baseline: left, candidate: right};
    records.push(record);
    seen.set(key, record);
    fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify(records, null, 2));
    console.log(`ASSERT_REACHED streams branch=${row.kind}:${row.line} input=${index}`);
    assert.deepEqual(right.normalized, left.normalized, `streams branch=${row.kind}:${row.line} input=${index}`);
    console.log(`ASSERT_PASS streams input=${index} rc=${right.rc}`);
  }
}
console.log(`TABLE_PASS rows=${table.rows.length} inputs=${records.length}`);
