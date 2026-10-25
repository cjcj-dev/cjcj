#!/usr/bin/env zx
// Exercise the installed candidate through the real compiler driver and linker.
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';

const [compiler, sdk, output, arm = 'candidate'] = process.argv.slice(2);
if (!compiler || !sdk || !output || !['candidate', 'cut', 'restored'].includes(arm)) {
  throw new Error('usage: zx run.mjs COMPILER SDK OUTPUT [candidate|cut|restored]');
}
fs.mkdirSync(output, {recursive: true});
const hash = file => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const env = {...process.env, CANGJIE_HOME: sdk};
env.LD_LIBRARY_PATH = ['runtime/lib', 'lib'].map(p => path.join(sdk, p, 'linux_x86_64_cjnative'))
  .concat(['third_party/llvm/lib', 'tools/lib'].map(p => path.join(sdk, p))).join(':');
const widths = [['Int8', '-128', '127'], ['Int16', '-32768', '32767'],
  ['Int32', '-2147483648', '2147483647'], ['Int64', '-9223372036854775808', '9223372036854775807'],
  ['IntNative', '-9223372036854775808', '9223372036854775807']];
const record = {arm, compiler, compiler_sha256: hash(compiler), sdk, cases: [], assertions: [], not_run: []};
let failed = false;
function execute(label, cmd) {
  const start = Date.now();
  const child = spawnSync(cmd[0], cmd.slice(1), {env, cwd: output, encoding: 'utf8', timeout: 180000,
    maxBuffer: 8 * 1024 * 1024});
  const text = (child.stdout || '') + (child.stderr || '');
  fs.writeFileSync(path.join(output, label + '.log'), text);
  record.cases.push({label, command: cmd, rc: child.status, signal: child.signal,
    error: child.error?.message, wall_ms: Date.now() - start});
  fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify(record, null, 2) + '\n');
  return {rc: child.status, text};
}
function check(label, passed) {
  record.assertions.push({label, passed});
  console.log(`TARGET_ASSERT ${label} ${passed ? 'PASS' : 'FAIL'}`);
  if (!passed) failed = true;
}
function assertProcess(result, label) {
  if (result.rc !== 0 || /Internal Compiler Error|Assertion.*failed|Segmentation fault/i.test(result.text)) {
    throw new Error(`unknown product failure at ${label}; dependent cases stopped`);
  }
}
try {
  // An independent arithmetic control runs before the targeted boundary.
  for (const mode of ['throwing', 'wrapping', 'saturating']) {
    for (const name of ['control', 'constant_mod', 'dynamic_mod', 'dynamic_div', 'constant_div']) {
      const label = `${mode}.${name}`;
      const source = path.join(import.meta.dirname, name + '.cj');
      const elf = path.join(output, label);
      const r = execute(label + '.compile', [compiler, source, '-O2', '--int-overflow', mode,
        '--diagnostic-format=noColor', '-o', elf]);
      record.cases.at(-1).source_sha256 = hash(source);
      const expectedDivError = name === 'constant_div' && mode === 'throwing';
      const expectedCutError = name === 'constant_mod' && mode === 'throwing' && arm === 'cut';
      if (expectedDivError || expectedCutError) {
        check(label + '.overflow_diagnostic', r.rc === 1 && /overflow/i.test(r.text) &&
          r.text.includes(expectedDivError ? '/' : '%') && !/Internal Compiler Error|Assertion.*failed/i.test(r.text));
        if (!record.assertions.at(-1).passed) throw new Error(`expected diagnostic missing at ${label}`);
        // Record the invariant's red separately from the expected cut observation.
        if (expectedCutError) check(label + '.accepted', false);
        continue;
      }
      if (r.rc !== 0 && name === 'constant_mod' && mode === 'throwing' && /overflow/i.test(r.text)) {
        check(label + '.accepted', false);
        throw new Error(`target invariant failed at ${label}`);
      }
      assertProcess(r, label);
      record.cases.at(-1).elf_sha256 = hash(elf);
      if (name.startsWith('dynamic_')) {
        for (const [width, min, max] of widths) {
          const run = execute(label + '.' + width, [elf, width, min, '-1']);
          assertProcess(run, label + '.' + width);
          const expected = name === 'dynamic_mod' ? '0' : mode === 'throwing' ? 'overflow' : mode === 'saturating' ? max : min;
          check(label + '.' + width, run.text.includes(`ASSERT ${name}.${width}=${expected}\n`));
          if (!record.assertions.at(-1).passed) throw new Error(`target invariant failed at ${label}.${width}`);
        }
      } else {
        const run = execute(label + '.run', [elf]);
        assertProcess(run, label);
        if (name === 'control') check(label, run.text.includes('ASSERT ordinary_arithmetic=PASS'));
        else for (const [width, min, max] of widths) {
          const expected = name === 'constant_mod' ? '0' : mode === 'saturating' ? max : min;
          check(label + '.' + width, run.text.includes(`ASSERT ${name}.${width}=${expected}\n`));
        }
        if (failed && arm !== 'cut') throw new Error(`target invariant failed at ${label}`);
      }
    }
  }
} catch (e) {
  record.stop = e.message;
  failed = true;
} finally {
  record.rc = failed ? 1 : 0;
  fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify(record, null, 2) + '\n');
}
process.exitCode = record.rc;
