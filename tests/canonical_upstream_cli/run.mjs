#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';

const [compilerArg, sdkArg, outputArg, arm = 'candidate'] = process.argv.slice(2);
if (!compilerArg || !sdkArg || !outputArg || !['candidate', 'cut', 'restored'].includes(arm)) {
  throw new Error('usage: zx run.mjs COMPILER SDK NEW_OUTPUT [candidate|cut|restored]');
}
const compiler = fs.realpathSync(compilerArg), sdk = fs.realpathSync(sdkArg);
const output = path.resolve(outputArg);
fs.mkdirSync(output); // Refuse to overwrite a prior execution, including a failed one.
const hash = file => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const env = {...process.env, CANGJIE_HOME: sdk, LD_LIBRARY_PATH:
  ['runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative', 'third_party/llvm/lib', 'tools/lib']
    .map(p => path.join(sdk, p)).join(':')};
const result = {arm, compiler, compiler_sha256: hash(compiler), sdk, commands: [], assertions: [], rc: 1};
const cases = [
  ['control', []], ['resource_bound', []], ['array_copy', ['4099']],
  ['alias_store', ['41']], ['match_guard', []],
];
function save() { fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify(result, null, 2) + '\n'); }
function run(label, argv) {
  const child = spawnSync(argv[0], argv.slice(1), {cwd: output, env, encoding: 'utf8',
    timeout: 180000, maxBuffer: 8 * 1024 * 1024});
  const text = (child.stdout || '') + (child.stderr || '');
  fs.writeFileSync(path.join(output, label + '.log'), text);
  result.commands.push({label, argv, rc: child.status, signal: child.signal,
    error: child.error?.message ?? null});
  save();
  return {child, text};
}
try {
  for (const optimization of ['-O0', '-O2']) {
    for (const [name, args] of cases) {
      const label = optimization.slice(1) + '.' + name;
      const source = path.join(import.meta.dirname, name + '.cj');
      const elf = path.join(output, label);
      const input = {label, source, source_sha256: hash(source)};
      const compiled = run(label + '.compile', [compiler, source, optimization,
        '--diagnostic-format=noColor', '-o', elf]);
      Object.assign(result.commands.at(-1), input);
      if (compiled.child.status !== 0) throw new Error('compile failed: ' + label);
      // Match reachability is observable at the real compiler diagnostic boundary.
      if (name === 'match_guard') {
        const passed = !/unreachable/i.test(compiled.text);
        result.assertions.push({label: label + '.reachable', passed});
        console.log(`TARGET_ASSERT ${label}.reachable ${passed ? 'PASS' : 'FAIL'}`);
        if (!passed) throw new Error('reachable match case diagnosed unreachable');
      }
      const elfSha = hash(elf);
      const ran = run(label + '.run', [elf, ...args]);
      result.commands.at(-1).elf_sha256 = elfSha;
      const passed = ran.child.status === 0 && ran.text.split(/\r?\n/).includes(`ASSERT ${name}=PASS`);
      result.assertions.push({label, passed});
      console.log(`TARGET_ASSERT ${label} ${passed ? 'PASS' : 'FAIL'}`);
      if (!passed) throw new Error('consumer invariant failed: ' + label);
    }
  }
  result.rc = 0;
} catch (error) {
  result.stop = error.message;
} finally {
  save();
}
process.exitCode = result.rc;
