#!/usr/bin/env zx
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const [compiler, output] = argv._.map(String);
if (![compiler, output].every(p => p && path.isAbsolute(p))) throw Error('usage: zx run.mjs /absolute/bin/cjc /new/output');
const root = path.resolve(output);
fs.mkdirSync(root); // Require fresh outputs: a stale CJO must never pass.
const enabled = ['--experimental', '--enable-local-mode', '--output-type=cjo'];
const signatures = fileURLToPath(new URL('./signatures.cj', import.meta.url));
const failures = [];
function compile(name, source, args, diag, cjoPackage = 'client') {
  const cwd = path.join(root, name);
  fs.mkdirSync(cwd);
  const archive = path.join(cwd, name + '.a');
  const cjo = args.includes('--output-type=cjo');
  const argv = [...args, ...(cjo ? [] : ['--output-type=staticlib']), '--diagnostic-format=json', source, '-o', cjo ? cwd : archive];
  const r = spawnSync(compiler, argv, {cwd, encoding:'utf8'});
  const archiveBytes = fs.statSync(archive, {throwIfNoEntry:false})?.size ?? null;
  fs.writeFileSync(path.join(cwd, 'result.json'), JSON.stringify({compiler, argv, rc:r.status, archiveBytes,
    signal:r.signal, stdout:r.stdout, stderr:r.stderr}, null, 2));
  if (r.error) throw r.error;
  const ok = r.status === (diag ? 1 : 0) && (!diag || diag.test(r.stderr + r.stdout)) &&
    (!diag || cjo || archiveBytes === null);
  console.log(name, 'compiler rc', r.status, 'expected', diag?.source ?? 'success', ok ? 'PASS' : 'FAIL');
  if (ok && !diag) {
    const product = cjo ? path.join(cwd, cjoPackage + '.cjo') : archive;
    assert(fs.statSync(product).size > 0, 'missing ' + product);
  }
  if (!ok) failures.push(name);
  if (cjoPackage !== 'client') assert(ok, 'failed to produce interface: ' + r.stderr);
  return cwd;
}
compile('defaultSource', signatures, [], /"DiagKind":\s*"parse_local_mode_disabled"/);
const nativeDir = compile('nativeSignatures', signatures, enabled.slice(0, 2));
assert.equal(fs.readFileSync(path.join(nativeDir, 'nativeSignatures.a')).subarray(0, 8).toString(), '!<arch>\n');
const producer = compile('producer', signatures, enabled, undefined, 'modalsigs');
assert(fs.statSync(path.join(producer, 'modalsigs.cjo')).size > 0);
assert(!fs.existsSync(path.join(producer, 'producer.a')));
function consumer(name, body, options, diag) {
  const file = path.join(root, name + '.cj');
  fs.writeFileSync(file, 'package client\nimport modalsigs.*\npublic func check(): Int64 {\n' + body + '\n}\n');
  compile(name, file, [...options, '--import-path', producer], diag);
}
const disabled = /"DiagKind":\s*"sema_local_api_disabled"/;
consumer('unusedImport', '42', []);
consumer('ordinary', 'let f = plain\nplainNested(f)', []);
consumer('directDisabled', 'full(20, 22)', [], disabled);
consumer('directEnabled', 'full(20, 22)', enabled);
consumer('bareFull', 'let f = full\nf(20, 22)', [], disabled);
consumer('bareHalf', 'let f = half\nf(20, 22)', [], disabled);
consumer('nestedDisabled', 'let f = nested\n0', [], disabled);
consumer('enabledNested', 'let f = full\nnested(f)', enabled);
consumer('enabledHalf', 'let f = half\nnested(f)', enabled);
const noMatch = /"DiagKind":\s*"sema_no_match_function_declaration_for_ref"/;
consumer('wrongMode', 'nested(plain)', enabled, noMatch);
consumer('wrongSlot', 'let f: (Int64 @local!, Int64) -> Int64 = full\nf(20, 22)', enabled,
  noMatch);
consumer('nonCopyRejected', 'let x: String @local! = "s"\n0', enabled, /"DiagKind":\s*"parse_unexpected_modal_type"/);
const unsupported = path.join(root, 'nonCopyParam.cj');
fs.writeFileSync(unsupported, 'package client\npublic func nope(s: String @local!): Int64 { 0 }\n');
compile('nonCopyParam', unsupported, enabled, /"DiagKind":\s*"parse_unexpected_modal_type"/);
// A second, independently produced interface keeps the original 16 inputs intact.
const aliases = compile('aliasProducer', fileURLToPath(new URL('./aliases.cj', import.meta.url)),
  enabled, undefined, 'aliassigs');
function typeUse(name, imported, declaration, options, rejectedType) {
  const file = path.join(root, name + '.cj');
  fs.writeFileSync(file, `package client\nimport ${imported}\n${declaration}\n`);
  const cwd = compile(name, file, [...options, '--import-path', aliases], rejectedType ? disabled : undefined);
  if (rejectedType) {
    const {stderr} = JSON.parse(fs.readFileSync(path.join(cwd, 'result.json'), 'utf8'));
    let errors = [];
    try { errors = JSON.parse(stderr).Diags.filter(d => d.Severity === 'error'); }
    catch { /* An absent or malformed diagnostic fails this case; run the remaining controls. */ }
    const column = declaration.indexOf(rejectedType) + 1;
    if (errors.length !== 1 || errors[0].DiagKind !== 'sema_local_api_disabled' ||
        errors[0].Location.File !== file || errors[0].Location.Line !== 3 || errors[0].Location.Column !== column) {
      failures.push(name + ': expected one diagnostic at the type reference');
    }
  }
}
const keep = type => `public func keep(f: ${type}): Int64 { 0 }`;
typeUse('aliasDirect', 'aliassigs.Callback', keep('Callback'), [], 'Callback');
typeUse('aliasNestedParam', 'aliassigs.Visitor', keep('Visitor'), [], 'Visitor');
typeUse('aliasNestedReturn', 'aliassigs.Factory', keep('Factory'), [], 'Factory');
typeUse('aliasQualified', 'aliassigs', keep('aliassigs.Callback'), [], 'aliassigs.Callback');
typeUse('aliasReexport', 'aliassigs.Callback', 'public type Again = Callback', [], 'Callback');
typeUse('aliasPlain', 'aliassigs.Plain', keep('Plain'), []);
typeUse('aliasUnused', 'aliassigs.Callback', 'public func keep(): Int64 { 0 }', []);
typeUse('aliasEnabled', 'aliassigs.Callback', keep('Callback'), enabled);
typeUse('aliasNestedEnabled', 'aliassigs.Visitor', keep('Visitor'), enabled);
assert.deepEqual(failures, []);
console.log('CJO cross-package signature controls passed');
