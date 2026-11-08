#!/usr/bin/env zx
// Fused interface lookup regression: compile main.cj with the candidate public
// compiler at -O0 and -O2, check the emitted LLVM IR per function and run the
// executables. Usage: zx run.mjs COMPILER SDK OUTPUT
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const here = path.dirname(new URL(import.meta.url).pathname);
const [compiler, sdk, output] = process.argv.slice(2);
if (!compiler || !sdk || !output) throw new Error('usage: zx run.mjs COMPILER SDK OUTPUT');
fs.mkdirSync(output, {recursive: true});
const env = {...process.env, CANGJIE_HOME: sdk, CANGJIE_PATH: sdk + '/modules/linux_x86_64_cjnative',
  LD_LIBRARY_PATH: ['runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative', 'third_party/llvm/lib', 'tools/lib']
    .map(p => path.join(sdk, p)).join(':')};
const source = path.join(here, 'main.cj');
const result = {compiler, sdk, source_sha256: createHash('sha256').update(fs.readFileSync(source)).digest('hex'),
  steps: [], assertions: []};
function run(label, command, cwd) {
  const child = spawnSync(command[0], command.slice(1), {cwd, env, encoding: 'utf8', timeout: 600000});
  const text = (child.stdout || '') + (child.stderr || '');
  fs.writeFileSync(path.join(output, label + '.log'), text);
  result.steps.push({label, command, rc: child.status, signal: child.signal, error: child.error?.message});
  return {rc: child.status, text};
}
function assert(name, passed, observed) {
  result.assertions.push({name, passed, observed});
  console.log(`ASSERT ${name} ${passed ? 'PASS' : 'FAIL'}`);
}
const llvmDis = ['third_party/llvm/bin/llvm-dis', 'tools/bin/llvm-dis'].map(p => path.join(sdk, p)).find(fs.existsSync);
function functions(ir) {
  const map = new Map();
  for (const body of ir.split(/^(?=define )/m).slice(1)) {
    const name = body.match(/^define [^@]*@("[^"]+"|[\w.$]+)/)?.[1] ?? '';
    map.set(name, body.slice(0, body.indexOf('\n}\n') + 2));
  }
  return map;
}
const find = (fns, id) => [...fns].filter(([name]) => name.includes(id.length + id)).map(([, body]) => body);
for (const opt of ['O0', 'O2']) {
  const dir = path.join(output, opt);
  fs.rmSync(dir, {recursive: true, force: true});
  fs.mkdirSync(path.join(dir, 'temps'), {recursive: true});
  const exe = path.join(dir, 'main');
  const compile = run(`${opt}.compile`, [compiler, source, '-' + opt, '--save-temps', path.join(dir, 'temps'),
    '--fno-chir-function-inlining', '-o', exe], dir);
  assert(`${opt}:compile`, compile.rc === 0, compile.rc);
  if (compile.rc !== 0) continue;
  const exec = run(`${opt}.run`, [exe], dir);
  assert(`${opt}:run`, exec.rc === 0 && exec.text.includes('typeinfo_fused_lookup OK'), exec.rc);
  // Inspect only backend inputs. The sibling .opt.bc has already lowered these
  // intrinsics and must not overwrite the same functions in the map below.
  const bcs = fs.readdirSync(path.join(dir, 'temps'), {recursive: true}).map(String)
    .filter(f => /typeinfo_fused_lookup\.(bc|ll)$/.test(f)).map(f => path.join(dir, 'temps', f));
  let ir = '';
  for (const f of bcs) {
    if (f.endsWith('.ll')) ir += fs.readFileSync(f, 'utf8');
    else if (llvmDis) ir += run(`${opt}.dis.${path.basename(f)}`, [llvmDis, f, '-o', '-'], dir).text;
  }
  result[`${opt}_ir_inputs`] = bcs;
  const fns = functions(ir);
  const fused = 'llvm.cj.get.mtable.func.outertype(', legacy = 'llvm.cj.get.mtable.func(',
    outer = 'llvm.cj.get.method.outertype(', vtable = 'llvm.cj.get.vtable.func(';
  const count = (bodies, s) => bodies.reduce((n, b) => n + b.split(s).length - 1, 0);
  const site = id => find(fns, id);
  const fusedSite = site('fusedSite'), plainSite = site('plainSite'), classSite = site('classSite'),
    loopSite = site('loopSite'), optionLoop = site('optionLoop'), throwingSite = site('throwingSite');
  assert(`${opt}:fusedSite one fused lookup, no separate outer lookup`, fusedSite.length > 0 &&
    count(fusedSite, fused) === 1 && count(fusedSite, outer) === 0 && count(fusedSite, legacy) === 0,
    {defs: fusedSite.length, fused: count(fusedSite, fused), outer: count(fusedSite, outer)});
  assert(`${opt}:plainSite keeps legacy mtable only`, plainSite.length > 0 && count(plainSite, legacy) === 1 &&
    count(plainSite, fused) === 0 && count(plainSite, outer) === 0, {defs: plainSite.length});
  assert(`${opt}:classSite keeps vtable path`, classSite.length > 0 && count(classSite, vtable) >= 1 &&
    count(classSite, fused) === 0, {defs: classSite.length});
  for (const [name, bodies] of [['loopSite', loopSite], ['optionLoop', optionLoop], ['throwingSite', throwingSite]]) {
    // The lookup stays at the dispatch inside the loop: not in the entry block.
    const entry = bodies.map(b => b.split(/\n\n|\n(?=[\w.$"-]+:)/)[0]);
    // A for-in loop also invokes generic Iterator.next through its vtable.
    // That independent class dispatch retains its own outer-TypeInfo lookup.
    const iteratorTI = '@"std.core:Iterator<typeinfo_fused_lookup:Shape<Int64>>.ti"';
    const outerLines = bodies.flatMap(b => b.split('\n').filter(line => line.includes(outer)));
    const iteratorOuter = name === 'loopSite' ? bodies.flatMap(b => b.split(/\n\n/))
      .filter(block => block.split('\n').some(line => line.includes(vtable) && line.includes(iteratorTI)))
      .flatMap(block => block.split('\n').filter(line => line.includes(outer) && line.includes(iteratorTI))) : [];
    if (name === 'loopSite' && opt === 'O0')
      assert(`${opt}:generic iterator retains vtable plus outer lookup`, iteratorOuter.length === 1,
        {iteratorOuter: iteratorOuter.length});
    assert(`${opt}:${name} per-iteration fused lookup`, bodies.length > 0 && count(bodies, fused) >= 1 &&
      count(entry, fused) === 0 && outerLines.length === iteratorOuter.length,
      {defs: bodies.length, fused: count(bodies, fused), entry: count(entry, fused),
        outer: outerLines.length, independentIteratorOuter: iteratorOuter.length});
  }
}
result.passed = result.assertions.length > 0 && result.assertions.every(a => a.passed);
fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify(result, null, 2) + '\n');
console.log(`typeinfo_fused_lookup ${result.passed ? 'PASS' : 'FAIL'}`);
process.exit(result.passed ? 0 : 1);
