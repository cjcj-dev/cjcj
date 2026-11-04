#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const [compiler, sdk, output] = process.argv.slice(2);
if (!compiler || !sdk || !output) throw new Error('usage: zx run.mjs COMPILER SDK OUTPUT');
fs.mkdirSync(output, {recursive: true});
const env = {...process.env, CANGJIE_HOME: sdk, CANGJIE_PATH: sdk + '/modules/linux_x86_64_cjnative',
  LD_LIBRARY_PATH: ['runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative', 'third_party/llvm/lib', 'tools/lib']
    .map(p => path.join(sdk, p)).join(':')};
const compilerEnv = {...env, LD_LIBRARY_PATH: process.env.COMPILER_LD_LIBRARY_PATH || env.LD_LIBRARY_PATH};
const result = {compiler, sdk, cases: [], rc: 0};
function run(label, command) {
  const child = spawnSync(command[0], command.slice(1), {cwd: output, env: label.endsWith('.compile') ? compilerEnv : env, encoding: 'utf8', timeout: 180000});
  const text = (child.stdout || '') + (child.stderr || '');
  fs.writeFileSync(path.join(output, label + '.log'), text);
  result.cases.push({label, command, rc: child.status, signal: child.signal, error: child.error?.message});
  return {rc: child.status, text};
}
for (const [name, constants, assertions] of [['control', 4, 1], ['full_width', 8, 8]]) {
  const source = path.join(import.meta.dirname, name + '.cj');
  const elf = path.join(output, name);
  const compiled = run(name + '.compile', [compiler, source, '-O0', '--chir-opt-debug', '--diagnostic-format=noColor', '-o', elf]);
  const evaluated = (compiled.text.match(/debug: consteval .* (?:replaced|evaluated) initializer function/g) || []).length;
  console.log(`CONST_EVAL ${name} evaluated=${evaluated} expected=${constants} compile_rc=${compiled.rc}`);
  if (compiled.rc !== 0 || evaluated !== constants || /not evaluated successfully/.test(compiled.text)) {
    result.rc = 1;
    continue;
  }
  const inputs = name === 'control' ? ['true', 'false', '255', '0'] :
    ['256', '257', '258', '-1', '9223372036854775808', '1', '18446744073709551615', '9223372036854775809'];
  const executed = run(name + '.run', [elf, ...inputs]);
  console.log(executed.text.trimEnd());
  const passed = (executed.text.match(/^ASSERT .* PASS$/gm) || []).length;
  if (executed.rc !== 0 || passed !== assertions) result.rc = 1;
}
fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify(result, null, 2) + '\n');
process.exitCode = result.rc;
