#!/usr/bin/env zx
// Qualify the tools used by the native runtime teardown gate before building.
// Keep the raw probe output and the first failing tool's exit status.
import fs from 'node:fs/promises';
import path from 'node:path';
import {toCommandPath} from './common.mjs';

const log = argv._[0];
if (!log) {
  console.error('usage: qualify_teardown_tools.mjs LOG');
  process.exit(1);
}
await fs.mkdir(path.dirname(log), {recursive: true});
await fs.writeFile(log, '');
let rc = 0;
for (const tool of ['gdb', 'timeout']) {
  const probe = await $({nothrow: true, quiet: true})`command -v ${tool}`;
  await fs.appendFile(log, probe.stdall);
  if (probe.exitCode !== 0) {
    rc = 127;
    await fs.appendFile(log, `GC_UNIT_TEARDOWN_TOOL_FAIL tool=${tool} rc=127 reason=not-found\n`);
    break;
  }
  const version = await $({nothrow: true, quiet: true})`${toCommandPath(tool)} --version`;
  await fs.appendFile(log, version.stdall);
  rc = version.exitCode;
  await fs.appendFile(log, `GC_UNIT_TEARDOWN_TOOL_${rc === 0 ? 'OK' : 'FAIL'} tool=${tool} rc=${rc}\n`);
  if (rc !== 0) break;
}
process.stdout.write(await fs.readFile(log, 'utf8'));
process.exitCode = rc;
