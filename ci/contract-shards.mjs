#!/usr/bin/env node
// Manifest scheduling and receipts only; Node remains the test executor.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawn, execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {GATING, repoRoot} from './test-manifest.mjs';
import {verifiedTool, testEnvironment} from './test-zx.mjs';
import {pinnedOfficialSdkRoot, readHostSdkPinToolchain} from '../build/lib/package-lineage.mjs';
export const GROUPS = 4;
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const requireThat = (ok, why) => { if (!ok) throw new Error(`CONTRACT_SHARDS: ${why}`); };
const git = (...args) => execFileSync('git', ['-C', repoRoot, ...args], {encoding: 'utf8'}).trim();
const source = () => {
  requireThat(git('diff', '--name-only', 'HEAD', '--') === '', 'tracked source differs from frozen checkout');
  return {head: git('rev-parse', 'HEAD'), tree: git('rev-parse', 'HEAD^{tree}')};
};
const save = (file, data) => fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
export function makePlan(files, identity) {
  const plan = {schema: 1, source: identity, files, groups: Array.from({length: GROUPS}, (_, id) => ({id, files: files.filter((_, index) => index % GROUPS === id)}))};
  validatePlan(plan, files);
  return plan;
}
export function validatePlan(plan, expected) {
  requireThat(plan?.schema === 1 && equal(plan.files, expected), 'manifest differs from complete expected set');
  requireThat(expected.length >= GROUPS && new Set(expected).size === expected.length, 'empty or duplicate manifest');
  requireThat(plan.groups?.length === GROUPS, 'missing or duplicate groups');
  for (let id = 0; id < GROUPS; id++) {
    const group = plan.groups[id];
    requireThat(group?.id === id && group.files?.length > 0, 'empty or unordered group');
    requireThat(equal(group.files, expected.filter((_, index) => index % GROUPS === id)), `assignment differs for group ${id}`);
  }
  return plan;
}
const planHash = plan => hash(JSON.stringify(plan));
export function totals(text) {
  const names = ['tests', 'suites', 'pass', 'fail', 'cancelled', 'skipped', 'todo'];
  const result = {};
  for (const name of names) {
    const matches = [...text.matchAll(new RegExp(`^# ${name} (\\d+)\\r?$`, 'gm'))];
    if (matches.length !== 1) return null;
    result[name] = Number(matches[0][1]);
  }
  if (!/^1\.\.\d+\r?$/m.test(text) || !/^# duration_ms [\d.]+\r?$/m.test(text)) return null;
  if (result.tests <= 0 || result.tests !== result.pass + result.fail + result.cancelled + result.skipped + result.todo) return null;
  return result;
}
export async function executeNode(files, directory, {env = process.env} = {}) {
  fs.mkdirSync(directory, {recursive: true});
  const argv = [process.execPath, '--test', '--test-reporter=tap', '--test-timeout=300000', ...files];
  const start = {argv, cwd: repoRoot, started: new Date().toISOString()};
  save(path.join(directory, 'start.json'), start);
  const out = fs.openSync(path.join(directory, 'stdout.tap'), 'w');
  const err = fs.openSync(path.join(directory, 'stderr.log'), 'w');
  return new Promise(resolve => {
    const child = spawn(argv[0], argv.slice(1), {cwd: repoRoot, env, stdio: ['ignore', 'pipe', 'pipe']});
    let error = null;
    child.on('error', value => { error = String(value); });
    child.stdout.on('data', data => { fs.writeSync(out, data); process.stdout.write(data); });
    child.stderr.on('data', data => { fs.writeSync(err, data); process.stderr.write(data); });
    child.on('exit', (code, signal) => save(path.join(directory, 'exit.json'), {code, signal, ended: new Date().toISOString()}));
    let cancellationRequested = null;
    const cancel = signal => {
      cancellationRequested = {signal, at: new Date().toISOString()};
      save(path.join(directory, 'cancellation.json'), cancellationRequested);
      child.kill(signal);
    };
    const term = () => cancel('SIGTERM'), interrupt = () => cancel('SIGINT');
    process.on('SIGTERM', term); process.on('SIGINT', interrupt);
    child.on('close', (code, signal) => {
      process.removeListener('SIGTERM', term); process.removeListener('SIGINT', interrupt);
      fs.closeSync(out); fs.closeSync(err);
      const result = {...start, code, signal, error, cancellationRequested, ended: new Date().toISOString(), totals: totals(fs.readFileSync(path.join(directory, 'stdout.tap'), 'utf8'))};
      save(path.join(directory, 'node-result.json'), result);
      resolve(result);
    });
  });
}
async function inputs() {
  const tool = verifiedTool();
  const runtime = process.env.GC_FIX_RUNTIME_CHECKOUT;
  requireThat(runtime, 'runtime checkout missing');
  const runtimeGit = (...args) => execFileSync('git', ['-C', runtime, ...args], {encoding: 'utf8'}).trim();
  requireThat(runtimeGit('status', '--porcelain', '--untracked-files=all') === '', 'dirty runtime input');
  const expectedRuntime = fs.readFileSync(path.join(repoRoot, 'ci/runtime_pin.env'), 'utf8').match(/^RUNTIME_REF=([a-f0-9]{40})$/m)?.[1];
  requireThat(runtimeGit('rev-parse', 'HEAD') === expectedRuntime, 'runtime differs from formal pin');
  const historyBlob = git('rev-parse', '3b1fe439310269257a43685407df523f55a47cf6:ci/fetch-llvm-runtime.sh');
  requireThat(historyBlob === '52e9de86a83eeeabe5545041b653f80eb11b9f69', 'historical input differs');
  const sdk = await pinnedOfficialSdkRoot();
  return {node: {version: process.version, sha256: hash(fs.readFileSync(process.execPath))},
    zx: {version: tool.version, cliSha256: tool.cliSha256, packageSha256: tool.packageSha256},
    runtime: {head: runtimeGit('rev-parse', 'HEAD'), tree: runtimeGit('rev-parse', 'HEAD^{tree}')},
    pins: Object.fromEntries(['runtime_pin.env', 'host_sdk_pin.env'].map(name => [name, hash(fs.readFileSync(path.join(repoRoot, 'ci', name)))])),
    historyBlob,
    host: {version: await readHostSdkPinToolchain(), cjcSha256: hash(fs.readFileSync(path.join(sdk, 'bin/cjc'))),
      coreSha256: hash(fs.readFileSync(path.join(sdk, 'lib/linux_x86_64_cjnative/libcangjie-std-core.a')))}};
}
export function aggregate(plan, receipts, expected = plan.files) {
  validatePlan(plan, expected);
  requireThat(receipts.length === GROUPS && new Set(receipts.map(r => r.id)).size === GROUPS, 'missing or duplicate receipts');
  const ordered = [...receipts].sort((a, b) => a.id - b.id);
  const sum = {tests: 0, pass: 0, fail: 0, cancelled: 0, skipped: 0, todo: 0};
  for (let id = 0; id < GROUPS; id++) {
    const row = ordered[id], group = plan.groups[id];
    requireThat(row.id === id && row.planHash === planHash(plan) && equal(row.source, plan.source), `identity mismatch group ${id}`);
    requireThat(equal(row.files, group.files) && equal(row.node.argv.slice(1), ['--test', '--test-reporter=tap', '--test-timeout=300000', ...group.files]), `argv mismatch group ${id}`);
    const input = row.inputs;
    requireThat(input && typeof input.node?.version === 'string' && /^[a-f0-9]{64}$/.test(input.node.sha256)
      && typeof input.zx?.version === 'string' && /^[a-f0-9]{64}$/.test(input.zx.cliSha256)
      && /^[a-f0-9]{64}$/.test(input.zx.packageSha256) && /^[a-f0-9]{40}$/.test(input.runtime?.head)
      && /^[a-f0-9]{40}$/.test(input.runtime.tree) && /^[a-f0-9]{40}$/.test(input.historyBlob)
      && typeof input.host?.version === 'string' && /^[a-f0-9]{64}$/.test(input.host.cjcSha256)
      && /^[a-f0-9]{64}$/.test(input.host.coreSha256) && equal(input, ordered[0].inputs), `tool/input mismatch group ${id}`);
    requireThat(row.node.code === 0 && row.node.signal === null && !row.node.error && row.node.cancellationRequested === null, `Node failed or cancelled group ${id}`);
    const t = row.node.totals;
    requireThat(t && t.tests > 0 && t.fail === 0 && t.cancelled === 0 && t.tests === t.pass + t.skipped + t.todo, `missing or failed totals group ${id}`);
    for (const key of Object.keys(sum)) { requireThat(Number.isSafeInteger(t[key]) && t[key] >= 0, `invalid count ${key}`); sum[key] += t[key]; }
  }
  return {status: 'PASS', source: plan.source, files: plan.files.length, groups: GROUPS, totals: sum};
}
async function main([mode, first, second, third]) {
  if (mode === 'plan') {
    // The formal CLI validates registration before emitting the sole full plan.
    const text = second ? fs.readFileSync(second, 'utf8')
      : execFileSync(process.execPath, ['ci/test-manifest.mjs', 'list'], {cwd: repoRoot, encoding: 'utf8'});
    const files = text.trim().split('\n');
    requireThat(equal(files, [...GATING]), 'manifest export differs from registered set');
    const plan = makePlan(files, source()); save(first, plan);
  } else if (mode === 'run') {
    const plan = validatePlan(JSON.parse(fs.readFileSync(first)), [...GATING]);
    requireThat(equal(plan.source, source()), 'checkout differs from plan');
    const id = Number(second); requireThat(Number.isInteger(id) && id >= 0 && id < GROUPS, 'invalid group');
    const input = await inputs(), directory = path.resolve(third);
    fs.mkdirSync(directory, {recursive: true});
    const env = testEnvironment(path.join(directory, 'bin'), {...process.env, CJCJ_TEST_ZX_LOG: path.join(directory, 'zx-calls.jsonl')});
    const initial = {id, files: plan.groups[id].files, planHash: planHash(plan), source: source(), inputs: input};
    save(path.join(directory, 'group-start.json'), initial);
    const node = await executeNode(initial.files, directory, {env});
    save(path.join(directory, 'result.json'), {...initial, node});
    process.exitCode = node.code === 0 && !node.signal && !node.error && !node.cancellationRequested && node.totals ? 0 : 1;
  } else if (mode === 'summary') {
    const plan = validatePlan(JSON.parse(fs.readFileSync(first)), [...GATING]);
    requireThat(equal(plan.source, source()), 'summary checkout differs');
    const rows = fs.readdirSync(second).filter(n => n.startsWith('contract-group-'));
    requireThat(rows.length === GROUPS, 'missing group artifacts');
    const receipts = rows.map(name => {
      const directory = path.join(second, name);
      const row = JSON.parse(fs.readFileSync(path.join(directory, 'result.json')));
      const start = JSON.parse(fs.readFileSync(path.join(directory, 'start.json')));
      const exit = JSON.parse(fs.readFileSync(path.join(directory, 'exit.json')));
      requireThat(name === `contract-group-${row.id}` && equal(start.argv, row.node.argv), 'artifact/start identity mismatch');
      requireThat(exit.code === row.node.code && exit.signal === row.node.signal, 'exit receipt mismatch');
      requireThat(equal(totals(fs.readFileSync(path.join(directory, 'stdout.tap'), 'utf8')), row.node.totals), 'raw TAP totals mismatch');
      fs.accessSync(path.join(directory, 'stderr.log'));
      return row;
    });
    console.log(JSON.stringify(aggregate(plan, receipts, [...GATING]), null, 2));
  } else throw new Error('usage: contract-shards.mjs plan FILE | run PLAN GROUP OUT | summary PLAN ARTIFACTS');
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch(error => { console.error(error); process.exitCode = 1; });
}
