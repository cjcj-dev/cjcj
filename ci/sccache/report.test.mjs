import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {formatRate, main, outputs, renderSummary, statusLine, summarize, verdict} from './report.mjs';

const script = path.resolve(import.meta.dirname, 'report.mjs');
// Captured from `sccache --show-stats --stats-format=json`, sccache 0.18.0, after
// two compiles of the same translation unit: one miss, one hit.
const fixture = path.resolve(import.meta.dirname, 'fixtures-stats-v0.18.0.json');
const real = JSON.parse(fs.readFileSync(fixture, 'utf8'));

const withStats = overrides => ({...real, stats: {...real.stats, ...overrides}});
const counts = (c, cpp) => ({counts: {C: c, 'C/C++': cpp}, adv_counts: {}});

test('summarize reads the sccache 0.18 document: requests, hits, misses, rate, size', () => {
  const summary = summarize(real);
  assert.equal(summary.compileRequests, 2);
  assert.equal(summary.hits, 1);
  assert.equal(summary.misses, 1);
  assert.equal(summary.hitRate, 0.5);
  assert.equal(summary.cacheSize, 783);
  assert.equal(summary.version, '0.18.0');
  assert.equal(formatRate(summary.hitRate), '50.0%');
});

test('hit rate is undefined, not zero, when nothing was decided', () => {
  const summary = summarize(withStats({compile_requests: 0, cache_hits: counts(0, 0), cache_misses: counts(0, 0)}));
  assert.equal(summary.hitRate, null);
  assert.equal(formatRate(summary.hitRate), 'n/a');
  assert.throws(() => summarize({version: '0.18.0'}), /no stats\.compile_requests/);
});

test('a job that compiled nothing through the launcher is a problem only when compiles are required', () => {
  const idle = summarize(withStats({compile_requests: 0, cache_hits: counts(0, 0), cache_misses: counts(0, 0)}));
  assert.deepEqual(verdict(idle, {requireCompiles: false}), []);
  const [problem] = verdict(idle, {requireCompiles: true});
  assert.match(problem, /0 compile requests: the C\+\+ build did not go through the launcher/);
  assert.equal(outputs(idle, []).save, 'false', 'nothing compiled, nothing to persist');
});

test('compiles that sccache could not cache at all are a problem too: the job is not actually cached', () => {
  const uncached = summarize(withStats({compile_requests: 40, cache_hits: counts(0, 0), cache_misses: counts(0, 0), non_cacheable_compilations: 40}));
  const [problem] = verdict(uncached, {requireCompiles: true});
  assert.match(problem, /40 compile requests but decided none of them .*non-cacheable=40/);
  const cached = summarize(withStats({compile_requests: 40, cache_hits: counts(10, 20), cache_misses: counts(3, 7)}));
  assert.deepEqual(verdict(cached, {requireCompiles: true}), []);
  assert.equal(cached.hits, 30);
  assert.equal(cached.misses, 10);
  assert.equal(formatRate(cached.hitRate), '75.0%');
  assert.deepEqual(outputs(cached, []), {compile_requests: '40', cache_hits: '30', cache_misses: '10', hit_rate: '75.0', save: 'true'});
});

test('status line and summary say cold or warm from the restored key', () => {
  const summary = summarize(real);
  const cold = statusLine({component: 'llvm', platform: 'linux_x86_64', restoredKey: '', summary});
  assert.match(cold, /^SCCACHE component=llvm platform=linux_x86_64 cache=cold restored_key=- requests=2 hits=1 misses=1 hit_rate=50\.0% errors=0 size_bytes=783$/);
  const warm = renderSummary({component: 'llvm', platform: 'linux_x86_64', restoredKey: 'sccache-llvm-linux_x86_64-abc-1-1', summary, problems: ['boom']});
  assert.match(warm, /\| cache \| warm \(restored `sccache-llvm-linux_x86_64-abc-1-1`\) \|/);
  assert.match(warm, /\| hit rate \| 50\.0% \|/);
  assert.match(warm, /> ❌ boom/);
});

test('main writes the summary and outputs and returns the exit status the composite action keys on', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sccache-report-'));
  const summaryFile = path.join(dir, 'summary.md');
  const outputFile = path.join(dir, 'output');
  const logs = [];
  const rc = main(['--stats', fixture, '--component', 'runtime', '--platform', 'linux-x64', '--restored-key', 'k', '--summary', summaryFile, '--github-output', outputFile, '--require-compiles'], {log: line => logs.push(line), warn: () => {}});
  assert.equal(rc, 0);
  assert.match(logs[0], /^SCCACHE component=runtime platform=linux-x64 cache=warm/);
  assert.match(fs.readFileSync(summaryFile, 'utf8'), /### sccache · runtime · linux-x64/);
  assert.match(fs.readFileSync(outputFile, 'utf8'), /^hit_rate=50\.0$/m);
  assert.match(fs.readFileSync(outputFile, 'utf8'), /^save=true$/m);

  const idle = path.join(dir, 'idle.json');
  fs.writeFileSync(idle, JSON.stringify(withStats({compile_requests: 0, cache_hits: counts(0, 0), cache_misses: counts(0, 0)})));
  const red = spawnSync(process.execPath, [script, '--stats', idle, '--component', 'llvm', '--platform', 'p', '--require-compiles'], {encoding: 'utf8'});
  assert.equal(red.status, 1);
  assert.match(red.stderr, /::error::sccache saw 0 compile requests/);
  const green = spawnSync(process.execPath, [script, '--stats', idle, '--component', 'llvm', '--platform', 'p'], {encoding: 'utf8'});
  assert.equal(green.status, 0, green.stderr);
  const usage = spawnSync(process.execPath, [script, '--stats', idle], {encoding: 'utf8'});
  assert.equal(usage.status, 2);
  assert.match(usage.stderr, /--component is required/);
});
