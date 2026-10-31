#!/usr/bin/env zx
// A real TempFileManager consumer; the caller builds Main with the selected
// option package. The interposer touches only its uniquely owned fixture root.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const [elf, workArg, expected = 'fixed'] = process.argv.slice(process.argv.findIndex(x => x.endsWith('.mjs')) + 1);
assert.ok(process.platform === 'linux' && process.arch === 'x64' &&
  path.isAbsolute(elf ?? '') && path.isAbsolute(workArg ?? ''));
assert.ok(['fixed', 'old'].includes(expected));
assert.ok(!fs.existsSync(workArg), 'new evidence root required');
fs.mkdirSync(workArg, {recursive: true});
const fixture = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../tests/temp_file_ownership');
const rows = [];
function run(name, argv, env) {
  const out = fs.openSync(path.join(workArg, name + '.stdout'), 'wx');
  const err = fs.openSync(path.join(workArg, name + '.stderr'), 'wx');
  const started = new Date().toISOString();
  const p = spawnSync(argv[0], argv.slice(1), {cwd: workArg, env, stdio: ['ignore', out, err], timeout: 60000});
  fs.closeSync(out); fs.closeSync(err);
  rows.push({name, argv, started, ended: new Date().toISOString(), pid: p.pid,
    rc: p.status, signal: p.signal, error: p.error?.message ?? null});
  fs.writeFileSync(path.join(workArg, 'commands.json'), JSON.stringify(rows, null, 2) + '\n');
  assert.equal(p.error, undefined, name); assert.equal(p.signal, null, name);
  return {rc: p.status, stdout: fs.readFileSync(path.join(workArg, name + '.stdout'), 'utf8'),
    stderr: fs.readFileSync(path.join(workArg, name + '.stderr'), 'utf8')};
}
const clean = {...process.env}; delete clean.LD_PRELOAD; delete clean.LD_AUDIT;
const tools = {...clean}; delete tools.LD_LIBRARY_PATH;
const so = path.join(workArg, 'mkdir-race.so');
assert.equal(run('hook-build', [process.env.CC ?? '/usr/bin/cc', '-std=c11', '-shared', '-fPIC', '-O2',
  '-Wall', '-Wextra', '-Werror', path.join(fixture, 'mkdir_race.c'), '-o', so], tools).rc, 0);
for (const race of [false, true]) {
  const root = path.join(workArg, race ? 'race' : 'control');
  fs.mkdirSync(path.join(root, 'tmp'), {recursive: true});
  fs.mkdirSync(path.join(root, 'output'));
  const r = run(race ? 'race' : 'control', [elf], {...clean, LD_PRELOAD: so,
    TEMP_OWNERSHIP_ROOT: root, TEMP_OWNERSHIP_RACE: race ? '1' : '0'});
  const expectRc = race && expected === 'old' ? 2 : 0;
  assert.equal(r.rc, expectRc);
  if (race) {
    assert.equal((r.stderr.match(/RACE_WINDOW /g) ?? []).length, 1);
    assert.match(r.stderr, /absent=1 mkdir=-1 errno=17 /);
    assert.match(r.stdout, expected === 'old'
      ? /TEMP_OWNERSHIP race=true distinct=false ownGone=true protected=false/
      : /TEMP_OWNERSHIP race=true distinct=true ownGone=true protected=true/);
    const other = fs.readFileSync(path.join(root, 'contended-path'), 'utf8');
    if (expected === 'fixed') assert.equal(fs.readFileSync(path.join(other, 'sentinel'), 'utf8'), 'other-process');
    else assert.ok(!fs.existsSync(other), 'old cross-owner deletion must be observed');
  } else {
    assert.ok(!r.stderr.includes('RACE_WINDOW'));
    assert.match(r.stdout, /TEMP_OWNERSHIP race=false distinct=true ownGone=true protected=true/);
  }
}
console.log(`TEMP_OWNERSHIP_GATE ${expected} control=0 race=${expected === 'old' ? 2 : 0}`);
