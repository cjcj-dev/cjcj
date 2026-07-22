#!/usr/bin/env zx
// Diagnostic serialization gate for imported missing declarations, generic calls, and external interface implementations.

import fs from 'node:fs/promises';
import path from 'node:path';
import {copy, ensureInputs, fail, invoke, makeWork, output, reference, run, selfhost} from './septest_lib.mjs';

const work = await makeWork('septest-diag-');
const prefix = 'SEPTEST-DIAG';
const flat = text => text.replaceAll('\n', ' ');
try {
  await ensureInputs(prefix, work);
  for (const [source, destination] of [
    ['pkgA/pkgA.cj', 'pkgA/pkgA.cj'], ['pkgB/missing_decl.cj', 'pkgB/missing_decl.cj'], ['pkgB/generic_func_without_type_arg.cj', 'pkgB/generic_func_without_type_arg.cj'],
    ['pkgExtIface/pkgExtIface.cj', 'pkgExtIface/pkgExtIface.cj'], ['pkgExtUse/extend_implements.cj', 'pkgExtUse/extend_implements.cj'],
  ]) await copy(source, path.join(work, destination));
  await Promise.all([fs.mkdir(path.join(work, 'ref')), fs.mkdir(path.join(work, 'self'))]);
  async function buildDependency(source, archive, packageName) {
    const result = await invoke(reference, [source, '--output-type=staticlib', '-o', archive, '--set-runtime-rpath']);
    if (result.exitCode !== 0) fail(prefix, `reference ${packageName} compile failed: ${flat(result.stderr)}`);
    for (const file of [`${packageName}.cjo`, path.basename(archive)]) try { await fs.access(path.join(path.dirname(archive), file)); } catch { fail(prefix, `reference ${packageName} did not produce ${file}`); }
  }
  await buildDependency(path.join(work, 'pkgA/pkgA.cj'), path.join(work, 'pkgA/libpkgA.a'), 'pkgA');
  await buildDependency(path.join(work, 'pkgExtIface/pkgExtIface.cj'), path.join(work, 'pkgExtIface/libpkgExtIface.a'), 'pkgExtIface');

  const diagnostics = {};
  async function expectFailure(who, compiler, kind, source, args, label) {
    const result = await invoke(compiler, [source, '--diagnostic-format', 'json', ...args, '-o', path.join(work, who, kind), '--set-runtime-rpath']);
    const subject = label ? `${who} ${label}` : who;
    if (result.exitCode === 0) fail(prefix, `${subject} unexpectedly succeeded`);
    diagnostics[`${who}.${kind}`] = result.stderr;
    console.log(`SEPTEST-DIAG-PASS ${subject} failed exit=${result.exitCode}`);
  }
  const importArgs = ['--import-path', path.join(work, 'pkgA'), '-L', path.join(work, 'pkgA'), '-lpkgA'];
  await expectFailure('ref', reference, 'missing_decl', path.join(work, 'pkgB/missing_decl.cj'), importArgs, '');
  await expectFailure('self', selfhost, 'missing_decl', path.join(work, 'pkgB/missing_decl.cj'), importArgs, '');

  function field(text, name) { return text.split('\n').map(line => line.match(new RegExp(`.*"${name}": "(.*)",`))?.[1]).find(Boolean) || ''; }
  function numberField(text, name, occurrence) {
    const values = text.split('\n').flatMap(line => [...line.matchAll(new RegExp(`"${name}": ([0-9]+)`, 'g'))].map(match => match[1]));
    return values[occurrence - 1] || '';
  }
  const refText = diagnostics['ref.missing_decl']; const selfText = diagnostics['self.missing_decl'];
  const refKind = field(refText, 'DiagKind'); const selfKind = field(selfText, 'DiagKind');
  const refMessage = field(refText, 'Message'); const selfMessage = field(selfText, 'Message');
  if (refKind !== 'package_decl_not_find_in_package') fail(prefix, `reference kind '${refKind}' did not match package_decl_not_find_in_package`);
  console.log(`SEPTEST-DIAG-PASS reference kind=${refKind}`);
  if (selfKind !== refKind) fail(prefix, `selfhost kind '${selfKind}' did not match reference '${refKind}'`);
  console.log('SEPTEST-DIAG-PASS selfhost kind matches reference');
  if (!refMessage) fail(prefix, 'reference message was empty');
  if (selfMessage !== refMessage) fail(prefix, `selfhost message '${selfMessage}' did not match reference '${refMessage}'`);
  console.log(`SEPTEST-DIAG-PASS selfhost message matches reference: ${selfMessage}`);
  if (!selfMessage.includes('doesNotExist') || !selfMessage.includes('pkgA')) fail(prefix, `selfhost message '${selfMessage}' did not name missing decl and package`);
  console.log('SEPTEST-DIAG-PASS selfhost message names missing decl and package');
  const refBegin = numberField(refText, 'Column', 2); const refEnd = numberField(refText, 'Column', 3); const selfBegin = numberField(selfText, 'Column', 2); const selfEnd = numberField(selfText, 'Column', 3);
  if (!refBegin || !refEnd) fail(prefix, 'reference range columns were empty'); if (!selfBegin || !selfEnd) fail(prefix, 'selfhost range columns were empty');
  if (selfBegin !== refBegin || selfEnd !== refEnd) fail(prefix, `selfhost range columns ${selfBegin}-${selfEnd} did not match reference ${refBegin}-${refEnd}`);
  console.log(`SEPTEST-DIAG-PASS selfhost range matches reference columns=${selfBegin}-${selfEnd}`);
  if (selfText.includes('undeclared identifier')) fail(prefix, `unexpected text 'undeclared identifier' in ${work}/self.stderr`);
  console.log('SEPTEST-DIAG-PASS old diagnostic absent');

  await expectFailure('ref', reference, 'generic', path.join(work, 'pkgB/generic_func_without_type_arg.cj'), [], 'generic-func-without-type-arg');
  await expectFailure('self', selfhost, 'generic', path.join(work, 'pkgB/generic_func_without_type_arg.cj'), [], 'generic-func-without-type-arg');
  const refGeneric = diagnostics['ref.generic']; const selfGeneric = diagnostics['self.generic'];
  const refGenericKind = field(refGeneric, 'DiagKind'); const selfGenericKind = field(selfGeneric, 'DiagKind'); const refGenericMessage = field(refGeneric, 'Message'); const selfGenericMessage = field(selfGeneric, 'Message');
  if (refGenericKind !== 'sema_generic_func_without_type_arg') fail(prefix, `reference generic kind '${refGenericKind}' did not match sema_generic_func_without_type_arg`);
  console.log(`SEPTEST-DIAG-PASS reference generic kind=${refGenericKind}`);
  if (selfGenericKind !== refGenericKind) fail(prefix, `selfhost generic kind '${selfGenericKind}' did not match reference '${refGenericKind}'`);
  console.log('SEPTEST-DIAG-PASS selfhost generic kind matches reference');
  if (selfGenericMessage !== refGenericMessage) fail(prefix, `selfhost generic message '${selfGenericMessage}' did not match reference '${refGenericMessage}'`);
  console.log(`SEPTEST-DIAG-PASS selfhost generic message matches reference: ${selfGenericMessage}`);
  if (selfGenericMessage !== "type arguments needed for the generic function 'id'") fail(prefix, `selfhost generic message '${selfGenericMessage}' did not name id`);
  const rgb = numberField(refGeneric, 'Column', 2); const rge = numberField(refGeneric, 'Column', 3); const sgb = numberField(selfGeneric, 'Column', 2); const sge = numberField(selfGeneric, 'Column', 3);
  if (!rgb || !rge) fail(prefix, 'reference generic range columns were empty'); if (!sgb || !sge) fail(prefix, 'selfhost generic range columns were empty');
  if (sgb !== rgb || sge !== rge) fail(prefix, `selfhost generic range columns ${sgb}-${sge} did not match reference ${rgb}-${rge}`);
  console.log(`SEPTEST-DIAG-PASS selfhost generic range matches reference columns=${sgb}-${sge}`);
  if (selfGeneric.includes('IllegalStateException')) fail(prefix, `unexpected text 'IllegalStateException' in ${work}/self.generic.stderr`);
  console.log('SEPTEST-DIAG-PASS selfhost generic diagnostic did not crash');

  const linkArgs = ['--import-path', path.join(work, 'pkgExtIface'), '-L', path.join(work, 'pkgExtIface'), '-lpkgExtIface'];
  for (const [who, compiler] of [['ref', reference], ['self', selfhost]]) {
    const result = await invoke(compiler, [path.join(work, 'pkgExtUse/extend_implements.cj'), ...linkArgs, '-o', path.join(work, who, 'extend_implements'), '--set-runtime-rpath']);
    if (result.exitCode !== 0) fail(prefix, `${who === 'ref' ? 'reference' : 'selfhost'} extend_implements compile failed: ${flat(result.stderr)}`);
    if (who === 'self') for (const needle of ['sema_need_member_implementation', 'sema_class_need_abstract_modifier_or_func_need_impl', 'IllegalStateException']) if (result.stderr.includes(needle)) fail(prefix, `unexpected text '${needle}' in ${work}/extend_implements.self.stderr`);
  }
  console.log('SEPTEST-DIAG-PASS selfhost extend implementation emitted no unimplemented-interface diagnostic');
  const extendRef = await run(path.join(work, 'ref/extend_implements')); const extendSelf = await run(path.join(work, 'self/extend_implements')); const extendRefOut = output(extendRef); const extendSelfOut = output(extendSelf);
  if (extendRef.exitCode !== extendSelf.exitCode) fail(prefix, `extend_implements exit mismatch: reference=${extendRef.exitCode} selfhost=${extendSelf.exitCode}`);
  if (extendRefOut !== extendSelfOut) fail(prefix, `extend_implements output mismatch: reference='${extendRefOut}' selfhost='${extendSelfOut}'`);
  if (extendSelfOut !== '1') fail(prefix, `extend_implements output '${extendSelfOut}' did not match expected '1'`);
  console.log(`SEPTEST-DIAG-PASS extend_implements output=${extendSelfOut} exit=${extendSelf.exitCode}`);
  console.log('SEPTEST-DIAG-PASS');
} finally { await fs.rm(work, {recursive: true, force: true}); }
