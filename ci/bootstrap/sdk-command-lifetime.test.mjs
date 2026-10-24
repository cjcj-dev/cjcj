#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {spawn, spawnSync} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';
import assert from 'node:assert/strict';
import test from 'node:test';

const source = fileURLToPath(new URL('./sdk-command-lifetime.mjs', import.meta.url));
const base = process.env.RELEASE_EVIDENCE_TEST_ROOT;
assert(base && path.isAbsolute(base), 'owned absolute RELEASE_EVIDENCE_TEST_ROOT required');
const root = fs.mkdtempSync(path.join(base, 'supervisor-entry-'));
const linkDir = path.join(root, 'vendor scripts');
fs.symlinkSync(path.dirname(source), linkDir, 'dir');
const link = path.join(linkDir, path.basename(source));
const records = [];
function environment(label) {
  const env = {...process.env, CJCJ_SUPERVISOR_WORK:path.join(root, label),
    CANGJIE_JOBSERVER_LOG:path.join(root, label + '.events.jsonl')};
  for (const key of ['MAKEFLAGS', 'MFLAGS', 'CARGO_MAKEFLAGS',
    'CJCJ_SUPERVISOR_OWNER_FD', 'CJCJ_COMMAND_LIFETIME_FD']) delete env[key];
  return env;
}
function record(label, argv, p) {
  records.push({label, argv, pid:p.pid, rc:p.status, signal:p.signal});
  fs.writeFileSync(path.join(root, 'commands.json'), JSON.stringify(records, null, 2));
}
function run(label, args) {
  const argv = [process.execPath, ...args];
  const out = fs.openSync(path.join(root, label + '.stdout'), 'wx');
  const err = fs.openSync(path.join(root, label + '.stderr'), 'wx');
  const p = spawnSync(argv[0], argv.slice(1), {cwd:root, env:environment(label),
    stdio:['ignore', out, err], timeout:15000});
  fs.closeSync(out); fs.closeSync(err); record(label, argv, p);
  assert.ifError(p.error);
  return p.status;
}
function body(label, entry, flags = []) {
  const marker = path.join(root, label + '.body');
  const rc = run(label, [...flags, entry, '--', process.execPath, '-e',
    'require("fs").writeFileSync(process.argv[1],"BODY");process.exit(23)', marker]);
  assert.equal(rc, 23, 'CLI must execute payload and propagate its nonzero exit');
  assert.equal(fs.readFileSync(marker, 'utf8'), 'BODY');
  console.log('BODY_AND_RC_ASSERT_REACHED', label);
}
test('absolute and relative CLI execute payload', () => {
  body('absolute', source);
  body('relative', path.relative(root, source));
});
test('symlink CLI executes body and propagates nonzero', () => {
  body('symlink', path.relative(root, link));
  body('preserve-main', link, ['--preserve-symlinks-main']);
});
test('import remains inert for direct and symlink modules', () => {
  for (const [name, target] of [['direct', source], ['link', link]]) {
    const driver = path.join(root, name + '-import.mjs');
    fs.writeFileSync(driver, `import {supervisedCommand} from ${JSON.stringify(pathToFileURL(target).href)};\nconsole.log(typeof supervisedCommand);\n`);
    assert.equal(run('import-' + name, [driver]), 0);
    assert.equal(fs.readFileSync(path.join(root, 'import-' + name + '.stdout'), 'utf8'), 'function\n');
    assert(!fs.existsSync(path.join(root, 'import-' + name + '.events.jsonl')));
  }
  // Eval has either no argv[1] or an application argument, not a module entry.
  const code = `await import(${JSON.stringify(pathToFileURL(link).href)});console.log('IMPORTED')`;
  for (const [label, extra] of [['eval', []], ['eval-argument', ['missing entry']]]) {
    assert.equal(run(label, ['--input-type=module', '-e', code, ...extra]), 0);
    assert.equal(fs.readFileSync(path.join(root, label + '.stdout'), 'utf8'), 'IMPORTED\n');
  }
  console.log('IMPORT_CONTROL_ASSERT_REACHED');
});
test('symlink CLI reports successful body and child signal', () => {
  assert.equal(run('success', [link, '--', process.execPath, '-e', 'console.log("EXECUTED")']), 0);
  assert.equal(fs.readFileSync(path.join(root, 'success.stdout'), 'utf8'), 'EXECUTED\n');
  assert.equal(run('child-term', [link, '--', process.execPath, '-e', 'process.kill(process.pid,"SIGTERM")']), 143);
});
test('symlink CLI cancellation reaches owned child', async () => {
  for (const [signal, expected] of [['SIGINT', 130], ['SIGTERM', 143]]) {
    const label = 'cancel-' + signal, marker = path.join(root, label + '.ready');
    const out = fs.openSync(path.join(root, label + '.stdout'), 'wx');
    const err = fs.openSync(path.join(root, label + '.stderr'), 'wx');
    const argv = [process.execPath, link, '--', process.execPath, '-e',
      'require("fs").writeFileSync(process.argv[1],String(process.pid));setInterval(()=>{},1000)', marker];
    const p = spawn(argv[0], argv.slice(1), {cwd:root, env:environment(label), stdio:['ignore',out,err]});
    let result;
    const done = new Promise((resolve, reject) => {
      p.once('error', reject);
      p.once('close', (status, termination) => {result={pid:p.pid,status,signal:termination}; resolve(result);});
    });
    try {
      for (let i=0; i<1000 && !fs.existsSync(marker) && !result; i++) await delay(10);
      assert(fs.existsSync(marker), 'payload ready before cancellation');
      const pid = Number(fs.readFileSync(marker, 'utf8'));
      assert(p.kill(signal));
      await done; record(label, argv, result);
      assert.equal(result.status, expected);
      assert.throws(() => process.kill(pid, 0), {code:'ESRCH'});
      console.log('CANCEL_REAP_ASSERT_REACHED', signal);
    } finally {
      if (!result) {p.kill('SIGTERM'); await done; record(label, argv, result);}
      fs.closeSync(out); fs.closeSync(err);
    }
  }
});
