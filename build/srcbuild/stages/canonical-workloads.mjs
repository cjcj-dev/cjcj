import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {CANONICAL_WORKLOADS} from '../../lib/canonical-workloads.mjs';
import {classifyProvenanceText, fileSha256} from '../../lib/package-lineage.mjs';
import {run as command} from '../../lib/runner.mjs';
import {consumerSdk} from './common.mjs';
import {assertBootstrapCompiler} from '../../../ci/srcbuild/lib/bootstrap-handoff.mjs';
import {stdIdentity} from '../../../ci/srcbuild/lib/final-compiler.mjs';

const repository = fileURLToPath(new URL('../../..', import.meta.url));
export async function run(config) {
  const sdk = consumerSdk(config);
  const output = path.join(config.softwareDir, 'canonical-workloads');
  const manifest = path.join(output, 'CANONICAL_WORKLOADS.json');
  await fs.mkdir(output, {recursive: true});
  // A failed attempt cannot leave the previous run's identity publishable.
  await fs.rm(manifest, {force: true});
  const compiler = path.join(sdk, 'bin', 'cjc');
  const identity = await assertBootstrapCompiler({sdk, command: compiler});
  const finalStd = path.join(config.softwareDir, 'final-std-stage2');
  const provenance = await fs.readFile(path.join(finalStd, 'PROVENANCE.txt'), 'utf8');
  if (!['cjcj-stage2', 'final-std'].includes(classifyProvenanceText(provenance))) {
    throw new Error('canonical workloads require stage2-built final std');
  }
  const stdSha256 = await stdIdentity(finalStd);
  if (await stdIdentity(sdk, finalStd) !== stdSha256) {
    throw new Error('canonical workloads SDK does not contain final std');
  }
  if (process.env.CANGJIE_BUILD_DRY_RUN === '1') {
    console.log('CANONICAL_WORKLOADS planned; no ELF identity emitted');
    return;
  }
  const runtimeRoot = config.repoPath('runtime');
  const gitHead = async cwd => (await command(['git', 'rev-parse', 'HEAD'],
    {cwd, capture: true, logOutput: false})).stdout.trim();
  const cjcjHead = await gitHead(repository);
  const runtimeHead = await gitHead(runtimeRoot);
  const startedUtc = new Date().toISOString();
  const rows = [];
  for (const {name, source} of CANONICAL_WORKLOADS) {
    const input = path.join(runtimeRoot, source);
    const binary = path.join(output, name);
    const sourceSha256 = await fileSha256(input);
    await fs.rm(binary, {force: true});
    await command([compiler, '-O2', '--static-std', input, '-o', binary], {
      cwd: runtimeRoot, stage: `canonical-workloads.${name}`,
    });
    const elfSha256 = await fileSha256(binary);
    const handle = await fs.open(binary, 'r');
    const magic = Buffer.alloc(4);
    try { await handle.read(magic, 0, 4, 0); } finally { await handle.close(); }
    if (!magic.equals(Buffer.from([0x7f, 0x45, 0x4c, 0x46]))) throw new Error(`${name}: compiler did not produce ELF`);
    if (await fileSha256(input) !== sourceSha256) throw new Error(`${name}: source changed during compilation`);
    rows.push({name, file: name, source, source_sha256: sourceSha256, elf_sha256: elfSha256});
    console.log(`CANONICAL_ELF name=${name} elf_sha256=${elfSha256} BIN=${binary}`);
  }
  await assertBootstrapCompiler({sdk, command: compiler});
  if (await stdIdentity(sdk, finalStd) !== stdSha256) throw new Error('final std changed during workload compilation');
  if (await gitHead(repository) !== cjcjHead || await gitHead(runtimeRoot) !== runtimeHead) {
    throw new Error('source revision changed during workload compilation');
  }
  const record = {
    schema: 1, cjcj_head_sha: cjcjHead, runtime_source_sha: runtimeHead,
    started_utc: startedUtc, finished_utc: new Date().toISOString(),
    compiler: {kind: 'cjcj-stage2', sha256: identity.compilerSha256},
    final_std_sha256: stdSha256, flags: ['-O2', '--static-std'], workloads: rows,
  };
  await fs.writeFile(manifest, `${JSON.stringify(record, null, 2)}\n`);
  console.log(`CANONICAL_MANIFEST=${manifest}`);
  return manifest;
}
