#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

function option(name, fallback = '') {
  const index = process.argv.indexOf(name);
  return index < 0 ? fallback : process.argv[index + 1];
}

const sourceRoot = path.resolve(option('--source-root', path.join(import.meta.dirname, '..')));
const compiler = option('--compiler');
const outputRoot = option('--out');
const expectation = option('--expect', 'green');
if (!['green', 'box-cut', 'step5-cut'].includes(expectation)) {
  throw new Error(`unsupported --expect value: ${expectation}`);
}
if (Boolean(compiler) !== Boolean(outputRoot)) {
  throw new Error('--compiler and --out must be provided together');
}

const expected = {
  green: {box: 'typed', step5: 'typed'},
  'box-cut': {box: 'raw', step5: 'typed'},
  'step5-cut': {box: 'typed', step5: 'raw'},
}[expectation];
const results = [];

function record(name, ok, detail) {
  results.push({name, ok, detail});
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}: ${detail}`);
}

function between(text, start, end, label) {
  const first = text.indexOf(start);
  const last = text.indexOf(end, first + start.length);
  if (first < 0 || last < 0) throw new Error(`cannot locate ${label}`);
  return text.slice(first, last + end.length);
}

function checkSource() {
  const boxFile = path.join(sourceRoot, 'packages/codegen/src/TypeCastImpl.cj');
  const packageFile = path.join(sourceRoot, 'packages/codegen/src/EmitPackageIR.cj');
  const box = between(fs.readFileSync(boxFile, 'utf8'),
    'if (IsThisArgOfStructMethod(sourceValue))', 'return tmp', 'erased Box branch');
  const step5 = between(fs.readFileSync(packageFile, 'utf8'),
    'if (!item.isCalleeMutOrCtor)', '        }\n    }\n}', 'withoutTI step 5');
  const flatBox = box.replaceAll(/\s+/g, '');
  const flatStep5 = step5.replaceAll(/\s+/g, '');
  const boxTyped = flatBox.includes(
    'CallGCWriteGenericPayloadFromSrc(tmp,sourceRawValue,size,typeInfo)') || flatBox.includes(
    'CallGCWriteGenericPayload(tmp,sourceRawValue,size)');
  const boxRaw = flatBox.includes(
    'CreateMemCpy(payloadPtr,0u32,sourceRawValue,0u32,size)');
  const boxTypeInfo = flatBox.includes('lettypeInfo=irBuilder.CreateTypeInfo(sourceType)') &&
    flatBox.includes('CallClassIntrinsicAlloc(ArrayList<LLVMValueRef>([typeInfo,size]))');
  const step5Typed = flatStep5.includes(
    'CallGCWriteGenericPayloadFromSrc(basePtr,payloadPtr,size32,thisParamTypeInfo)') || flatStep5.includes(
    'CallGCReadGeneric(basePtr,thisParamWithTI,payloadPtr,size32)');
  const step5Raw = flatStep5.includes(
    'CreateMemCpy(thisParamWithoutTI,0u32,payloadPtr,0u32,size32)');

  record('source.p1p0.box', expected.box === 'typed'
    ? boxTyped && !boxRaw && boxTypeInfo
    : boxRaw && !boxTyped,
  `expected=${expected.box} dispatcher=${Number(boxTyped)} raw=${Number(boxRaw)} typeinfo=${Number(boxTypeInfo)}`);
  record('source.p1p1.step5', expected.step5 === 'typed'
    ? step5Typed && !step5Raw
    : step5Raw && !step5Typed,
  `expected=${expected.step5} dispatcher=${Number(step5Typed)} raw=${Number(step5Raw)}`);
}

function functionSlices(ir, terms) {
  const definitions = [...ir.matchAll(/^define\b[^\n]*\{[\s\S]*?^}/gm)].map(match => match[0]);
  return definitions.filter(definition => terms.every(term => definition.includes(term)));
}

function compileFixture(name) {
  const fixture = path.join(sourceRoot, 'scripts/erased_dynpayload_fixtures', `${name}.cj`);
  const armRoot = path.resolve(outputRoot, name);
  const temps = path.join(armRoot, 'temps');
  fs.mkdirSync(temps, {recursive: true});
  const args = [fixture, '--output-type=staticlib', '--dump-ir', '--dump-to-screen',
    '--save-temps', temps, '-o', path.join(armRoot, `${name}.a`)];
  const run = spawnSync(path.resolve(compiler), args, {encoding: 'utf8', env: process.env});
  fs.writeFileSync(path.join(armRoot, 'compile.log'), `${run.stdout || ''}${run.stderr || ''}`);
  fs.writeFileSync(path.join(armRoot, 'compile.rc'), `${run.status ?? 255}\n`);
  record(`compile.${name}`, run.status === 0, `rc=${run.status ?? 255}`);
  return `${run.stdout || ''}${run.stderr || ''}`;
}

function checkIR() {
  const rangeIR = compileFixture('range_provider');
  const rangeFunctions = functionSlices(rangeIR, ['Range', 'provide', '$withoutTI']);
  const rangeBody = rangeFunctions.join('\n');
  const boxTyped = rangeBody.includes('llvm.cj.gcwrite.generic.payload');
  const boxRaw = rangeBody.includes('llvm.memcpy.p1i8.p0i8');
  record('ir.p1p0.box', rangeFunctions.length > 0 && (expected.box === 'typed'
    ? boxTyped && !boxRaw
    : boxRaw && !boxTyped),
  `functions=${rangeFunctions.length} expected=${expected.box} helper=${Number(boxTyped)} raw=${Number(boxRaw)}`);

  const lazyIR = compileFixture('externally_locked_lazy_reverse');
  const lazyFunctions = functionSlices(lazyIR, ['ExternallyLockedLazy', 'compute', '$withoutTI']);
  const lazyBody = lazyFunctions.join('\n');
  const step5Typed = lazyBody.includes('llvm.cj.gcread.generic');
  const step5Raw = lazyBody.includes('llvm.memcpy.p1i8.p1i8');
  record('ir.p1p1.step5', lazyFunctions.length > 0 && (expected.step5 === 'typed'
    ? step5Typed && !step5Raw
    : step5Raw && !step5Typed),
  `functions=${lazyFunctions.length} expected=${expected.step5} helper=${Number(step5Typed)} raw=${Number(step5Raw)}`);
}

checkSource();
if (compiler) checkIR();
if (outputRoot) {
  fs.mkdirSync(path.resolve(outputRoot), {recursive: true});
  fs.writeFileSync(path.resolve(outputRoot, 'results.json'), `${JSON.stringify(results, null, 2)}\n`);
}
process.exitCode = results.some(result => !result.ok) ? 1 : 0;
