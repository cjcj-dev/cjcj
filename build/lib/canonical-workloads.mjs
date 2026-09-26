import fs from 'node:fs/promises';
import {fileSha256} from './package-lineage.mjs';
import path from 'node:path';
import {run} from './runner.mjs';

export const CANONICAL_WORKLOADS = Object.freeze([
  {name: 'natural_wave_notime', source: 'runtime/tests/perf_vs_official/natural_wave_notime.cj'},
  {name: 'survival_dense', source: 'runtime/tests/gcparity/survival_dense.cj'},
]);

// Check the archive itself, after packaging, including nested directory entries.
export async function assertNoCanonicalWorkloads(archive) {
  if (process.env.CANGJIE_BUILD_DRY_RUN === '1') {
    console.log(`CANONICAL_PACKAGE_EXCLUSION planned archive=${archive}`);
    return;
  }
  const argv = archive.endsWith('.tar.gz') ? ['tar', '-tzf', archive]
    : archive.endsWith('.zip') ? ['unzip', '-Z1', archive] : null;
  if (!argv) throw new Error(`unsupported package archive: ${archive}`);
  const {stdout} = await run(argv, {capture: true, logOutput: false, stage: 'package.canonical-exclusion'});
  const names = new Set(CANONICAL_WORKLOADS.flatMap(({name}) => [name, `${name}.exe`]));
  const rejected = stdout.split('\n').filter(entry => names.has(path.posix.basename(entry.replace(/\/$/, ''))));
  if (rejected.length) throw new Error(`canonical-workload-in-package: ${rejected.join(', ')}`);
  console.log(`CANONICAL_PACKAGE_EXCLUSION archive=${archive} matches=0`);
}

// Evidence archives retain the producer record alongside the exact binaries.
export async function validateCanonicalWorkloads(directory, {head} = {}) {
  const record = JSON.parse(await fs.readFile(path.join(directory, 'CANONICAL_WORKLOADS.json'), 'utf8'));
  const sha256 = value => typeof value === 'string' && /^[0-9a-f]{64}$/.test(value);
  const sha40 = value => typeof value === 'string' && /^[0-9a-f]{40}$/.test(value);
  if (record.schema !== 1 || record.compiler?.kind !== 'cjcj-stage2'
    || !sha256(record.compiler?.sha256) || !sha256(record.final_std_sha256)
    || !sha40(record.cjcj_head_sha) || (head && record.cjcj_head_sha !== head)
    || !sha40(record.runtime_source_sha)
    || JSON.stringify(record.flags) !== JSON.stringify(['-O2', '--static-std'])) {
    throw new Error('canonical-workload-producer-identity');
  }
  if (!Array.isArray(record.workloads) || record.workloads.length !== CANONICAL_WORKLOADS.length) {
    throw new Error('canonical-workload-membership');
  }
  for (const {name, source} of CANONICAL_WORKLOADS) {
    const rows = record.workloads.filter(row => row.name === name);
    if (rows.length !== 1 || rows[0].source !== source || rows[0].file !== name
      || !sha256(rows[0].source_sha256) || !sha256(rows[0].elf_sha256)) {
      throw new Error(`canonical-workload-identity:${name}`);
    }
    const file = path.join(directory, name);
    if (!(await fs.lstat(file)).isFile() || await fileSha256(file) !== rows[0].elf_sha256) {
      throw new Error(`canonical-workload-elf-sha256:${name}`);
    }
  }
  return record;
}
