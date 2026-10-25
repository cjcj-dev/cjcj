#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const [compiler, sdk, output] = process.argv.slice(2);
if (!compiler || !sdk || !output) throw new Error('usage: zx run.mjs COMPILER SDK OUTPUT');
fs.mkdirSync(output, {recursive: true});
const hash = file => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const env = {...process.env, CANGJIE_HOME: sdk, LD_LIBRARY_PATH:
  ['runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative', 'third_party/llvm/lib', 'tools/lib']
    .map(p => path.join(sdk, p)).join(':')};
const result = {compiler, compiler_sha256: hash(compiler), sdk, cases: [], rc: 0};
function run(label, command) {
  const child = spawnSync(command[0], command.slice(1), {cwd: output, env, encoding: 'utf8', timeout: 180000});
  const text = (child.stdout || '') + (child.stderr || '');
  fs.writeFileSync(path.join(output, label + '.log'), text);
  result.cases.push({label, command, rc: child.status, signal: child.signal, error: child.error?.message});
  return {rc: child.status, text};
}
try {
  for (const name of ['control', 'main', 'diagnostic']) {
    const source = path.join(import.meta.dirname, name + '.cj');
    const elf = path.join(output, name);
    const r = run(name + '.compile', [compiler, source, '-O2', '--diagnostic-format=noColor', '-o', elf]);
    result.cases.at(-1).source_sha256 = hash(source);
    if (/Internal Compiler Error|Assertion.*failed/i.test(r.text)) throw new Error('internal error at ' + name);
    if (name === 'diagnostic') {
      const passed = r.rc === 1 && /type.*(mismatch|match)|expected.*Int64|cannot.*String/i.test(r.text) &&
        /diagnostic.cj:\d+:[1-9]\d*/.test(r.text);
      console.log(`TARGET_ASSERT generic_type_diagnostic ${passed ? 'PASS' : 'FAIL'}`);
      if (!passed) throw new Error('generic diagnostic missing');
    } else {
      if (r.rc !== 0) throw new Error('compile failure at ' + name);
      result.cases.at(-1).elf_sha256 = hash(elf);
      const r2 = run(name + '.run', [elf]);
      const marker = name === 'main' ? 'generic_substitution' : 'generic_control';
      const passed = r2.rc === 0 && r2.text.includes(`ASSERT ${marker}=PASS`);
      console.log(`TARGET_ASSERT ${marker} ${passed ? 'PASS' : 'FAIL'}`);
      if (!passed) throw new Error('runtime invariant failed at ' + name);
    }
  }
} catch (e) { result.rc = 1; result.stop = e.message; }
fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify(result, null, 2) + '\n');
process.exitCode = result.rc;
