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

const searchRoot = argv._[0] || path.join(
  process.env.PLATFORM_CI_ROOT || path.join(process.cwd(), '.platform-ci'),
  'runtime-install',
);
const runtimeDll = await findRuntimeDll(searchRoot);
if (!runtimeDll) {
  console.error(`FATAL: libcangjie-runtime.dll not found under ${path.resolve(searchRoot)}`);
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
  /\[Ordinal\/Name Pointer\] Table\s*\r?\n([\s\S]*?)(?:\r?\n\s*\r?\n|$)/i,
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
const unexpectedImports = [...imports].filter((dll) => !officialImports.has(dll));
const missingImports = [...officialImports].filter((dll) => !imports.has(dll));
const prefixCount = (prefix) => [...exports].filter((symbol) => symbol.startsWith(prefix)).length;
const mccCount = prefixCount('MCC_');
const cjMccCount = prefixCount('CJ_MCC_');
const mrtCount = prefixCount('MRT_');

console.log(`WINDOWS_RUNTIME_EXPORT_GUARD dll=${runtimeDll}`);
console.log(
  `WINDOWS_RUNTIME_EXPORT_GUARD exports=${exports.size} required=${requiredExports.length} missing=${missing.length} ` +
  `MCC=${mccCount} CJ_MCC=${cjMccCount} MRT=${mrtCount} imports=${[...imports].sort().join(',')}`,
);
if (missing.length) console.error(`FATAL: missing required exports: ${missing.join(',')}`);
if (unexpectedImports.length) console.error(`FATAL: unexpected imports: ${unexpectedImports.join(',')}`);
if (missingImports.length) console.error(`FATAL: missing official imports: ${missingImports.join(',')}`);
if (mccCount !== 158 || cjMccCount !== 192 || mrtCount !== 61) {
  console.error('FATAL: runtime export-family counts differ from the official Windows SDK');
}
if (
  missing.length || unexpectedImports.length || missingImports.length ||
  mccCount !== 158 || cjMccCount !== 192 || mrtCount !== 61
) process.exit(1);
