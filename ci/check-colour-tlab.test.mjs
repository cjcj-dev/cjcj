import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

const entry = new URL('./check-colour-tlab.mjs', import.meta.url).pathname;
function fixture(t, {old = false, colour = true} = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'colour-tlab-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const source = path.join(root, 'input.c'), object = path.join(root, 'input.o');
  const sequences = ['498b17488b02488b4a08', '498b014d8b5108', ...(old ? ['488b12488b02488b4a08', '4d8b09498b014d8b5108'] : [])];
  fs.writeFileSync(source, `unsigned char bytes[] = {${sequences.join('').match(/../g).map(byte => '0x' + byte).join(',')}};\n`
    + (colour ? 'extern void g_cjLoadFixture(void); void references(void) { g_cjLoadFixture(); }\n' : 'void references(void) {}\n'));
  const build = spawnSync('cc', ['-c', source, '-o', object], {encoding: 'utf8'});
  assert.equal(build.status, 0, build.stderr);
  const result = spawnSync(process.execPath, [entry, object], {encoding: 'utf8'});
  assert.equal(result.signal, null);
  return {result, row: JSON.parse(result.stdout)};
}
test('TLAB CLI accepts two-level bytes with a real undefined colour reference', t => {
  const {result, row} = fixture(t);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(row.assertions, {three_level_zero: true, two_level_present: true, colour_refs_present: true});
  assert.equal(row.two_level, 2);
});
test('TLAB CLI rejects old std byte sequences independently of colour references', t => {
  const {result, row} = fixture(t, {old: true});
  console.log(`TARGET_ASSERT old-std rejection reached three_level=${row.three_level}`);
  assert.equal(result.status, 1, 'old std must be rejected by the real CLI');
  assert.deepEqual(row.assertions, {three_level_zero: false, two_level_present: true, colour_refs_present: true});
  assert.equal(row.three_level, 2);
  assert.equal(row.two_level, 2, 'old array suffix must not count as a new array');
});
test('TLAB CLI rejects missing colour references independently of byte layout', t => {
  const {result, row} = fixture(t, {colour: false});
  assert.equal(result.status, 1);
  assert.deepEqual(row.assertions, {three_level_zero: true, two_level_present: true, colour_refs_present: false});
});
