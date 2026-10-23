#!/usr/bin/env zx
// Exercise the real difftest CLI and its G8 count consumer, not a copied classifier.
// DIFFTEST_TIMEOUT_SDK optionally uses a real installed compiler for the CJ cases.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawn, spawnSync} from 'node:child_process';
import {parseSummary} from '../ci/release/g8.mjs';
import {buildFullGateFloor} from '../build/lib/full-gate-floor-schema.mjs';

const root = await fs.mkdtemp(path.join(os.tmpdir(), 'difftest-timeout-test-'));
const script = path.resolve(argv.script || path.join(import.meta.dirname, 'difftest.mjs'));
const evidence = argv.evidence ? path.resolve(argv.evidence) : root;
await fs.mkdir(evidence, {recursive: true});
try {
  if (argv.loader) {
    const corpus = path.join(root, 'corpus');
    const sdk = path.join(root, 'sdk');
    await fs.mkdir(corpus);
    await fs.mkdir(path.join(sdk, 'runtime/lib/linux_x86_64_cjnative'), {recursive: true});
    await fs.writeFile(path.join(sdk, 'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so'), 'fixture only');
    // A real ELF/DT_NEEDED failure, not a program printing a loader message.
    await fs.writeFile(path.join(root, 'dependency.c'), 'int difftest_dependency(void) { return 0; }\n');
    await fs.writeFile(path.join(root, 'consumer.c'), 'extern int difftest_dependency(void); int main(void) { return difftest_dependency(); }\n');
    const builds = [
      ['cc', '-shared', '-fPIC', path.join(root, 'dependency.c'), '-o', path.join(root, 'libdifftest_missing.so')],
      ['cc', path.join(root, 'consumer.c'), '-L' + root, '-ldifftest_missing', '-Wl,-rpath,' + root, '-o', path.join(root, 'missing-loader')],
    ];
    for (const [index, command] of builds.entries()) {
      const result = spawnSync(command[0], command.slice(1), {encoding: 'utf8', timeout: 30000});
      await fs.writeFile(path.join(evidence, `loader-build-${index}.json`), JSON.stringify({command, rc: result.status, signal: result.signal, stdout: result.stdout, stderr: result.stderr, error: result.error?.message}) + '\n');
      assert.equal(result.error, undefined);
      assert.equal(result.status, 0, result.stderr);
    }
    await fs.rename(path.join(root, 'libdifftest_missing.so'), path.join(root, 'libdifftest_missing.hidden'));
    const missingLoader = spawnSync(path.join(root, 'missing-loader'), [], {encoding: 'utf8', timeout: 10000});
    await fs.writeFile(path.join(evidence, 'loader-native.execution.json'), JSON.stringify({rc: missingLoader.status, signal: missingLoader.signal, stderr: missingLoader.stderr, error: missingLoader.error?.message}) + '\n');
    assert.equal(missingLoader.error, undefined);
    assert.equal(missingLoader.status, 127);
    assert.match(missingLoader.stderr, /error while loading shared libraries: libdifftest_missing\.so/);
    const cases = ['plain', 'exit127', 'ref-loader-real', 'ref-diagnostic'];
    for (const name of cases) await fs.writeFile(path.join(corpus, name + '.cj'), '// controlled compiler boundary\n');
    const compiler = path.join(root, 'compiler.mjs');
    await fs.writeFile(compiler, `#!${process.execPath}
      import fs from 'node:fs';
      import path from 'node:path';
      if (process.argv.includes('--version')) process.exit(0);
      const name = path.basename(process.argv[2], '.cj');
      const out = process.argv[process.argv.indexOf('-o') + 1];
      const reference = out.endsWith('.ref');
      if (name === 'ref-loader-real' && reference) fs.copyFileSync(${JSON.stringify(path.join(root, 'missing-loader'))}, out);
      else {
        let body = 'process.exit(0)';
        if (name === 'exit127' || name === 'ref-loader-real') body = 'process.exit(127)';
        if (name === 'ref-diagnostic') body = 'console.log("same output");' + (reference ? 'console.error("undefined symbol: ordinary diagnostic");' : '') + 'process.exit(0)';
        fs.writeFileSync(out, ${JSON.stringify(`#!${process.execPath}\n`)} + body + '\\n', {mode: 0o755});
      }
    `, {mode: 0o755});
    const env = {...process.env, DIFFTEST_SELF: compiler, DIFFTEST_REF: compiler, DIFFTEST_SELF_TC: sdk, DIFFTEST_TC: sdk};
    delete env.CJ_HOST_RTLIB;
    const result = spawnSync(process.execPath, [process.argv[1], script, '--jobs', '2', corpus],
      {env, encoding: 'utf8', timeout: 30000, maxBuffer: 4 * 1024 * 1024});
    await fs.writeFile(path.join(evidence, 'loader.stdout.log'), result.stdout || '');
    await fs.writeFile(path.join(evidence, 'loader.stderr.log'), result.stderr || '');
    await fs.writeFile(path.join(evidence, 'loader.execution.json'), JSON.stringify({rc: result.status, signal: result.signal, error: result.error?.message}) + '\n');
    assert.equal(result.error, undefined);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /^PASS +plain +exit=0$/m);
    assert.match(result.stdout, /^PASS +exit127 +exit=127$/m);
    // The CLI intentionally bounds its diagnostic preview; the raw loader
    // error above proves the fixture independently of the path's length.
    assert.match(result.stdout, /^FAIL +ref-loader-real +HARNESS: reference product ABI\/runtime mismatch:/m);
    console.log('PASS loader controls: exit0, exit127, real missing DT_NEEDED library');
    assert.match(result.stdout, /^PASS +ref-diagnostic +exit=0$/m, 'successful reference stderr must not be classified as loader failure');
    console.log('PASS reference ordinary stderr diagnostic');
  } else if (argv.matrix) {
    const corpus = path.join(root, 'corpus');
    const sdk = path.join(root, 'sdk');
    await fs.mkdir(corpus);
    await fs.mkdir(path.join(sdk, 'runtime/lib/linux_x86_64_cjnative'), {recursive: true});
    await fs.writeFile(path.join(sdk, 'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so'), 'fixture only');
    const cases = ['exit42', 'exit124', 'exit143', 'exit127', 'ref-timeout', 'self-timeout',
      'ref-signal', 'self-signal', 'ref-loader', 'compile-fail', 'unequal', 'spawn-error', 'output-limit', 'pipe'];
    for (const name of cases) await fs.writeFile(path.join(corpus, name + '.cj'), '// controlled product\n');
    const compiler = path.join(root, 'compiler.mjs');
    await fs.writeFile(compiler, `#!${process.execPath}
      import fs from 'node:fs';
      import path from 'node:path';
      if (process.argv.includes('--version')) process.exit(0);
      const name = path.basename(process.argv[2], '.cj');
      const out = process.argv[process.argv.indexOf('-o') + 1];
      const arm = out.endsWith('.ref') ? 'ref' : 'self';
      if (name === 'compile-fail') process.exit(1);
      if (name === 'spawn-error') process.exit(0);
      let body = 'process.exit(0)';
      if (name.startsWith('exit')) body = 'process.exit(' + Number(name.slice(4)) + ')';
      if (name === arm + '-timeout') body = 'setInterval(() => {}, 1000)';
      if (name === arm + '-signal') body = 'process.kill(process.pid, "SIGTERM")';
      if (name === 'ref-loader') body = arm === 'ref' ? 'console.error("error while loading shared libraries: fixture.so");process.exit(127)' : 'process.exit(127)';
      if (name === 'unequal') body = 'console.log(' + JSON.stringify(arm) + ')';
      if (name === 'output-limit') body = 'process.stdout.write("x".repeat(1024 * 1024 + 1))';
      if (name === 'pipe') body = 'require("node:child_process").spawn(process.execPath,["-e","setTimeout(() => {}, 4000)"],{stdio:["ignore",1,2]});process.exit(42)';
      fs.writeFileSync(out, ${JSON.stringify(`#!${process.execPath}\n`)} + body + '\\n', {mode: 0o755});
    `, {mode: 0o755});
    const env = {...process.env, DIFFTEST_SELF: compiler, DIFFTEST_REF: compiler, DIFFTEST_SELF_TC: sdk, DIFFTEST_TC: sdk};
    delete env.CJ_HOST_RTLIB;
    const unrelated = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], {stdio: 'ignore'});
    try {
      const result = spawnSync(process.execPath, [process.argv[1], script, '--jobs', '2', corpus],
        {env, encoding: 'utf8', timeout: 100_000, maxBuffer: 4 * 1024 * 1024});
      await fs.writeFile(path.join(evidence, 'matrix.stdout.log'), result.stdout || '');
      await fs.writeFile(path.join(evidence, 'matrix.stderr.log'), result.stderr || '');
      await fs.writeFile(path.join(evidence, 'matrix.execution.json'), JSON.stringify({rc: result.status, signal: result.signal, error: result.error?.message}) + '\n');
      assert.equal(result.error, undefined);
      assert.equal(result.status, 0, result.stderr);
      for (const code of [42, 124, 143, 127]) assert.match(result.stdout, new RegExp('^PASS +exit' + code + ' +exit=' + code + '$', 'm'));
      for (const name of cases.filter(name => !name.startsWith('exit') && name !== 'unequal')) assert.match(result.stdout, new RegExp('^FAIL +' + name + ' +', 'm'));
      assert.match(result.stdout, /^MISMATCH +unequal +/m);
      assert.match(result.stdout, /^FAIL +ref-loader +HARNESS: reference product/m);
      assert.match(result.stdout, /^FAIL +spawn-error +.*RUN-ERROR ENOENT/m);
      assert.match(result.stdout, /^FAIL +output-limit +.*RUN-OUTPUT-LIMIT/m);
      assert.match(result.stdout, /^FAIL +pipe +.*RUN-PIPE-INCOMPLETE/m);
      assert.equal(unrelated.exitCode, null);
      assert.doesNotThrow(() => process.kill(unrelated.pid, 0));
      console.log('PASS matrix controls, single-arm failures, loader, output/pipe bounds, unrelated process');
    } finally {
      unrelated.kill('SIGTERM');
      await new Promise(resolve => unrelated.once('close', resolve));
    }
  } else if (argv.lifecycle) {
    const corpus = path.join(root, 'corpus');
    const sdk = path.join(root, 'sdk');
    await fs.mkdir(corpus);
    await fs.mkdir(path.join(sdk, 'runtime/lib/linux_x86_64_cjnative'), {recursive: true});
    await fs.writeFile(path.join(sdk, 'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so'), 'fixture only');
    await fs.writeFile(path.join(corpus, 'descendant.cj'), '// controlled descendant fixture\n');
    const leaf = `
      const fs = require('node:fs');
      const stat = fs.readFileSync('/proc/self/stat', 'utf8');
      const record = process.argv[1];
      const identity = JSON.stringify({pid: process.pid, start: stat.slice(stat.lastIndexOf(')') + 2).split(' ')[19]});
      const pending = record + '.pending';
      const publish = () => {
        fs.writeFileSync(pending, ${argv['identity-invalid'] ? "'invalid identity JSON'" : 'identity'});
        fs.renameSync(pending, record);
        process.send('ready');
      };
      if (${Boolean(argv['identity-delay'] || argv['identity-never'])}) {
        fs.writeFileSync(pending, identity.slice(0, 8));
        const timer = setInterval(() => {
          if (!${Boolean(argv['identity-never'])} && fs.existsSync(process.env.DIFFTEST_IDENTITY_RELEASE)) {
            clearInterval(timer);
            publish();
          }
        }, 10);
      } else publish();
      setInterval(() => {}, 1000);
      setTimeout(() => process.exit(0), 12000);
    `;
    const product = `#!${process.execPath}
      const {spawn} = require('node:child_process');
      const path = require('node:path');
      const child = spawn(process.execPath, ['-e', ${JSON.stringify(leaf)}, path.join(process.env.DIFFTEST_DESCENDANTS, path.basename(process.argv[1]) + '.json')], {detached: ${Boolean(argv.escape)}, stdio: ${JSON.stringify(argv.escape ? ['ignore', 1, 2, 'ipc'] : ['ignore', 'ignore', 'ignore', 'ipc'])}});
      child.once('message', () => ${argv.cancel ? 'setInterval(() => {}, 1000)' : 'process.exit(42)'});
    `;
    const compiler = path.join(root, 'compiler.mjs');
    await fs.writeFile(compiler, `#!${process.execPath}
      import fs from 'node:fs';
      if (process.argv.includes('--version')) process.exit(0);
      fs.writeFileSync(process.argv[process.argv.indexOf('-o') + 1], ${JSON.stringify(product)}, {mode: 0o755});
    `, {mode: 0o755});
    const records = path.join(evidence, 'descendants');
    await fs.mkdir(records);
    const release = path.join(evidence, 'identity.release');
    const env = {...process.env, DIFFTEST_SELF: compiler, DIFFTEST_REF: compiler,
      DIFFTEST_SELF_TC: sdk, DIFFTEST_TC: sdk, DIFFTEST_DESCENDANTS: records, DIFFTEST_IDENTITY_RELEASE: release};
    delete env.CJ_HOST_RTLIB;
    let execution;
    if (argv.cancel) {
      const cli = spawn(process.execPath, [process.argv[1], script, '--jobs', '1', corpus], {env, stdio: ['ignore', 'pipe', 'pipe']});
      let stdout = '', stderr = '';
      cli.stdout.on('data', data => { stdout += data; });
      cli.stderr.on('data', data => { stderr += data; });
      const closed = new Promise(resolve => cli.once('close', (status, signal) => resolve({status, signal, stdout, stderr})));
      let partialObserved = false;
      async function waitForIdentity() {
        const start = Date.now();
        while (Date.now() - start < 10_000) {
          const names = await fs.readdir(records);
          const published = names.filter(name => name.endsWith('.json'));
          if (published.length) {
            for (const name of published) {
              const text = await fs.readFile(path.join(records, name), 'utf8');
              let identity;
              assert.doesNotThrow(() => { identity = JSON.parse(text); }, 'INVALID_DESCENDANT_IDENTITY');
              assert.ok(Number.isSafeInteger(identity.pid) && identity.pid > 0 && /^\d+$/.test(identity.start), 'INVALID_DESCENDANT_IDENTITY');
              const stat = await fs.readFile(`/proc/${identity.pid}/stat`, 'utf8');
              const fields = stat.slice(stat.lastIndexOf(')') + 2).split(' ');
              assert.equal(fields[19], identity.start, 'descendant identity must still be live before cancellation');
              assert.ok(!['Z', 'X'].includes(fields[0]), 'descendant must have started before cancellation');
            }
            return;
          }
          if (argv['identity-delay'] && names.some(name => name.endsWith('.pending')) && !partialObserved) {
            const partial = await fs.readFile(path.join(records, names.find(name => name.endsWith('.pending'))), 'utf8');
            assert.throws(() => JSON.parse(partial), 'controlled write must still be incomplete');
            partialObserved = true;
            await fs.writeFile(release, 'complete the controlled identity write\n');
          }
          await new Promise(resolve => setTimeout(resolve, 20));
        }
        throw Error('DESCENDANT_READY_TIMEOUT: no complete identity published');
      }
      try {
        await waitForIdentity();
      } catch (error) {
        // This is preparation failure, not an effective cancellation sample.
        cli.kill('SIGTERM');
        execution = await closed;
        await fs.writeFile(path.join(evidence, 'readiness.json'), JSON.stringify({validSample: false, error: error.message, cleanup: {rc: execution.status, signal: execution.signal}}) + '\n');
        throw error;
      }
      cli.kill(String(argv.cancel));
      execution = await closed;
      await new Promise(resolve => setTimeout(resolve, 200));
      const published = (await fs.readdir(records)).filter(name => name.endsWith('.json'));
      await fs.writeFile(path.join(evidence, 'readiness.json'), JSON.stringify({validSample: published.length > 0, partialObserved, published, rc: execution.status, signal: execution.signal}) + '\n');
      assert.ok(published.length > 0, 'cancellation must wait for a completely published identity');
      if (argv['identity-delay']) assert.ok(partialObserved, 'controlled partial write must be observed before cancellation');
    } else {
      execution = spawnSync(process.execPath, [process.argv[1], script, '--jobs', '1', corpus],
        {env, encoding: 'utf8', timeout: 45_000, maxBuffer: 4 * 1024 * 1024});
    }
    await fs.writeFile(path.join(evidence, 'lifecycle.stdout.log'), execution.stdout || '');
    await fs.writeFile(path.join(evidence, 'lifecycle.stderr.log'), execution.stderr || '');
    const descendants = await Promise.all((await fs.readdir(records)).filter(name => name.endsWith('.json')).map(async name => JSON.parse(await fs.readFile(path.join(records, name), 'utf8'))));
    async function states() {
      return Promise.all(descendants.map(async identity => {
        const stat = await fs.readFile(`/proc/${identity.pid}/stat`, 'utf8').catch(() => '');
        const fields = stat.slice(stat.lastIndexOf(')') + 2).split(' ');
        return {...identity, state: fields[19] === identity.start ? fields[0] : 'gone'};
      }));
    }
    const atReturn = await states();
    // A broken baseline's fixture exits itself. Observe before that deadline;
    // do not rely on the outer systemd unit to clean up a leaked descendant.
    if (atReturn.some(item => !['gone', 'Z', 'X'].includes(item.state))) {
      await new Promise(resolve => setTimeout(resolve, 13_000));
    }
    const terminal = await states();
    await fs.writeFile(path.join(evidence, 'lifecycle.json'), JSON.stringify({
      rc: execution.status, signal: execution.signal, error: execution.error?.message, atReturn, terminal,
    }, null, 2) + '\n');
    assert.equal(execution.error, undefined);
    if (argv.cancel) {
      assert.ok(execution.signal || execution.status !== 0);
      assert.ok(descendants.length > 0);
    } else {
      assert.equal(execution.status, 0, execution.stderr);
      assert.match(execution.stdout, argv.escape ? /^FAIL +descendant +.*RUN-PIPE-INCOMPLETE/m : /^PASS +descendant +exit=42$/m);
      assert.equal(descendants.length, 2);
    }
    if (!argv.escape) assert.ok(atReturn.every(item => ['gone', 'Z', 'X'].includes(item.state)), JSON.stringify(atReturn));
    assert.ok(terminal.every(item => ['gone', 'Z', 'X'].includes(item.state)), JSON.stringify(terminal));
    console.log('PASS descendant lifecycle, cancellation or bounded escaped-pipe failure');
  } else {
  const corpus = path.join(root, 'corpus');
  await fs.mkdir(corpus);
  for (const [name, body] of [
    ['timeout', 'while (true) {}\nreturn 0'],
    ['exit42', 'return 42'],
    ['exit124', 'return 124'],
  ]) await fs.writeFile(path.join(corpus, `${name}.cj`), `main(): Int64 {\n${body}\n}\n`);

  let sdk = process.env.DIFFTEST_TIMEOUT_SDK ? path.resolve(process.env.DIFFTEST_TIMEOUT_SDK) : '';
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
  }
} finally {
  if (argv.evidence) await fs.rm(root, {recursive: true, force: true});
  else console.log(`Evidence: ${evidence}`);
}
