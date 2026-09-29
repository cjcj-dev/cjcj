import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs/promises';
import {evaluate, skippedWho} from './run.mjs';

const ids = Array.from({length: 50}, (_, i) => `case${i}`);
const ok = () => ({rc: 0, signal: null, error: null, timed_out: false, skipped_who: 0, signature: 'OK'});
function records() {
  return ['official', 'selfhost'].flatMap(arm => ['version', 'compile', 'crashsweep'].flatMap(phase =>
    (phase === 'crashsweep' ? ids : Array.from({length: 20}, (_, i) => String(i + 1))).map(id =>
      phase === 'version' ? {arm, phase, id, invoke: ok()} : {arm, phase, id, compile: ok(), run: ok(), elf_sha256: 'a'.repeat(64)})));
}

test('complete two-arm records pass; one runtime signal names exactly that case', () => {
  const input = records();
  assert.equal(evaluate(input, ids).status, 'MET');
  const target = input.find(r => r.arm === 'selfhost' && r.id === 'case17');
  target.run = {...ok(), rc: null, signal: 'SIGABRT', signature: 'SIGNAL:SIGABRT'};
  assert.deepEqual(evaluate(input, ids).failures, [{arm: 'selfhost', phase: 'crashsweep', id: 'case17', step: 'run', reason: 'SIGNAL:SIGABRT'}]);
  assert.equal(evaluate(input, ids).status, 'NOT_MET');
});

test('missing, duplicate, unlaunched, timeout, skipped WHO and absent ELF cannot pass', () => {
  for (const mutation of [
    rows => rows.pop(), rows => rows.push(rows.at(-1)),
    rows => { rows.at(-1).run = {...ok(), rc: null, error: 'ENOENT'}; },
    rows => { rows.at(-1).run.timed_out = true; },
    rows => { rows.at(-1).compile.skipped_who = 1; },
    rows => { delete rows.at(-1).elf_sha256; },
  ]) {
    const input = records(); mutation(input);
    assert.equal(evaluate(input, ids).status, 'NOT_MET');
  }
});

test('unavailable selfhost is UNKNOWN, while an observed official failure remains NOT_MET', () => {
  const input = records().filter(r => r.arm === 'official');
  assert.equal(evaluate(input, ids, {selfhost: 'wait #135'}).status, 'UNKNOWN');
  input.at(-1).run.rc = 1;
  assert.equal(evaluate(input, ids, {selfhost: 'wait #135'}).status, 'NOT_MET');
});

test('SKIPPED_WHO counts diagnostic records and explicit aggregates without treating zero as a failure', () => {
  assert.equal(skippedWho('SKIPPED_WHO=0\n'), 0);
  assert.equal(skippedWho('SKIPPED_WHO=2\nSKIPPED_WHO: 3\nSKIPPED_WHO name\n'), 6);
});

test('normal corpus has 50 distinct sources and excludes the positive failure control', async () => {
  const corpus = JSON.parse(await fs.readFile(new URL('./corpus.json', import.meta.url)));
  assert.equal(corpus.cases.length, 50);
  assert.equal(new Set(corpus.cases.map(c => c.id)).size, 50);
  const sources = await Promise.all(corpus.cases.map(c => fs.readFile(new URL(c.file, import.meta.url), 'utf8')));
  assert.equal(new Set(sources).size, 50);
  for (const entry of corpus.cases) {
    assert.equal(entry.expected_rc, 0);
    assert.match(entry.file, /^progs\//);
  }
});
