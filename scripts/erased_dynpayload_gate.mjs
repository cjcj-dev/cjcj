#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

function option(name, fallback = '') {
  const index = process.argv.indexOf(name);
  return index < 0 ? fallback : process.argv[index + 1];
}

const sourceRoot = path.resolve(option('--source-root', path.join(import.meta.dirname, '..')));
const fixtureRoot = path.resolve(option('--fixture-root', sourceRoot));
const compiler = option('--compiler');
const outputRoot = option('--out');
const expectation = option('--expect', 'green');
const baselineReport = option('--baseline-report');
const candidateReport = option('--candidate-report');
const reportExpectation = option('--report-expect', 'green');
if (!['baseline', 'green', 'box-cut', 'step5-cut'].includes(expectation)) {
  throw new Error(`unsupported --expect value: ${expectation}`);
}
if (!['green', 'box-cut', 'step5-cut'].includes(reportExpectation)) {
  throw new Error(`unsupported --report-expect value: ${reportExpectation}`);
}
if (compiler && !outputRoot) {
  throw new Error('--compiler requires --out');
}
if (Boolean(baselineReport) !== Boolean(candidateReport)) {
  throw new Error('--baseline-report and --candidate-report must be provided together');
}

const expected = {
  baseline: {box: 'raw', step5: 'raw'},
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
    'CallGCWriteGenericPayloadFromSrc(thisParamWithoutTI,payloadPtr,size32,thisParamTypeInfo)') ||
    flatStep5.includes(
      'CallGCReadGeneric(thisParamWithoutTI,thisParamWithTI,payloadPtr,size32)');
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
  const fixture = path.join(fixtureRoot, 'scripts/erased_dynpayload_fixtures', `${name}.cj`);
  const armRoot = path.resolve(outputRoot, name);
  const temps = path.join(armRoot, 'temps');
  fs.mkdirSync(temps, {recursive: true});
  // -g is the product switch that runs EmitPackageIR.ReplaceFunction; -O2 and
  // --apc=1 mirror the stdlib package recipe that exposes these two sites.
  const args = [fixture, '--output-type=staticlib', '-g', '-O2', '--apc=1', '-j1',
    '--dump-ir', '--dump-to-screen', '--save-temps', temps,
    '-o', path.join(armRoot, `${name}.a`)];
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

const reportFields = [
  'module', 'function', 'rule', 'instruction', 'dest_as', 'src_as', 'length',
  'dest_root', 'src_root', 'source_type',
];

function readReport(file) {
  const lines = fs.readFileSync(path.resolve(file), 'utf8').split(/\r?\n/).filter(Boolean);
  if (lines.length === 0 || lines[0] !== reportFields.join('\t')) {
    throw new Error(`${file}: missing exact ten-field header`);
  }
  return lines.slice(1).filter(line => line !== reportFields.join('\t')).map((line, index) => {
    const fields = line.split('\t');
    if (fields.length !== reportFields.length) {
      throw new Error(`${file}:${index + 2}: expected ${reportFields.length} fields, got ${fields.length}`);
    }
    return Object.fromEntries(reportFields.map((name, fieldIndex) => [name, fields[fieldIndex]]));
  });
}

function rowKey(row) {
  return reportFields.map(field => row[field]).join('\t');
}

function targetKind(row) {
  if (!row.rule.startsWith('Bare memcpy/memmove payload provenance is unknown') ||
      row.instruction !== 'memcpy' || !row.length.startsWith('%')) return '';
  if (row.dest_as === '1' && row.src_as === '0' && row.function.includes('Range') &&
      /provide|provider/.test(row.function) && row.dest_root === 'call' &&
      row.src_root === 'alloca' && row.source_type === 'i8*') return 'p1p0';
  if (row.dest_as === '1' && row.src_as === '1' &&
      row.function.includes('ExternallyLockedLazy') && row.function.includes('compute') &&
      row.dest_root === 'argument' && row.src_root === 'call' &&
      row.source_type === 'i8* addrspace(1)*') return 'p1p1';
  return '';
}

function multiset(rows) {
  const result = new Map();
  for (const row of rows) {
    const key = rowKey(row);
    const found = result.get(key);
    if (found) found.count += 1;
    else result.set(key, {row, count: 1});
  }
  return result;
}

function subtract(leftRows, rightRows) {
  const left = multiset(leftRows);
  const right = multiset(rightRows);
  const difference = [];
  for (const [key, entry] of left) {
    const count = entry.count - (right.get(key)?.count || 0);
    for (let index = 0; index < count; index += 1) difference.push(entry.row);
  }
  return difference;
}

function countsByTarget(rows) {
  const counts = {p1p0: 0, p1p1: 0, other: 0};
  for (const row of rows) counts[targetKind(row) || 'other'] += 1;
  return counts;
}

function checkReport() {
  const baseline = readReport(baselineReport);
  const candidate = readReport(candidateReport);
  const removed = subtract(baseline, candidate);
  const added = subtract(candidate, baseline);
  const baselineTargets = countsByTarget(baseline);
  const candidateTargets = countsByTarget(candidate);
  const removedTargets = countsByTarget(removed);
  const expectedRemoved = {
    green: ['p1p0', 'p1p1'],
    'box-cut': ['p1p1'],
    'step5-cut': ['p1p0'],
  }[reportExpectation];
  const expectedKept = ['p1p0', 'p1p1'].filter(kind => !expectedRemoved.includes(kind));

  record('report.baseline-positive', baselineTargets.p1p0 > 0 && baselineTargets.p1p1 > 0,
    `p1p0=${baselineTargets.p1p0} p1p1=${baselineTargets.p1p1}`);
  record('report.new-empty', added.length === 0, `NEW=${added.length}`);
  record('report.other-unchanged', removedTargets.other === 0,
    `removed_other=${removedTargets.other}`);
  for (const kind of expectedRemoved) {
    record(`report.${kind}.removed`, candidateTargets[kind] === 0 &&
      removedTargets[kind] === baselineTargets[kind],
    `baseline=${baselineTargets[kind]} candidate=${candidateTargets[kind]} removed=${removedTargets[kind]}`);
  }
  for (const kind of expectedKept) {
    record(`report.${kind}.kept`, candidateTargets[kind] === baselineTargets[kind] &&
      removedTargets[kind] === 0,
    `baseline=${baselineTargets[kind]} candidate=${candidateTargets[kind]} removed=${removedTargets[kind]}`);
  }
}

checkSource();
if (compiler) checkIR();
if (baselineReport) checkReport();
if (outputRoot) {
  fs.mkdirSync(path.resolve(outputRoot), {recursive: true});
  fs.writeFileSync(path.resolve(outputRoot, 'results.json'), `${JSON.stringify(results, null, 2)}\n`);
}
process.exitCode = results.some(result => !result.ok) ? 1 : 0;
