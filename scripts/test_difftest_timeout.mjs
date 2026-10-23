#!/usr/bin/env zx
// Exercise the real difftest CLI and its G8 count consumer, not a copied classifier.
// DIFFTEST_TIMEOUT_SDK optionally uses a real installed compiler for the CJ cases.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {parseSummary} from '../ci/release/g8.mjs';
import {buildFullGateFloor} from '../build/lib/full-gate-floor-schema.mjs';

const root = await fs.mkdtemp(path.join(os.tmpdir(), 'difftest-timeout-test-'));
const script = path.resolve(argv.script || path.join(import.meta.dirname, 'difftest.mjs'));
const evidence = argv.evidence ? path.resolve(argv.evidence) : root;
await fs.mkdir(evidence, {recursive: true});
try {
  const corpus = path.join(root, 'corpus');
  await fs.mkdir(corpus);
  for (const [name, body] of [
    ['timeout', 'while (true) {}\nreturn 0'],
    ['exit42', 'return 42'],
    ['exit124', 'return 124'],
  ]) await fs.writeFile(path.join(corpus, `${name}.cj`), `main(): Int64 {\n${body}\n}\n`);

  let sdk = process.env.DIFFTEST_TIMEOUT_SDK;
  let compiler;
  if (sdk) {
    compiler = path.join(sdk, 'bin/cjc');
  } else {
    // Controlled compiler boundary: the executables really run/hang/signal.
    // No replacement for timeout, zx, difftest, or G8 is installed.
    sdk = path.join(root, 'fixture-sdk');
    await fs.mkdir(path.join(sdk, 'runtime/lib/linux_x86_64_cjnative'), {recursive: true});
    await fs.writeFile(path.join(sdk, 'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so'), 'fixture only');
    compiler = path.join(root, 'compiler.mjs');
    await fs.writeFile(compiler, `#!${process.execPath}
import fs from 'node:fs';
import path from 'node:path';
const args = process.argv.slice(2);
if (args.includes('--version')) { console.log('difftest controlled compiler'); process.exit(0); }
const name = path.basename(args[0], '.cj');
const bodies = {timeout: 'while (true) {}', exit42: 'process.exit(42)', exit124: 'process.exit(124)', signal: "process.kill(process.pid, 'SIGTERM')", exit143: 'process.exit(143)'};
if (!Object.hasOwn(bodies, name)) throw Error('unknown fixture ' + name);
fs.writeFileSync(args[args.indexOf('-o') + 1], ${JSON.stringify(`#!${process.execPath}\n`)} + bodies[name] + '\\n', {mode: 0o755});
`, {mode: 0o755});
    await fs.writeFile(path.join(corpus, 'signal.cj'), '// controlled signal fixture\n');
    await fs.writeFile(path.join(corpus, 'exit143.cj'), '// controlled normal exit143 fixture\n');
  }
  const env = {...process.env, DIFFTEST_SELF: compiler, DIFFTEST_REF: compiler,
    DIFFTEST_SELF_TC: sdk, DIFFTEST_TC: sdk};
  delete env.CJ_HOST_RTLIB;
  // zx's CLI entry, as used to launch this test, avoids a network dependency.
  const execution = spawnSync(process.execPath, [process.argv[1], script, '--jobs', '2', corpus],
    {env, encoding: 'utf8', timeout: 150_000, maxBuffer: 4 * 1024 * 1024});
  await fs.writeFile(path.join(evidence, 'difftest.stdout.log'), execution.stdout || '');
  await fs.writeFile(path.join(evidence, 'difftest.stderr.log'), execution.stderr || '');
  await fs.writeFile(path.join(evidence, 'difftest.execution.json'), JSON.stringify({
    command: [process.execPath, process.argv[1], script, '--jobs', '2', corpus],
    compiler, sdk, rc: execution.status, signal: execution.signal, error: execution.error?.message,
  }, null, 2) + '\n');
  console.log(execution.stdout);
  assert.equal(execution.error, undefined);
  assert.equal(execution.status, 0, execution.stderr);
  const checks = [];
  function check(name, fn) {
    try { fn(); checks.push({name, pass: true}); }
    catch (error) { checks.push({name, pass: false, error: error.message}); }
  }
  for (const code of process.env.DIFFTEST_TIMEOUT_SDK ? [42, 124] : [42, 124, 143]) {
    check(`normal-exit-${code}`, () => assert.match(execution.stdout, new RegExp(`^PASS +exit${code} +exit=${code}$`, 'm')));
  }
  check('timeout-is-not-pass', () => assert.match(execution.stdout, /^FAIL +timeout +.*RUN-TIMEOUT/m));
  if (!process.env.DIFFTEST_TIMEOUT_SDK) {
    check('signal-is-not-pass', () => assert.match(execution.stdout, /^FAIL +signal +.*SIGNAL/m));
  }
  const counts = parseSummary('difftest', execution.stdout);
  const failures = process.env.DIFFTEST_TIMEOUT_SDK ? 1 : 2;
  check('g8-counts', () => assert.deepEqual(counts, {total: failures + (failures === 1 ? 2 : 3), pass: failures === 1 ? 2 : 3, mismatch: 0, fail: failures}));
  const sha = '08148651dc2aeee42eae161eca98d83a5cdb4935';
  const floor = difftest => buildFullGateFloor({campaign_id: `${sha}-20261023T000000Z-1`,
    cjcj_head_sha: sha, measured_utc: '2026-10-23T00:00:00Z', baseline: {
      difftest, smoke: {pass: 1, fail: 0},
      bcgate: {shared: 1, byte_identical: 1, differing: 0, compile_errors: 0}, verify_exit: 0,
    }});
  check('g8-rejects-incomplete-products', () => assert.throws(() => floor(counts), /difftest/));
  const controls = path.join(root, 'controls');
  await fs.mkdir(controls);
  for (const code of [42, 124]) {
    await fs.copyFile(path.join(corpus, `exit${code}.cj`), path.join(controls, `exit${code}.cj`));
  }
  const controlExecution = spawnSync(process.execPath, [process.argv[1], script, '--jobs', '2', controls],
    {env, encoding: 'utf8', timeout: 90_000, maxBuffer: 4 * 1024 * 1024});
  await fs.writeFile(path.join(evidence, 'controls.stdout.log'), controlExecution.stdout || '');
  await fs.writeFile(path.join(evidence, 'controls.stderr.log'), controlExecution.stderr || '');
  await fs.writeFile(path.join(evidence, 'controls.execution.json'), JSON.stringify({
    command: [process.execPath, process.argv[1], script, '--jobs', '2', controls],
    compiler, sdk, rc: controlExecution.status, signal: controlExecution.signal, error: controlExecution.error?.message,
  }, null, 2) + '\n');
  check('g8-accepts-normal-controls', () => {
    assert.equal(controlExecution.error, undefined);
    assert.equal(controlExecution.status, 0, controlExecution.stderr);
    const controlCounts = parseSummary('difftest', controlExecution.stdout);
    assert.deepEqual(controlCounts, {total: 2, pass: 2, mismatch: 0, fail: 0});
    assert.doesNotThrow(() => floor(controlCounts));
  });
  await fs.writeFile(path.join(evidence, 'checks.json'), JSON.stringify(checks, null, 2) + '\n');
  for (const item of checks) console.log(`${item.pass ? 'PASS' : 'FAIL'} ${item.name}${item.error ? ': ' + item.error : ''}`);
  process.exitCode = checks.every(item => item.pass) ? 0 : 1;
} finally {
  if (argv.evidence) await fs.rm(root, {recursive: true, force: true});
  else console.log(`Evidence: ${evidence}`);
}
