#!/usr/bin/env zx
// Bounded real-upstream regression. Reuse a retained failed case's ELF and .so;
// never write its original work directory or rerun the full source inventory.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {writeFileSync} from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const [inputs, sdk, originalBinary, baselineAdapter, output] = process.argv.slice(2);
if (!output) throw Error('Usage: zx adapt-loader.integration.mjs WORKTREES SDK RETAINED_BINARY BASELINE_ADAPTER NEW_OUTPUT');
const here = path.dirname(fileURLToPath(import.meta.url));
const relative = 'src/tests/13_multi_language_interoperability/01_c_interoperability/03_type_mapping/02_pointers/a04/test_a04_51';
const source = path.join(inputs, 'cangjie_test/Conformance/Compiler/testsuite', relative);
const baseEnv = {...process.env, PYTHONDONTWRITEBYTECODE: '1'};
assert.equal(baseEnv.CANGJIE_HOME, sdk, 'run with the selected private SDK environment');
assert.ok(baseEnv.LD_LIBRARY_PATH, 'retain the selected SDK loader paths');
await fs.mkdir(output); // Existing evidence must not be overwritten.
const results = [];
function invoke(argv, cwd, env, name) {
  const started = new Date().toISOString();
  const child = spawnSync(argv[0], argv.slice(1), {cwd, env, encoding: 'utf8', timeout: 90000, maxBuffer: 8 * 1024 * 1024});
  const result = {name, argv, cwd, env: {CANGJIE_HOME: env.CANGJIE_HOME, LD_LIBRARY_PATH: env.LD_LIBRARY_PATH},
    started, ended: new Date().toISOString(), rc: child.status, signal: child.signal, error: child.error?.message};
  writeFileSync(path.join(output, name + '.stdout'), child.stdout || '');
  writeFileSync(path.join(output, name + '.stderr'), child.stderr || '');
  results.push(result);
  assert.equal(child.status, 0, JSON.stringify(result) + '\n' + child.stderr);
  assert.equal(child.signal, null);
  return child.stdout;
}
try {
  for (const [name, adapter, explicitLibrary] of [
    ['baseline-red', baselineAdapter, false],
    ['configured-control', baselineAdapter, true],
    ['restored', path.join(here, 'adapt.mjs'), false],
  ]) {
    const root = path.join(output, name);
    await fs.mkdir(root);
    // Public adapter creates only its existing mutable harness copies.
    const selected = JSON.parse(invoke([process.execPath, adapter, inputs, root], here, baseEnv, name + '-prepare'));
    const bin = path.join(root, 'bin');
    await fs.mkdir(bin);
    await fs.copyFile(originalBinary, path.join(bin, path.basename(originalBinary)));
    await fs.copyFile(path.join(path.dirname(originalBinary), 'libfunc.so'), path.join(bin, 'libfunc.so'));
    const env = {...baseEnv};
    if (explicitLibrary) env.LD_LIBRARY_PATH += path.delimiter + bin;
    invoke(['/usr/bin/python3', '-B', path.join(selected.harness, 'harness.py'),
      '--test-root', source, '--work-dir', path.join(root, 'work'), '--binary-output-path', bin,
      '--test-run-output-path', path.join(root, 'artifacts'), '--run-mode', 'execute',
      '--cjc', path.join(sdk, 'bin/cjc'), '--comp-threads', '1', '--exec-threads', '1',
      '--base-timeout', '30', '--log-file', path.join(root, 'results.log'), '--no-color', '--log-mode', 'short'],
      selected.harness, env, name + '-execute');
    const raw = JSON.parse(await fs.readFile(path.join(root, 'results.log.json'), 'utf8'));
    const cases = raw.filter(x => x.test_path);
    assert.equal(cases.length, 1, 'exact original upstream case, no source filter expansion');
    const row = cases[0];
    results.push({name: name + '-verdict', status: row.result, executeLog: row.execute_log});
    if (name === 'baseline-red') {
      assert.equal(row.result, 'ERRORED');
      assert.match(row.execute_log, /error while loading shared libraries: libfunc\.so:/);
      assert.match(row.execute_log.replace(/\x1b\[[0-9;]*m/g, ''), /return code:\s*127/);
    } else {
      assert.equal(row.result, 'PASSED', row.execute_log);
      assert.match(row.execute_log.replace(/\x1b\[[0-9;]*m/g, ''), /return code:\s*0/);
    }
  }
  console.log('ORIGINAL_CASE baseline=127 configured_control=0 restored=0; full_suite=NOT_RUN');
} finally {
  await fs.writeFile(path.join(output, 'commands.json'), JSON.stringify(results, null, 2) + '\n');
}
