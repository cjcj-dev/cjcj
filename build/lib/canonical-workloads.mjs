import path from 'node:path';
import {run} from './runner.mjs';

export const CANONICAL_WORKLOADS = Object.freeze([
  {name: 'natural_wave_notime', source: 'runtime/tests/perf_vs_official/natural_wave_notime.cj'},
  {name: 'survival_dense', source: 'runtime/tests/gcparity/survival_dense.cj'},
]);

// Check the archive itself, after packaging, including nested directory entries.
export async function assertNoCanonicalWorkloads(archive) {
  const argv = archive.endsWith('.tar.gz') ? ['tar', '-tzf', archive]
    : archive.endsWith('.zip') ? ['unzip', '-Z1', archive] : null;
  if (!argv) throw new Error(`unsupported package archive: ${archive}`);
  const {stdout} = await run(argv, {capture: true, logOutput: false, stage: 'package.canonical-exclusion'});
  const names = new Set(CANONICAL_WORKLOADS.flatMap(({name}) => [name, `${name}.exe`]));
  const rejected = stdout.split('\n').filter(entry => names.has(path.posix.basename(entry.replace(/\/$/, ''))));
  if (rejected.length) throw new Error(`canonical-workload-in-package: ${rejected.join(', ')}`);
  console.log(`CANONICAL_PACKAGE_EXCLUSION archive=${archive} matches=0`);
}
