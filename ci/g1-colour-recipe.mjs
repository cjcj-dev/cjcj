#!/usr/bin/env zx
import fs from 'node:fs';
import assert from 'node:assert/strict';
const [token, workflow, tuple] = process.argv.slice(2);
const failures = [];
for (const file of [workflow, tuple]) {
  if (!fs.readFileSync(file, 'utf8').includes(token)) failures.push(`MISSING_LIBXML2_OFF ${file}`);
  else console.log(`LIBXML2_PRODUCER_CONTROL_PRESENT ${file}`);
}
// Only the workflow actually invokes this checker. The tuple producer has a
// real CMake flag, but no checker call; do not invent one for symmetry.
if (!fs.readFileSync(workflow, 'utf8').includes('assert_no_libxml2_needed.sh'))
  failures.push(`MISSING_NEEDED_CHECK ${workflow}`);
else console.log('LIBXML2_CHECKER_CALL_CONTROL_PRESENT');
console.log('RECIPE_TARGET_ASSERT_REACHED');
for (const failure of failures) console.error(failure);
assert.equal(failures.length, 0, 'active LLVM producers and checker call must remain wired');
console.log('RECIPE_LIBXML2_OFF_PRESENT');
