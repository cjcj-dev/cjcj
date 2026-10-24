#!/usr/bin/env zx
import {spawnSync} from 'node:child_process';
import {mkdirSync, readdirSync, readFileSync, writeFileSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

// Port the fixed af008 finalizer CHIR assertions, using the caller's installed
// compiler and resource environment. This is a finite frontend test, not core IR.
const [compilerArg, outputArg, readerArg] = process.argv.slice(2);
if (!compilerArg || !outputArg) throw new Error('usage: run.mjs INSTALLED_CJC NEW_OUTPUT [PRODUCT_CHIR_READER]');
const compiler = resolve(compilerArg), output = resolve(outputArg);
const fixtures = dirname(fileURLToPath(import.meta.url));
mkdirSync(output); // Never overwrite an earlier arm.
const results = [];
const save = () => writeFileSync(join(output, 'results.json'), JSON.stringify(results, null, 2) + '\n');

function functions(text) {
  const bodies = new Map();
  for (const match of text.matchAll(/^[^\n]*\bFunc (@[^\s(]+)\(/gm)) {
    const end = text.indexOf('\n}\n', match.index + match[0].length);
    if (end >= 0) bodies.set(match[1], text.slice(match.index, end + 3));
  }
  return bodies;
}
const calls = body => [...body.matchAll(/Apply\([^\n]*?(@[^\s,)]+)/g)].map(m => m[1]);
function reaches(name, bodies, seen = new Set()) {
  if (seen.has(name) || !bodies.has(name)) return false;
  seen.add(name);
  const body = bodies.get(name);
  return body.includes('Intrinsic(registerFinalizer,') || calls(body).some(callee => reaches(callee, bodies, seen));
}
const initializer = (bodies, name) => [...bodies].find(([, body]) => body.includes(`srcCodeIdentifier: gv$_${name},`)) ?? ['', ''];
function check(name, phase, text) {
  const bodies = functions(text), checks = {};
  if (name !== 'control') {
    const root = [...bodies.values()].find(body => body.includes('declaredParent: @_CNat6ObjectE, kind: classConstructor')) ?? '';
    const lines = root.split('\n').map(line => line.trim()).filter(Boolean);
    const exits = lines.map((line, i) => line.startsWith('Exit(') ? i : -1).filter(i => i >= 0);
    checks.root_event_before_normal_exit = exits.length > 0 && exits.every(i => i > 0 && lines[i - 1].includes('Intrinsic(registerFinalizer,'));
    const constructors = [...bodies].filter(([, body]) => body.includes('kind: classConstructor') && body !== root);
    if (phase === 'raw') checks.one_constructor_edge_per_derived_body = constructors.length > 0 && constructors.every(([, body]) => calls(body).filter(call => call.includes('<init>')).length === 1);
    checks.derived_constructor_reaches_root_event = constructors.length > 0 && constructors.every(([symbol]) => reaches(symbol, bodies));
  }
  if (phase === 'opt' && ['const_finalized', 'const_nested', 'const_temporary'].includes(name)) {
    const globalName = {const_finalized: 'instance', const_nested: 'nested', const_temporary: 'answer'}[name];
    const [symbol, body] = initializer(bodies, globalName);
    checks.const_batch_retains_runtime_event = Boolean(body) && reaches(symbol, bodies);
    if (name !== 'const_temporary') {
      const [, shared] = initializer(bodies, 'shared');
      checks.shared_global_keeps_identity = Boolean(shared) && !shared.includes('Allocate(Class-') && new RegExp(`Load\\(@[^\\n]*${globalName}`).test(shared);
    }
  }
  if (phase === 'opt' && name === 'const_plain') {
    const [, body] = initializer(bodies, 'instance');
    checks.plain_const_still_materializes = body.includes('Allocate(Class-') && calls(body).length === 0 && !body.includes('registerFinalizer');
  }
  if (phase === 'opt' && name === 'control') checks.scalar_const_still_folds = text.split('\n').some(line => line.includes('= 41i //') && line.includes('srcCodeIdentifier: answer,'));
  return checks;
}

function run(argv, directory, label) {
  const started = new Date().toISOString();
  const result = spawnSync(argv[0], argv.slice(1), {cwd: directory, env: process.env, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024, timeout: 300000});
  writeFileSync(join(directory, `${label}.stdout`), result.stdout ?? '');
  writeFileSync(join(directory, `${label}.stderr`), result.stderr ?? '');
  return {argv, started, finished: new Date().toISOString(), rc: result.status, signal: result.signal, error: result.error?.message ?? null};
}

let failed = false;
for (const name of ['root', 'delegated', 'implicit', 'const_finalized', 'const_nested', 'const_temporary', 'const_plain', 'control']) {
  for (const phase of ['raw', 'opt']) for (const optimization of ['O0', 'O2']) {
    const directory = join(output, `${name}-${phase}-${optimization}`);
    mkdirSync(directory);
    const binary = join(directory, 'output.chir');
    const command = run([compiler, join(fixtures, `${name}.cj`), '--no-prelude', '--experimental', '--output-type=staticlib', `-${optimization}`, '--jobs', '1', `--emit-chir=${phase}`, '--dump-chir', '-o', binary], directory, 'compile');
    const row = {name, phase, optimization, command, checks: {}, status: 'NOT_RUN'};
    results.push(row); save();
    if (command.rc !== 0 || command.signal || command.error) { failed = true; continue; }
    const dump = join(directory, 'output_CHIR');
    let artifacts = [];
    try { artifacts = readdirSync(dump).filter(path => path.endsWith(phase === 'raw' ? 'AST_CHIR.chirtxt' : 'EraseUselessDebugExpr.chirtxt')); } catch (error) { row.artifactError = error.message; }
    if (artifacts.length !== 1) { failed = true; save(); continue; }
    row.artifact = join(dump, artifacts[0]);
    row.checks = check(name, phase, readFileSync(row.artifact, 'utf8'));
    row.status = Object.values(row.checks).every(Boolean) ? 'PASS' : 'FAIL';
    if (phase === 'raw' && name === 'control') row.status = 'COMPILE_CONTROL';
    if (readerArg && (name === 'root' || (name === 'control' && phase === 'opt'))) {
      row.reader = run([resolve(readerArg), binary, name === 'control' ? 'scalar' : 'root'], directory, 'reader');
      const body = readFileSync(join(directory, 'reader.stdout'), 'utf8');
      row.checks.serialization_reader = row.reader.rc === 0 && !row.reader.signal && body.includes('TARGET ');
      if (!row.checks.serialization_reader) row.status = 'FAIL';
    }
    if (row.status === 'FAIL') failed = true;
    for (const [key, pass] of Object.entries(row.checks)) console.log(`TARGET ${name}/${phase}/${optimization} ${key}=${pass ? 'PASS' : 'FAIL'}`);
    save();
  }
}
process.exitCode = failed ? 1 : 0;
