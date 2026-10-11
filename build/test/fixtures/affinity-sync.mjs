#!/usr/bin/env zx
// Private fixture synchronization; never supplies process or affinity data.
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const root = process.env.AFFINITY_FIXTURE_ROOT;
const ready = path.join(root, 'make.pid');
const observed = path.join(root, 'observed');
const outcome = path.join(root, 'outcome');

if (path.basename(process.argv[1]) === 'taskset') {
  const args = process.argv.slice(2);
  const result = spawnSync('/usr/bin/taskset', args, {stdio: ['inherit', 'pipe', 'pipe']});
  if (result.stdout) fs.writeSync(1, result.stdout);
  if (result.stderr) fs.writeSync(2, result.stderr);
  if (result.error) throw result.error;
  // Only a successful real query of this live top-level make releases it.
  if (result.status === 0 && args.length === 2 && args[0] === '-pc'
      && fs.existsSync(ready) && args[1] === fs.readFileSync(ready, 'utf8').trim()) {
    fs.writeFileSync(path.join(root, 'query.json'), JSON.stringify({
      pid: args[1], rc: result.status, stdout: result.stdout.toString(), stderr: result.stderr.toString(),
    }));
    fs.writeFileSync(observed, `${args[1]}\n`);
  }
  if (result.signal) process.kill(process.pid, result.signal);
  else process.exitCode = result.status;
} else {
  const timeoutMs = Number(process.argv[2]);
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs <= 0) throw new Error('invalid fixture timeout');
  // make executes this recipe directly; the PID is read, never synthesized.
  fs.writeFileSync(ready, `${process.ppid}\n`);
  const state = await new Promise(resolve => {
    let timer;
    const watcher = fs.watch(root, check);
    function finish(value) {
      clearTimeout(timer);
      watcher.close();
      resolve(value);
    }
    function check() {
      if (fs.existsSync(observed)) finish('observed');
    }
    timer = setTimeout(() => finish('timeout'), timeoutMs);
    check(); // Covers a query that completed before the watcher was installed.
  });
  fs.writeFileSync(outcome, `${state}\n`);
  // A missing observation releases make safely; the record assertions decide.
}
