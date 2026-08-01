#!/usr/bin/env zx

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const expectedDefinition = path.resolve(argv._[0] || path.join(import.meta.dirname, 'windows_x86_64_exports.def'));
const definition = await fs.readFile(expectedDefinition, 'utf8');
const expectedExports = definition
  .split(/\r?\n/)
  .map((line) => line.trim().match(/^(\S+)\s+@\d+(?:\s+DATA)?$/)?.[1])
  .filter(Boolean);
const removedExport = 'CJ_MCC_StickyLogLine';
const replacementExport = 'CJ_MCC_GuardlistReplacement';
if (!expectedExports.includes(removedExport)) {
  console.error(`FATAL: test anchor ${removedExport} is absent from ${expectedDefinition}`);
  process.exit(2);
}

const temporaryRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'guardlist-'));
try {
  const runtimeDll = path.join(temporaryRoot, 'libcangjie-runtime.dll');
  const fakeObjdump = path.join(temporaryRoot, 'fake-objdump.mjs');
  await fs.writeFile(runtimeDll, 'offline fixture\n');
  await fs.writeFile(fakeObjdump, [
    '#!/usr/bin/env node',
    "import fs from 'node:fs';",
    "const names = fs.readFileSync(process.env.FAKE_EXPORTS_FILE, 'utf8').trim().split(/\\r?\\n/);",
    "const imports = ['dbghelp.dll', 'kernel32.dll', 'libboundscheck.dll', 'msvcrt.dll', 'ws2_32.dll'];",
    "const lines = [...imports.map((dll) => `DLL Name: ${dll}`), '', '[Ordinal/Name Pointer] Table'];",
    "lines.push(...names.map((name, index) => `  [${index}] ${name}`), '', '');",
    "process.stdout.write(lines.join('\\n'));",
    '',
  ].join('\n'));
  await fs.chmod(fakeObjdump, 0o755);

  const guard = path.join(import.meta.dirname, 'verify_windows_runtime_exports.mjs');
  const runCase = async (name, exports) => {
    const exportsFile = path.join(temporaryRoot, `${name}.exports`);
    await fs.writeFile(exportsFile, `${exports.join('\n')}\n`);
    const result = spawnSync(
      'npx',
      ['--yes', 'zx@8', guard, temporaryRoot, '--expected-def', expectedDefinition],
      {
        encoding: 'utf8',
        env: {...process.env, OBJDUMP: fakeObjdump, FAKE_EXPORTS_FILE: exportsFile},
        maxBuffer: 64 * 1024 * 1024,
      },
    );
    console.log(`SELFTEST_CASE=${name} rc=${result.status}`);
    process.stdout.write(result.stdout);
    process.stdout.write(result.stderr);
    return result;
  };

  const current = await runCase('current', expectedExports);
  const removed = expectedExports.filter((symbol) => symbol !== removedExport);
  const missing = await runCase('missing-one', removed);
  const withExtra = [...expectedExports, replacementExport];
  const extra = await runCase('extra-one', withExtra);
  const replaced = [...removed, replacementExport];
  const replacement = await runCase('equal-count-replacement', replaced);

  const failures = [];
  if (current.status !== 0 || !current.stdout.includes('missing=0 unexpected=0')) {
    failures.push('current export surface did not pass cleanly');
  }
  if (missing.status !== 1 || !missing.stderr.includes(`FATAL: missing exports: ${removedExport}`)) {
    failures.push('single deletion did not report its missing ABI name');
  }
  if (extra.status !== 1 || !extra.stderr.includes(`FATAL: unexpected exports: ${replacementExport}`)) {
    failures.push('single addition did not report its unexpected ABI name');
  }
  if (
    replacement.status !== 1 ||
    !replacement.stdout.includes(`exports=${expectedExports.length} expected=${expectedExports.length}`) ||
    !replacement.stderr.includes(`FATAL: missing exports: ${removedExport}`) ||
    !replacement.stderr.includes(`FATAL: unexpected exports: ${replacementExport}`)
  ) {
    failures.push('equal-count replacement did not report both sides of the set difference');
  }
  if (failures.length) {
    for (const failure of failures) console.error(`SELFTEST_FAILURE=${failure}`);
    process.exitCode = 1;
  } else {
    console.log('SELFTEST_RESULT=PASS');
  }
} finally {
  await fs.rm(temporaryRoot, {recursive: true, force: true});
}
