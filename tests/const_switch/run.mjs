#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const [compiler, sdk, output] = process.argv.slice(2);
if (!compiler || !sdk || !output) throw new Error('usage: zx run.mjs COMPILER SDK OUTPUT');
fs.mkdirSync(output, {recursive: true});
const env = {...process.env, CANGJIE_HOME: sdk, CANGJIE_PATH: sdk + '/modules/linux_x86_64_cjnative',
  LD_LIBRARY_PATH: ['runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative', 'third_party/llvm/lib', 'tools/lib']
    .map(p => path.join(sdk, p)).join(':')};
const compilerEnv = {...env, LD_LIBRARY_PATH: process.env.COMPILER_LD_LIBRARY_PATH || env.LD_LIBRARY_PATH};
const result = {compiler, sdk, cases: [], wiring: [], rc: 0};
function run(label, command) {
  const started = new Date().toISOString();
  const child = spawnSync(command[0], command.slice(1), {cwd: output, env: label.endsWith('.compile') ? compilerEnv : env, encoding: 'utf8', timeout: 180000});
  const text = (child.stdout || '') + (child.stderr || '');
  fs.writeFileSync(path.join(output, label + '.log'), text);
  result.cases.push({label, command, started, ended: new Date().toISOString(), rc: child.status, signal: child.signal, error: child.error?.message});
  return {rc: child.status, text};
}
// These dumps bracket RunConstantEvaluation in CodeGenBridge. Require real
// initializer calls before interpretation and literal globals afterwards.
function inspect(name, globals, selectors) {
  const dir = path.join(output, name + '_CHIR');
  const files = fs.existsSync(dir) ? fs.readdirSync(dir) : [];
  const read = suffix => {
    const matches = files.filter(f => f.endsWith('_' + suffix + '.chirtxt'));
    if (matches.length !== 1) throw Error('expected one ' + suffix + ' CHIR dump');
    return fs.readFileSync(path.join(dir, matches[0]), 'utf8');
  };
  const before = read('ClosureConversion'), after = read('CFFIFuncWrapper');
  const vars = text => text.split('vars===============================')[1]?.split('==========================funcs')[0] ?? '';
  const functions = text => text.split(/(?=^.*\bFunc )/m).slice(1);
  const beforeFuncs = functions(before), afterFuncs = functions(after);
  const constants = globals.map(global => {
    const find = text => vars(text).split('\n').find(line => line.includes('srcCodeIdentifier: ' + global + ','));
    const oldLine = find(before) ?? '', newLine = find(after) ?? '';
    const initializer = oldLine.match(/ = ([^ ]+)\(\)/)?.[1];
    const oldBody = beforeFuncs.find(body => body.includes('Func ' + initializer + '(')) ?? '';
    const literal = newLine.match(/ = (-?\d+)i\b/)?.[1];
    return {global, initializer, literal, callBefore: /\bApply\(/.test(oldBody),
      removedAfter: !!initializer && !afterFuncs.some(body => body.includes('Func ' + initializer + '(')),
      oldLine, newLine};
  });
  const switches = selectors.map(selector => {
    const body = beforeFuncs.find(body => body.split('{ Block Group:')[0].includes('srcCodeIdentifier: ' + selector + ',')) ?? '';
    return {selector, switchBefore: /\bMultiBranch\(/.test(body)};
  });
  return {name, constants, switches, ok: constants.every(c => c.initializer && c.literal !== undefined && c.callBefore && c.removedAfter) && switches.every(s => s.switchBefore)};
}
for (const [name, globals, selectors, assertions] of [
  ['control', ['boolTrue', 'boolFalse', 'byteMax', 'byteZero'], ['select8'], 1],
  ['full_width', ['wide256', 'wide257', 'wideDefault', 'negative', 'highBit', 'lowBit', 'allBits', 'highDefault'], ['select16', 'selectSigned', 'select64'], 8],
]) {
  const source = path.join(import.meta.dirname, name + '.cj');
  const elf = path.join(output, name);
  const compiled = run(name + '.compile', [compiler, source, '-O2', '--fno-chir-function-inlining', '--dump-chir', '--diagnostic-format=noColor', '-o', elf]);
  if (compiled.rc !== 0) { result.rc = 1; continue; }
  result.cases.at(-1).elf_sha256 = createHash('sha256').update(fs.readFileSync(elf)).digest('hex');
  let wiring;
  try { wiring = inspect(name, globals, selectors); }
  catch (error) { wiring = {name, ok: false, error: error.message}; }
  result.wiring.push(wiring);
  console.log('CONST_EVAL ' + JSON.stringify(wiring));
  if (!wiring.ok) result.rc = 1;
  const inputs = name === 'control' ? ['true', 'false', '255', '0'] :
    ['256', '257', '258', '-1', '9223372036854775808', '1', '18446744073709551615', '9223372036854775809'];
  const executed = run(name + '.run', [elf, ...inputs]);
  console.log(executed.text.trimEnd());
  const passed = (executed.text.match(/^ASSERT .* PASS$/gm) || []).length;
  if (executed.rc !== 0 || passed !== assertions) result.rc = 1;
}
fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify(result, null, 2) + '\n');
process.exitCode = result.rc;
