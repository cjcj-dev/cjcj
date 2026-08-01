#!/usr/bin/env zx

import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const requiredExports = [
  'StringCchCopyNA',
  '__cosl_internal',
  '__mingw_strtod',
  '__mingw_strtof',
  '__mingw_strtold',
  '__mingw_vfprintf',
  '__mingw_vsnprintf',
  '__mingw_vsnwprintf',
  '__mingw_wcstod',
  '__mingw_wcstof',
  '__ms_vsnprintf',
  '__stack_chk_fail',
  'strtold',
  'wcstold',
  'wcstoll',
  'wcstoull',
];

const officialImports = new Set([
  'dbghelp.dll',
  'kernel32.dll',
  'libboundscheck.dll',
  'msvcrt.dll',
  'ws2_32.dll',
]);

async function findRuntimeDll(candidate) {
  const resolved = path.resolve(candidate);
  const info = await fs.stat(resolved).catch(() => undefined);
  if (!info) return '';
  if (info.isFile()) return path.basename(resolved).toLowerCase() === 'libcangjie-runtime.dll' ? resolved : '';
  for (const entry of await fs.readdir(resolved, {withFileTypes: true})) {
    const child = path.join(resolved, entry.name);
    if (entry.isFile() && entry.name.toLowerCase() === 'libcangjie-runtime.dll') return child;
    if (entry.isDirectory()) {
      const found = await findRuntimeDll(child);
      if (found) return found;
    }
  }
  return '';
}

async function findExportDefinition(candidate) {
  const resolved = path.resolve(candidate);
  const info = await fs.stat(resolved).catch(() => undefined);
  if (!info) return '';
  if (info.isFile()) {
    return path.basename(resolved) === 'windows_x86_64_exports.def' ? resolved : '';
  }
  for (const entry of await fs.readdir(resolved, {withFileTypes: true})) {
    const child = path.join(resolved, entry.name);
    if (entry.isFile() && entry.name === 'windows_x86_64_exports.def') return child;
    if (entry.isDirectory()) {
      const found = await findExportDefinition(child);
      if (found) return found;
    }
  }
  return '';
}

function parseExportDefinition(contents, filename) {
  const expected = new Set();
  let hasExportsHeader = false;
  for (const [index, original] of contents.split(/\r?\n/).entries()) {
    const line = original.trim();
    if (!line || line.startsWith(';')) continue;
    if (line === 'EXPORTS') {
      hasExportsHeader = true;
      continue;
    }
    const matched = line.match(/^(\S+)\s+@\d+(?:\s+DATA)?$/);
    if (!hasExportsHeader || !matched) {
      throw new Error(`${filename}:${index + 1}: malformed export definition: ${original}`);
    }
    if (expected.has(matched[1])) {
      throw new Error(`${filename}:${index + 1}: duplicate export: ${matched[1]}`);
    }
    expected.add(matched[1]);
  }
  if (!hasExportsHeader || !expected.size) throw new Error(`${filename}: empty export definition`);
  return expected;
}

const sortedDifference = (left, right) => [...left].filter((value) => !right.has(value)).sort();

const searchRoot = argv._[0] || path.join(
  process.env.PLATFORM_CI_ROOT || path.join(process.cwd(), '.platform-ci'),
  'runtime-install',
);
const runtimeDll = await findRuntimeDll(searchRoot);
if (!runtimeDll) {
  console.error(`FATAL: libcangjie-runtime.dll not found under ${path.resolve(searchRoot)}`);
  process.exit(2);
}
// Authoritative expected set: checked-in observation from CI PE export table.
// Prefer --expected-def, then in-tree def next to this script, then runtime-source,
// then a staged copy under the runtime-install search root.
const checkedInDefinition = path.join(import.meta.dirname, 'windows_x86_64_exports.def');
const runtimeSourceDefinition = path.join(
  process.cwd(),
  'runtime-source',
  'runtime',
  'src',
  'windows_x86_64_exports.def',
);
const expectedDefinition = typeof argv['expected-def'] === 'string'
  ? path.resolve(argv['expected-def'])
  : await findExportDefinition(checkedInDefinition)
    || await findExportDefinition(runtimeSourceDefinition)
    || await findExportDefinition(searchRoot);
if (!expectedDefinition) {
  console.error(
    `FATAL: windows_x86_64_exports.def not found next to this script, in runtime-source, or under ${path.resolve(searchRoot)}`,
  );
  process.exit(2);
}
let expectedExports;
try {
  expectedExports = parseExportDefinition(await fs.readFile(expectedDefinition, 'utf8'), expectedDefinition);
} catch (error) {
  console.error(`FATAL: ${error.message}`);
  process.exit(2);
}

const objdump = process.env.OBJDUMP || 'objdump';
const inspected = spawnSync(objdump, ['-p', runtimeDll], {
  encoding: 'utf8',
  maxBuffer: 64 * 1024 * 1024,
});
if (inspected.status !== 0) {
  process.stderr.write(inspected.stderr || String(inspected.error || 'objdump failed'));
  process.exit(inspected.status || 3);
}

const dump = inspected.stdout || '';
const exportTable = dump.match(
  /\[Ordinal\/Name Pointer\] Table[^\r\n]*\r?\n([\s\S]*?)(?:\r?\n\s*\r?\n|$)/i,
)?.[1] || '';
const exports = new Set(
  [...exportTable.matchAll(
    /^\s*\[\s*\d+\]\s+(?:\+base\[\s*\d+\]\s+[0-9a-f]+\s+)?(\S.*)$/gim,
  )]
    .map((match) => match[1].trim()),
);
const imports = new Set(
  [...dump.matchAll(/^\s*DLL Name:\s*(\S+)/gim)]
    .map((match) => match[1].toLowerCase()),
);
const missing = requiredExports.filter((symbol) => !exports.has(symbol));
const missingExpected = sortedDifference(expectedExports, exports);
const unexpectedExports = sortedDifference(exports, expectedExports);
const unexpectedImports = [...imports].filter((dll) => !officialImports.has(dll));
const missingImports = [...officialImports].filter((dll) => !imports.has(dll));

console.log(`WINDOWS_RUNTIME_EXPORT_GUARD dll=${runtimeDll} expected_def=${expectedDefinition}`);
console.log(
  `WINDOWS_RUNTIME_EXPORT_GUARD exports=${exports.size} expected=${expectedExports.size} ` +
  `missing=${missingExpected.length} unexpected=${unexpectedExports.length} ` +
  `required=${requiredExports.length} missing_required=${missing.length} imports=${[...imports].sort().join(',')}`,
);
if (missing.length) console.error(`FATAL: missing required exports: ${missing.join(',')}`);
if (missingExpected.length) console.error(`FATAL: missing exports: ${missingExpected.join(',')}`);
if (unexpectedExports.length) console.error(`FATAL: unexpected exports: ${unexpectedExports.join(',')}`);
if (unexpectedImports.length) console.error(`FATAL: unexpected imports: ${unexpectedImports.join(',')}`);
if (missingImports.length) console.error(`FATAL: missing official imports: ${missingImports.join(',')}`);
if (
  missing.length || missingExpected.length || unexpectedExports.length ||
  unexpectedImports.length || missingImports.length
) process.exit(1);
