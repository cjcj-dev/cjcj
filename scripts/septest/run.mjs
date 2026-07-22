#!/usr/bin/env zx
// End-to-end serialization persistence gate for imports, signatures, re-exports, and protected LUB metadata.

import fs from 'node:fs/promises';
import path from 'node:path';
import {copy, ensureInputs, fail, invoke, makeWork, output, reference, run, selfhost} from './septest_lib.mjs';

const work = await makeWork('septest-');
const prefix = 'SEPTEST';
const stderrText = result => result.stderr.replaceAll('\n', ' ');
try {
  await ensureInputs(prefix, work);
  const copies = [
    ['pkgA/pkgA.cj', 'pkgA/pkgA.cj'], ['pkgSig/pkgSig.cj', 'pkgSig/pkgSig.cj'], ['pkgA4/pkgA4.cj', 'pkgA4/pkgA4.cj'],
    ['pkgReExportP/pkgReExportP.cj', 'pkgReExportP/pkgReExportP.cj'], ['pkgReExportQ/pkgReExportQ.cj', 'pkgReExportQ/pkgReExportQ.cj'], ['pkgReExportM/use_reexport.cj', 'pkgReExportM/use_reexport.cj'],
    ['pkgReParamBase/kind.cj', 'pkgReParamBase/kind.cj'], ['pkgReParamHub/hub.cj', 'pkgReParamHubRef/hub.cj'], ['pkgReParamHub/hub.cj', 'pkgReParamHub/hub.cj'], ['pkgReParamUse/use.cj', 'pkgReParamUse/use.cj'],
    ...['function.cj', 'function_single.cj', 'greeting.cj', 'imported_signature.cj'].map(file => [`pkgB/${file}`, `pkgB/${file}`]),
    ['pkgB4/protected_lub.cj', 'pkgB4/protected_lub.cj'],
  ];
  for (const [source, destination] of copies) await copy(source, path.join(work, destination));
  await Promise.all([fs.mkdir(path.join(work, 'ref')), fs.mkdir(path.join(work, 'self'))]);

  async function compileOrFail(compiler, args, label, stem) {
    const result = await invoke(compiler, args, stem ? path.join(work, `${stem}.stdout`) : undefined, stem ? path.join(work, `${stem}.stderr`) : undefined);
    if (result.exitCode !== 0) fail(prefix, `${label}: ${stderrText(result)}`);
  }
  async function requireArtifacts(dir, packageName, archiveName, producer) {
    for (const file of [`${packageName}.cjo`, archiveName]) try { await fs.access(path.join(work, dir, file)); } catch { fail(prefix, `${producer} did not produce ${file}`); }
  }

  await compileOrFail(reference, [path.join(work, 'pkgA/pkgA.cj'), '--output-type=staticlib', '-o', path.join(work, 'pkgA/libpkgA.a'), '--set-runtime-rpath'], 'reference pkgA compile failed', 'pkgA.ref');
  await requireArtifacts('pkgA', 'pkgA', 'libpkgA.a', 'reference pkgA');
  await compileOrFail(reference, [path.join(work, 'pkgSig/pkgSig.cj'), '--output-type=staticlib', '-o', path.join(work, 'pkgSig/libpkgSig.a'), '--set-runtime-rpath'], 'reference pkgSig compile failed', 'pkgSig.ref');
  await requireArtifacts('pkgSig', 'pkgSig', 'libpkgSig.a', 'reference pkgSig');
  await compileOrFail(reference, [path.join(work, 'pkgA4/pkgA4.cj'), '--output-type=staticlib', '-o', path.join(work, 'pkgA4/libpkgA4.a'), '--set-runtime-rpath'], 'reference pkgA4 compile failed', 'pkgA4.ref');
  await requireArtifacts('pkgA4', 'pkgA4', 'libpkgA4.a', 'reference pkgA4');
  await compileOrFail(reference, [path.join(work, 'pkgReExportP/pkgReExportP.cj'), '--output-type=staticlib', '-o', path.join(work, 'pkgReExportP/libpkgReExportP.a'), '--set-runtime-rpath'], 'reference pkgReExportP compile failed', 'pkgReExportP.ref');
  await requireArtifacts('pkgReExportP', 'pkgReExportP', 'libpkgReExportP.a', 'reference pkgReExportP');
  await compileOrFail(reference, [path.join(work, 'pkgReExportQ/pkgReExportQ.cj'), '--import-path', path.join(work, 'pkgReExportP'), '-L', path.join(work, 'pkgReExportP'), '-lpkgReExportP', '--output-type=staticlib', '-o', path.join(work, 'pkgReExportQ/libpkgReExportQ.a'), '--set-runtime-rpath'], 'reference pkgReExportQ compile failed', 'pkgReExportQ.ref');
  await requireArtifacts('pkgReExportQ', 'pkgReExportQ', 'libpkgReExportQ.a', 'reference pkgReExportQ');
  await compileOrFail(reference, [path.join(work, 'pkgReParamBase/kind.cj'), '--output-type=staticlib', '-o', path.join(work, 'pkgReParamBase/libpkgReParamBase.a'), '--set-runtime-rpath'], 'reference pkgReParamBase compile failed', 'pkgReParamBase.ref');
  await requireArtifacts('pkgReParamBase', 'pkgReParamBase', 'libpkgReParamBase.a', 'reference pkgReParamBase');
  const baseArgs = ['--import-path', path.join(work, 'pkgReParamBase'), '-L', path.join(work, 'pkgReParamBase'), '-lpkgReParamBase', '--output-type=staticlib', '--set-runtime-rpath'];
  await compileOrFail(reference, [path.join(work, 'pkgReParamHubRef/hub.cj'), ...baseArgs.slice(0, -1), '-o', path.join(work, 'pkgReParamHubRef/libpkgReParamHub.a'), '--set-runtime-rpath'], 'reference pkgReParamHub compile failed', 'pkgReParamHub.ref');
  await compileOrFail(selfhost, [path.join(work, 'pkgReParamHub/hub.cj'), ...baseArgs.slice(0, -1), '-o', path.join(work, 'pkgReParamHub/libpkgReParamHub.a'), '--set-runtime-rpath'], 'selfhost pkgReParamHub compile failed', 'pkgReParamHub.self');
  await requireArtifacts('pkgReParamHub', 'pkgReParamHub', 'libpkgReParamHub.a', 'selfhost pkgReParamHub');

  async function paired(name, source, linkArgs, expected, outputLabel = name) {
    const binaries = {ref: path.join(work, 'ref', name), self: path.join(work, 'self', name)};
    await compileOrFail(reference, [source, ...linkArgs, '-o', binaries.ref, '--set-runtime-rpath'], `reference ${outputLabel} compile failed`, `${name}.ref`);
    await compileOrFail(selfhost, [source, ...linkArgs, '-o', binaries.self, '--set-runtime-rpath'], `selfhost ${outputLabel} compile failed`, `${name}.self`);
    const refRun = await run(binaries.ref, path.join(work, `${name}.ref.run.stderr`));
    const selfRun = await run(binaries.self, path.join(work, `${name}.self.run.stderr`));
    const refOut = output(refRun); const selfOut = output(selfRun);
    if (refRun.exitCode !== selfRun.exitCode) fail(prefix, `${name} exit mismatch: reference=${refRun.exitCode} selfhost=${selfRun.exitCode}`);
    if (refOut !== selfOut) fail(prefix, `${name} output mismatch: reference='${refOut}' selfhost='${selfOut}'`);
    if (expected !== undefined && selfOut !== expected) fail(prefix, `${name} output '${selfOut}' did not match expected '${expected}'`);
    console.log(`SEPTEST-${name}-PASS output=${selfOut} exit=${selfRun.exitCode}`);
  }
  const pkgAArgs = ['--import-path', path.join(work, 'pkgA'), '-L', path.join(work, 'pkgA'), '-lpkgA'];
  await paired('function', path.join(work, 'pkgB/function.cj'), pkgAArgs, '42', 'pkgB function');
  await paired('function_single', path.join(work, 'pkgB/function_single.cj'), pkgAArgs, '42', 'pkgB function_single');
  await paired('greeting', path.join(work, 'pkgB/greeting.cj'), pkgAArgs, 'hello from pkgA', 'pkgB greeting');
  await paired('imported_signature', path.join(work, 'pkgB/imported_signature.cj'), ['--import-path', path.join(work, 'pkgSig'), '-L', path.join(work, 'pkgSig'), '-lpkgSig'], undefined, 'pkgB imported_signature');
  await paired('use_reexport', path.join(work, 'pkgReExportM/use_reexport.cj'), ['--import-path', path.join(work, 'pkgReExportQ'), '--import-path', path.join(work, 'pkgReExportP'), '-L', path.join(work, 'pkgReExportQ'), '-lpkgReExportQ', '-L', path.join(work, 'pkgReExportP'), '-lpkgReExportP'], '7', 'pkgReExportM');

  const paramSource = path.join(work, 'pkgReParamUse/use.cj');
  const refBinary = path.join(work, 'ref/use_reexport_param'); const selfBinary = path.join(work, 'self/use_reexport_param');
  await compileOrFail(reference, [paramSource, '--import-path', path.join(work, 'pkgReParamHubRef'), '--import-path', path.join(work, 'pkgReParamBase'), '-L', path.join(work, 'pkgReParamHubRef'), '-lpkgReParamHub', '-L', path.join(work, 'pkgReParamBase'), '-lpkgReParamBase', '-o', refBinary, '--set-runtime-rpath'], 'reference pkgReParamUse compile failed', 'use_reexport_param.ref');
  await compileOrFail(selfhost, [paramSource, '--import-path', path.join(work, 'pkgReParamHub'), '--import-path', path.join(work, 'pkgReParamBase'), '-L', path.join(work, 'pkgReParamHub'), '-lpkgReParamHub', '-L', path.join(work, 'pkgReParamBase'), '-lpkgReParamBase', '-o', selfBinary, '--set-runtime-rpath'], 'selfhost pkgReParamUse compile failed', 'use_reexport_param.self');
  const paramRef = await run(refBinary); const paramSelf = await run(selfBinary); const paramRefOut = output(paramRef); const paramSelfOut = output(paramSelf);
  if (paramRef.exitCode !== paramSelf.exitCode) fail(prefix, `use_reexport_param exit mismatch: reference=${paramRef.exitCode} selfhost=${paramSelf.exitCode}`);
  if (paramRefOut !== paramSelfOut) fail(prefix, `use_reexport_param output mismatch: reference='${paramRefOut}' selfhost='${paramSelfOut}'`);
  if (paramSelfOut !== 'true') fail(prefix, `use_reexport_param output '${paramSelfOut}' did not match expected 'true'`);
  console.log(`SEPTEST-use_reexport_param-PASS output=${paramSelfOut} exit=${paramSelf.exitCode}`);
  await paired('protected_lub', path.join(work, 'pkgB4/protected_lub.cj'), ['--import-path', path.join(work, 'pkgA4'), '-L', path.join(work, 'pkgA4'), '-lpkgA4'], '17', 'pkgB4 protected_lub');
  console.log('SEPTEST-PASS');
} finally { await fs.rm(work, {recursive: true, force: true}); }
