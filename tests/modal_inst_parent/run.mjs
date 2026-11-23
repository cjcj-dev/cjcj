#!/usr/bin/env node
// Usage: node run.mjs /absolute/bin/cjc /new/output-dir
// GetInstParentType (packages/chir/src/Utils.cj) must pick the instantiated parent whose parameters match the
// call by data type when the declared parameter carries a Local Mode modal the argument does not (cjcj::mangle and
// cjcj::modules, RC Stage 2). Each fixture is compiled with the given compiler and its program must exit 0.
// The mismatching call is reached at -O2 (the cjpm `compile-option`); the default level keeps the same source as a
// control that compiles on either side of the fix.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const [compiler, root] = process.argv.slice(2);
assert([compiler, root].every(p => p && path.isAbsolute(p)), 'usage: node run.mjs /absolute/bin/cjc /new/output-dir');
fs.mkdirSync(root);
const here = path.dirname(fileURLToPath(import.meta.url));
// The program loads the runtime of the SDK that owns the compiler (envsetup.sh LD_LIBRARY_PATH).
const sdk = path.dirname(path.dirname(compiler));
const arch = {x64: 'x86_64', arm64: 'aarch64'}[process.arch];
const runEnv = {...process.env, LD_LIBRARY_PATH: [path.join(sdk, 'runtime/lib', `linux_${arch}_cjnative`),
  path.join(sdk, 'tools/lib'), process.env.LD_LIBRARY_PATH].filter(Boolean).join(path.delimiter)};
const failures = [];

function check(name, flags) {
  const label = [name, ...flags].join('').replace(/[^A-Za-z0-9_]/g, '_');
  const cwd = path.join(root, label);
  fs.mkdirSync(cwd);
  const source = path.join(here, name + '.cj'), program = path.join(cwd, name);
  const argv = [...flags, source, '-o', program];
  const build = spawnSync(compiler, argv, {cwd, encoding: 'utf8'});
  if (build.error) throw build.error;
  const run = build.status === 0 ? spawnSync(program, [], {cwd, env: runEnv, encoding: 'utf8'}) : null;
  if (run?.error) throw run.error;
  const unmatched = /instantiated parent type of callee is not available/.test(build.stdout + build.stderr);
  fs.writeFileSync(path.join(cwd, 'result.json'), JSON.stringify({compiler, argv, rc: build.status,
    signal: build.signal, unmatched, stdout: build.stdout, stderr: build.stderr, runRc: run?.status ?? null,
    runSignal: run?.signal ?? null}, null, 2));
  const ok = build.status === 0 && run.status === 0;
  console.log(label, 'compile rc', build.status, 'run rc', run?.status ?? 'NOT_RUN',
    unmatched ? 'UNMATCHED_PARENT' : '', ok ? 'PASS' : 'FAIL');
  if (!ok) failures.push(label);
}

check('subclass_equatable_key', []);
check('subclass_equatable_key', ['-O2']);
assert.deepEqual(failures, []);
