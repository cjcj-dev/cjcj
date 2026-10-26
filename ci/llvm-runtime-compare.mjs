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
    const explicit=input.env[table.mode]==='private';
    const sha=input.env[table.shaVariable];
    const removedSelection=input.env[table.mode] && !explicit
      || explicit && (input.env[table.urlVariable]!==table.privateEnv[table.urlVariable]
        || Object.hasOwn(input.env,'RUNTIME_REF') || Object.hasOwn(input.env,'RUNTIME_SRC_URL'));
    if(explicit&&!/^[a-f0-9]{40}$/.test(sha||'')) {
      record.contract='canonical pair rejects incomplete/invalid identity';
      assert.equal(right.rc,1);
      assert.match(right.stderr,sha?/NATIVE_LLVM_REF_INVALID/:/NATIVE_RUNTIME_EXPLICIT_PAIR_REQUIRED/);
    } else if(removedSelection) {
      record.contract='retired environment selection is ignored; canonical pair/default remains';
      assert.equal(right.rc,0,right.stderr);
      assert.doesNotMatch(right.stdout,/sha=(?:present|inherited)/);
    } else {
      record.contract='unchanged Git/argv/exit/stream behavior';
      assert.deepEqual(right.normalized, left.normalized, `streams branch=${row.kind}:${row.line} input=${index}`);
    }
    fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify(records, null, 2));
    console.log(`ASSERT_PASS streams input=${index} rc=${right.rc}`);
  }
}
console.log(`TABLE_CONTRACT_PASS rows=${table.rows.length} inputs=${records.length}`);
