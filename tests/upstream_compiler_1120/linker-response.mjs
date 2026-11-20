#!/usr/bin/env zx
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const [compiler, work] = argv._.map(String);
if (!compiler || !work || ![compiler, work].every(p => path.isAbsolute(p))) {
  throw Error('usage: zx linker-response.mjs /absolute/bin/cjc /new/work');
}

const windows = process.platform === 'win32';
const source = path.join(import.meta.dirname, 'local_type_control.cj');
const count = 6100;
const flags = Array(count).fill('-L.').join(' ');
// The public compiler receives one argument below the Windows process limit;
// the linker would receive thousands of individually quoted arguments.
assert(flags.length < 25000 && count * ' "-L."'.length > 32767);
fs.mkdirSync(work);

function run(root, name, command, args) {
  const child = spawnSync(command, args, {cwd: root, encoding: 'utf8', maxBuffer: 4 * 1024 * 1024});
  fs.writeFileSync(path.join(root, `${name}.json`), JSON.stringify({command, args, rc: child.status,
    signal: child.signal, error: child.error?.message}, null, 2));
  fs.writeFileSync(path.join(root, `${name}.stdout`), child.stdout ?? '');
  fs.writeFileSync(path.join(root, `${name}.stderr`), child.stderr ?? '');
  assert.equal(child.status, 0, `${name}: ${child.error ?? child.stderr}`);
  return child.stdout;
}

for (const [name, long, save] of [['short', false, false], ['long', true, false], ['saved', true, true]]) {
  const root = path.join(work, name);
  fs.mkdirSync(root);
  const saveDir = path.join(root, 'saved intermediates');
  if (save) fs.mkdirSync(saveDir);
  const executable = path.join(root, windows ? 'sample.exe' : 'sample');
  const stdout = run(root, 'cjc', compiler, ['-V', source, '-o', executable,
    ...(long ? ['--link-options', flags] : []), ...(save ? ['--save-temps', saveDir] : [])]);
  const response = stdout.match(/^"[^"\r\n]*\bld\.lld\.exe" "@([^"\r\n]+\.rsp)"\r?$/im)?.[1];
  assert.equal(Boolean(response), windows && long, `${name}: effective linker command`);
  if (response) {
    assert.equal(fs.existsSync(response), save, `${name}: response file lifetime`);
    if (save) {
      const body = fs.readFileSync(response, 'utf8');
      assert.equal(body.split(/\r?\n/).filter(line => line === '"-L."').length, count);
    }
  }
  assert.equal(run(root, 'sample', executable, []).trim(), '42');
  console.log(`PASS ${name}`);
}
