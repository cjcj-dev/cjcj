#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {repo, cliArgs} from './entry-common.mjs';
// Manual Linux entry: real source cuts and signals require exclusive ownership.
const source = repo;
assert(cliArgs.length === 1 && cliArgs[0], 'usage: test-g1-signal-cleanup.mjs NEW_EVIDENCE');
const evidence = path.resolve(cliArgs[0]);
fs.mkdirSync(evidence);
const {inventory, exportBranches, expandInputs} = await import(path.join(source, 'ci/g1-entry-branches.mjs'));
const entry = 'ci/test-ast-support-wiring.mjs';
const rows = inventory().filter(row => row.entry === entry);
const signals = rows.filter(row => row.kind === 'command' && row.name === 'trap' &&
  !row.scope.length && row.arguments[0]?.type === 'raw_string').map(row => {
    const handler = exportBranches(row.arguments[0].text.slice(1, -1));
    assert.equal(handler.length, 1);
    assert.equal(handler[0].kind, 'exit');
    const rc = Number(handler[0].arguments[0].text);
    assert(Number.isInteger(rc));
    return {signal: `SIG${row.arguments[1].text}`, rc, row};
  });
assert.equal(signals.length, 2);
const consumer = path.join(source, 'ci/release/prepare_bootstrap_inputs.mjs');
const original = fs.readFileSync(consumer);
const old = path.join(source, 'ci/.g1-old-signal.bash.txt');
assert.equal(spawnSync('git', ['status', '--porcelain', '--', consumer], {cwd: source, encoding: 'utf8'}).stdout, '');
fs.symlinkSync('fixtures/g1/test-ast-support-wiring.bash.txt', old);
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const records = [];
let safeToRestore = true;
function descendants(pid) {
  let children;
  try { children = fs.readFileSync(`/proc/${pid}/task/${pid}/children`, 'utf8').trim(); }
  catch (error) { if (error.code === 'ENOENT' || error.code === 'ESRCH') return []; throw error; }
  return children ? children.split(' ').flatMap(value => {const child = Number(value); return [child, ...descendants(child)];}) : [];
}
function processState(pid) {
  try {
    const stat = fs.readFileSync(`/proc/${pid}/stat`, 'utf8');
    const fields = stat.slice(stat.lastIndexOf(')') + 2).split(' ');
    return {pid, state: fields[0], started: fields[19]};
  } catch (error) { if (error.code === 'ENOENT' || error.code === 'ESRCH') return undefined; throw error; }
}
function rememberTree(pid, owned) {
  const state = processState(pid);
  if (!state || (owned.has(pid) && owned.get(pid).started !== state.started)) return;
  owned.set(pid, state);
  for (const child of descendants(pid)) {
    const state = processState(child);
    if (state && (!owned.has(child) || owned.get(child).started === state.started)) owned.set(child, state);
  }
}
const live = owned => [...owned.values()].filter(saved => {
  const state = processState(saved.pid);
  return state && state.started === saved.started && state.state !== 'Z';
});
async function stopOwned(owned, record) {
  // GNU timeout can create a different process group. Track exact descendants
  // plus kernel start times, rather than assuming one process-group kill stops
  // all children or risking a recycled PID.
  for (const pid of [...owned.keys()]) rememberTree(pid, owned);
  record.ownedProcesses = [...owned.values()];
  record.cleanupSignals = [];
  for (const signal of ['SIGTERM', 'SIGKILL']) {
    for (const saved of live(owned).reverse()) {
      try { process.kill(saved.pid, signal); record.cleanupSignals.push({pid: saved.pid, signal}); }
      catch (error) { if (error.code !== 'ESRCH') throw error; }
    }
    const deadline = Date.now() + 3000;
    while (live(owned).length && Date.now() < deadline) await delay(20);
    if (!live(owned).length) break;
  }
  record.liveAfterCleanup = live(owned);
  assert.deepEqual(record.liveAfterCleanup, [], 'owned processes must stop before harness restoration');
}
try {
  for (const specification of signals) {
    for (const arm of ['old', 'candidate']) {
      const directory = path.join(evidence, `${specification.signal}-${arm}`);
      fs.mkdirSync(directory);
      const work = path.join(directory, 'output');
      const [input] = expandInputs(rows.filter(row => row.kind === 'required'),
        {[entry]: {args: [work], env: {}}}).filter(row => row.outcome === 'set');
      assert.equal(input.status, 'READY');
      const command = arm === 'old' ? ['bash', old, ...input.args] : ['npx', '--yes', 'zx@8', path.join(source, entry), ...input.args];
      const fd = fs.openSync(path.join(directory, 'run.log'), 'wx');
      const child = spawn(command[0], command.slice(1), {cwd: source, detached: true,
        stdio: ['ignore', fd, fd], env: {...process.env, LC_ALL: 'C'}});
      let finished;
      const closed = new Promise((resolve, reject) => {
        child.once('error', reject);
        child.once('close', (rc, signal) => {finished = {rc, signal}; resolve(finished);});
      });
      closed.catch(() => {});
      const owned = new Map();
      rememberTree(child.pid, owned);
      safeToRestore = false;
      const record = {arm, ...specification, input, command, parentPid: child.pid};
      records.push(record);
      try {
        // The actual old entry already bounds each Node arm to 180s + 5s kill
        // grace. Preparation cannot use a shorter unrelated 30s deadline.
        const deadline = Date.now() + 185000;
        const cut = path.join(work, 'selection-cut.diff');
        while (!fs.existsSync(cut) || fs.readFileSync(consumer).equals(original)) {
          assert(!finished, `entry exited before actual cut: ${JSON.stringify(finished)}`);
          assert(Date.now() < deadline, 'actual selection cut not reached before deadline');
          await delay(5);
        }
        record.cutReached = true;
        let targetPid = child.pid;
        if (arm === 'candidate') {
          const candidates = descendants(child.pid).filter(pid => {
            try {
              const args = fs.readFileSync(`/proc/${pid}/cmdline`, 'utf8').split('\0');
              return path.basename(args[0]) === 'node' && args.includes(path.join(source, entry)) &&
                (args[1].endsWith('/zx') || args[1].endsWith('/zx/build/cli.js'));
            } catch (error) { if (error.code === 'ENOENT' || error.code === 'ESRCH') return false; throw error; }
          });
          assert.equal(candidates.length, 1, `exact zx entry pid: ${candidates}`);
          [targetPid] = candidates;
        }
        record.signalTargetPid = targetPid;
        rememberTree(child.pid, owned);
        process.kill(targetPid, specification.signal);
        const deadlineAfterSignal = Date.now() + 20000;
        while (!finished) {
          assert(Date.now() < deadlineAfterSignal, 'signalled entry did not exit');
          await delay(10);
        }
        record.result = await closed;
        record.sourceRestoredByEntry = fs.readFileSync(consumer).equals(original);
        record.exitArtifacts = Object.fromEntries(['exit.sha256', 'exit.status'].map(name =>
          [name, fs.existsSync(path.join(work, name)) ? fs.readFileSync(path.join(work, name), 'utf8') : null]));
        record.targetReached = true;
        console.log(`SIGNAL_TARGET_ASSERT_REACHED arm=${arm} signal=${specification.signal} rc=${record.result.rc} restored=${record.sourceRestoredByEntry}`);
      } finally {
        try {
          await stopOwned(owned, record);
          safeToRestore = true;
          record.parentResult = await closed.catch(error => ({error: error.message}));
          fs.writeFileSync(consumer, original);
        } finally {
          fs.closeSync(fd);
          fs.writeFileSync(path.join(evidence, 'results.json'), JSON.stringify(records, null, 2));
        }
      }
    }
  }
  for (const specification of signals) {
    const [before, after] = records.filter(record => record.signal === specification.signal);
    for (const record of [before, after]) {
      assert.equal(record.result.rc, specification.rc);
      assert(record.sourceRestoredByEntry);
      assert(record.exitArtifacts['exit.sha256']);
      assert.equal(record.exitArtifacts['exit.status'], '');
    }
    assert.deepEqual(after.exitArtifacts, before.exitArtifacts);
  }
  console.log(`SIGNAL_PARITY_PASS N=${signals.length}`);
} finally {
  if (safeToRestore) {
    fs.writeFileSync(consumer, original);
    fs.unlinkSync(old);
    const result = spawnSync('git', ['diff', '--exit-code', '--', consumer], {cwd: source, encoding: 'utf8'});
    fs.writeFileSync(path.join(evidence, 'restored.diff'), result.stdout);
    assert.equal(result.status, 0);
  }
}
